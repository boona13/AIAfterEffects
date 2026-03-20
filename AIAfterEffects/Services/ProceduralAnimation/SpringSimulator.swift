//
//  SpringSimulator.swift
//  AIAfterEffects
//
//  Physically-based spring simulation that generates dense keyframes.
//  Produces organic overshoot, bounce, and settle that no easing curve can replicate.
//

import Foundation

struct SpringSimulator {
    
    /// Simulates a critically/under-damped spring and returns dense keyframes.
    ///
    /// - Parameters:
    ///   - from: Starting value
    ///   - to: Target/rest value
    ///   - stiffness: Spring constant (higher = faster oscillation). Range: 50–1000.
    ///   - damping: Friction (higher = less oscillation). Range: 1–50.
    ///   - mass: Object mass (higher = slower, heavier feel). Range: 0.5–5.
    ///   - sampleCount: Number of keyframes to generate (more = smoother). Default 30.
    ///   - settleThreshold: When displacement < this fraction of total travel, stop.
    /// - Returns: Array of Keyframe with normalized time (0–1) and double values.
    static func simulate(
        from: Double,
        to: Double,
        stiffness: Double = 200,
        damping: Double = 10,
        mass: Double = 1.0,
        sampleCount: Int = 30,
        settleThreshold: Double = 0.001
    ) -> [Keyframe] {
        let travel = to - from
        guard abs(travel) > 0.0001 else {
            return [Keyframe(time: 0, value: .double(from)), Keyframe(time: 1, value: .double(to))]
        }
        
        // Simulate spring: x'' = (-stiffness * x - damping * x') / mass
        // where x is displacement from target (initially = from - to)
        var x = from - to
        var v = 0.0
        let dt = 1.0 / 120.0  // 120 Hz internal simulation rate
        
        // Find the settle time first (simulate until motion < threshold)
        let maxSimTime = 5.0
        var totalTime = 0.0
        var simX = x
        var simV = v
        
        while totalTime < maxSimTime {
            let springForce = -stiffness * simX
            let dampForce = -damping * simV
            let accel = (springForce + dampForce) / mass
            simV += accel * dt
            simX += simV * dt
            totalTime += dt
            
            if abs(simX) < abs(travel) * settleThreshold && abs(simV) < abs(travel) * settleThreshold * 10 {
                break
            }
        }
        
        // Now sample at sampleCount points over the settle time
        let sampleInterval = totalTime / Double(sampleCount - 1)
        var keyframes: [Keyframe] = []
        x = from - to
        v = 0.0
        var simClock = 0.0
        var nextSampleTime = 0.0
        var sampleIndex = 0
        
        keyframes.append(Keyframe(time: 0, value: .double(from)))
        sampleIndex += 1
        nextSampleTime = sampleInterval
        
        while sampleIndex < sampleCount - 1 {
            let springForce = -stiffness * x
            let dampForce = -damping * v
            let accel = (springForce + dampForce) / mass
            v += accel * dt
            x += v * dt
            simClock += dt
            
            if simClock >= nextSampleTime {
                let normalizedTime = Double(sampleIndex) / Double(sampleCount - 1)
                let currentValue = to + x
                keyframes.append(Keyframe(time: normalizedTime, value: .double(currentValue)))
                sampleIndex += 1
                nextSampleTime = Double(sampleIndex) * sampleInterval
            }
        }
        
        keyframes.append(Keyframe(time: 1.0, value: .double(to)))
        return keyframes
    }
    
    /// Generates keyframes for a "spring bounce" scale animation.
    /// Object scales from `from` to `to` with natural overshoot and settle.
    static func springScale(
        from: Double = 0,
        to: Double = 1,
        stiffness: Double = 180,
        damping: Double = 12
    ) -> [Keyframe] {
        return simulate(from: from, to: to, stiffness: stiffness, damping: damping)
    }
    
    /// Generates a spring-based "impact" — quick compression then expand with oscillation.
    /// Great for landing/collision effects.
    static func impactSquash(
        restScale: Double = 1.0,
        squashAmount: Double = 0.3,
        stiffness: Double = 300,
        damping: Double = 8
    ) -> (scaleX: [Keyframe], scaleY: [Keyframe]) {
        let squashedY = restScale - squashAmount
        let stretchedX = restScale + squashAmount * 0.5
        
        let yFrames = simulate(from: squashedY, to: restScale, stiffness: stiffness, damping: damping)
        let xFrames = simulate(from: stretchedX, to: restScale, stiffness: stiffness, damping: damping)
        return (scaleX: xFrames, scaleY: yFrames)
    }
    
    /// Generates a spring "anticipation → action → settle" sequence.
    /// Pulls back slightly before springing to the target.
    static func anticipationSpring(
        from: Double,
        to: Double,
        pullbackRatio: Double = 0.15,
        stiffness: Double = 250,
        damping: Double = 14,
        sampleCount: Int = 30
    ) -> [Keyframe] {
        let travel = to - from
        let pullbackTarget = from - travel * pullbackRatio
        
        // Phase 1: Pull back (first 15% of keyframes)
        let pullbackCount = max(3, sampleCount / 6)
        let springCount = sampleCount - pullbackCount
        
        var keyframes: [Keyframe] = []
        for i in 0..<pullbackCount {
            let t = Double(i) / Double(pullbackCount)
            let eased = t * t  // ease-in for anticipation
            let value = from + (pullbackTarget - from) * eased
            let normalizedTime = t * 0.15
            keyframes.append(Keyframe(time: normalizedTime, value: .double(value)))
        }
        
        // Phase 2: Spring from pullback to target (remaining 85%)
        let springFrames = simulate(
            from: pullbackTarget,
            to: to,
            stiffness: stiffness,
            damping: damping,
            sampleCount: springCount
        )
        
        for frame in springFrames {
            let remappedTime = 0.15 + frame.time * 0.85
            keyframes.append(Keyframe(time: remappedTime, value: frame.value))
        }
        
        return keyframes
    }
    
    // MARK: - Noise-Based Organic Motion
    
    /// Generates perlin-like noise keyframes for organic floating/drifting.
    /// Each call produces a unique curve — no two cycles are identical.
    static func organicNoise(
        center: Double = 0,
        amplitude: Double = 10,
        octaves: Int = 3,
        sampleCount: Int = 30,
        seed: UInt64 = 0
    ) -> [Keyframe] {
        var rng = SeededRNG(seed: seed == 0 ? UInt64.random(in: 0...UInt64.max) : seed)
        
        // Generate layered sinusoidal noise
        var keyframes: [Keyframe] = []
        for i in 0..<sampleCount {
            let t = Double(i) / Double(sampleCount - 1)
            var value = center
            
            for octave in 0..<octaves {
                let freq = Double(octave + 1) * 1.7
                let amp = amplitude / Double(octave + 1)
                let phase = Double.random(in: 0...(.pi * 2), using: &rng)
                value += sin(t * .pi * 2 * freq + phase) * amp
            }
            
            keyframes.append(Keyframe(time: t, value: .double(value)))
        }
        
        // Ensure start and end are close to center for loopability
        if let first = keyframes.first, let last = keyframes.last {
            keyframes[0] = Keyframe(time: 0, value: .double(center))
            keyframes[keyframes.count - 1] = Keyframe(time: 1, value: .double(center))
        }
        
        return keyframes
    }
}

// MARK: - Seeded RNG for reproducible noise

private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    
    init(seed: UInt64) {
        self.state = seed
    }
    
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
