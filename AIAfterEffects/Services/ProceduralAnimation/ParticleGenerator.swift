//
//  ParticleGenerator.swift
//  AIAfterEffects
//
//  Generates arrays of SceneActions that create particle systems:
//  bursts, splashes, trails, and shatter effects.
//  Each particle is a real scene object with physics-baked keyframes.
//

import Foundation

struct ParticleConfig {
    var origin: (x: Double, y: Double)
    var count: Int = 15
    var spreadAngle: Double = 360       // degrees — 360 = all directions, 90 = cone
    var directionAngle: Double = -90    // degrees — base direction (0=right, -90=up)
    var minVelocity: Double = 150
    var maxVelocity: Double = 400
    var gravity: Double = 600
    var drag: Double = 0.02
    var lifetime: Double = 1.5
    var particleSize: Double = 8
    var particleSizeVariance: Double = 4
    var color: CodableColor = .white
    var colorVariance: Double = 0.1
    var shape: String = "circle"        // "circle", "rectangle", or any ShapePreset name
    var fadeOut: Bool = true
    var shrink: Bool = true
    var spin: Bool = false
    var startTime: Double = 0
    var namePrefix: String = "particle"
}

struct SplashConfig {
    var impactPoint: (x: Double, y: Double)
    var surfaceAngle: Double = 0        // degrees — 0 = horizontal surface
    var dropletCount: Int = 12
    var energy: Double = 1.0            // multiplier for velocity
    var gravity: Double = 800
    var dropletSize: Double = 6
    var color: CodableColor = .white
    var startTime: Double = 0
    var namePrefix: String = "splash"
}

struct ShatterConfig {
    var sourceRect: (x: Double, y: Double, width: Double, height: Double)
    var fragmentCount: Int = 12
    var explosionForce: Double = 300
    var gravity: Double = 500
    var lifetime: Double = 2.0
    var color: CodableColor = .white
    var startTime: Double = 0
    var namePrefix: String = "fragment"
}

struct TrailConfig {
    var ghostCount: Int = 4
    var fadeStep: Double = 0.2
    var delayStep: Double = 0.05
    var sizeDecay: Double = 0.95
    var color: CodableColor = .white
    var startTime: Double = 0
    var namePrefix: String = "trail"
}

// MARK: - Generated Output

struct GeneratedParticleAction {
    let objectType: String
    let name: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let fillColor: CodableColor
    let opacity: Double
    let shapePreset: String?
    let closePath: Bool
    let animations: [AnimationDefinition]
    let zIndex: Int
    var blurRadius: Double = 0
    var cornerRadius: Double = 0
    var strokeColor: CodableColor? = nil
    var strokeWidth: Double = 0
    var shadowColor: CodableColor? = nil
    var shadowRadius: Double = 0
    var rotation: Double = 0
}

// MARK: - Particle Tier (hero, mid, dust)

private enum ParticleTier {
    case hero   // few large, glowing, dramatic
    case mid    // medium count, standard
    case dust   // many tiny, subtle fill
    
    var sizeMultiplier: Double {
        switch self {
        case .hero: return 2.5
        case .mid: return 1.0
        case .dust: return 0.35
        }
    }
    
    var blurMultiplier: Double {
        switch self {
        case .hero: return 1.0
        case .mid: return 0.4
        case .dust: return 0.0
        }
    }
    
    var glowIntensity: Double {
        switch self {
        case .hero: return 1.0
        case .mid: return 0.5
        case .dust: return 0.0
        }
    }
}

struct ParticleGenerator {
    
    // MARK: - Particle Burst
    
    static func generateBurst(config: ParticleConfig) -> [GeneratedParticleAction] {
        var results: [GeneratedParticleAction] = []
        
        // Sanitize velocity bounds — LLM may set max < min
        let vMin = min(config.minVelocity, config.maxVelocity)
        let vMax = max(config.minVelocity, config.maxVelocity, vMin + 1)
        
        let heroCount = max(1, config.count / 6)
        let midCount = config.count / 2
        let dustCount = config.count - heroCount - midCount
        
        let tiers: [(tier: ParticleTier, count: Int)] = [
            (.hero, heroCount),
            (.mid, midCount),
            (.dust, dustCount)
        ]
        
        var particleIndex = 0
        let halfSpread = config.spreadAngle / 2
        let baseAngleRad = config.directionAngle * .pi / 180
        
        for (tier, count) in tiers {
            for _ in 0..<count {
                let angleOffset = Double.random(in: -halfSpread...halfSpread) * .pi / 180
                let angle = baseAngleRad + angleOffset
                
                let velocityRange: ClosedRange<Double>
                switch tier {
                case .hero: velocityRange = (vMin * 0.6)...max(vMin * 0.6, vMax * 0.8)
                case .mid:  velocityRange = vMin...vMax
                case .dust: velocityRange = (vMax * 0.8)...(vMax * 1.3)
                }
                
                let velocity = Double.random(in: velocityRange)
                let vx = cos(angle) * velocity
                let vy = sin(angle) * velocity
                let speed = velocity
                
                let baseSize = max(2, config.particleSize + Double.random(in: -config.particleSizeVariance...config.particleSizeVariance))
                let size = baseSize * tier.sizeMultiplier
                let lifetime = config.lifetime * Double.random(in: 0.6...1.0)
                
                // Stagger: hero first, dust last with wider spread
                let stagger: Double
                switch tier {
                case .hero: stagger = Double.random(in: 0...0.03)
                case .mid:  stagger = Double.random(in: 0.01...0.06)
                case .dust: stagger = Double.random(in: 0.02...0.1)
                }
                
                let (moveXFrames, moveYFrames) = simulatePhysics(
                    vx: vx, vy: vy,
                    gravity: config.gravity * (tier == .dust ? 1.3 : 1.0),
                    drag: config.drag * (tier == .hero ? 0.5 : 1.0),
                    duration: lifetime,
                    sampleCount: tier == .hero ? 30 : 20
                )
                
                var animations: [AnimationDefinition] = []
                let animStart = config.startTime + stagger
                
                // Position X
                animations.append(AnimationDefinition(
                    type: .moveX, startTime: animStart, duration: lifetime,
                    easing: .linear, keyframes: moveXFrames
                ))
                
                // Position Y
                animations.append(AnimationDefinition(
                    type: .moveY, startTime: animStart, duration: lifetime,
                    easing: .linear, keyframes: moveYFrames
                ))
                
                // Fade out — hero particles linger, dust vanishes quickly
                if config.fadeOut {
                    let fadeDelay: Double
                    let fadeDuration: Double
                    switch tier {
                    case .hero:
                        fadeDelay = lifetime * 0.5
                        fadeDuration = lifetime * 0.5
                    case .mid:
                        fadeDelay = lifetime * 0.35
                        fadeDuration = lifetime * 0.65
                    case .dust:
                        fadeDelay = lifetime * 0.2
                        fadeDuration = lifetime * 0.8
                    }
                    animations.append(AnimationDefinition(
                        type: .fade, startTime: animStart + fadeDelay, duration: fadeDuration,
                        easing: .easeIn,
                        keyframes: [
                            Keyframe(time: 0, value: .double(tier == .hero ? 0.9 : 1.0)),
                            Keyframe(time: 1, value: .double(0))
                        ]
                    ))
                }
                
                // Shrink — hero particles keep presence, dust shrinks fast
                if config.shrink {
                    let shrinkDelay = tier == .hero ? lifetime * 0.6 : lifetime * 0.2
                    animations.append(AnimationDefinition(
                        type: .scale, startTime: animStart + shrinkDelay, duration: lifetime - shrinkDelay,
                        easing: tier == .hero ? .easeInOut : .easeIn,
                        keyframes: [
                            Keyframe(time: 0, value: .double(1)),
                            Keyframe(time: 1, value: .double(tier == .hero ? 0.3 : 0.05))
                        ]
                    ))
                }
                
                // Twinkle for hero/mid — rapid opacity flicker during flight
                if tier == .hero || (tier == .mid && Bool.random()) {
                    let flickerCount = tier == .hero ? 4 : 2
                    let flickerDuration = lifetime * 0.4
                    var flickerFrames: [Keyframe] = []
                    for f in 0...flickerCount {
                        let t = Double(f) / Double(flickerCount)
                        let val = f % 2 == 0 ? 1.0 : Double.random(in: 0.4...0.7)
                        flickerFrames.append(Keyframe(time: t, value: .double(val)))
                    }
                    animations.append(AnimationDefinition(
                        type: .fade, startTime: animStart, duration: flickerDuration,
                        easing: .linear, keyframes: flickerFrames
                    ))
                }
                
                // Spin — hero particles rotate slowly, dust spins fast
                let shouldSpin = config.spin || tier == .dust || (tier == .mid && Bool.random())
                if shouldSpin {
                    let spinDirection = Bool.random() ? 1.0 : -1.0
                    let spinAmount: Double
                    switch tier {
                    case .hero: spinAmount = Double.random(in: 45...180) * spinDirection
                    case .mid:  spinAmount = Double.random(in: 180...540) * spinDirection
                    case .dust: spinAmount = Double.random(in: 360...1080) * spinDirection
                    }
                    animations.append(AnimationDefinition(
                        type: .rotate, startTime: animStart, duration: lifetime, easing: .easeOut,
                        keyframes: [
                            Keyframe(time: 0, value: .double(0)),
                            Keyframe(time: 1, value: .double(spinAmount))
                        ]
                    ))
                }
                
                let color = varyColor(config.color, variance: config.colorVariance)
                let isPreset = ShapePreset(rawValue: config.shape.lowercased()) != nil
                let objectType: String
                let shapePreset: String?
                
                switch tier {
                case .hero where !isPreset:
                    objectType = "circle"
                    shapePreset = nil
                case .dust:
                    objectType = "circle"
                    shapePreset = nil
                default:
                    objectType = isPreset ? "path" : config.shape
                    shapePreset = isPreset ? config.shape.lowercased() : nil
                }
                
                // Motion-blur elongation: stretch particle along its velocity direction
                let elongation: Double
                let initialRotation: Double
                switch tier {
                case .hero:
                    elongation = 1.0
                    initialRotation = 0
                case .mid:
                    let speedFactor = min(speed / config.maxVelocity, 1.0)
                    elongation = 1.0 + speedFactor * 1.8
                    initialRotation = atan2(vy, vx) * 180 / .pi
                case .dust:
                    let speedFactor = min(speed / config.maxVelocity, 1.0)
                    elongation = 1.0 + speedFactor * 2.5
                    initialRotation = atan2(vy, vx) * 180 / .pi
                }
                
                let particleWidth = size * elongation
                let particleHeight = size
                
                // Glow: soft blur on hero particles
                let blur = size * tier.blurMultiplier * 0.6
                
                // Glow halo via shadow
                let glowColor: CodableColor? = tier.glowIntensity > 0 ? color : nil
                let glowRadius = tier == .hero ? size * 0.8 : (tier == .mid ? size * 0.3 : 0)
                
                results.append(GeneratedParticleAction(
                    objectType: objectType,
                    name: "\(config.namePrefix)_\(particleIndex)",
                    x: config.origin.x,
                    y: config.origin.y,
                    width: particleWidth,
                    height: particleHeight,
                    fillColor: color,
                    opacity: 1.0,
                    shapePreset: shapePreset,
                    closePath: true,
                    animations: animations,
                    zIndex: tier == .hero ? 110 + particleIndex : 100 + particleIndex,
                    blurRadius: blur,
                    cornerRadius: elongation > 1.3 ? particleHeight * 0.5 : 0,
                    strokeColor: nil,
                    strokeWidth: 0,
                    shadowColor: glowColor,
                    shadowRadius: glowRadius,
                    rotation: initialRotation
                ))
                
                particleIndex += 1
            }
        }
        
        return results
    }
    
    // MARK: - Splash (Impact)
    
    static func generateSplash(config: SplashConfig) -> [GeneratedParticleAction] {
        let surfaceRad = config.surfaceAngle * .pi / 180
        let normalAngle = surfaceRad - .pi / 2
        
        var burstConfig = ParticleConfig(origin: config.impactPoint)
        burstConfig.count = config.dropletCount
        burstConfig.spreadAngle = 140
        burstConfig.directionAngle = normalAngle * 180 / .pi
        burstConfig.minVelocity = 80 * config.energy
        burstConfig.maxVelocity = 300 * config.energy
        burstConfig.gravity = config.gravity
        burstConfig.particleSize = config.dropletSize
        burstConfig.particleSizeVariance = config.dropletSize * 0.6
        burstConfig.color = config.color
        burstConfig.shape = "circle"
        burstConfig.fadeOut = true
        burstConfig.shrink = false
        burstConfig.startTime = config.startTime
        burstConfig.namePrefix = config.namePrefix
        burstConfig.lifetime = 1.4
        burstConfig.drag = 0.008
        
        var droplets = generateBurst(config: burstConfig)
        
        // Add a central splash crown ring
        let crownSize = config.dropletSize * 4
        var crownAnims: [AnimationDefinition] = []
        crownAnims.append(AnimationDefinition(
            type: .scale, startTime: config.startTime, duration: 0.4, easing: .easeOutExpo,
            keyframes: [
                Keyframe(time: 0, value: .double(0.2)),
                Keyframe(time: 1, value: .double(3.0))
            ]
        ))
        crownAnims.append(AnimationDefinition(
            type: .fade, startTime: config.startTime, duration: 0.5, easing: .easeIn,
            keyframes: [
                Keyframe(time: 0, value: .double(0.7)),
                Keyframe(time: 1, value: .double(0))
            ]
        ))
        
        droplets.append(GeneratedParticleAction(
            objectType: "circle",
            name: "\(config.namePrefix)_crown",
            x: config.impactPoint.x,
            y: config.impactPoint.y,
            width: crownSize,
            height: crownSize,
            fillColor: CodableColor(red: config.color.red, green: config.color.green, blue: config.color.blue, alpha: 0),
            opacity: 0.7,
            shapePreset: nil,
            closePath: false,
            animations: crownAnims,
            zIndex: 115,
            blurRadius: crownSize * 0.3,
            strokeColor: config.color,
            strokeWidth: 2
        ))
        
        return droplets
    }
    
    // MARK: - Shatter (Fragmentation)
    
    static func generateShatter(config: ShatterConfig) -> [GeneratedParticleAction] {
        var results: [GeneratedParticleAction] = []
        let cx = config.sourceRect.x
        let cy = config.sourceRect.y
        let hw = config.sourceRect.width / 2
        let hh = config.sourceRect.height / 2
        
        for i in 0..<config.fragmentCount {
            let fragX = cx + Double.random(in: -hw...hw)
            let fragY = cy + Double.random(in: -hh...hh)
            
            let dx = fragX - cx
            let dy = fragY - cy
            let dist = max(1, sqrt(dx * dx + dy * dy))
            let normDx = dx / dist
            let normDy = dy / dist
            let velocity = config.explosionForce * Double.random(in: 0.5...1.5)
            let vx = normDx * velocity + Double.random(in: -50...50)
            let vy = normDy * velocity + Double.random(in: -80...30)
            
            let fragSize = max(4, min(hw, hh) * Double.random(in: 0.15...0.4))
            let lifetime = config.lifetime * Double.random(in: 0.7...1.0)
            let stagger = Double(i) * 0.012
            
            let (moveXFrames, moveYFrames) = simulatePhysics(
                vx: vx, vy: vy,
                gravity: config.gravity,
                drag: 0.01,
                duration: lifetime,
                sampleCount: 25
            )
            
            var animations: [AnimationDefinition] = []
            let animStart = config.startTime + stagger
            
            animations.append(AnimationDefinition(
                type: .moveX, startTime: animStart, duration: lifetime, easing: .linear, keyframes: moveXFrames
            ))
            animations.append(AnimationDefinition(
                type: .moveY, startTime: animStart, duration: lifetime, easing: .linear, keyframes: moveYFrames
            ))
            
            // Multi-axis spin for tumbling
            let spinAmount = Double.random(in: -720...720)
            animations.append(AnimationDefinition(
                type: .rotate, startTime: animStart, duration: lifetime, easing: .easeOut,
                keyframes: [
                    Keyframe(time: 0, value: .double(0)),
                    Keyframe(time: 1, value: .double(spinAmount))
                ]
            ))
            
            // Scale wobble during flight (squash/stretch on tumble)
            let wobbleFrames: [Keyframe] = [
                Keyframe(time: 0, value: .double(1.0)),
                Keyframe(time: 0.15, value: .double(0.7)),
                Keyframe(time: 0.3, value: .double(1.1)),
                Keyframe(time: 0.5, value: .double(0.85)),
                Keyframe(time: 0.7, value: .double(1.0)),
                Keyframe(time: 1.0, value: .double(0.6))
            ]
            animations.append(AnimationDefinition(
                type: .scale, startTime: animStart, duration: lifetime, easing: .linear,
                keyframes: wobbleFrames
            ))
            
            // Fade near end
            animations.append(AnimationDefinition(
                type: .fade, startTime: animStart + lifetime * 0.55, duration: lifetime * 0.45, easing: .easeIn,
                keyframes: [
                    Keyframe(time: 0, value: .double(1)),
                    Keyframe(time: 1, value: .double(0))
                ]
            ))
            
            let color = varyColor(config.color, variance: 0.15)
            let aspectRatio = Double.random(in: 0.3...1.0)
            
            results.append(GeneratedParticleAction(
                objectType: "rectangle",
                name: "\(config.namePrefix)_\(i)",
                x: fragX,
                y: fragY,
                width: fragSize,
                height: fragSize * aspectRatio,
                fillColor: color,
                opacity: 1.0,
                shapePreset: nil,
                closePath: false,
                animations: animations,
                zIndex: 100 + i,
                cornerRadius: fragSize * 0.1,
                shadowColor: CodableColor(red: color.red, green: color.green, blue: color.blue, alpha: 0.5),
                shadowRadius: fragSize * 0.3
            ))
        }
        
        // Flash core at detonation point
        var flashAnims: [AnimationDefinition] = []
        flashAnims.append(AnimationDefinition(
            type: .scale, startTime: config.startTime, duration: 0.3, easing: .easeOutExpo,
            keyframes: [
                Keyframe(time: 0, value: .double(0.5)),
                Keyframe(time: 1, value: .double(4.0))
            ]
        ))
        flashAnims.append(AnimationDefinition(
            type: .fade, startTime: config.startTime, duration: 0.4, easing: .easeIn,
            keyframes: [
                Keyframe(time: 0, value: .double(0.8)),
                Keyframe(time: 1, value: .double(0))
            ]
        ))
        
        let flashSize = max(hw, hh) * 0.5
        results.append(GeneratedParticleAction(
            objectType: "circle",
            name: "\(config.namePrefix)_flash",
            x: cx,
            y: cy,
            width: flashSize,
            height: flashSize,
            fillColor: CodableColor(red: 1, green: 1, blue: 1, alpha: 1),
            opacity: 0.8,
            shapePreset: nil,
            closePath: false,
            animations: flashAnims,
            zIndex: 120,
            blurRadius: flashSize * 0.8,
            shadowColor: config.color,
            shadowRadius: flashSize
        ))
        
        return results
    }
    
    // MARK: - Trail (Ghost Copies)
    
    static func generateTrail(
        parentAnimations: [AnimationDefinition],
        parentPosition: (x: Double, y: Double),
        parentSize: (w: Double, h: Double),
        config: TrailConfig
    ) -> [GeneratedParticleAction] {
        var results: [GeneratedParticleAction] = []
        
        let moveXAnim = parentAnimations.first(where: { $0.type == .moveX })
        let moveYAnim = parentAnimations.first(where: { $0.type == .moveY })
        
        for i in 0..<config.ghostCount {
            let ghostIndex = i + 1
            let delay = config.delayStep * Double(ghostIndex)
            let opacity = max(0.05, 1.0 - config.fadeStep * Double(ghostIndex))
            let sizeMult = pow(config.sizeDecay, Double(ghostIndex))
            
            var animations: [AnimationDefinition] = []
            
            if let mx = moveXAnim {
                var delayed = mx
                delayed.delay += delay
                animations.append(delayed)
            }
            if let my = moveYAnim {
                var delayed = my
                delayed.delay += delay
                animations.append(delayed)
            }
            
            // Gradual fade rather than constant
            let trailLifetime = (moveXAnim?.duration ?? moveYAnim?.duration ?? 2.0) + delay
            animations.append(AnimationDefinition(
                type: .fade, startTime: config.startTime,
                duration: trailLifetime,
                easing: .easeIn,
                keyframes: [
                    Keyframe(time: 0, value: .double(opacity)),
                    Keyframe(time: 0.7, value: .double(opacity * 0.5)),
                    Keyframe(time: 1, value: .double(0))
                ]
            ))
            
            results.append(GeneratedParticleAction(
                objectType: "circle",
                name: "\(config.namePrefix)_\(i)",
                x: parentPosition.x,
                y: parentPosition.y,
                width: parentSize.w * sizeMult,
                height: parentSize.h * sizeMult,
                fillColor: config.color,
                opacity: opacity,
                shapePreset: nil,
                closePath: false,
                animations: animations,
                zIndex: 90 - i,
                blurRadius: parentSize.w * sizeMult * 0.2
            ))
        }
        
        return results
    }
    
    // MARK: - Physics Simulation
    
    private static func simulatePhysics(
        vx: Double,
        vy: Double,
        gravity: Double,
        drag: Double,
        duration: Double,
        sampleCount: Int
    ) -> (moveX: [Keyframe], moveY: [Keyframe]) {
        var currentVx = vx
        var currentVy = vy
        var posX = 0.0
        var posY = 0.0
        let dt = 1.0 / 60.0
        
        var xPositions: [(time: Double, value: Double)] = [(0, 0)]
        var yPositions: [(time: Double, value: Double)] = [(0, 0)]
        
        let totalSteps = Int(duration / dt)
        let sampleInterval = max(1, totalSteps / (sampleCount - 1))
        
        for step in 1...totalSteps {
            currentVx *= (1.0 - drag)
            currentVy *= (1.0 - drag)
            currentVy += gravity * dt
            posX += currentVx * dt
            posY += currentVy * dt
            
            if step % sampleInterval == 0 || step == totalSteps {
                let t = min(1.0, Double(step) / Double(totalSteps))
                xPositions.append((t, posX))
                yPositions.append((t, posY))
            }
        }
        
        let moveXFrames = xPositions.map { Keyframe(time: $0.time, value: .double($0.value)) }
        let moveYFrames = yPositions.map { Keyframe(time: $0.time, value: .double($0.value)) }
        
        return (moveXFrames, moveYFrames)
    }
    
    // MARK: - Color Variance
    
    private static func varyColor(_ base: CodableColor, variance: Double) -> CodableColor {
        CodableColor(
            red: max(0, min(1, base.red + Double.random(in: -variance...variance))),
            green: max(0, min(1, base.green + Double.random(in: -variance...variance))),
            blue: max(0, min(1, base.blue + Double.random(in: -variance...variance))),
            alpha: base.alpha
        )
    }
    
    // MARK: - GPU Particle Data Generation
    
    static func generateGPUBurstData(config: ParticleConfig) -> [ParticleSystemData.ParticleData] {
        let vMin = min(config.minVelocity, config.maxVelocity)
        let vMax = max(config.minVelocity, config.maxVelocity, vMin + 1)
        
        let heroCount = max(1, config.count / 6)
        let midCount = config.count / 2
        let dustCount = config.count - heroCount - midCount
        
        let tiers: [(tier: ParticleTier, count: Int, tierVal: Int)] = [
            (.hero, heroCount, 0), (.mid, midCount, 1), (.dust, dustCount, 2)
        ]
        
        var particles: [ParticleSystemData.ParticleData] = []
        let halfSpread = config.spreadAngle / 2
        let baseAngleRad = config.directionAngle * .pi / 180
        
        for (tier, count, tierVal) in tiers {
            for _ in 0..<count {
                let angleOffset = Double.random(in: -halfSpread...halfSpread) * .pi / 180
                let angle = baseAngleRad + angleOffset
                
                let velocityRange: ClosedRange<Double>
                switch tier {
                case .hero: velocityRange = (vMin * 0.6)...max(vMin * 0.6, vMax * 0.8)
                case .mid:  velocityRange = vMin...vMax
                case .dust: velocityRange = (vMax * 0.8)...(vMax * 1.3)
                }
                
                let velocity = Double.random(in: velocityRange)
                let vx = cos(angle) * velocity
                let vy = sin(angle) * velocity
                
                let baseSize = max(2, config.particleSize + Double.random(in: -config.particleSizeVariance...config.particleSizeVariance))
                let size = baseSize * tier.sizeMultiplier
                let lifetime = config.lifetime * Double.random(in: 0.6...1.0)
                
                let stagger: Double
                switch tier {
                case .hero: stagger = Double.random(in: 0...0.03)
                case .mid:  stagger = Double.random(in: 0.01...0.06)
                case .dust: stagger = Double.random(in: 0.02...0.1)
                }
                
                let fadeDelay: Double
                switch tier {
                case .hero: fadeDelay = lifetime * 0.5
                case .mid:  fadeDelay = lifetime * 0.35
                case .dust: fadeDelay = lifetime * 0.2
                }
                
                let elongation: Double
                let initRotation: Double
                if tier != .hero {
                    let speed = sqrt(vx * vx + vy * vy)
                    elongation = min(3.0, 1.0 + speed / 300.0)
                    initRotation = atan2(vy, vx)
                } else {
                    elongation = 1.0
                    initRotation = 0
                }
                
                let spinSpeed = config.spin ? Double.random(in: -6...6) * (tier == .dust ? 2.0 : 0.5) : 0
                let drag = config.drag * (tier == .hero ? 0.5 : 1.0)
                let gravity = config.gravity * (tier == .dust ? 1.3 : 1.0)
                let color = varyColor(config.color, variance: config.colorVariance)
                let glowRadius = tier == .hero ? size * 0.8 : 0
                
                particles.append(ParticleSystemData.ParticleData(
                    originX: config.origin.x,
                    originY: config.origin.y,
                    velocityX: vx,
                    velocityY: vy,
                    gravity: gravity,
                    drag: drag,
                    delay: stagger,
                    lifetime: lifetime,
                    fadeDelay: fadeDelay,
                    size: size,
                    elongation: elongation,
                    initialRotation: initRotation,
                    spinSpeed: spinSpeed,
                    colorR: color.red,
                    colorG: color.green,
                    colorB: color.blue,
                    colorA: color.alpha,
                    glowRadius: glowRadius,
                    tier: tierVal
                ))
            }
        }
        return particles
    }
    
    static func generateGPUShatterData(config: ShatterConfig) -> [ParticleSystemData.ParticleData] {
        var particles: [ParticleSystemData.ParticleData] = []
        let cx = config.sourceRect.x
        let cy = config.sourceRect.y
        
        for _ in 0..<config.fragmentCount {
            let angle = Double.random(in: 0...(2 * .pi))
            let force = config.explosionForce * Double.random(in: 0.4...1.0)
            let vx = cos(angle) * force
            let vy = sin(angle) * force
            let size = Double.random(in: 8...20)
            let lifetime = config.lifetime * Double.random(in: 0.6...1.0)
            let color = varyColor(config.color, variance: 0.1)
            
            particles.append(ParticleSystemData.ParticleData(
                originX: cx + Double.random(in: -config.sourceRect.width/4...config.sourceRect.width/4),
                originY: cy + Double.random(in: -config.sourceRect.height/4...config.sourceRect.height/4),
                velocityX: vx,
                velocityY: vy,
                gravity: config.gravity,
                drag: 0.02,
                delay: Double.random(in: 0...0.05),
                lifetime: lifetime,
                fadeDelay: lifetime * 0.3,
                size: size,
                elongation: min(2.5, 1.0 + abs(force) / 400.0),
                initialRotation: atan2(vy, vx),
                spinSpeed: Double.random(in: -8...8),
                colorR: color.red,
                colorG: color.green,
                colorB: color.blue,
                colorA: color.alpha,
                glowRadius: 0,
                tier: size > 15 ? 0 : (size > 10 ? 1 : 2)
            ))
        }
        return particles
    }
    
    static func generateGPUSplashData(config: SplashConfig) -> [ParticleSystemData.ParticleData] {
        var particles: [ParticleSystemData.ParticleData] = []
        let surfaceRad = config.surfaceAngle * .pi / 180
        let upAngle = surfaceRad - .pi / 2
        
        for _ in 0..<config.dropletCount {
            let spread = Double.random(in: -0.8...0.8)
            let angle = upAngle + spread
            let velocity = config.energy * Double.random(in: 200...500)
            let vx = cos(angle) * velocity
            let vy = sin(angle) * velocity
            let size = config.dropletSize * Double.random(in: 0.5...1.5)
            let lifetime = Double.random(in: 0.8...1.5)
            let color = varyColor(config.color, variance: 0.05)
            
            particles.append(ParticleSystemData.ParticleData(
                originX: config.impactPoint.x + Double.random(in: -10...10),
                originY: config.impactPoint.y,
                velocityX: vx,
                velocityY: vy,
                gravity: config.gravity,
                drag: 0.01,
                delay: Double.random(in: 0...0.04),
                lifetime: lifetime,
                fadeDelay: lifetime * 0.4,
                size: size,
                elongation: min(2.0, 1.0 + abs(velocity) / 400.0),
                initialRotation: atan2(vy, vx),
                spinSpeed: 0,
                colorR: color.red,
                colorG: color.green,
                colorB: color.blue,
                colorA: color.alpha,
                glowRadius: 0,
                tier: size > config.dropletSize ? 0 : 2
            ))
        }
        return particles
    }
}
