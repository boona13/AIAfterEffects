//
//  ProceduralEffectService.swift
//  AIAfterEffects
//
//  Bridges the LLM's `applyEffect` action to the procedural generators.
//  Converts ActionParameters into generator configs, executes them,
//  and returns SceneActions for the CanvasViewModel to process.
//

import Foundation

struct ProceduralEffectService {
    
    /// Processes an `applyEffect` action and returns the expanded SceneActions.
    /// If the LLM provided `shaderCode`, creates a shader object directly (AI-driven).
    /// Otherwise falls back to non-particle procedural effects (spring, path, morph).
    static func processEffect(
        params: ActionParameters,
        originObject: (x: Double, y: Double, width: Double, height: Double)?,
        startTime: Double
    ) -> [SceneAction] {
        let effectType = params.effectType?.lowercased() ?? ""
        
        // AI-authored particle/effect shader: the LLM wrote the Metal code
        let particleEffects: Set<String> = [
            "particleburst", "burst", "particles",
            "splash", "watersplash", "impact",
            "shatter", "explode", "fragment",
            "sparks", "fire", "smoke", "rain", "snow", "confetti",
            "energywave", "shockwave", "ripplewave"
        ]
        if particleEffects.contains(effectType) || params.shaderCode != nil {
            return processShaderEffect(params: params, origin: originObject, startTime: startTime)
        }
        
        switch effectType {
        case "trail", "ghost", "afterimage":
            return processTrail(params: params, origin: originObject, startTime: startTime)
            
        case "motionpath", "arc", "curve", "path":
            return processMotionPath(params: params, origin: originObject, startTime: startTime)
            
        case "spring", "springscale", "springbounce":
            return processSpring(params: params, startTime: startTime)
            
        case "pathmorph", "morph", "shapetransition":
            return processPathMorph(params: params, startTime: startTime)
            
        default:
            DebugLogger.shared.warning("[ProceduralEffect] Unknown effect type: '\(effectType)'")
            return []
        }
    }
    
    // MARK: - AI-Authored Shader Effect
    
    private static func processShaderEffect(
        params: ActionParameters,
        origin: (x: Double, y: Double, width: Double, height: Double)?,
        startTime: Double
    ) -> [SceneAction] {
        let name = params.effectiveName ?? "effect_\(Int.random(in: 1000...9999))"
        
        guard let shaderCode = params.shaderCode, !shaderCode.isEmpty else {
            DebugLogger.shared.warning(
                "[ProceduralEffect] Particle effect '\(name)' has no shaderCode — the AI must write the Metal shader. Skipping.",
                category: .canvas
            )
            return []
        }
        
        var createParams = ActionParameters()
        createParams.objectType = "shader"
        createParams.name = name
        createParams.shaderCode = shaderCode
        createParams.opacity = 1.0
        createParams.zIndex = params.zIndex ?? 100
        createParams.shaderParam1 = params.shaderParam1 ?? startTime
        createParams.shaderParam2 = params.shaderParam2 ?? (params.effectLifetime ?? 2.0)
        createParams.shaderParam3 = params.shaderParam3 ?? 0.0
        createParams.shaderParam4 = params.shaderParam4 ?? 0.0
        
        if let color = params.fillColor {
            createParams.fillColor = color
        }
        if let color2 = params.strokeColor {
            createParams.strokeColor = color2
        }
        
        return [SceneAction(type: .createObject, target: nil, parameters: createParams)]
    }
    
    // MARK: - Trail
    
    private static func processTrail(
        params: ActionParameters,
        origin: (x: Double, y: Double, width: Double, height: Double)?,
        startTime: Double
    ) -> [SceneAction] {
        var config = TrailConfig()
        config.ghostCount = params.effectCount ?? 4
        config.startTime = startTime
        config.namePrefix = params.effectiveName ?? "trail"
        
        if let color = params.effectiveFillColor {
            config.color = color.toCodableColor()
        }
        
        let trails = ParticleGenerator.generateTrail(
            parentAnimations: [],
            parentPosition: (x: origin?.x ?? 540, y: origin?.y ?? 540),
            parentSize: (w: origin?.width ?? 50, h: origin?.height ?? 50),
            config: config
        )
        return convertToSceneActions(trails)
    }
    
    // MARK: - Motion Path
    
    private static func processMotionPath(
        params: ActionParameters,
        origin: (x: Double, y: Double, width: Double, height: Double)?,
        startTime: Double
    ) -> [SceneAction] {
        guard let targetName = params.effectiveName else { return [] }
        
        let duration = params.duration ?? 2.0
        let easing: EasingType = .linear  // Dense keyframes provide their own easing
        
        var moveXFrames: [Keyframe]
        var moveYFrames: [Keyframe]
        
        if let points = params.controlPoints, points.count >= 2 {
            let pathPoints = points.map { pt in
                MotionPathPoint(x: pt["x"] ?? 0, y: pt["y"] ?? 0, time: pt["time"] ?? 0)
            }
            let result = MotionPathGenerator.generateKeyframes(controlPoints: pathPoints)
            moveXFrames = result.moveX
            moveYFrames = result.moveY
        } else {
            let fromX = origin?.x ?? 540
            let fromY = origin?.y ?? 540
            let toX = params.x ?? fromX + 200
            let toY = params.y ?? fromY
            let arcH = params.effectArcHeight ?? -100
            
            let result = MotionPathGenerator.arcPath(
                from: (x: fromX, y: fromY),
                to: (x: toX, y: toY),
                arcHeight: arcH
            )
            moveXFrames = result.moveX
            moveYFrames = result.moveY
        }
        
        var animParams = ActionParameters()
        animParams.animationType = "moveX"
        animParams.startTime = startTime
        animParams.duration = duration
        animParams.easing = "linear"
        animParams.keyframes = moveXFrames.map { kf in
            KeyframeParameter(time: kf.time, value: AnimationValue(doubleValue: kf.value.doubleVal))
        }
        
        let moveXAction = SceneAction(
            type: .addAnimation,
            target: targetName,
            parameters: animParams
        )
        
        var animParamsY = ActionParameters()
        animParamsY.animationType = "moveY"
        animParamsY.startTime = startTime
        animParamsY.duration = duration
        animParamsY.easing = "linear"
        animParamsY.keyframes = moveYFrames.map { kf in
            KeyframeParameter(time: kf.time, value: AnimationValue(doubleValue: kf.value.doubleVal))
        }
        
        let moveYAction = SceneAction(
            type: .addAnimation,
            target: targetName,
            parameters: animParamsY
        )
        
        return [moveXAction, moveYAction]
    }
    
    // MARK: - Spring
    
    private static func processSpring(
        params: ActionParameters,
        startTime: Double
    ) -> [SceneAction] {
        guard let targetName = params.effectiveName else { return [] }
        
        let fromVal = params.effectiveFromValue.flatMap { fv -> Double? in
            if case .number(let d) = fv { return d }; return nil
        } ?? 0
        let toVal = params.effectiveToValue.flatMap { fv -> Double? in
            if case .number(let d) = fv { return d }; return nil
        } ?? 1
        let stiffness = params.effectStiffness ?? 200
        let damping = params.effectDamping ?? 12
        let animType = params.animationType ?? "scale"
        let duration = params.duration ?? 1.5
        
        let keyframes = SpringSimulator.simulate(
            from: fromVal, to: toVal,
            stiffness: stiffness, damping: damping
        )
        
        var animParams = ActionParameters()
        animParams.animationType = animType
        animParams.startTime = startTime
        animParams.duration = duration
        animParams.easing = "linear"
        animParams.keyframes = keyframes.map { kf in
            KeyframeParameter(time: kf.time, value: AnimationValue(doubleValue: kf.value.doubleVal))
        }
        
        return [SceneAction(type: .addAnimation, target: targetName, parameters: animParams)]
    }
    
    // MARK: - Path Morph
    
    private static func processPathMorph(
        params: ActionParameters,
        startTime: Double
    ) -> [SceneAction] {
        guard let targetName = params.effectiveName else { return [] }
        guard let targetPresetName = params.targetShapePreset,
              let preset = ShapePreset(rawValue: targetPresetName.lowercased()) else { return [] }
        
        let targetPath = preset.commands(points: params.shapePresetPoints ?? 5)
        let duration = params.duration ?? 1.5
        let easingStr = params.easing ?? "easeInOut"
        
        var animParams = ActionParameters()
        animParams.animationType = "pathMorph"
        animParams.startTime = startTime
        animParams.duration = duration
        animParams.easing = easingStr
        animParams.pathData = targetPath
        
        return [SceneAction(type: .addAnimation, target: targetName, parameters: animParams)]
    }
    
    // MARK: - Trail with Parent Animations (called from CanvasViewModel with scene state access)
    
    static func processTrailWithAnimations(
        params: ActionParameters,
        origin: (x: Double, y: Double, width: Double, height: Double),
        parentAnimations: [AnimationDefinition],
        startTime: Double
    ) -> [SceneAction] {
        var config = TrailConfig()
        config.ghostCount = params.effectCount ?? 4
        config.startTime = startTime
        config.namePrefix = params.effectiveName ?? "trail"
        
        if let color = params.effectiveFillColor {
            config.color = color.toCodableColor()
        }
        
        let trails = ParticleGenerator.generateTrail(
            parentAnimations: parentAnimations,
            parentPosition: (x: origin.x, y: origin.y),
            parentSize: (w: origin.width, h: origin.height),
            config: config
        )
        return convertToSceneActions(trails)
    }
    
    // MARK: - Helpers (SwiftUI objects - used for trails)
    
    private static func convertToSceneActions(_ particles: [GeneratedParticleAction]) -> [SceneAction] {
        var actions: [SceneAction] = []
        
        for p in particles {
            var createParams = ActionParameters()
            createParams.objectType = p.objectType
            createParams.name = p.name
            createParams.x = p.x
            createParams.y = p.y
            createParams.width = p.width
            createParams.height = p.height
            createParams.fillColor = ColorParameters(
                red: p.fillColor.red, green: p.fillColor.green,
                blue: p.fillColor.blue, alpha: p.fillColor.alpha
            )
            createParams.opacity = p.opacity
            createParams.shapePreset = p.shapePreset
            createParams.closePath = p.closePath
            createParams.zIndex = p.zIndex
            
            if p.blurRadius > 0 {
                createParams.blurRadius = p.blurRadius
            }
            if p.cornerRadius > 0 {
                createParams.cornerRadius = p.cornerRadius
            }
            if let sc = p.strokeColor {
                createParams.strokeColor = ColorParameters(
                    red: sc.red, green: sc.green, blue: sc.blue, alpha: sc.alpha
                )
            }
            if p.strokeWidth > 0 {
                createParams.strokeWidth = p.strokeWidth
            }
            if let shc = p.shadowColor {
                createParams.shadowColor = ColorParameters(
                    red: shc.red, green: shc.green, blue: shc.blue, alpha: shc.alpha
                )
            }
            if p.shadowRadius > 0 {
                createParams.shadowRadius = p.shadowRadius
            }
            if abs(p.rotation) > 0.01 {
                createParams.rotation = p.rotation
            }
            
            actions.append(SceneAction(type: .createObject, target: nil, parameters: createParams))
            
            for anim in p.animations {
                var animParams = ActionParameters()
                animParams.name = p.name
                animParams.animationType = anim.type.rawValue
                animParams.startTime = anim.startTime
                animParams.duration = anim.duration
                animParams.easing = anim.easing.rawValue
                animParams.repeatCount = anim.repeatCount
                animParams.keyframes = anim.keyframes.map { kf in
                    KeyframeParameter(time: kf.time, value: AnimationValue(doubleValue: kf.value.doubleVal))
                }
                
                actions.append(SceneAction(type: .addAnimation, target: p.name, parameters: animParams))
            }
        }
        
        return actions
    }
}

