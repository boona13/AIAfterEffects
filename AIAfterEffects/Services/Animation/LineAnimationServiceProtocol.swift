//
//  LineAnimationServiceProtocol.swift
//  AIAfterEffects
//
//  Protocol for line-based animation presets
//

import Foundation

protocol LineAnimationServiceProtocol {
    func lineDrawAnimations(
        for object: SceneObject,
        startTime: Double,
        duration: Double?,
        intensity: Double
    ) -> [AnimationDefinition]
    
    func lineSweepGlowAnimations(
        for object: SceneObject,
        startTime: Double,
        duration: Double?,
        intensity: Double
    ) -> [AnimationDefinition]
    
    func lineUnderlineAnimations(
        for object: SceneObject,
        startTime: Double,
        duration: Double?,
        intensity: Double
    ) -> [AnimationDefinition]
    
    func lineStackStaggerAnimations(
        for object: SceneObject,
        startTime: Double,
        duration: Double?,
        intensity: Double
    ) -> [AnimationDefinition]
}
