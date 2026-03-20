//
//  MotionPathGenerator.swift
//  AIAfterEffects
//
//  Converts bezier control points into dense moveX/moveY keyframes,
//  enabling objects to follow smooth curved paths instead of straight lines.
//

import Foundation

struct MotionPathPoint {
    let x: Double
    let y: Double
    let time: Double  // 0.0–1.0, where along the path this point sits
}

struct MotionPathGenerator {
    
    /// Generates dense moveX and moveY keyframe arrays from control points.
    /// Uses Catmull-Rom spline interpolation for smooth curves through all points.
    ///
    /// - Parameters:
    ///   - controlPoints: Ordered path control points with position and normalized time.
    ///   - sampleCount: Number of dense keyframes to generate. Default 30.
    ///   - tension: Catmull-Rom tension. 0 = Catmull-Rom, 1 = linear. Default 0.
    /// - Returns: (moveX keyframes, moveY keyframes) for the two animation channels.
    static func generateKeyframes(
        controlPoints: [MotionPathPoint],
        sampleCount: Int = 30,
        tension: Double = 0
    ) -> (moveX: [Keyframe], moveY: [Keyframe]) {
        guard controlPoints.count >= 2 else {
            let p = controlPoints.first ?? MotionPathPoint(x: 0, y: 0, time: 0)
            return (
                [Keyframe(time: 0, value: .double(p.x)), Keyframe(time: 1, value: .double(p.x))],
                [Keyframe(time: 0, value: .double(p.y)), Keyframe(time: 1, value: .double(p.y))]
            )
        }
        
        let sorted = controlPoints.sorted { $0.time < $1.time }
        
        var moveX: [Keyframe] = []
        var moveY: [Keyframe] = []
        
        for i in 0..<sampleCount {
            let t = Double(i) / Double(sampleCount - 1)
            let point = catmullRomSample(points: sorted, t: t, tension: tension)
            moveX.append(Keyframe(time: t, value: .double(point.x)))
            moveY.append(Keyframe(time: t, value: .double(point.y)))
        }
        
        return (moveX, moveY)
    }
    
    /// Generates a smooth arc path between two points via a control height.
    ///
    /// - Parameters:
    ///   - from: Start position (x, y)
    ///   - to: End position (x, y)
    ///   - arcHeight: How high/low the arc peaks (positive = upward, negative = downward)
    ///   - sampleCount: Dense keyframe count
    /// - Returns: (moveX keyframes, moveY keyframes)
    static func arcPath(
        from: (x: Double, y: Double),
        to: (x: Double, y: Double),
        arcHeight: Double = -100,
        sampleCount: Int = 25
    ) -> (moveX: [Keyframe], moveY: [Keyframe]) {
        let midX = (from.x + to.x) / 2
        let midY = (from.y + to.y) / 2 + arcHeight
        
        let points = [
            MotionPathPoint(x: from.x, y: from.y, time: 0),
            MotionPathPoint(x: midX, y: midY, time: 0.5),
            MotionPathPoint(x: to.x, y: to.y, time: 1.0)
        ]
        
        return generateKeyframes(controlPoints: points, sampleCount: sampleCount)
    }
    
    /// Generates a parabolic arc (gravity-affected) trajectory.
    /// Objects launched at an angle and pulled down by gravity.
    ///
    /// - Parameters:
    ///   - origin: Launch point (x, y)
    ///   - velocity: Initial velocity (vx, vy) in pixels/sec
    ///   - gravity: Downward acceleration in pixels/sec². Default 800.
    ///   - duration: How long the arc lasts in seconds.
    ///   - sampleCount: Dense keyframe count.
    /// - Returns: (moveX keyframes, moveY keyframes)
    static func gravityArc(
        origin: (x: Double, y: Double),
        velocity: (vx: Double, vy: Double),
        gravity: Double = 800,
        duration: Double = 1.5,
        sampleCount: Int = 25
    ) -> (moveX: [Keyframe], moveY: [Keyframe]) {
        var moveX: [Keyframe] = []
        var moveY: [Keyframe] = []
        
        for i in 0..<sampleCount {
            let t = Double(i) / Double(sampleCount - 1)
            let simTime = t * duration
            let x = origin.x + velocity.vx * simTime
            let y = origin.y + velocity.vy * simTime + 0.5 * gravity * simTime * simTime
            
            moveX.append(Keyframe(time: t, value: .double(x)))
            moveY.append(Keyframe(time: t, value: .double(y)))
        }
        
        return (moveX, moveY)
    }
    
    /// Generates a spiral motion path.
    ///
    /// - Parameters:
    ///   - center: Center of the spiral (x, y)
    ///   - startRadius: Initial distance from center
    ///   - endRadius: Final distance from center (0 = spiral inward completely)
    ///   - revolutions: Number of full rotations
    ///   - sampleCount: Dense keyframe count
    /// - Returns: (moveX keyframes, moveY keyframes)
    static func spiralPath(
        center: (x: Double, y: Double),
        startRadius: Double = 200,
        endRadius: Double = 0,
        revolutions: Double = 2,
        sampleCount: Int = 40
    ) -> (moveX: [Keyframe], moveY: [Keyframe]) {
        var moveX: [Keyframe] = []
        var moveY: [Keyframe] = []
        
        for i in 0..<sampleCount {
            let t = Double(i) / Double(sampleCount - 1)
            let angle = t * revolutions * 2 * .pi
            let radius = startRadius + (endRadius - startRadius) * t
            let x = center.x + cos(angle) * radius
            let y = center.y + sin(angle) * radius
            
            moveX.append(Keyframe(time: t, value: .double(x)))
            moveY.append(Keyframe(time: t, value: .double(y)))
        }
        
        return (moveX, moveY)
    }
    
    // MARK: - Catmull-Rom Spline
    
    private static func catmullRomSample(
        points: [MotionPathPoint],
        t: Double,
        tension: Double
    ) -> (x: Double, y: Double) {
        guard points.count >= 2 else {
            return (points.first?.x ?? 0, points.first?.y ?? 0)
        }
        
        // Find the segment this t falls into
        var segIndex = 0
        for i in 0..<points.count - 1 {
            if t >= points[i].time && t <= points[i + 1].time {
                segIndex = i
                break
            }
            if i == points.count - 2 { segIndex = i }
        }
        
        // Local t within this segment
        let segStart = points[segIndex].time
        let segEnd = points[min(segIndex + 1, points.count - 1)].time
        let segLen = segEnd - segStart
        let localT = segLen > 0.0001 ? (t - segStart) / segLen : 0
        
        // Get the four control points (p0, p1, p2, p3) with clamped boundary
        let p0 = points[max(0, segIndex - 1)]
        let p1 = points[segIndex]
        let p2 = points[min(segIndex + 1, points.count - 1)]
        let p3 = points[min(segIndex + 2, points.count - 1)]
        
        let x = catmullRomInterp(p0.x, p1.x, p2.x, p3.x, t: localT, tension: tension)
        let y = catmullRomInterp(p0.y, p1.y, p2.y, p3.y, t: localT, tension: tension)
        
        return (x, y)
    }
    
    private static func catmullRomInterp(
        _ v0: Double, _ v1: Double, _ v2: Double, _ v3: Double,
        t: Double, tension: Double
    ) -> Double {
        let s = (1 - tension) / 2
        let t2 = t * t
        let t3 = t2 * t
        
        let h1 = 2 * t3 - 3 * t2 + 1
        let h2 = t3 - 2 * t2 + t
        let h3 = -2 * t3 + 3 * t2
        let h4 = t3 - t2
        
        let m1 = s * (v2 - v0)
        let m2 = s * (v3 - v1)
        
        return h1 * v1 + h2 * m1 + h3 * v2 + h4 * m2
    }
}
