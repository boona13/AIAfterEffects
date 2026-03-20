//
//  PathMorpher.swift
//  AIAfterEffects
//
//  Interpolates between two sets of PathCommands for smooth shape morphing.
//  Normalizes command counts and types so any shape can morph into any other.
//

import Foundation

struct PathMorpher {
    
    /// Interpolates between two path command arrays at a given progress (0–1).
    /// Handles mismatched command counts by normalizing (subdividing or padding).
    static func interpolate(
        from sourcePath: [PathCommand],
        to targetPath: [PathCommand],
        progress: Double
    ) -> [PathCommand] {
        let (normSource, normTarget) = normalize(sourcePath, targetPath)
        
        var result: [PathCommand] = []
        for (s, t) in zip(normSource, normTarget) {
            result.append(interpolateCommand(s, t, progress: progress))
        }
        return result
    }
    
    /// Pre-computes N intermediate path states for dense keyframe-style morphing.
    static func generateMorphSteps(
        from sourcePath: [PathCommand],
        to targetPath: [PathCommand],
        steps: Int = 20
    ) -> [[PathCommand]] {
        let (normSource, normTarget) = normalize(sourcePath, targetPath)
        
        var allSteps: [[PathCommand]] = []
        for i in 0..<steps {
            let t = Double(i) / Double(steps - 1)
            var stepPath: [PathCommand] = []
            for (s, target) in zip(normSource, normTarget) {
                stepPath.append(interpolateCommand(s, target, progress: t))
            }
            allSteps.append(stepPath)
        }
        return allSteps
    }
    
    // MARK: - Normalization
    
    /// Makes two path command arrays the same length and compatible types.
    /// Shorter paths get subdivided or padded to match the longer one.
    private static func normalize(
        _ a: [PathCommand],
        _ b: [PathCommand]
    ) -> ([PathCommand], [PathCommand]) {
        var source = a.filter { $0.command.lowercased() != "close" }
        var target = b.filter { $0.command.lowercased() != "close" }
        
        // Pad the shorter array by subdividing its last segment
        while source.count < target.count {
            if let last = source.last {
                source.append(last)
            } else {
                source.append(PathCommand(command: "line", x: 0, y: 0))
            }
        }
        while target.count < source.count {
            if let last = target.last {
                target.append(last)
            } else {
                target.append(PathCommand(command: "line", x: 0, y: 0))
            }
        }
        
        // Convert mismatched command types to the more complex type
        for i in 0..<source.count {
            let (s, t) = promoteToCommonType(source[i], target[i])
            source[i] = s
            target[i] = t
        }
        
        // Re-add close commands
        source.append(PathCommand(command: "close"))
        target.append(PathCommand(command: "close"))
        
        return (source, target)
    }
    
    /// Promotes two commands to a common interpolatable type.
    /// line → quadCurve (control point = midpoint), quadCurve → curve (duplicate control).
    private static func promoteToCommonType(
        _ a: PathCommand, _ b: PathCommand
    ) -> (PathCommand, PathCommand) {
        let aType = a.command.lowercased()
        let bType = b.command.lowercased()
        
        if aType == bType { return (a, b) }
        
        let typeRank: [String: Int] = ["move": 0, "moveto": 0, "m": 0,
                                        "line": 1, "lineto": 1, "l": 1,
                                        "quadcurve": 2, "quad": 2, "q": 2,
                                        "curve": 3, "cubic": 3, "c": 3]
        let aRank = typeRank[aType] ?? 1
        let bRank = typeRank[bType] ?? 1
        let targetRank = max(aRank, bRank)
        
        let promoted_a = promote(a, toRank: targetRank)
        let promoted_b = promote(b, toRank: targetRank)
        return (promoted_a, promoted_b)
    }
    
    private static func promote(_ cmd: PathCommand, toRank rank: Int) -> PathCommand {
        let cmdType = cmd.command.lowercased()
        let currentRank: Int
        switch cmdType {
        case "move", "moveto", "m": currentRank = 0
        case "line", "lineto", "l": currentRank = 1
        case "quadcurve", "quad", "q": currentRank = 2
        case "curve", "cubic", "c": currentRank = 3
        default: currentRank = 1
        }
        
        if currentRank >= rank { return cmd }
        
        var result = cmd
        
        // Promote line → quadCurve: control point at the endpoint
        if currentRank <= 1 && rank >= 2 {
            result.command = "quadCurve"
            result.cx1 = result.x ?? 0
            result.cy1 = result.y ?? 0
        }
        
        // Promote quadCurve → curve: duplicate control point
        if currentRank <= 2 && rank >= 3 {
            result.command = "curve"
            result.cx2 = result.cx1 ?? (result.x ?? 0)
            result.cy2 = result.cy1 ?? (result.y ?? 0)
            if result.cx1 == nil {
                result.cx1 = result.x ?? 0
                result.cy1 = result.y ?? 0
            }
        }
        
        return result
    }
    
    // MARK: - Interpolation
    
    private static func interpolateCommand(
        _ a: PathCommand, _ b: PathCommand, progress: Double
    ) -> PathCommand {
        let t = progress
        let cmdType = a.command  // Already normalized to same type
        
        return PathCommand(
            command: cmdType,
            x: lerp(a.x, b.x, t: t),
            y: lerp(a.y, b.y, t: t),
            cx1: lerp(a.cx1, b.cx1, t: t),
            cy1: lerp(a.cy1, b.cy1, t: t),
            cx2: lerp(a.cx2, b.cx2, t: t),
            cy2: lerp(a.cy2, b.cy2, t: t),
            rx: lerp(a.rx, b.rx, t: t),
            ry: lerp(a.ry, b.ry, t: t),
            startAngle: lerp(a.startAngle, b.startAngle, t: t),
            endAngle: lerp(a.endAngle, b.endAngle, t: t),
            clockwise: t < 0.5 ? a.clockwise : b.clockwise
        )
    }
    
    private static func lerp(_ a: Double?, _ b: Double?, t: Double) -> Double? {
        guard let a = a, let b = b else { return a ?? b }
        return a + (b - a) * t
    }
}
