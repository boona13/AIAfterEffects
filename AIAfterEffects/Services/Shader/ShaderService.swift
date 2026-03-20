//
//  ShaderService.swift
//  AIAfterEffects
//
//  Runtime Metal shader compilation service.
//  Takes AI-generated shader code, wraps it in a template with standard uniforms,
//  compiles it at runtime, and caches the pipeline state for rendering.
//

import Metal
import Foundation

// MARK: - Shader Uniforms

/// Uniforms passed to every shader — matches the Metal struct layout.
struct ShaderUniforms {
    var time: Float        // Current timeline time in seconds
    var resolution: SIMD2<Float>  // Canvas size in pixels (width, height)
    var color1: SIMD4<Float>      // Primary color (from fillColor)
    var color2: SIMD4<Float>      // Secondary color (from strokeColor)
    var param1: Float      // Custom parameter 1 (AI-defined)
    var param2: Float      // Custom parameter 2
    var param3: Float      // Custom parameter 3
    var param4: Float      // Custom parameter 4
}

// MARK: - Compiled Shader

/// A successfully compiled shader, ready to render.
struct CompiledShader {
    let pipelineState: MTLRenderPipelineState
    let sourceHash: Int   // Hash of the source code for cache lookup
}

// MARK: - Shader Compilation Error

enum ShaderCompilationError: Error, LocalizedError {
    case noDevice
    case compilationFailed(String)
    case pipelineFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noDevice:
            return "No Metal GPU device available"
        case .compilationFailed(let msg):
            return "Shader compilation failed: \(msg)"
        case .pipelineFailed(let msg):
            return "Pipeline creation failed: \(msg)"
        }
    }
}

// MARK: - Shader Service

class ShaderService {
    static let shared = ShaderService()
    
    let device: MTLDevice?
    private var cache: [Int: CompiledShader] = [:]
    private let lock = NSLock()
    
    private init() {
        self.device = MTLCreateSystemDefaultDevice()
        if device == nil {
            DebugLogger.shared.error("ShaderService: No Metal device available", category: .canvas)
        }
    }
    
    // MARK: - Public API
    
    /// Compile AI-generated shader code into a renderable pipeline.
    /// The `fragmentBody` is the body of a fragment shader function.
    /// It will be wrapped in a template with standard uniforms and utility functions.
    ///
    /// Returns a cached result if the same code was compiled before.
    func compile(fragmentBody: String) throws -> CompiledShader {
        guard let device = device else {
            throw ShaderCompilationError.noDevice
        }
        
        let hash = fragmentBody.hashValue
        
        // Check cache
        lock.lock()
        if let cached = cache[hash] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        
        // Build full Metal source
        let fullSource = Self.wrapFragmentBody(fragmentBody)
        
        // Compile
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: fullSource, options: nil)
        } catch {
            throw ShaderCompilationError.compilationFailed(error.localizedDescription)
        }
        
        guard let vertexFn = library.makeFunction(name: "shaderVertex"),
              let fragmentFn = library.makeFunction(name: "shaderFragment") else {
            throw ShaderCompilationError.compilationFailed("Could not find shaderVertex/shaderFragment functions")
        }
        
        // Create pipeline
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        // Enable alpha blending so shaders can be transparent
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        let pipelineState: MTLRenderPipelineState
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw ShaderCompilationError.pipelineFailed(error.localizedDescription)
        }
        
        let compiled = CompiledShader(pipelineState: pipelineState, sourceHash: hash)
        
        // Cache
        lock.lock()
        cache[hash] = compiled
        lock.unlock()
        
        DebugLogger.shared.success("Shader compiled successfully (hash: \(hash))", category: .canvas)
        
        return compiled
    }
    
    /// Evict a specific shader from the cache.
    func evict(fragmentBody: String) {
        let hash = fragmentBody.hashValue
        lock.lock()
        cache.removeValue(forKey: hash)
        lock.unlock()
    }
    
    /// Clear the entire cache.
    func clearCache() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }
    
    // MARK: - Template
    
    /// Wraps the AI-generated fragment body in the full Metal shader template.
    /// The template provides:
    /// - Standard uniforms (time, resolution, color1, color2, param1-4)
    /// - Utility functions (hash, noise, fbm, hsl2rgb)
    /// - A vertex shader for full-screen quad rendering
    /// - The fragment function with the AI code as its body
    static func wrapFragmentBody(_ body: String) -> String {
        return """
        #include <metal_stdlib>
        using namespace metal;
        
        // --- Uniforms ---
        struct Uniforms {
            float time;
            float2 resolution;
            float4 color1;
            float4 color2;
            float param1;
            float param2;
            float param3;
            float param4;
        };
        
        struct VertexOut {
            float4 position [[position]];
            float2 uv;
        };
        
        // --- Utility Functions (available to all AI shaders) ---
        
        float _hash(float2 p) {
            float3 p3 = fract(float3(p.xyx) * 0.13);
            p3 += dot(p3, p3.yzx + 3.333);
            return fract((p3.x + p3.y) * p3.z);
        }
        
        float _noise(float2 p) {
            float2 i = floor(p);
            float2 f = fract(p);
            f = f * f * (3.0 - 2.0 * f);
            return mix(
                mix(_hash(i + float2(0, 0)), _hash(i + float2(1, 0)), f.x),
                mix(_hash(i + float2(0, 1)), _hash(i + float2(1, 1)), f.x),
                f.y
            );
        }
        
        float _fbm(float2 p, int octaves) {
            float value = 0.0;
            float amplitude = 0.5;
            for (int i = 0; i < octaves; i++) {
                value += amplitude * _noise(p);
                p *= 2.0;
                amplitude *= 0.5;
            }
            return value;
        }
        
        float3 _hsl2rgb(float3 hsl) {
            float3 rgb = clamp(abs(fmod(hsl.x * 6.0 + float3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
            return hsl.z + hsl.y * (rgb - 0.5) * (1.0 - abs(2.0 * hsl.z - 1.0));
        }
        
        // --- Particle Utility Functions ---
        
        // Deterministic per-particle random (seeded by particle index)
        float _prand(float id, float seed) {
            return fract(sin(id * 127.1 + seed * 311.7) * 43758.5453);
        }
        
        // Soft circle SDF: returns 0.0 outside, 1.0 at center, smooth falloff
        float _circle(float2 p, float radius) {
            return 1.0 - smoothstep(radius * 0.7, radius, length(p));
        }
        
        // Star SDF: n-pointed star shape
        float _star(float2 p, float r, int n, float inset) {
            float an = 3.14159265 / float(n);
            float en = 3.14159265 / (inset == 0.0 ? 3.0 : inset);
            float2 acs = float2(cos(an), sin(an));
            float2 ecs = float2(cos(en), sin(en));
            float bn = fmod(atan2(p.x, p.y), 2.0 * an) - an;
            p = length(p) * float2(cos(bn), abs(sin(bn)));
            p -= r * acs;
            p += ecs * clamp(-dot(p, ecs), 0.0, r * acs.y / ecs.y);
            return length(p) * sign(p.x);
        }
        
        // Physics: position of a particle with velocity, gravity, and drag
        float2 _particlePos(float2 origin, float2 velocity, float gravity, float drag, float t) {
            float df = exp(-drag * t);
            float invDrag = 1.0 / max(drag, 0.001);
            float px = origin.x + velocity.x * invDrag * (1.0 - df);
            float py = origin.y + velocity.y * invDrag * (1.0 - df) + 0.5 * gravity * t * t;
            return float2(px, py);
        }
        
        // Ease-out cubic
        float _easeOut(float t) { float f = 1.0 - t; return 1.0 - f * f * f; }
        
        // --- Vertex Shader (full-screen quad) ---
        
        vertex VertexOut shaderVertex(uint vertexID [[vertex_id]]) {
            float2 positions[4] = {float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1)};
            float2 uvs[4] = {float2(0, 1), float2(1, 1), float2(0, 0), float2(1, 0)};
            VertexOut out;
            out.position = float4(positions[vertexID], 0, 1);
            out.uv = uvs[vertexID];
            return out;
        }
        
        // --- Fragment Shader (AI-generated body) ---
        
        fragment float4 shaderFragment(VertexOut in [[stage_in]],
                                       constant Uniforms &uniforms [[buffer(0)]]) {
            float2 uv = in.uv;
            float time = uniforms.time;
            float2 resolution = uniforms.resolution;
            float4 color1 = uniforms.color1;
            float4 color2 = uniforms.color2;
            float param1 = uniforms.param1;
            float param2 = uniforms.param2;
            float param3 = uniforms.param3;
            float param4 = uniforms.param4;
            
            // Aspect ratio: use to correct UV coordinates for non-square canvases.
            // e.g. float2 st = (uv - 0.5) * float2(aspect, 1.0); makes circles circular.
            float aspect = resolution.x / resolution.y;
            
            // Suppress unused variable warnings (AI may not use all uniforms)
            (void)uv; (void)time; (void)resolution; (void)aspect;
            (void)color1; (void)color2;
            (void)param1; (void)param2; (void)param3; (void)param4;
            
            // ===== AI-GENERATED CODE =====
            \(body)
            // ===== END AI CODE =====
        }
        """
    }
}
