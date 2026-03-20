//
//  MathAnimationServiceProtocol.swift
//  AIAfterEffects
//
//  Protocol for math/trig-based animation presets
//

import Foundation

protocol MathAnimationServiceProtocol {
    func orbitAnimations(
        for object: SceneObject,
        startTime: Double,
        duration: Double?,
        intensity: Double
    ) -> [AnimationDefinition]
    
    func sineDriftAnimations(
        for object: SceneObject,
        startTime: Double,
        duration: Double?,
        intensity: Double
    ) -> [AnimationDefinition]
    
    func lissajousAnimations(
        for object: SceneObject,
        startTime: Double,
        duration: Double?,
        intensity: Double
    ) -> [AnimationDefinition]
    
    func pendulumAnimations(
        for object: SceneObject,
        startTime: Double,
        duration: Double?,
        intensity: Double
    ) -> [AnimationDefinition]
}
