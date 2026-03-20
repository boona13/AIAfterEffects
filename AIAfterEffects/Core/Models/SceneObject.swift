//
//  SceneObject.swift
//  AIAfterEffects
//
//  Core model representing objects on the canvas (shapes, text, etc.)
//

import SwiftUI
import Foundation

// MARK: - Scene Object Types

enum SceneObjectType: String, Codable, Equatable {
    case rectangle
    case circle
    case ellipse
    case polygon
    case line
    case text
    case icon
    case image
    case path
    case model3D
    case shader
    case particleSystem
}

// MARK: - Timing Dependency

/// Defines a timing relationship between objects.
/// When set, the object's animations start relative to another object's timing.
struct TimingDependency: Codable, Equatable {
    /// The object ID this depends on
    var dependsOn: UUID
    /// When to trigger relative to the dependency
    var trigger: DependencyTrigger
    /// Seconds after the trigger point (negative = overlap)
    var gap: Double
    
    init(dependsOn: UUID, trigger: DependencyTrigger = .afterEnd, gap: Double = 0) {
        self.dependsOn = dependsOn
        self.trigger = trigger
        self.gap = gap
    }
}

/// Determines how an object's start time relates to its dependency.
enum DependencyTrigger: String, Codable, Equatable {
    /// Start after the dependency object's last animation ends
    case afterEnd
    /// Start at the same time the dependency object starts (for parallel groups)
    case withStart
}

// MARK: - Scene Object

struct SceneObject: Identifiable, Codable, Equatable {
    let id: UUID
    var type: SceneObjectType
    var name: String
    var properties: ObjectProperties
    var animations: [AnimationDefinition]
    var zIndex: Int
    var isVisible: Bool
    /// When true, the object cannot be moved/edited from the inspector or deleted from the layer panel.
    var isLocked: Bool
    /// Optional timing dependency — when set, this object's animations start
    /// relative to another object. nil = absolute timing (backward compatible).
    var timingDependency: TimingDependency?
    
    init(
        id: UUID = UUID(),
        type: SceneObjectType,
        name: String,
        properties: ObjectProperties = ObjectProperties(),
        animations: [AnimationDefinition] = [],
        zIndex: Int = 0,
        isVisible: Bool = true,
        isLocked: Bool = false,
        timingDependency: TimingDependency? = nil
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.properties = properties
        self.animations = animations
        self.zIndex = zIndex
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.timingDependency = timingDependency
    }
    
    // MARK: - Backward-Compatible Codable
    
    enum CodingKeys: String, CodingKey {
        case id, type, name, properties, animations, zIndex, isVisible, isLocked, timingDependency
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(SceneObjectType.self, forKey: .type)
        name = try container.decode(String.self, forKey: .name)
        properties = try container.decode(ObjectProperties.self, forKey: .properties)
        animations = try container.decodeIfPresent([AnimationDefinition].self, forKey: .animations) ?? []
        zIndex = try container.decodeIfPresent(Int.self, forKey: .zIndex) ?? 0
        isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        timingDependency = try container.decodeIfPresent(TimingDependency.self, forKey: .timingDependency)
    }
}

// MARK: - Object Properties

struct ObjectProperties: Codable, Equatable {
    // Transform
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var rotation: Double
    var scaleX: Double
    var scaleY: Double
    var anchorX: Double
    var anchorY: Double
    
    // Appearance
    var fillColor: CodableColor
    var strokeColor: CodableColor
    var strokeWidth: Double
    var opacity: Double
    var cornerRadius: Double
    
    // Text-specific
    var text: String?
    var fontSize: Double?
    var fontName: String?
    var fontWeight: String?
    var textAlignment: String?
    
    // Icon-specific
    var iconName: String?
    var iconSize: Double?
    
    // Image-specific
    var imageData: String?
    
    // Polygon-specific
    var sides: Int?
    
    // Path-specific
    var pathData: [PathCommand]?
    /// If true, close the path back to the first point
    var closePath: Bool?
    /// Line cap style: "round", "butt", "square"
    var lineCap: String?
    /// Line join style: "round", "bevel", "miter"
    var lineJoin: String?
    /// Dash pattern: array of [dash, gap, dash, gap, ...] lengths
    var dashPattern: [Double]?
    /// Dash phase offset (animatable for marching ants effect)
    var dashPhase: Double?
    /// Trim path start (0.0-1.0) — portion of path to skip from the beginning
    var trimStart: Double?
    /// Trim path end (0.0-1.0) — portion of path to draw up to
    var trimEnd: Double?
    /// Trim path offset (0.0-1.0) — shifts the trim region along the path
    var trimOffset: Double?
    
    // 3D Model properties (model3D type)
    var modelAssetId: String?        // References AssetManager catalog ID
    var modelFilePath: String?       // Local file path to USDZ/glTF
    var rotationX: Double?           // 3D rotation around X axis (degrees)
    var rotationY: Double?           // 3D rotation around Y axis (degrees)
    var rotationZ: Double?           // 3D rotation around Z axis (degrees)
    var position3DX: Double?         // 3D position X offset in scene units
    var position3DY: Double?         // 3D position Y offset in scene units
    var position3DZ: Double?         // 3D position Z offset in scene units
    var scaleZ: Double?              // Independent Z-axis scaling
    var cameraDistance: Double?      // Viewing distance for the 3D viewport
    var cameraAngleX: Double?        // Camera pitch angle
    var cameraAngleY: Double?        // Camera yaw angle
    var cameraTargetX: Double?       // Camera pan target X (look-at point)
    var cameraTargetY: Double?       // Camera pan target Y (look-at point)
    var cameraTargetZ: Double?       // Camera pan target Z (look-at point)
    var environmentLighting: String? // e.g. "studio", "outdoor", "neutral"
    
    // Metal Shader properties (shader type)
    var shaderCode: String?          // AI-generated Metal fragment shader body
    var shaderParam1: Double?        // Custom parameter 1 (speed, scale, etc.)
    var shaderParam2: Double?        // Custom parameter 2
    var shaderParam3: Double?        // Custom parameter 3
    var shaderParam4: Double?        // Custom parameter 4
    
    // GPU Particle System (particleSystem type)
    var particleSystemData: ParticleSystemData?
    
    // Visual Effects (applicable to ALL object types)
    var blurRadius: Double
    var brightness: Double       // -1.0 to 1.0  (0 = normal)
    var contrast: Double         //  0.0 to 3.0  (1 = normal)
    var saturation: Double       //  0.0 to 3.0  (1 = normal, 0 = grayscale)
    var hueRotation: Double      // degrees (0 = normal)
    var grayscale: Double        // 0.0 to 1.0  (0 = normal, 1 = fully gray)
    var blendMode: String?       // "multiply","screen","overlay","softLight","hardLight","colorDodge","colorBurn","difference","exclusion"
    var shadowColor: CodableColor?
    var shadowRadius: Double
    var shadowOffsetX: Double
    var shadowOffsetY: Double
    var colorInvert: Bool
    
    init(
        x: Double = 0,
        y: Double = 0,
        width: Double = 100,
        height: Double = 100,
        rotation: Double = 0,
        scaleX: Double = 1,
        scaleY: Double = 1,
        anchorX: Double = 0.5,
        anchorY: Double = 0.5,
        fillColor: CodableColor = CodableColor(red: 1, green: 1, blue: 1, alpha: 1),
        strokeColor: CodableColor = CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
        strokeWidth: Double = 0,
        opacity: Double = 1,
        cornerRadius: Double = 0,
        text: String? = nil,
        fontSize: Double? = nil,
        fontName: String? = nil,
        fontWeight: String? = nil,
        textAlignment: String? = nil,
        sides: Int? = nil,
        pathData: [PathCommand]? = nil,
        closePath: Bool? = nil,
        lineCap: String? = nil,
        lineJoin: String? = nil,
        dashPattern: [Double]? = nil,
        dashPhase: Double? = nil,
        trimStart: Double? = nil,
        trimEnd: Double? = nil,
        trimOffset: Double? = nil,
        iconName: String? = nil,
        iconSize: Double? = nil,
        imageData: String? = nil,
        modelAssetId: String? = nil,
        modelFilePath: String? = nil,
        rotationX: Double? = nil,
        rotationY: Double? = nil,
        rotationZ: Double? = nil,
        position3DX: Double? = nil,
        position3DY: Double? = nil,
        position3DZ: Double? = nil,
        scaleZ: Double? = nil,
        cameraDistance: Double? = nil,
        cameraAngleX: Double? = nil,
        cameraAngleY: Double? = nil,
        cameraTargetX: Double? = nil,
        cameraTargetY: Double? = nil,
        cameraTargetZ: Double? = nil,
        environmentLighting: String? = nil,
        blurRadius: Double = 0,
        brightness: Double = 0,
        contrast: Double = 1,
        saturation: Double = 1,
        hueRotation: Double = 0,
        grayscale: Double = 0,
        blendMode: String? = nil,
        shadowColor: CodableColor? = nil,
        shadowRadius: Double = 0,
        shadowOffsetX: Double = 0,
        shadowOffsetY: Double = 0,
        colorInvert: Bool = false
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.rotation = rotation
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.anchorX = anchorX
        self.anchorY = anchorY
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.opacity = opacity
        self.cornerRadius = cornerRadius
        self.text = text
        self.fontSize = fontSize
        self.fontName = fontName
        self.fontWeight = fontWeight
        self.textAlignment = textAlignment
        self.sides = sides
        self.pathData = pathData
        self.closePath = closePath
        self.lineCap = lineCap
        self.lineJoin = lineJoin
        self.dashPattern = dashPattern
        self.dashPhase = dashPhase
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.trimOffset = trimOffset
        self.iconName = iconName
        self.iconSize = iconSize
        self.imageData = imageData
        self.modelAssetId = modelAssetId
        self.modelFilePath = modelFilePath
        self.rotationX = rotationX
        self.rotationY = rotationY
        self.rotationZ = rotationZ
        self.position3DX = position3DX
        self.position3DY = position3DY
        self.position3DZ = position3DZ
        self.scaleZ = scaleZ
        self.cameraDistance = cameraDistance
        self.cameraAngleX = cameraAngleX
        self.cameraAngleY = cameraAngleY
        self.cameraTargetX = cameraTargetX
        self.cameraTargetY = cameraTargetY
        self.cameraTargetZ = cameraTargetZ
        self.environmentLighting = environmentLighting
        self.blurRadius = blurRadius
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.hueRotation = hueRotation
        self.grayscale = grayscale
        self.blendMode = blendMode
        self.shadowColor = shadowColor
        self.shadowRadius = shadowRadius
        self.shadowOffsetX = shadowOffsetX
        self.shadowOffsetY = shadowOffsetY
        self.colorInvert = colorInvert
    }
}

// MARK: - Path Command

/// A single drawing command for custom path objects.
/// Coordinates are relative to the object's center (0,0 = center).
/// The bounding box is defined by the object's width/height.
struct PathCommand: Codable, Equatable {
    /// Command type: "move", "line", "quadCurve", "curve", "arc", "close"
    var command: String
    /// End point x (relative to object center, normalized -0.5...0.5 of width)
    var x: Double?
    /// End point y (relative to object center, normalized -0.5...0.5 of height)
    var y: Double?
    /// Control point 1 x (for quadCurve and curve)
    var cx1: Double?
    /// Control point 1 y
    var cy1: Double?
    /// Control point 2 x (for curve / cubic bezier)
    var cx2: Double?
    /// Control point 2 y
    var cy2: Double?
    /// Arc radius x
    var rx: Double?
    /// Arc radius y
    var ry: Double?
    /// Arc start angle in degrees (for arc command)
    var startAngle: Double?
    /// Arc end angle in degrees (for arc command)
    var endAngle: Double?
    /// Whether the arc sweeps clockwise
    var clockwise: Bool?
}

// MARK: - Codable Color

struct CodableColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
    
    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
    
    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
    
    // Common colors
    static let white = CodableColor(red: 1, green: 1, blue: 1)
    static let black = CodableColor(red: 0, green: 0, blue: 0)
    static let red = CodableColor(red: 1, green: 0, blue: 0)
    static let green = CodableColor(red: 0, green: 1, blue: 0)
    static let blue = CodableColor(red: 0, green: 0, blue: 1)
    static let yellow = CodableColor(red: 1, green: 1, blue: 0)
    static let orange = CodableColor(red: 1, green: 0.5, blue: 0)
    static let purple = CodableColor(red: 0.5, green: 0, blue: 0.5)
    static let pink = CodableColor(red: 1, green: 0.4, blue: 0.7)
    static let cyan = CodableColor(red: 0, green: 1, blue: 1)
    static let clear = CodableColor(red: 0, green: 0, blue: 0, alpha: 0)
}

// MARK: - Scene State

struct SceneState: Codable, Equatable {
    var objects: [SceneObject]
    var canvasWidth: Double
    var canvasHeight: Double
    var backgroundColor: CodableColor
    var duration: Double // Total animation duration in seconds
    var fps: Int
    
    init(
        objects: [SceneObject] = [],
        canvasWidth: Double = 1920,
        canvasHeight: Double = 1080,
        backgroundColor: CodableColor = CodableColor(red: 0.96, green: 0.95, blue: 0.94),
        duration: Double = 12.0,
        fps: Int = 60
    ) {
        self.objects = objects
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.backgroundColor = backgroundColor
        self.duration = duration
        self.fps = fps
    }
    
    /// Get a text description of the current scene for AI context
    func describe() -> String {
        let orientation = canvasWidth > canvasHeight ? "LANDSCAPE" : (canvasHeight > canvasWidth ? "PORTRAIT" : "SQUARE")
        
        if objects.isEmpty {
            var desc = "The canvas is empty. Size: \(Int(canvasWidth))x\(Int(canvasHeight))px (\(orientation)), duration: \(String(format: "%.1f", duration))s\n"
            desc += emptyCanvasReference()
            return desc
        }
        
        var description = "Canvas: \(Int(canvasWidth))x\(Int(canvasHeight))px (\(orientation)), center: (\(Int(canvasWidth / 2)), \(Int(canvasHeight / 2))), duration: \(String(format: "%.1f", duration))s\n"
        description += "Objects on canvas (\(objects.count) total):\n"
        
        for (index, obj) in objects.enumerated() {
            let x = Int(obj.properties.x)
            let y = Int(obj.properties.y)
            let w = Int(obj.properties.width)
            let h = Int(obj.properties.height)
            let left = x - w / 2
            let right = x + w / 2
            let top = y - h / 2
            let bottom = y + h / 2
            
            let p = obj.properties
            description += "\(index + 1). \(obj.name) [id:\(obj.id)] (\(obj.type.rawValue))"
            description += " center:(\(x),\(y)) size:\(w)x\(h)"
            description += " bounds:[L:\(left) R:\(right) T:\(top) B:\(bottom)]"
            description += " z:\(obj.zIndex)"
            
            // Transform (only non-default values)
            if p.rotation != 0 { description += " rot:\(String(format: "%.1f", p.rotation))" }
            if p.scaleX != 1 { description += " scaleX:\(String(format: "%.2f", p.scaleX))" }
            if p.scaleY != 1 { description += " scaleY:\(String(format: "%.2f", p.scaleY))" }
            if p.opacity != 1 { description += " opacity:\(String(format: "%.2f", p.opacity))" }
            
            // Appearance (only non-default)
            if p.strokeWidth != 0 { description += " strokeW:\(String(format: "%.1f", p.strokeWidth))" }
            if p.cornerRadius != 0 { description += " radius:\(String(format: "%.1f", p.cornerRadius))" }
            
            // Text properties
            if let text = p.text {
                description += " text:\"\(text)\""
                if let fs = p.fontSize, fs > 0 { description += " fontSize:\(Int(fs))" }
                if let fn = p.fontName, !fn.isEmpty { description += " font:\(fn)" }
                if let fw = p.fontWeight, !fw.isEmpty { description += " weight:\(fw)" }
                if let ta = p.textAlignment, !ta.isEmpty { description += " align:\(ta)" }
            }
            
            // Image
            if obj.type == .image {
                let hasImage = (p.imageData?.isEmpty == false)
                description += " image:\(hasImage ? "attached" : "missing")"
            }
            
            // Icon
            if obj.type == .icon {
                if let name = p.iconName { description += " iconName:\(name)" }
                if let size = p.iconSize { description += " iconSize:\(Int(size))" }
            }
            
            // Path / Line
            if obj.type == .path || obj.type == .line {
                if let ts = p.trimStart, ts != 0 { description += " trimStart:\(String(format: "%.2f", ts))" }
                if let te = p.trimEnd, te != 1 { description += " trimEnd:\(String(format: "%.2f", te))" }
                if let to = p.trimOffset, to != 0 { description += " trimOffset:\(String(format: "%.2f", to))" }
                if let dp = p.dashPhase, dp != 0 { description += " dashPhase:\(String(format: "%.1f", dp))" }
                if let cp = p.closePath, cp { description += " closePath:true" }
                if let lc = p.lineCap, !lc.isEmpty { description += " lineCap:\(lc)" }
                if let lj = p.lineJoin, !lj.isEmpty { description += " lineJoin:\(lj)" }
            }
            
            // 3D Model
            if obj.type == .model3D {
                if let assetId = p.modelAssetId { description += " model3D:assetId=\(assetId)" }
                if let env = p.environmentLighting { description += " lighting:\(env)" }
                if let px = p.position3DX, px != 0 { description += " pos3DX:\(String(format: "%.2f", px))" }
                if let py = p.position3DY, py != 0 { description += " pos3DY:\(String(format: "%.2f", py))" }
                if let pz = p.position3DZ, pz != 0 { description += " pos3DZ:\(String(format: "%.2f", pz))" }
                if let rx = p.rotationX, rx != 0 { description += " rotX:\(String(format: "%.1f", rx))" }
                if let ry = p.rotationY, ry != 0 { description += " rotY:\(String(format: "%.1f", ry))" }
                if let rz = p.rotationZ, rz != 0 { description += " rotZ:\(String(format: "%.1f", rz))" }
                if let sz = p.scaleZ, sz != 1 { description += " scaleZ:\(String(format: "%.2f", sz))" }
                if let ctx = p.cameraTargetX, ctx != 0 { description += " camTargetX:\(String(format: "%.2f", ctx))" }
                if let cty = p.cameraTargetY, cty != 0 { description += " camTargetY:\(String(format: "%.2f", cty))" }
                if let ctz = p.cameraTargetZ, ctz != 0 { description += " camTargetZ:\(String(format: "%.2f", ctz))" }
            }
            
            // Shader
            if obj.type == .shader {
                let hasCode = p.shaderCode?.isEmpty == false
                description += " shader:\(hasCode ? "active" : "no code")"
                if let p1 = p.shaderParam1, p1 != 1.0 { description += " p1:\(String(format: "%.1f", p1))" }
                if let p2 = p.shaderParam2, p2 != 1.0 { description += " p2:\(String(format: "%.1f", p2))" }
            }
            
            // Polygon
            if obj.type == .polygon {
                if let sides = p.sides { description += " sides:\(sides)" }
            }
            
            // Visual effects (only non-default)
            if p.blurRadius != 0 { description += " blur:\(String(format: "%.1f", p.blurRadius))" }
            if p.brightness != 0 { description += " brightness:\(String(format: "%.2f", p.brightness))" }
            if p.contrast != 1 { description += " contrast:\(String(format: "%.2f", p.contrast))" }
            if p.saturation != 1 { description += " saturation:\(String(format: "%.2f", p.saturation))" }
            if p.hueRotation != 0 { description += " hueRotation:\(String(format: "%.1f", p.hueRotation))" }
            if p.grayscale != 0 { description += " grayscale:\(String(format: "%.2f", p.grayscale))" }
            if p.shadowRadius != 0 { description += " shadowRadius:\(String(format: "%.1f", p.shadowRadius))" }
            
            // Flag objects that are clipped
            if left < 0 || right > Int(canvasWidth) || top < 0 || bottom > Int(canvasHeight) {
                description += " ⚠️CLIPPED"
            }
            
            if let dep = obj.timingDependency {
                description += " dependsOn:\(dep.dependsOn)(\(dep.trigger.rawValue),gap:\(String(format: "%.1f", dep.gap)))"
            }
            
            if !obj.animations.isEmpty {
                let animationDetails = obj.animations.map { anim in
                    let start = String(format: "%.2f", anim.startTime)
                    let duration = String(format: "%.2f", anim.duration)
                    let delay = String(format: "%.2f", anim.delay)
                    let repeatCount = anim.repeatCount != 0 ? ", repeat:\(anim.repeatCount)" : ""
                    let autoReverse = anim.autoReverse ? ", autoReverse:true" : ""
                    return "\(anim.type.rawValue)(start:\(start)s,dur:\(duration)s,delay:\(delay)s\(repeatCount)\(autoReverse))"
                }
                description += " animations: \(animationDetails.joined(separator: "; "))"
            }
            
            description += "\n"
        }
        
        // Append the visual canvas map
        description += visualMap()
        
        return description
    }
    
    /// Compact spatial reference for an empty canvas — shows landmark positions the AI can use for planning.
    /// Adapts to any canvas size (portrait, landscape, square) with dynamic layout.
    private func emptyCanvasReference() -> String {
        let cw = Int(canvasWidth)
        let ch = Int(canvasHeight)
        let cx = Int(canvasWidth / 2)
        let cy = Int(canvasHeight / 2)
        let topY = Int(canvasHeight * 0.15)
        let botY = Int(canvasHeight * 0.85)
        let leftX = Int(canvasWidth * 0.2)
        let rightX = Int(canvasWidth * 0.8)
        let thirdY = Int(canvasHeight * 0.33)
        let twoThirdY = Int(canvasHeight * 0.67)
        let orientation = canvasWidth > canvasHeight ? "LANDSCAPE" : (canvasHeight > canvasWidth ? "PORTRAIT" : "SQUARE")
        
        // Build content lines first, then compute box width
        let topRow    = "  TL(\(leftX),\(topY))    TC(\(cx),\(topY))    TR(\(rightX),\(topY))  "
        let midRow    = "  ML(\(leftX),\(cy))    CENTER(\(cx),\(cy))   MR(\(rightX),\(cy))  "
        let botRow    = "  BL(\(leftX),\(botY))    BC(\(cx),\(botY))    BR(\(rightX),\(botY))  "
        let thirdLine = "          1/3 line: y=\(thirdY)"
        let twoThLine = "          2/3 line: y=\(twoThirdY)"
        
        let maxLen = max(topRow.count, midRow.count, botRow.count, thirdLine.count, twoThLine.count)
        let boxW = maxLen + 2  // +2 for padding
        
        func pad(_ s: String) -> String {
            let needed = boxW - s.count
            return s + String(repeating: " ", count: max(0, needed))
        }
        
        let border = "+" + String(repeating: "-", count: boxW) + "+"
        let emptyLine = "|" + String(repeating: " ", count: boxW) + "|"
        
        var ref = "\n"
        ref += "--- CANVAS REFERENCE (\(cw)x\(ch) \(orientation)) — empty, all positions available ---\n"
        ref += border + "\n"
        ref += "|" + pad(topRow) + "|\n"
        ref += emptyLine + "\n"
        ref += "|" + pad(thirdLine) + "|\n"
        ref += emptyLine + "\n"
        ref += "|" + pad(midRow) + "|\n"
        ref += emptyLine + "\n"
        ref += "|" + pad(twoThLine) + "|\n"
        ref += emptyLine + "\n"
        ref += "|" + pad(botRow) + "|\n"
        ref += border + "\n"
        ref += "0,0=top-left | \(cw),\(ch)=bottom-right | Center: (\(cx),\(cy)) | Safe width: \(Int(Double(cw) * 0.9))px\n"
        ref += "You have FULL creative freedom — place objects at ANY (x,y) coordinate.\n"
        ref += "--- END REFERENCE ---\n"
        return ref
    }
    
    /// Generate a visual ASCII map of the canvas showing where objects are positioned.
    /// This helps the AI "see" the canvas layout at a glance — occupied zones, free space, overlaps.
    private func visualMap() -> String {
        let cw = Int(canvasWidth)
        let ch = Int(canvasHeight)
        
        // Separate 3D models from 2D objects — 3D models fill the entire canvas
        // and would pollute every grid cell, making the map useless for layout planning.
        let model3DObjects = objects.filter { $0.type == .model3D }
        let objects2D = objects.filter { $0.type != .model3D }
        
        // Grid dimensions: 6 columns, rows proportional to aspect ratio (capped 3-10)
        let gridCols = 6
        let cellW = canvasWidth / Double(gridCols)
        let gridRows = max(3, min(10, Int(round(canvasHeight / cellW))))
        let cellH = canvasHeight / Double(gridRows)
        
        // Track 2D objects per grid cell (by center point) — excludes model3D
        var cellCount = Array(repeating: Array(repeating: 0, count: gridCols), count: gridRows)
        var cellFirstName = Array(repeating: Array(repeating: "", count: gridCols), count: gridRows)
        
        for obj in objects2D {
            let col = min(gridCols - 1, max(0, Int(obj.properties.x / cellW)))
            let row = min(gridRows - 1, max(0, Int(obj.properties.y / cellH)))
            cellCount[row][col] += 1
            if cellFirstName[row][col].isEmpty {
                cellFirstName[row][col] = String(obj.name.prefix(5))
            }
        }
        
        var map = "\n--- CANVAS VISUAL MAP (\(cw)x\(ch)) --- cell = \(Int(cellW))x\(Int(cellH))px ---\n"
        
        // 3D model layer note — shown above the grid so the AI knows a 3D model underlays everything
        if !model3DObjects.isEmpty {
            let modelNames = model3DObjects.map { "\($0.name) (z:\($0.zIndex))" }.joined(separator: ", ")
            map += "⚠️ 3D MODEL LAYER: \(modelNames) — fills ENTIRE canvas as a background/hero layer.\n"
            map += "   All 2D objects below are OVERLAID on top of the 3D model via zIndex.\n"
            map += "   Place text/shapes where the 3D model has visual space (edges, corners, top/bottom).\n"
            map += "   The 3D model is controlled by camera angles, NOT by x/y position.\n"
        }
        
        // Column x-coordinate headers
        map += "      "
        for c in 0..<gridCols {
            let xVal = Int(Double(c) * cellW)
            let label = "\(xVal)"
            map += label + String(repeating: " ", count: max(1, 7 - label.count))
        }
        map += "\(cw)\n"
        
        // Grid rendering
        let hBorder = "      +" + String(repeating: "------+", count: gridCols)
        map += hBorder + "\n"
        
        for r in 0..<gridRows {
            let yVal = Int(Double(r) * cellH)
            let yLabel = "\(yVal)"
            map += String(repeating: " ", count: max(0, 5 - yLabel.count)) + yLabel + " |"
            
            for c in 0..<gridCols {
                let count = cellCount[r][c]
                let name = cellFirstName[r][c]
                let cellStr: String
                if count == 0 {
                    cellStr = "  .   "
                } else if count == 1 {
                    let padded = name.count >= 5 ? String(name.prefix(5)) : name + String(repeating: " ", count: 5 - name.count)
                    cellStr = " " + padded
                } else {
                    let short = String(name.prefix(3))
                    let multi = short + "+" + "\(count - 1)"
                    let padded = multi.count >= 5 ? String(multi.prefix(5)) : multi + String(repeating: " ", count: 5 - multi.count)
                    cellStr = " " + padded
                }
                map += cellStr + "|"
            }
            map += "\n"
            map += hBorder + "\n"
        }
        map += " \(ch)\n"
        
        // Zone analysis: divide canvas into horizontal thirds (exclude model3D — it spans all zones)
        let zoneNames = ["TOP", "MID", "BOT"]
        let zoneH = canvasHeight / 3.0
        var zoneParts: [String] = []
        for (i, zoneName) in zoneNames.enumerated() {
            let yStart = Double(i) * zoneH
            let yEnd = yStart + zoneH
            let inZone = objects2D.filter { obj in
                let objTop = obj.properties.y - obj.properties.height / 2
                let objBot = obj.properties.y + obj.properties.height / 2
                return objBot > yStart && objTop < yEnd
            }
            if inZone.isEmpty {
                zoneParts.append("\(zoneName)(y:\(Int(yStart))-\(Int(yEnd))): EMPTY")
            } else {
                let names = inZone.map { $0.name }
                zoneParts.append("\(zoneName)(y:\(Int(yStart))-\(Int(yEnd))): \(names.joined(separator: ", "))")
            }
        }
        map += "Zones: " + zoneParts.joined(separator: " | ") + "\n"
        
        // Overlap detection (skip full-canvas backgrounds and model3D to reduce noise)
        if objects2D.count >= 2 {
            var overlaps: [String] = []
            for i in 0..<objects2D.count {
                let a = objects2D[i]
                if a.properties.width >= canvasWidth * 0.95 && a.properties.height >= canvasHeight * 0.95 { continue }
                let aL = a.properties.x - a.properties.width / 2
                let aR = a.properties.x + a.properties.width / 2
                let aT = a.properties.y - a.properties.height / 2
                let aB = a.properties.y + a.properties.height / 2
                for j in (i + 1)..<objects2D.count {
                    let b = objects2D[j]
                    if b.properties.width >= canvasWidth * 0.95 && b.properties.height >= canvasHeight * 0.95 { continue }
                    let bL = b.properties.x - b.properties.width / 2
                    let bR = b.properties.x + b.properties.width / 2
                    let bT = b.properties.y - b.properties.height / 2
                    let bB = b.properties.y + b.properties.height / 2
                    if aL < bR && aR > bL && aT < bB && aB > bT {
                        overlaps.append("\(a.name) <-> \(b.name)")
                        if overlaps.count >= 6 { break }
                    }
                }
                if overlaps.count >= 6 { break }
            }
            if !overlaps.isEmpty {
                map += "Overlapping: \(overlaps.joined(separator: ", "))\n"
            }
        }
        
        map += "--- END MAP ---\n"
        
        // Animation timeline map — shows WHEN objects appear/animate
        map += timelineMap()
        
        return map
    }
    
    /// Generate a timeline visualization showing when objects and their animations are active.
    /// This helps the AI coordinate timing between 2D text/shapes and 3D model animations.
    private func timelineMap() -> String {
        guard !objects.isEmpty else { return "" }
        
        let totalDuration = max(duration, 1.0)
        let timelineCols = 20  // 20 columns representing the timeline
        let colDuration = totalDuration / Double(timelineCols)
        
        var timeline = "\n--- ANIMATION TIMELINE (duration: \(String(format: "%.1f", totalDuration))s) ---\n"
        
        // Header: time markers
        timeline += "         "
        for c in 0..<timelineCols {
            if c % 4 == 0 {
                let timeLabel = String(format: "%.0f", Double(c) * colDuration)
                timeline += timeLabel
                timeline += String(repeating: " ", count: max(0, 2 - timeLabel.count))
            } else {
                timeline += "  "
            }
        }
        timeline += String(format: " %.0fs\n", totalDuration)
        
        // Each object gets a row showing when its animations are active
        for obj in objects {
            // Object name (truncated to 8 chars for alignment)
            let name = String(obj.name.prefix(8))
            let paddedName = name + String(repeating: " ", count: max(0, 9 - name.count))
            timeline += paddedName
            
            if obj.animations.isEmpty {
                // Static object — show as solid bar (visible entire time)
                timeline += String(repeating: "■", count: timelineCols)
            } else {
                // Build timeline bar
                var bar = Array(repeating: "·", count: timelineCols)
                
                // Check for entrance animations that hide the object before they start
                let entranceTypes: Set<AnimationType> = [
                    .fadeIn, .slideIn, .pop, .grow, .scale, .reveal, .wipeIn, .clipIn,
                    .scaleUp3D, .popIn3D, .tornado, .materialFade,
                    .springBounce3D, .slamDown3D, .dropAndSettle, .corkscrew, .zigzagDrop, .unwrap
                ]
                let hasEntrance = obj.animations.contains { entranceTypes.contains($0.type) }
                let earliestEntrance = obj.animations
                    .filter { entranceTypes.contains($0.type) }
                    .map { $0.startTime + $0.delay }
                    .min() ?? 0
                
                // Mark hidden period before entrance
                if hasEntrance && earliestEntrance > 0 {
                    let hiddenEndCol = min(timelineCols, Int(earliestEntrance / colDuration))
                    for c in 0..<hiddenEndCol {
                        bar[c] = "○"  // hidden/invisible
                    }
                }
                
                // Mark animation periods
                for anim in obj.animations {
                    let start = anim.startTime + anim.delay
                    let end: Double
                    if anim.repeatCount == -1 {
                        end = totalDuration  // infinite loop
                    } else {
                        let repeats = Double(max(1, anim.repeatCount + 1))
                        end = start + anim.duration * repeats
                    }
                    
                    let startCol = max(0, Int(start / colDuration))
                    let endCol = min(timelineCols, Int(ceil(end / colDuration)))
                    
                    let is3D = obj.type == .model3D
                    let symbol = is3D ? "▓" : "█"
                    
                    for c in startCol..<endCol {
                        if bar[c] == "○" {
                            continue  // don't overwrite hidden period
                        }
                        bar[c] = symbol
                    }
                }
                
                // After all animations end, object is visible but static
                let lastAnimEnd = obj.animations.map { anim -> Double in
                    let start = anim.startTime + anim.delay
                    if anim.repeatCount == -1 { return totalDuration }
                    let repeats = Double(max(1, anim.repeatCount + 1))
                    return start + anim.duration * repeats
                }.max() ?? 0
                
                if lastAnimEnd < totalDuration && hasEntrance {
                    let staticStart = Int(lastAnimEnd / colDuration)
                    for c in staticStart..<timelineCols {
                        if bar[c] == "·" { bar[c] = "■" }  // visible but static
                    }
                } else if !hasEntrance {
                    // No entrance — visible the entire time
                    for c in 0..<timelineCols {
                        if bar[c] == "·" { bar[c] = "■" }
                    }
                }
                
                timeline += bar.joined()
            }
            
            // Append type indicator for quick scanning
            if obj.type == .model3D {
                timeline += " [3D]"
            } else if obj.type == .shader {
                timeline += " [shd]"
            } else if obj.type == .text {
                timeline += " [txt]"
            } else if obj.type == .image {
                timeline += " [img]"
            }
            
            timeline += "\n"
        }
        
        timeline += "Legend: ○=hidden ■=visible(static) █=2D animating ▓=3D animating ·=inactive\n"
        timeline += "--- END TIMELINE ---\n"
        
        return timeline
    }
}
