//
//  ShapePresets.swift
//  AIAfterEffects
//
//  Generates PathCommand arrays for parametric shape presets.
//  All coordinates are in normalized space: (0,0) = center, ±0.5 = edges.
//

import Foundation

enum ShapePreset: String, CaseIterable {
    case arrow
    case arrowCurved
    case star
    case triangle
    case teardrop
    case ring
    case cross
    case heart
    case burst
    case chevron
    case lightning
    case crescent
    case diamond
    case hexagon
    case octagon
    case speechBubble
    case droplet
    
    /// Generates the PathCommand array for this preset with optional parameters.
    func commands(
        points: Int = 5,
        innerRadiusRatio: Double = 0.4,
        thickness: Double = 0.15,
        headSize: Double = 0.3
    ) -> [PathCommand] {
        switch self {
        case .arrow:       return Self.arrowCommands(headSize: headSize, shaftThickness: thickness)
        case .arrowCurved: return Self.curvedArrowCommands()
        case .star:        return Self.starCommands(points: points, innerRatio: innerRadiusRatio)
        case .triangle:    return Self.triangleCommands()
        case .teardrop:    return Self.teardropCommands()
        case .ring:        return Self.ringCommands(thickness: thickness)
        case .cross:       return Self.crossCommands(thickness: thickness)
        case .heart:       return Self.heartCommands()
        case .burst:       return Self.burstCommands(points: max(6, points * 2))
        case .chevron:     return Self.chevronCommands(thickness: thickness)
        case .lightning:   return Self.lightningCommands()
        case .crescent:    return Self.crescentCommands()
        case .diamond:     return Self.diamondCommands()
        case .hexagon:     return Self.regularPolygonCommands(sides: 6)
        case .octagon:     return Self.regularPolygonCommands(sides: 8)
        case .speechBubble: return Self.speechBubbleCommands()
        case .droplet:     return Self.dropletCommands()
        }
    }
    
    // MARK: - Arrow (right-pointing by default)
    
    private static func arrowCommands(headSize: Double, shaftThickness: Double) -> [PathCommand] {
        let ht = shaftThickness / 2
        let tip = 0.5
        let headStart = tip - headSize
        let headHalf = headSize * 0.7
        return [
            PathCommand(command: "move", x: -0.5, y: -ht),
            PathCommand(command: "line", x: headStart, y: -ht),
            PathCommand(command: "line", x: headStart, y: -headHalf),
            PathCommand(command: "line", x: tip, y: 0),
            PathCommand(command: "line", x: headStart, y: headHalf),
            PathCommand(command: "line", x: headStart, y: ht),
            PathCommand(command: "line", x: -0.5, y: ht),
            PathCommand(command: "close")
        ]
    }
    
    // MARK: - Curved Arrow
    
    private static func curvedArrowCommands() -> [PathCommand] {
        return [
            PathCommand(command: "move", x: -0.35, y: 0.3),
            PathCommand(command: "curve", x: 0.3, y: -0.05, cx1: -0.35, cy1: -0.25, cx2: 0.1, cy2: -0.35),
            PathCommand(command: "line", x: 0.2, y: -0.25),
            PathCommand(command: "line", x: 0.45, y: -0.05),
            PathCommand(command: "line", x: 0.2, y: 0.15),
            PathCommand(command: "line", x: 0.3, y: -0.05),
            PathCommand(command: "curve", x: -0.15, y: 0.3, cx1: 0.05, cy1: -0.2, cx2: -0.15, cy2: -0.1),
            PathCommand(command: "close")
        ]
    }
    
    // MARK: - Star
    
    private static func starCommands(points: Int, innerRatio: Double) -> [PathCommand] {
        let n = max(3, points)
        let outerR = 0.5
        let innerR = outerR * innerRatio
        var cmds: [PathCommand] = []
        let offset = -Double.pi / 2
        
        for i in 0..<(n * 2) {
            let angle = offset + Double(i) * .pi / Double(n)
            let r = i % 2 == 0 ? outerR : innerR
            let x = cos(angle) * r
            let y = sin(angle) * r
            cmds.append(PathCommand(command: i == 0 ? "move" : "line", x: x, y: y))
        }
        cmds.append(PathCommand(command: "close"))
        return cmds
    }
    
    // MARK: - Triangle
    
    private static func triangleCommands() -> [PathCommand] {
        return [
            PathCommand(command: "move", x: 0, y: -0.5),
            PathCommand(command: "line", x: 0.5, y: 0.5),
            PathCommand(command: "line", x: -0.5, y: 0.5),
            PathCommand(command: "close")
        ]
    }
    
    // MARK: - Teardrop
    
    private static func teardropCommands() -> [PathCommand] {
        return [
            PathCommand(command: "move", x: 0, y: -0.5),
            PathCommand(command: "curve", x: 0.35, y: 0.1, cx1: 0.2, cy1: -0.35, cx2: 0.45, cy2: -0.1),
            PathCommand(command: "curve", x: 0, y: 0.5, cx1: 0.35, cy1: 0.3, cx2: 0.15, cy2: 0.5),
            PathCommand(command: "curve", x: -0.35, y: 0.1, cx1: -0.15, cy1: 0.5, cx2: -0.35, cy2: 0.3),
            PathCommand(command: "curve", x: 0, y: -0.5, cx1: -0.45, cy1: -0.1, cx2: -0.2, cy2: -0.35),
        ]
    }
    
    // MARK: - Ring (circle outline as closed path for trim animations)
    
    private static func ringCommands(thickness: Double) -> [PathCommand] {
        let steps = 32
        var cmds: [PathCommand] = []
        let r = 0.45
        for i in 0...steps {
            let angle = Double(i) / Double(steps) * 2 * .pi - .pi / 2
            let x = cos(angle) * r
            let y = sin(angle) * r
            cmds.append(PathCommand(command: i == 0 ? "move" : "line", x: x, y: y))
        }
        cmds.append(PathCommand(command: "close"))
        return cmds
    }
    
    // MARK: - Cross / Plus
    
    private static func crossCommands(thickness: Double) -> [PathCommand] {
        let t = thickness / 2
        return [
            PathCommand(command: "move", x: -t, y: -0.5),
            PathCommand(command: "line", x: t, y: -0.5),
            PathCommand(command: "line", x: t, y: -t),
            PathCommand(command: "line", x: 0.5, y: -t),
            PathCommand(command: "line", x: 0.5, y: t),
            PathCommand(command: "line", x: t, y: t),
            PathCommand(command: "line", x: t, y: 0.5),
            PathCommand(command: "line", x: -t, y: 0.5),
            PathCommand(command: "line", x: -t, y: t),
            PathCommand(command: "line", x: -0.5, y: t),
            PathCommand(command: "line", x: -0.5, y: -t),
            PathCommand(command: "line", x: -t, y: -t),
            PathCommand(command: "close")
        ]
    }
    
    // MARK: - Heart
    
    private static func heartCommands() -> [PathCommand] {
        return [
            PathCommand(command: "move", x: 0, y: 0.45),
            PathCommand(command: "curve", x: -0.5, y: -0.05, cx1: -0.35, cy1: 0.25, cx2: -0.5, cy2: 0.12),
            PathCommand(command: "curve", x: -0.25, y: -0.45, cx1: -0.5, cy1: -0.2, cx2: -0.38, cy2: -0.45),
            PathCommand(command: "curve", x: 0, y: -0.18, cx1: -0.12, cy1: -0.45, cx2: 0, cy2: -0.32),
            PathCommand(command: "curve", x: 0.25, y: -0.45, cx1: 0, cy1: -0.32, cx2: 0.12, cy2: -0.45),
            PathCommand(command: "curve", x: 0.5, y: -0.05, cx1: 0.38, cy1: -0.45, cx2: 0.5, cy2: -0.2),
            PathCommand(command: "curve", x: 0, y: 0.45, cx1: 0.5, cy1: 0.12, cx2: 0.35, cy2: 0.25),
        ]
    }
    
    // MARK: - Burst (spiky starburst)
    
    private static func burstCommands(points: Int) -> [PathCommand] {
        let n = max(6, points)
        let outerR = 0.5
        let innerR = 0.3
        var cmds: [PathCommand] = []
        let offset = -Double.pi / 2
        
        for i in 0..<n {
            let angle = offset + Double(i) * 2 * .pi / Double(n)
            let r = i % 2 == 0 ? outerR : innerR
            let x = cos(angle) * r
            let y = sin(angle) * r
            cmds.append(PathCommand(command: i == 0 ? "move" : "line", x: x, y: y))
        }
        cmds.append(PathCommand(command: "close"))
        return cmds
    }
    
    // MARK: - Chevron (angle bracket)
    
    private static func chevronCommands(thickness: Double) -> [PathCommand] {
        let t = thickness
        return [
            PathCommand(command: "move", x: -0.3, y: -0.5),
            PathCommand(command: "line", x: 0.3, y: 0),
            PathCommand(command: "line", x: -0.3, y: 0.5),
            PathCommand(command: "line", x: -0.3 - t, y: 0.5 - t * 0.5),
            PathCommand(command: "line", x: 0.3 - t, y: 0),
            PathCommand(command: "line", x: -0.3 - t, y: -0.5 + t * 0.5),
            PathCommand(command: "close")
        ]
    }
    
    // MARK: - Lightning Bolt
    
    private static func lightningCommands() -> [PathCommand] {
        return [
            PathCommand(command: "move", x: 0.05, y: -0.5),
            PathCommand(command: "line", x: -0.15, y: -0.05),
            PathCommand(command: "line", x: 0.1, y: -0.05),
            PathCommand(command: "line", x: -0.05, y: 0.5),
            PathCommand(command: "line", x: 0.2, y: 0.0),
            PathCommand(command: "line", x: -0.05, y: 0.0),
            PathCommand(command: "close")
        ]
    }
    
    // MARK: - Crescent Moon
    
    private static func crescentCommands() -> [PathCommand] {
        var cmds: [PathCommand] = []
        let steps = 20
        let outerR = 0.45
        let innerR = 0.35
        let innerOffsetX = 0.15
        
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let angle = -Double.pi / 2 + t * 2 * .pi
            let x = cos(angle) * outerR
            let y = sin(angle) * outerR
            cmds.append(PathCommand(command: i == 0 ? "move" : "line", x: x, y: y))
        }
        for i in stride(from: steps, through: 0, by: -1) {
            let t = Double(i) / Double(steps)
            let angle = -Double.pi / 2 + t * 2 * .pi
            let x = cos(angle) * innerR + innerOffsetX
            let y = sin(angle) * innerR
            cmds.append(PathCommand(command: "line", x: x, y: y))
        }
        cmds.append(PathCommand(command: "close"))
        return cmds
    }
    
    // MARK: - Diamond
    
    private static func diamondCommands() -> [PathCommand] {
        return [
            PathCommand(command: "move", x: 0, y: -0.5),
            PathCommand(command: "line", x: 0.5, y: 0),
            PathCommand(command: "line", x: 0, y: 0.5),
            PathCommand(command: "line", x: -0.5, y: 0),
            PathCommand(command: "close")
        ]
    }
    
    // MARK: - Regular Polygon (reusable)
    
    private static func regularPolygonCommands(sides: Int) -> [PathCommand] {
        let n = max(3, sides)
        var cmds: [PathCommand] = []
        let r = 0.5
        let offset = -Double.pi / 2
        
        for i in 0..<n {
            let angle = offset + Double(i) * 2 * .pi / Double(n)
            let x = cos(angle) * r
            let y = sin(angle) * r
            cmds.append(PathCommand(command: i == 0 ? "move" : "line", x: x, y: y))
        }
        cmds.append(PathCommand(command: "close"))
        return cmds
    }
    
    // MARK: - Speech Bubble
    
    private static func speechBubbleCommands() -> [PathCommand] {
        let r = 0.12
        return [
            PathCommand(command: "move", x: -0.35, y: -0.35),
            PathCommand(command: "line", x: 0.35, y: -0.35),
            PathCommand(command: "curve", x: 0.45, y: -0.25, cx1: 0.45, cy1: -0.35, cx2: 0.45, cy2: -0.25),
            PathCommand(command: "line", x: 0.45, y: 0.15),
            PathCommand(command: "curve", x: 0.35, y: 0.25, cx1: 0.45, cy1: 0.25, cx2: 0.35, cy2: 0.25),
            PathCommand(command: "line", x: -0.05, y: 0.25),
            PathCommand(command: "line", x: -0.2, y: 0.48),
            PathCommand(command: "line", x: -0.15, y: 0.25),
            PathCommand(command: "line", x: -0.35, y: 0.25),
            PathCommand(command: "curve", x: -0.45, y: 0.15, cx1: -0.45, cy1: 0.25, cx2: -0.45, cy2: 0.15),
            PathCommand(command: "line", x: -0.45, y: -0.25),
            PathCommand(command: "curve", x: -0.35, y: -0.35, cx1: -0.45, cy1: -0.35, cx2: -0.35, cy2: -0.35),
        ]
    }
    
    // MARK: - Water Droplet (inverted teardrop: round bottom, pointed top)
    
    private static func dropletCommands() -> [PathCommand] {
        return [
            PathCommand(command: "move", x: 0, y: -0.5),
            PathCommand(command: "curve", x: 0.35, y: 0.1, cx1: 0.05, cy1: -0.3, cx2: 0.35, cy2: -0.15),
            PathCommand(command: "curve", x: 0, y: 0.45, cx1: 0.35, cy1: 0.3, cx2: 0.2, cy2: 0.45),
            PathCommand(command: "curve", x: -0.35, y: 0.1, cx1: -0.2, cy1: 0.45, cx2: -0.35, cy2: 0.3),
            PathCommand(command: "curve", x: 0, y: -0.5, cx1: -0.35, cy1: -0.15, cx2: -0.05, cy2: -0.3),
        ]
    }
}
