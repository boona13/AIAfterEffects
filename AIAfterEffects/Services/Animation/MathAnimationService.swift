//
//  MathAnimationService.swift
//  AIAfterEffects
//
//  Math/trig-based animation presets built from keyframes
//

import Foundation

final class MathAnimationService: MathAnimationServiceProtocol {
    static let shared = MathAnimationService()
    
    func orbitAnimations(
        for object: SceneObject,
        startTime: Double,
        duration: Double?,
        intensity: Double
    ) -> [AnimationDefinition] {
        let base = baseAmplitude(for: object)
        let radiusX = base * 1.1 * intensity
        let radiusY = base * 0.7 * intensity
        let animation = makeMoveAnimation(
            startTime: startTime,
            duration: duration ?? 3.5,
            points: sampledPoints(steps: 8) { t in
                let angle = t * 2 * Double.pi
                return (cos(angle) * radiusX, sin(angle) * radiusY)
            },
            repeatCount: -1
        )
        return [animation]
    }
    
    func sineDriftAnimations(
        for object: SceneObject,
        startTime: Double,
        duration: Double?,
        intensity: Double
    ) -> [AnimationDefinition] {
        let base = baseAmplitude(for: object)
        let ampX = base * 0.6 * intensity
        let ampY = base * 0.35 * intensity
        let animation = makeMoveAnimation(
            startTime: startTime,
            duration: duration ?? 2.8,
            points: sampledPoints(steps: 8) { t in
                let angle = t * 2 * Double.pi
                return (sin(angle) * ampX, cos(angle * 0.7) * ampY)
            },
            repeatCount: -1
        )
        return [animation]
    }
    
    func lissajousAnimations(
        for object: SceneObject,
        startTime: Double,
        duration: Double?,
        intensity: Double
    ) -> [AnimationDefinition] {
        let base = baseAmplitude(for: object)
        let ampX = base * 0.95 * intensity
        let ampY = base * 0.6 * intensity
        let a = 3.0
        let b = 2.0
        let phase = Double.pi / 2
        let animation = makeMoveAnimation(
            startTime: startTime,
            duration: duration ?? 4.2,
            points: sampledPoints(steps: 12) { t in
                let angle = t * 2 * Double.pi
                return (sin(a * angle + phase) * ampX, sin(b * angle) * ampY)
            },
            repeatCount: -1
        )
        return [animation]
    }
    
    func pendulumAnimations(
        for object: SceneObject,
        startTime: Double,
        duration: Double?,
        intensity: Double
    ) -> [AnimationDefinition] {
        let base = baseAmplitude(for: object)
        let amplitude = max(8, min(35, base * 0.3)) * intensity
        let decay = 2.2
        
        let keyframes = sampledPoints(steps: 8) { t in
            let decayFactor = exp(-decay * t)
            let angle = sin(t * 2 * Double.pi) * amplitude * decayFactor
            return (angle, 0)
        }
        .map { point in
            point
        }
        
        let frames = keyframes.enumerated().map { index, point in
            let t = Double(index) / Double(max(keyframes.count - 1, 1))
            return Keyframe(time: t, value: .double(object.properties.rotation + point.x))
        }
        
        return [
            AnimationDefinition(
                type: .rotate,
                startTime: startTime,
                duration: duration ?? 2.4,
                easing: .linear,
                keyframes: frames,
                repeatCount: 0,
                autoReverse: false,
                delay: 0
            )
        ]
    }
    
    private func sampledPoints(
        steps: Int,
        generator: (Double) -> (Double, Double)
    ) -> [(x: Double, y: Double)] {
        guard steps > 0 else { return [(0, 0)] }
        return (0...steps).map { step in
            let t = Double(step) / Double(steps)
            let point = generator(t)
            return (point.0, point.1)
        }
    }
    
    private func makeMoveAnimation(
        startTime: Double,
        duration: Double,
        points: [(x: Double, y: Double)],
        repeatCount: Int
    ) -> AnimationDefinition {
        let frames = points.enumerated().map { index, point in
            let t = Double(index) / Double(max(points.count - 1, 1))
            return Keyframe(time: t, value: .point(x: point.x, y: point.y))
        }
        
        return AnimationDefinition(
            type: .move,
            startTime: startTime,
            duration: duration,
            easing: .linear,
            keyframes: frames,
            repeatCount: repeatCount,
            autoReverse: false,
            delay: 0
        )
    }
    
    private func baseAmplitude(for object: SceneObject) -> Double {
        let minSize = min(object.properties.width, object.properties.height)
        let base = min(120, max(24, minSize * 0.6))
        return base
    }
}
