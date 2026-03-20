//
//  VideoExportService.swift
//  AIAfterEffects
//
//  Pixel-perfect video export using SwiftUI's ImageRenderer.
//
//  Architecture:
//    1. `ImageRenderer` renders the exact same SwiftUI view hierarchy used
//       on screen (ExportableSceneView), producing a CGImage per frame.
//       This guarantees pixel-perfect match with the in-app preview.
//    2. A Metal-backed `CIContext` converts CGImage → CVPixelBuffer on the
//       GPU, avoiding expensive CPU bitmap copies.
//    3. AVAssetWriter encodes H.264 with hardware acceleration.
//    4. Frames are rendered in batches with `Task.yield()` between batches
//       so the UI stays responsive during export.
//    5. Progress is published via @MainActor @Published properties.
//

import Foundation
import AVFoundation
import AppKit
import SwiftUI
import CoreImage
import Metal

// MARK: - Export Configuration

struct ExportConfiguration {
    var width: Int
    var height: Int
    var frameRate: Double = 60
    var videoBitrate: Int = 10_000_000 // 10 Mbps
    var outputURL: URL
    
    /// Create a config using the scene's actual canvas dimensions
    static func fromScene(_ sceneState: SceneState, outputURL: URL) -> ExportConfiguration {
        ExportConfiguration(
            width: Int(sceneState.canvasWidth),
            height: Int(sceneState.canvasHeight),
            frameRate: Double(max(sceneState.fps, 1)),
            outputURL: outputURL
        )
    }
}

// MARK: - Export Progress

struct ExportProgress: Sendable {
    var currentFrame: Int
    var totalFrames: Int
    var phase: ExportPhase
    
    var percentage: Double {
        guard totalFrames > 0 else { return 0 }
        return Double(currentFrame) / Double(totalFrames)
    }
    
    enum ExportPhase: Sendable {
        case preparing
        case rendering
        case finishing
        case completed
        case failed(String)
    }
}

// MARK: - Video Export Service

final class VideoExportService: ObservableObject, @unchecked Sendable {
    
    // Published on MainActor so SwiftUI can bind directly.
    @MainActor @Published var isExporting = false
    @MainActor @Published var progress: ExportProgress?
    @MainActor @Published var isCancelled = false
    
    private let logger = DebugLogger.shared
    
    /// Metal-backed CIContext for GPU-accelerated CGImage → CVPixelBuffer.
    /// Created once and reused across all frames for maximum performance.
    private let ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [
                .cacheIntermediates: false,
                .priorityRequestLow: false
            ])
        }
        // Fallback to default (still GPU-accelerated via OpenGL on older Macs)
        return CIContext(options: [.useSoftwareRenderer: false])
    }()
    
    /// Number of frames to render before yielding to the run loop.
    /// Higher = faster export but less responsive UI.
    private let batchSize = 4
    
    // MARK: - Public API
    
    /// Export the scene using ImageRenderer for pixel-perfect output.
    ///
    /// Renders the exact same SwiftUI view hierarchy shown on screen,
    /// guaranteeing visual fidelity.  Metal is used to accelerate
    /// CGImage → CVPixelBuffer conversion.
    @MainActor
    func exportScene(
        sceneState: SceneState,
        config: ExportConfiguration
    ) async throws {
        isExporting = true
        isCancelled = false
        progress = ExportProgress(currentFrame: 0, totalFrames: 0, phase: .preparing)
        
        defer { isExporting = false }
        
        logger.info("Starting ImageRenderer export to: \(config.outputURL.path)", category: .app)
        
        let frozenScene = sceneState
        let totalFrames = Int(frozenScene.duration * config.frameRate)
        
        // Prepare offscreen 3D renderers for model3D objects
        // (ImageRenderer cannot capture NSViewRepresentable/SceneKit content)
        let model3DManager = Model3DExportManager()
        model3DManager.prepare(sceneState: frozenScene)
        defer { model3DManager.cleanup() }
        
        // Identify shader objects that need offscreen rendering
        // (ImageRenderer cannot capture NSViewRepresentable/MTKView content)
        let shaderObjects = frozenScene.objects.filter { $0.type == .shader && $0.properties.shaderCode?.isEmpty == false }
        
        logger.debug(
            "Export config: \(config.width)x\(config.height) @ \(String(format: "%.2f", config.frameRate))fps | Scene: \(Int(frozenScene.canvasWidth))x\(Int(frozenScene.canvasHeight)) @ \(frozenScene.fps)fps | Objects: \(frozenScene.objects.count) | 3D models: \(model3DManager.hasModels ? "yes" : "none") | Shaders: \(shaderObjects.count) | Batch size: \(batchSize)",
            category: .app
        )
        
        progress = ExportProgress(currentFrame: 0, totalFrames: totalFrames, phase: .preparing)
        
        // Remove existing file
        let fm = FileManager.default
        if fm.fileExists(atPath: config.outputURL.path) {
            try? fm.removeItem(at: config.outputURL)
        }
        
        // ── Setup AVAssetWriter ──
        let writer = try AVAssetWriter(outputURL: config.outputURL, fileType: .mp4)
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: config.width,
            AVVideoHeightKey: config.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: config.videoBitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false
        
        let poolAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: config.width,
            kCVPixelBufferHeightKey as String: config.height,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: poolAttrs
        )
        
        writer.add(writerInput)
        
        guard writer.startWriting() else {
            let err = writer.error ?? NSError(
                domain: "VideoExport", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to start writing"]
            )
            progress = ExportProgress(currentFrame: 0, totalFrames: totalFrames, phase: .failed(err.localizedDescription))
            throw err
        }
        
        writer.startSession(atSourceTime: .zero)
        progress = ExportProgress(currentFrame: 0, totalFrames: totalFrames, phase: .rendering)
        
        // ── Frame loop (runs on @MainActor, yields between batches) ──
        let progressInterval = max(1, totalFrames / 200)
        
        for frameIndex in 0..<totalFrames {
            // Check cancellation
            if isCancelled {
                writerInput.markAsFinished()
                writer.cancelWriting()
                progress = ExportProgress(
                    currentFrame: frameIndex, totalFrames: totalFrames,
                    phase: .failed("Export cancelled")
                )
                return
            }
            
            let time = Double(frameIndex) / config.frameRate
            
            // Pre-render 3D models offscreen (SceneKit → NSImage)
            let model3DSnapshots = model3DManager.hasModels
                ? model3DManager.renderAll(sceneState: frozenScene, at: time)
                : [UUID: NSImage]()
            
            // Pre-render Metal shaders offscreen (Metal → NSImage)
            var shaderSnapshots: [UUID: NSImage] = [:]
            for obj in shaderObjects {
                if let code = obj.properties.shaderCode,
                   let cgImage = MetalShaderExportHelper.snapshot(
                    shaderCode: code,
                    time: time,
                    size: CGSize(width: obj.properties.width, height: obj.properties.height),
                    color1: obj.properties.fillColor,
                    color2: obj.properties.strokeColor,
                    param1: Float(obj.properties.shaderParam1 ?? 1.0),
                    param2: Float(obj.properties.shaderParam2 ?? 1.0),
                    param3: Float(obj.properties.shaderParam3 ?? 0.0),
                    param4: Float(obj.properties.shaderParam4 ?? 0.0)
                   ) {
                    shaderSnapshots[obj.id] = NSImage(cgImage: cgImage, size: NSSize(width: obj.properties.width, height: obj.properties.height))
                }
            }
            
            // Pre-render GPU particle systems offscreen (Metal → NSImage)
            for obj in frozenScene.objects where obj.type == .particleSystem {
                if let psData = obj.properties.particleSystemData,
                   let cgImage = MetalParticleExportHelper.snapshot(
                    particleData: psData,
                    time: time,
                    size: CGSize(width: obj.properties.width, height: obj.properties.height)
                   ) {
                    shaderSnapshots[obj.id] = NSImage(cgImage: cgImage, size: NSSize(width: obj.properties.width, height: obj.properties.height))
                }
            }
            
            // Render the exact same SwiftUI view shown on screen
            // 3D models and shaders use pre-rendered snapshots instead of NSViewRepresentable
            let frameView = ExportableSceneView(
                sceneState: frozenScene,
                currentTime: time,
                model3DSnapshots: model3DSnapshots,
                shaderSnapshots: shaderSnapshots
            )
            
            let renderer = ImageRenderer(content: frameView)
            renderer.scale = 1.0
            renderer.proposedSize = ProposedViewSize(
                width: CGFloat(config.width),
                height: CGFloat(config.height)
            )
            
            guard let cgImage = renderer.cgImage else {
                logger.warning("ImageRenderer returned nil for frame \(frameIndex) at t=\(String(format: "%.3f", time))s", category: .app)
                continue
            }
            
            // Wait for writer to be ready
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000) // 2ms
            }
            
            // Convert CGImage → CVPixelBuffer using Metal-backed CIContext
            guard let pixelBuffer = createPixelBufferMetal(
                from: cgImage,
                adaptor: adaptor,
                width: config.width,
                height: config.height
            ) else {
                logger.warning("Failed to create pixel buffer for frame \(frameIndex)", category: .app)
                continue
            }
            
            // Append frame
            let presentationTime = CMTime(
                value: CMTimeValue(frameIndex),
                timescale: CMTimeScale(config.frameRate)
            )
            if !adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                let err = writer.error ?? NSError(
                    domain: "VideoExport", code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to append frame \(frameIndex)"]
                )
                progress = ExportProgress(
                    currentFrame: frameIndex, totalFrames: totalFrames,
                    phase: .failed(err.localizedDescription)
                )
                throw err
            }
            
            // Update progress periodically
            if frameIndex % progressInterval == 0 || frameIndex == totalFrames - 1 {
                progress = ExportProgress(
                    currentFrame: frameIndex + 1, totalFrames: totalFrames,
                    phase: .rendering
                )
            }
            
            // Yield to run loop every `batchSize` frames to keep UI responsive
            if frameIndex % batchSize == 0 {
                await Task.yield()
            }
        }
        
        // ── Finalize ──
        progress = ExportProgress(currentFrame: totalFrames, totalFrames: totalFrames, phase: .finishing)
        
        writerInput.markAsFinished()
        
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }
        
        if let error = writer.error {
            progress = ExportProgress(
                currentFrame: totalFrames, totalFrames: totalFrames,
                phase: .failed(error.localizedDescription)
            )
            throw error
        }
        
        progress = ExportProgress(currentFrame: totalFrames, totalFrames: totalFrames, phase: .completed)
        logger.success("Video export completed: \(config.outputURL.path)", category: .app)
    }
    
    @MainActor
    func cancelExport() {
        isCancelled = true
    }
    
    // MARK: - Metal-Accelerated Pixel Buffer Conversion
    
    /// Convert CGImage → CVPixelBuffer using a Metal-backed CIContext.
    ///
    /// This is significantly faster than the CPU-based CGContext.draw()
    /// approach because:
    ///   - CIContext.render(_:to:) uses the GPU for the blit
    ///   - The pixel buffer pool recycles buffers (zero per-frame allocation)
    ///   - Metal command buffers are pipelined with the encoder
    private func createPixelBufferMetal(
        from cgImage: CGImage,
        adaptor: AVAssetWriterInputPixelBufferAdaptor,
        width: Int,
        height: Int
    ) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        
        // Prefer pool from adaptor (recycles buffers, zero allocation per frame)
        if let pool = adaptor.pixelBufferPool {
            let status = CVPixelBufferPoolCreatePixelBuffer(
                kCFAllocatorDefault, pool, &pixelBuffer
            )
            if status != kCVReturnSuccess { pixelBuffer = nil }
        }
        
        // Fallback: create a new buffer
        if pixelBuffer == nil {
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault, width, height,
                kCVPixelFormatType_32BGRA,
                attrs as CFDictionary,
                &pixelBuffer
            )
            guard status == kCVReturnSuccess else { return nil }
        }
        
        guard let buffer = pixelBuffer else { return nil }
        
        // Use CIContext (Metal-backed) to render directly into the pixel buffer
        let ciImage = CIImage(cgImage: cgImage)
        ciContext.render(
            ciImage,
            to: buffer,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        
        return buffer
    }
    
    // MARK: - Save Panel
    
    @MainActor
    func showSavePanel() -> URL? {
        let savePanel = NSSavePanel()
        savePanel.title = "Export Video"
        savePanel.nameFieldStringValue = "animation.mp4"
        savePanel.allowedContentTypes = [.mpeg4Movie]
        savePanel.canCreateDirectories = true
        
        let response = savePanel.runModal()
        return response == .OK ? savePanel.url : nil
    }
}
