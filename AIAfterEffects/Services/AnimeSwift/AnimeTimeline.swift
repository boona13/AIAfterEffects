//
//  AnimeTimeline.swift
//  AIAfterEffects
//
//  Timeline builder inspired by Anime.js createTimeline().
//  Generates AnimationDefinition arrays with computed startTime values.
//

import Foundation

// MARK: - Time Position

/// Specifies when an animation should start relative to the timeline.
enum TimePosition {
    /// Starts immediately after the previous animation ends (default)
    case afterPrevious
    
    /// Starts at the same time as the previous animation
    case withPrevious
    
    /// Starts at an offset from the end of the previous animation (can be negative for overlap)
    case offset(Double)
    
    /// Starts at an absolute time in the timeline (seconds)
    case absolute(Double)
}

// MARK: - Timeline Entry

private struct TimelineEntry {
    let type: AnimationType
    let duration: Double
    let easing: EasingType
    let keyframes: [Keyframe]
    let position: TimePosition
    let repeatCount: Int
    let autoReverse: Bool
    let delay: Double
}

// MARK: - AnimeTimeline

/// A builder that computes `startTime` values for a sequence of animations.
/// Does not replace the playback engine -- it just outputs `[AnimationDefinition]`
/// that the existing system already knows how to play.
class AnimeTimeline {
    private var entries: [TimelineEntry] = []
    
    /// The computed total duration of the timeline
    var totalDuration: Double {
        let built = build()
        return built.map { $0.startTime + $0.delay + $0.duration }.max() ?? 0
    }
    
    // MARK: - Building
    
    /// Add an animation to the timeline.
    @discardableResult
    func add(
        _ type: AnimationType,
        duration: Double = 1.0,
        easing: EasingType = .easeInOut,
        keyframes: [Keyframe] = [],
        at position: TimePosition = .afterPrevious,
        repeatCount: Int = 0,
        autoReverse: Bool = false,
        delay: Double = 0
    ) -> AnimeTimeline {
        entries.append(TimelineEntry(
            type: type,
            duration: duration,
            easing: easing,
            keyframes: keyframes,
            position: position,
            repeatCount: repeatCount,
            autoReverse: autoReverse,
            delay: delay
        ))
        return self
    }
    
    /// Add an animation with default keyframes from AnimationEngine.
    @discardableResult
    func addDefault(
        _ type: AnimationType,
        engine: AnimationEngine,
        at position: TimePosition = .afterPrevious,
        repeatCount: Int? = nil,
        autoReverse: Bool = false,
        delay: Double = 0
    ) -> AnimeTimeline {
        let keyframes = engine.defaultKeyframes(for: type)
        let duration = engine.recommendedDuration(for: type)
        let easing = engine.recommendedEasing(for: type)
        let repeat_ = repeatCount ?? engine.shouldRepeatByDefault(for: type)
        
        return add(
            type,
            duration: duration,
            easing: easing,
            keyframes: keyframes,
            at: position,
            repeatCount: repeat_,
            autoReverse: autoReverse,
            delay: delay
        )
    }
    
    /// Build the timeline into an array of AnimationDefinitions with computed startTimes.
    func build() -> [AnimationDefinition] {
        var results: [AnimationDefinition] = []
        var previousStart: Double = 0
        var previousDuration: Double = 0
        
        for entry in entries {
            let startTime: Double
            
            switch entry.position {
            case .afterPrevious:
                startTime = previousStart + previousDuration
                
            case .withPrevious:
                startTime = previousStart
                
            case .offset(let offset):
                startTime = max(0, previousStart + previousDuration + offset)
                
            case .absolute(let time):
                startTime = max(0, time)
            }
            
            let animation = AnimationDefinition(
                type: entry.type,
                startTime: startTime,
                duration: entry.duration,
                easing: entry.easing,
                keyframes: entry.keyframes,
                repeatCount: entry.repeatCount,
                autoReverse: entry.autoReverse,
                delay: entry.delay
            )
            
            results.append(animation)
            previousStart = startTime
            previousDuration = entry.duration
        }
        
        return results
    }
    
    /// Reset the timeline, removing all entries.
    func reset() {
        entries.removeAll()
    }
    
    // MARK: - Convenience: Staggered Timeline
    
    /// Create a timeline where each animation is staggered using AnimeStagger delays.
    static func staggered(
        type: AnimationType,
        count: Int,
        duration: Double = 0.5,
        easing: EasingType = .easeOutBack,
        keyframes: [Keyframe] = [],
        staggerEach: Double = 0.1,
        staggerFrom: StaggerFrom = .first,
        staggerEase: EasingType = .linear
    ) -> [AnimationDefinition] {
        let delays = AnimeStagger.delays(
            count: count,
            each: staggerEach,
            from: staggerFrom,
            ease: staggerEase
        )
        
        return delays.map { delay in
            AnimationDefinition(
                type: type,
                startTime: delay,
                duration: duration,
                easing: easing,
                keyframes: keyframes
            )
        }
    }
}
