//
//  MetalShaderView.swift
//  AIAfterEffects
//
//  NSViewRepresentable that wraps MTKView to render AI-generated Metal shaders.
//  Compiles shader code at runtime and renders it as a full-screen quad with
//  standard uniforms (time, resolution, colors, params) synced to the canvas timeline.
//

import SwiftUI
import MetalKit

struct MetalShaderView: NSViewRepresentable {
    let shaderCode: String
    let currentTime: Double
    let size: CGSize
    let color1: CodableColor
    let color2: CodableColor
    let param1: Float
    let param2: Float
    let param3: Float
    let param4: Float
    
    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = ShaderService.shared.device
        mtkView.delegate = context.coordinator
        mtkView.enableSetNeedsDisplay = true  // Manual redraw (driven by currentTime)
        mtkView.isPaused = true               // We control frame updates
        mtkView.layer?.isOpaque = false        // Transparent background
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        
        // Initial compilation
        context.coordinator.compileShader(code: shaderCode)
        
        return mtkView
    }
    
    func updateNSView(_ mtkView: MTKView, context: Context) {
        let coordinator = context.coordinator
        
        // Recompile if code changed
        if coordinator.currentShaderCode != shaderCode {
            coordinator.compileShader(code: shaderCode)
        }
        
        // Update uniforms
        coordinator.uniforms.time = Float(currentTime)
        coordinator.uniforms.resolution = SIMD2<Float>(Float(size.width), Float(size.height))
        coordinator.uniforms.color1 = SIMD4<Float>(
            Float(color1.red), Float(color1.green), Float(color1.blue), Float(color1.alpha)
        )
        coordinator.uniforms.color2 = SIMD4<Float>(
            Float(color2.red), Float(color2.green), Float(color2.blue), Float(color2.alpha)
        )
        coordinator.uniforms.param1 = param1
        coordinator.uniforms.param2 = param2
        coordinator.uniforms.param3 = param3
        coordinator.uniforms.param4 = param4
        
        // Trigger redraw
        mtkView.setNeedsDisplay(mtkView.bounds)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, MTKViewDelegate {
        var compiledShader: CompiledShader?
        var compilationError: String?
        var currentShaderCode: String = ""
        var uniforms = ShaderUniforms(
            time: 0,
            resolution: SIMD2<Float>(1, 1),
            color1: SIMD4<Float>(1, 1, 1, 1),
            color2: SIMD4<Float>(0, 0, 0, 1),
            param1: 0, param2: 0, param3: 0, param4: 0
        )
        
        func compileShader(code: String) {
            currentShaderCode = code
            compilationError = nil
            
            guard !code.isEmpty else {
                compiledShader = nil
                compilationError = "No shader code"
                return
            }
            
            do {
                compiledShader = try ShaderService.shared.compile(fragmentBody: code)
            } catch {
                compiledShader = nil
                compilationError = error.localizedDescription
                DebugLogger.shared.error("Shader compilation failed: \(error.localizedDescription)", category: .canvas)
            }
        }
        
        // MARK: - MTKViewDelegate
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // Size changes handled via uniforms.resolution
        }
        
        func draw(in view: MTKView) {
            guard let pipeline = compiledShader?.pipelineState,
                  let device = view.device,
                  let drawable = view.currentDrawable,
                  let renderPassDescriptor = view.currentRenderPassDescriptor else {
                return
            }
            
            // Set clear color to transparent
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            
            guard let commandBuffer = device.makeCommandQueue()?.makeCommandBuffer(),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                return
            }
            
            encoder.setRenderPipelineState(pipeline)
            
            // Use the actual drawable size for resolution uniform so the shader
            // always knows its true pixel dimensions (respects Retina scaling).
            var unis = uniforms
            let drawableSize = view.drawableSize
            unis.resolution = SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height))
            encoder.setFragmentBytes(&unis, length: MemoryLayout<ShaderUniforms>.stride, index: 0)
            
            // Draw full-screen quad (triangle strip, 4 vertices)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            
            encoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}

// MARK: - Shader Error View (fallback when compilation fails)

struct ShaderErrorView: View {
    let error: String
    let size: CGSize
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.8))
            
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.orange)
                
                Text("Shader Error")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)
                
                Text(error)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.gray)
                    .lineLimit(4)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Export Snapshot Helper

/// Captures a Metal shader frame as a CGImage for video export.
struct MetalShaderExportHelper {
    static func snapshot(
        shaderCode: String,
        time: Double,
        size: CGSize,
        color1: CodableColor,
        color2: CodableColor,
        param1: Float, param2: Float, param3: Float, param4: Float
    ) -> CGImage? {
        guard let device = ShaderService.shared.device,
              let compiled = try? ShaderService.shared.compile(fragmentBody: shaderCode) else {
            return nil
        }
        
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0 && height > 0 else { return nil }
        
        // Create offscreen texture
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        texDesc.usage = [.renderTarget, .shaderRead]
        guard let texture = device.makeTexture(descriptor: texDesc) else { return nil }
        
        // Render pass
        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = texture
        renderPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].storeAction = .store
        
        guard let queue = device.makeCommandQueue(),
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else {
            return nil
        }
        
        encoder.setRenderPipelineState(compiled.pipelineState)
        
        var uniforms = ShaderUniforms(
            time: Float(time),
            resolution: SIMD2<Float>(Float(width), Float(height)),
            color1: SIMD4<Float>(Float(color1.red), Float(color1.green), Float(color1.blue), Float(color1.alpha)),
            color2: SIMD4<Float>(Float(color2.red), Float(color2.green), Float(color2.blue), Float(color2.alpha)),
            param1: param1, param2: param2, param3: param3, param4: param4
        )
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // Read texture to CGImage
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        texture.getBytes(&pixels, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        
        // BGRA -> RGBA
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let b = pixels[i]
            pixels[i] = pixels[i + 2]
            pixels[i + 2] = b
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        return context.makeImage()
    }
}
