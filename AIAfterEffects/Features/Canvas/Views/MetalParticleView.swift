//
//  MetalParticleView.swift
//  AIAfterEffects
//
//  GPU-accelerated particle renderer using instanced Metal drawing.
//  Each particle is a single struct in a buffer; the GPU computes position,
//  velocity, gravity, fade, scale, and spin per-instance every frame.
//

import SwiftUI
import MetalKit

// MARK: - Particle Data (CPU → GPU)

struct GPUParticle {
    var originX: Float
    var originY: Float
    var velocityX: Float
    var velocityY: Float
    var gravity: Float
    var drag: Float
    var startTime: Float
    var lifetime: Float
    var fadeDelay: Float
    var size: Float
    var elongation: Float     // width/height ratio for motion blur streaks
    var initialRotation: Float
    var spinSpeed: Float
    var colorR: Float
    var colorG: Float
    var colorB: Float
    var colorA: Float
    var glowRadius: Float
    var tier: Float           // 0=hero, 1=mid, 2=dust (for GPU branching)
}

// MARK: - Particle System Uniforms

struct ParticleUniforms {
    var time: Float
    var resolution: SIMD2<Float>
    var canvasScale: Float    // maps canvas coords → NDC
    var canvasOffsetX: Float
    var canvasOffsetY: Float
}

// MARK: - Particle System Configuration (stored on SceneObject)

struct ParticleSystemData: Codable, Equatable {
    let particles: [ParticleData]
    let effectStartTime: Double
    
    struct ParticleData: Codable, Equatable {
        let originX: Double
        let originY: Double
        let velocityX: Double
        let velocityY: Double
        let gravity: Double
        let drag: Double
        let delay: Double   // stagger relative to effectStartTime
        let lifetime: Double
        let fadeDelay: Double
        let size: Double
        let elongation: Double
        let initialRotation: Double
        let spinSpeed: Double
        let colorR: Double
        let colorG: Double
        let colorB: Double
        let colorA: Double
        let glowRadius: Double
        let tier: Int  // 0=hero, 1=mid, 2=dust
    }
}

// MARK: - Metal Particle View

struct MetalParticleView: NSViewRepresentable {
    let particleData: ParticleSystemData
    let currentTime: Double
    let size: CGSize
    
    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = ShaderService.shared.device
        mtkView.delegate = context.coordinator
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = true
        mtkView.layer?.isOpaque = false
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        
        context.coordinator.setup(device: mtkView.device!, particleData: particleData)
        
        return mtkView
    }
    
    func updateNSView(_ mtkView: MTKView, context: Context) {
        let coordinator = context.coordinator
        
        if coordinator.particleCount != particleData.particles.count {
            coordinator.setup(device: mtkView.device!, particleData: particleData)
        }
        
        coordinator.uniforms.time = Float(currentTime)
        coordinator.uniforms.resolution = SIMD2<Float>(Float(size.width), Float(size.height))
        coordinator.effectStartTime = Float(particleData.effectStartTime)
        
        mtkView.setNeedsDisplay(mtkView.bounds)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, MTKViewDelegate {
        var pipelineState: MTLRenderPipelineState?
        var particleBuffer: MTLBuffer?
        var particleCount: Int = 0
        var effectStartTime: Float = 0
        var uniforms = ParticleUniforms(
            time: 0,
            resolution: SIMD2<Float>(1, 1),
            canvasScale: 1,
            canvasOffsetX: 0,
            canvasOffsetY: 0
        )
        
        private static var cachedPipeline: MTLRenderPipelineState?
        
        func setup(device: MTLDevice, particleData: ParticleSystemData) {
            particleCount = particleData.particles.count
            guard particleCount > 0 else { return }
            
            // Build GPU particle buffer
            var gpuParticles: [GPUParticle] = []
            gpuParticles.reserveCapacity(particleCount)
            
            for p in particleData.particles {
                gpuParticles.append(GPUParticle(
                    originX: Float(p.originX),
                    originY: Float(p.originY),
                    velocityX: Float(p.velocityX),
                    velocityY: Float(p.velocityY),
                    gravity: Float(p.gravity),
                    drag: Float(p.drag),
                    startTime: Float(particleData.effectStartTime + p.delay),
                    lifetime: Float(p.lifetime),
                    fadeDelay: Float(p.fadeDelay),
                    size: Float(p.size),
                    elongation: Float(p.elongation),
                    initialRotation: Float(p.initialRotation),
                    spinSpeed: Float(p.spinSpeed),
                    colorR: Float(p.colorR),
                    colorG: Float(p.colorG),
                    colorB: Float(p.colorB),
                    colorA: Float(p.colorA),
                    glowRadius: Float(p.glowRadius),
                    tier: Float(p.tier)
                ))
            }
            
            particleBuffer = device.makeBuffer(
                bytes: gpuParticles,
                length: MemoryLayout<GPUParticle>.stride * particleCount,
                options: .storageModeShared
            )
            
            // Compile pipeline (cached)
            if let cached = Self.cachedPipeline {
                pipelineState = cached
            } else {
                compilePipeline(device: device)
                Self.cachedPipeline = pipelineState
            }
        }
        
        private func compilePipeline(device: MTLDevice) {
            let source = Self.shaderSource
            do {
                let library = try device.makeLibrary(source: source, options: nil)
                guard let vertexFn = library.makeFunction(name: "particleVertex"),
                      let fragmentFn = library.makeFunction(name: "particleFragment") else { return }
                
                let desc = MTLRenderPipelineDescriptor()
                desc.vertexFunction = vertexFn
                desc.fragmentFunction = fragmentFn
                desc.colorAttachments[0].pixelFormat = .bgra8Unorm
                desc.colorAttachments[0].isBlendingEnabled = true
                desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                desc.colorAttachments[0].sourceAlphaBlendFactor = .one
                desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
                
                pipelineState = try device.makeRenderPipelineState(descriptor: desc)
            } catch {
                DebugLogger.shared.error("Particle shader compilation failed: \(error)", category: .canvas)
            }
        }
        
        // MARK: - MTKViewDelegate
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        
        func draw(in view: MTKView) {
            guard let pipeline = pipelineState,
                  let buffer = particleBuffer,
                  particleCount > 0,
                  let drawable = view.currentDrawable,
                  let rpd = view.currentRenderPassDescriptor else { return }
            
            rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            rpd.colorAttachments[0].loadAction = .clear
            
            guard let queue = view.device?.makeCommandQueue(),
                  let cmdBuf = queue.makeCommandBuffer(),
                  let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else { return }
            
            encoder.setRenderPipelineState(pipeline)
            
            var unis = uniforms
            let drawableSize = view.drawableSize
            unis.resolution = SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height))
            
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&unis, length: MemoryLayout<ParticleUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&unis, length: MemoryLayout<ParticleUniforms>.stride, index: 0)
            
            // Each particle = 6 vertices (quad from 2 triangles)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6 * particleCount)
            
            encoder.endEncoding()
            cmdBuf.present(drawable)
            cmdBuf.commit()
        }
        
        // MARK: - Metal Shader Source
        
        static let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;
        
        struct GPUParticle {
            float originX;
            float originY;
            float velocityX;
            float velocityY;
            float gravity;
            float drag;
            float startTime;
            float lifetime;
            float fadeDelay;
            float size;
            float elongation;
            float initialRotation;
            float spinSpeed;
            float colorR;
            float colorG;
            float colorB;
            float colorA;
            float glowRadius;
            float tier;
        };
        
        struct Uniforms {
            float time;
            float2 resolution;
            float canvasScale;
            float canvasOffsetX;
            float canvasOffsetY;
        };
        
        struct VertexOut {
            float4 position [[position]];
            float2 localUV;
            float4 color;
            float glow;
            float particleAlpha;
        };
        
        vertex VertexOut particleVertex(
            uint vertexID [[vertex_id]],
            const device GPUParticle *particles [[buffer(0)]],
            constant Uniforms &uniforms [[buffer(1)]]
        ) {
            uint particleIdx = vertexID / 6;
            uint cornerIdx = vertexID % 6;
            
            GPUParticle p = particles[particleIdx];
            
            float t = uniforms.time - p.startTime;
            
            VertexOut out;
            out.color = float4(p.colorR, p.colorG, p.colorB, p.colorA);
            out.glow = p.glowRadius;
            
            // Before start time: invisible
            if (t < 0.0 || t > p.lifetime) {
                out.position = float4(0, 0, 0, 0);
                out.localUV = float2(0, 0);
                out.particleAlpha = 0.0;
                return out;
            }
            
            // Physics: position with drag
            float dragFactor = exp(-p.drag * t);
            float posX = p.originX + (p.velocityX / max(p.drag, 0.001)) * (1.0 - dragFactor);
            float posY = p.originY + (p.velocityY / max(p.drag, 0.001)) * (1.0 - dragFactor)
                         + 0.5 * p.gravity * t * t;
            
            // Fade: hold then fade out
            float fadeProgress = 0.0;
            if (t > p.fadeDelay) {
                float fadeDuration = p.lifetime - p.fadeDelay;
                fadeProgress = clamp((t - p.fadeDelay) / max(fadeDuration, 0.001), 0.0, 1.0);
            }
            float alpha = p.colorA * (1.0 - fadeProgress);
            
            // Scale: shrink over time
            float scaleProgress = clamp(t / p.lifetime, 0.0, 1.0);
            float currentSize = p.size * mix(1.0, 0.1, scaleProgress * scaleProgress);
            
            // Rotation
            float angle = p.initialRotation + p.spinSpeed * t;
            float cosA = cos(angle);
            float sinA = sin(angle);
            
            // Quad corners (elongated for motion blur)
            float halfW = currentSize * max(1.0, p.elongation) * 0.5;
            float halfH = currentSize * 0.5;
            
            // 6 vertices per quad: 2 triangles
            float2 corners[6] = {
                float2(-halfW, -halfH), float2( halfW, -halfH), float2(-halfW,  halfH),
                float2( halfW, -halfH), float2( halfW,  halfH), float2(-halfW,  halfH)
            };
            float2 uvs[6] = {
                float2(0, 0), float2(1, 0), float2(0, 1),
                float2(1, 0), float2(1, 1), float2(0, 1)
            };
            
            float2 corner = corners[cornerIdx];
            // Apply rotation
            float2 rotated = float2(
                corner.x * cosA - corner.y * sinA,
                corner.x * sinA + corner.y * cosA
            );
            
            // Canvas coords → NDC
            float2 screenPos = float2(posX + rotated.x, posY + rotated.y);
            float2 ndc = float2(
                (screenPos.x / uniforms.resolution.x) * 2.0 - 1.0,
                1.0 - (screenPos.y / uniforms.resolution.y) * 2.0
            );
            
            out.position = float4(ndc, 0.0, 1.0);
            out.localUV = uvs[cornerIdx];
            out.particleAlpha = alpha;
            
            return out;
        }
        
        fragment float4 particleFragment(VertexOut in [[stage_in]]) {
            // Soft circle with glow
            float2 centered = in.localUV * 2.0 - 1.0;
            float dist = length(centered);
            
            // Core circle
            float circle = 1.0 - smoothstep(0.6, 1.0, dist);
            
            // Glow aura (for hero particles)
            float glow = 0.0;
            if (in.glow > 0.0) {
                glow = (1.0 - smoothstep(0.0, 1.0, dist)) * 0.4;
            }
            
            float finalAlpha = (circle + glow) * in.particleAlpha;
            if (finalAlpha < 0.001) discard_fragment();
            
            return float4(in.color.rgb, finalAlpha);
        }
        """
    }
}

// MARK: - Export Snapshot

struct MetalParticleExportHelper {
    static func snapshot(
        particleData: ParticleSystemData,
        time: Double,
        size: CGSize
    ) -> CGImage? {
        guard let device = ShaderService.shared.device else { return nil }
        
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0 && height > 0 else { return nil }
        
        let coordinator = MetalParticleView.Coordinator()
        coordinator.setup(device: device, particleData: particleData)
        coordinator.uniforms.time = Float(time)
        coordinator.uniforms.resolution = SIMD2<Float>(Float(width), Float(height))
        
        guard let pipeline = coordinator.pipelineState,
              let buffer = coordinator.particleBuffer,
              coordinator.particleCount > 0 else { return nil }
        
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
        )
        texDesc.usage = [.renderTarget, .shaderRead]
        guard let texture = device.makeTexture(descriptor: texDesc) else { return nil }
        
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = texture
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        
        guard let queue = device.makeCommandQueue(),
              let cmdBuf = queue.makeCommandBuffer(),
              let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else { return nil }
        
        encoder.setRenderPipelineState(pipeline)
        
        var unis = coordinator.uniforms
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&unis, length: MemoryLayout<ParticleUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&unis, length: MemoryLayout<ParticleUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6 * coordinator.particleCount)
        encoder.endEncoding()
        
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&pixels, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let b = pixels[i]
            pixels[i] = pixels[i + 2]
            pixels[i + 2] = b
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        return ctx.makeImage()
    }
}
