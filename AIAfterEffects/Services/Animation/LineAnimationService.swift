//
//  LineAnimationService.swift
//  AIAfterEffects
//
//  Line-based animation presets built from keyframes
//

import Foundation

final class LineAnimationService: LineAnimationServiceProtocol {
    static let shared = LineAnimationService()
    
    private let animationEngine: AnimationEngine
    
    init(animationEngine: AnimationEngine = AnimationEngine()) {
        self.animationEngine = animationEngine
    }
    
    func lineDrawAnimations(
        for object: SceneObject,
        startTime: Double,
        duration: Double?,
        intensity: Double
    ) -> [AnimationDefinition] {
        let drawDuration = max(0.2, duration ?? 0.5)
        let width = max(1, object.properties.width)
        let moveOffset = -width / 2
        
        return [
            makeCustomAnimation(
                type: .scaleX,
                startTime: startTime,
                duration: drawDuration,
                easing: .easeOutCubic,
                keyframes: [
                    Keyframe(time: 0, value: .double(0)),
                    Keyframe(time: 1, value: .double(1))
                ]
            ),
            makeCustomAnimation(
                type: .moveX,
                startTime: startTime,
                duration: drawDuration,
                easing: .easeOutCubic,
                keyframes: [
                    Keyframe(time: 0, value: .double(moveOffset)),
                    Keyframe(time: 1, value: .double(0))
                ]
            ),
            makeEngineAnimation(
                type: .fadeIn,
                startTime: startTime,
                duration: min(0.25, drawDuration * 0.6),
                easing: .easeOut,
                intensity: max(0.8, intensity)
            )
        ]
    }
    
    func lineSweepGlowAnimations(
        for object: SceneObject,
        startTime: Double,
        duration: Double?,
        intensity: Double
    ) -> [AnimationDefinition] {
        let drawDuration = max(0.25, duration ?? 0.6)
        var animations = lineDrawAnimations(
            for: object,
            startTime: startTime,
            duration: drawDuration,
            intensity: intensity
        )
        
        animations.append(
            makeEngineAnimation(
                type: .flash,
                startTime: startTime + drawDuration * 0.2,
                duration: min(0.3, drawDuration * 0.6),
                easing: .easeOutExpo,
                intensity: max(0.9, intensity)
            )
        )
        
        animations.append(
            makeEngineAnimation(
                type: .pulse,
                startTime: startTime + drawDuration * 0.6,
                duration: 0.9,
                easing: .easeInOut,
                intensity: max(0.7, intensity),
                repeatCount: 1
            )
        )
        
        return animations
    }
    
    func lineUnderlineAnimations(
        for object: SceneObject,
        startTime: Double,
        duration: Double?,
        intensity: Double
    ) -> [AnimationDefinition] {
        let drawDuration = max(0.2, duration ?? 0.35)
        let hold = max(0.2, drawDuration * 0.7)
        let exitStart = startTime + drawDuration + hold
        
        var animations = lineDrawAnimations(
            for: object,
            startTime: startTime,
            duration: drawDuration,
            intensity: intensity
        )
        
        animations.append(
            makeEngineAnimation(
                type: .fadeOut,
                startTime: exitStart,
                duration: 0.25,
                easing: .easeInCubic,
                intensity: 1
            )
        )
        
        animations.append(
            makeEngineAnimation(
                type: .slideOut,
                startTime: exitStart,
                duration: 0.3,
                easing: .easeInCubic,
                intensity: max(0.7, intensity)
            )
        )
        
        return animations
    }
    
    func lineStackStaggerAnimations(
        for object: SceneObject,
        startTime: Double,
        duration: Double?,
        intensity: Double
    ) -> [AnimationDefinition] {
        let drawDuration = max(0.18, duration ?? 0.28)
        var animations = lineDrawAnimations(
            for: object,
            startTime: startTime,
            duration: drawDuration,
            intensity: intensity
        )
        
        animations.append(
            makeEngineAnimation(
                type: .fadeIn,
                startTime: startTime,
                duration: min(0.2, drawDuration * 0.7),
                easing: .easeOut,
                intensity: 1
            )
        )
        
        return animations
    }
    
    private func makeCustomAnimation(
        type: AnimationType,
        startTime: Double,
        duration: Double,
        easing: EasingType,
        keyframes: [Keyframe],
        repeatCount: Int = 0
    ) -> AnimationDefinition {
        AnimationDefinition(
            type: type,
            startTime: startTime,
            duration: duration,
            easing: easing,
            keyframes: keyframes,
            repeatCount: repeatCount,
            autoReverse: false,
            delay: 0
        )
    }
    
    private func makeEngineAnimation(
        type: AnimationType,
        startTime: Double,
        duration: Double,
        easing: EasingType,
        intensity: Double,
        repeatCount: Int = 0
    ) -> AnimationDefinition {
        let keyframes = animationEngine.defaultKeyframes(for: type).map { kf in
            var value = kf.value
            switch value {
            case .double(let d):
                value = .double(d * intensity)
            case .point(let x, let y):
                value = .point(x: x * intensity, y: y * intensity)
            case .scale(let x, let y):
                value = .scale(x: x * max(0.1, intensity), y: y * max(0.1, intensity))
            case .color:
                break
            }
            return Keyframe(time: kf.time, value: value)
        }
        
        return AnimationDefinition(
            type: type,
            startTime: startTime,
            duration: duration,
            easing: easing,
            keyframes: keyframes,
            repeatCount: repeatCount,
            autoReverse: false,
            delay: 0
        )
    }
}
