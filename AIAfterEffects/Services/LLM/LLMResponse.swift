//
//  LLMResponse.swift
//  AIAfterEffects
//
//  Models for LLM response parsing and scene commands
//

import Foundation

// MARK: - LLM Response

struct LLMResponse {
    let textResponse: String
    let commands: SceneCommands?
    
    var hasCommands: Bool {
        commands != nil
    }
}

// MARK: - Scene Commands

/// Commands that the AI generates to modify the scene
struct SceneCommands: Codable {
    var message: String?
    var actions: [SceneAction]?
    
    init(message: String? = nil, actions: [SceneAction]? = nil) {
        self.message = message
        self.actions = actions
    }
}

// MARK: - Scene Action

struct SceneAction: Codable {
    let type: ActionType
    let target: String?
    let parameters: ActionParameters?
    
    init(type: ActionType, target: String?, parameters: ActionParameters?) {
        self.type = type
        self.target = target
        self.parameters = parameters
    }
    
    // Custom decoder to handle both nested and flat JSON formats
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKeys.self)
        
        // Decode action type
        self.type = try container.decode(ActionType.self, forKey: FlexibleCodingKeys(stringValue: "type")!)
        
        // Decode target (could be "target", "targetId", "id", or "name")
        if let target = try? container.decode(String.self, forKey: FlexibleCodingKeys(stringValue: "target")!) {
            self.target = target
        } else if let targetId = try? container.decode(String.self, forKey: FlexibleCodingKeys(stringValue: "targetId")!) {
            self.target = targetId
        } else if let id = try? container.decode(String.self, forKey: FlexibleCodingKeys(stringValue: "id")!) {
            self.target = id
        } else {
            self.target = nil
        }
        
        // Try to decode nested parameters first
        if let params = try? container.decode(ActionParameters.self, forKey: FlexibleCodingKeys(stringValue: "parameters")!) {
            self.parameters = params
        } else {
            // Flat format: decode the entire container as ActionParameters
            // Re-decode from the same container but as ActionParameters
            self.parameters = try? ActionParameters(from: decoder)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(target, forKey: .target)
        try container.encodeIfPresent(parameters, forKey: .parameters)
    }
    
    private enum CodingKeys: String, CodingKey {
        case type, target, parameters
    }
    
    // Flexible coding keys to handle any string key
    struct FlexibleCodingKeys: CodingKey {
        var stringValue: String
        var intValue: Int?
        
        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }
        
        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }
    
    enum ActionType: String, Codable, CaseIterable {
        // Object management
        case createObject
        case deleteObject
        case duplicateObject
        
        // Property changes
        case setProperty
        case updateProperties
        
        // Animation
        case addAnimation
        case removeAnimation
        case updateAnimation
        case applyPreset
        case clearAnimations       // Remove ALL animations from an object
        case replaceAllAnimations  // Clear all animations then add new ones (bulk replace)
        
        // Procedural Effects
        case applyEffect           // Particle burst, splash, shatter, trail, motionPath, spring
        
        // Shader Effects
        case applyShaderEffect
        case removeShaderEffect
        
        // Scene
        case clearScene
        case setCanvasSize
        case setBackgroundColor
        case setDuration
        
        // Multi-Scene (Project)
        case createScene          // AI creates a new scene
        case deleteScene          // AI removes a scene
        case switchScene          // AI switches to a different scene for editing
        case renameScene          // AI renames a scene
        case setTransition        // AI sets transition between two scenes
        case reorderScenes        // AI changes scene order
        
        // Custom decoder to handle case variations
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            
            // Try exact match first
            if let type = ActionType(rawValue: rawValue) {
                self = type
                return
            }
            
            // Try case-insensitive match
            let lowercased = rawValue.lowercased()
            for type in ActionType.allCases {
                if type.rawValue.lowercased() == lowercased {
                    self = type
                    return
                }
            }
            
            // Try common variations
            switch lowercased {
            case "create", "create_object", "createobject", "addobject", "add_object":
                self = .createObject
            case "delete", "delete_object", "deleteobject", "remove", "removeobject":
                self = .deleteObject
            case "animate", "add_animation", "addanimation":
                self = .addAnimation
            case "remove_animation", "removeanimation", "deletanimation":
                self = .removeAnimation
        case "applypreset", "apply_preset", "preset", "applyPreset":
            self = .applyPreset
            case "update", "modify", "change", "set":
                self = .updateProperties
            case "clearanimations", "clear_animations", "removeallanimations", "remove_all_animations", "stripanimations":
                self = .clearAnimations
            case "replaceallanimations", "replace_all_animations", "replaceanimations", "replace_animations", "resetanimations", "reset_animations":
                self = .replaceAllAnimations
            case "applyshadereffect", "apply_shader_effect", "shader", "shadereffect", "shader_effect", "addshader", "add_shader":
                self = .applyShaderEffect
            case "removeshadereffect", "remove_shader_effect", "removeshader", "remove_shader":
                self = .removeShaderEffect
            case "clear", "reset", "clearall":
                self = .clearScene
            case "createscene", "create_scene", "addscene", "add_scene", "newscene", "new_scene":
                self = .createScene
            case "deletescene", "delete_scene", "removescene", "remove_scene":
                self = .deleteScene
            case "switchscene", "switch_scene", "gotoscene", "go_to_scene", "selectscene", "select_scene":
                self = .switchScene
            case "renamescene", "rename_scene":
                self = .renameScene
            case "settransition", "set_transition", "addtransition", "add_transition", "transition":
                self = .setTransition
            case "reorderscenes", "reorder_scenes", "sortscenes", "sort_scenes":
                self = .reorderScenes
            default:
                DebugLogger.shared.error("Unknown action type: '\(rawValue)'", category: .parsing)
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown action type: \(rawValue)")
            }
        }
    }
}

// MARK: - Action Parameters

struct ActionParameters: Codable {
    // Object creation
    var objectType: String?
    var type: String? // Alias for objectType
    var name: String?
    
    // Position & Transform
    var x: Double?
    var y: Double?
    var width: Double?
    var height: Double?
    var size: Double? // Alternative for width/height
    var rotation: Double?
    var scaleX: Double?
    var scaleY: Double?
    var scale: Double? // Alternative for uniform scale
    
    // Appearance
    var fillColor: ColorParameters?
    var strokeColor: ColorParameters?
    var color: ColorParameters? // Alias for fillColor
    var strokeWidth: Double?
    var opacity: Double?
    var cornerRadius: Double?
    var radius: Double? // Alias for cornerRadius
    
    // Text properties
    var text: String?
    var content: String? // Alias for text
    var fontSize: Double?
    var fontName: String?
    var font: String? // Alias for fontName
    var fontWeight: String?
    var weight: String? // Alias for fontWeight
    var textAlignment: String?
    var alignment: String? // Alias for textAlignment
    
    // Icon properties
    var iconName: String?
    var icon: String?
    var symbol: String?
    var iconSize: Double?
    
    // Image properties
    var imageData: String?
    var imageUrl: String?
    var attachmentIndex: Int?
    var attachmentId: String?
    
    // 3D Model properties
    var modelAssetId: String?
    var modelFilePath: String?
    var rotationX: Double?
    var rotationY: Double?
    var rotationZ: Double?
    var scaleZ: Double?
    var cameraDistance: Double?
    var cameraAngleX: Double?
    var cameraAngleY: Double?
    var cameraTargetX: Double?
    var cameraTargetY: Double?
    var cameraTargetZ: Double?
    var environmentLighting: String?
    
    // Metal Shader
    var shaderCode: String?    // AI-generated Metal fragment shader body
    var shaderParam1: Double?  // Custom float parameter 1
    var shaderParam2: Double?  // Custom float parameter 2
    var shaderParam3: Double?  // Custom float parameter 3
    var shaderParam4: Double?  // Custom float parameter 4
    
    // Polygon
    var sides: Int?
    
    // Path / custom shape
    var shapePreset: String?
    var shapePresetPoints: Int?
    var pathData: [PathCommand]?
    var closePath: Bool?
    var lineCap: String?
    var lineJoin: String?
    var dashPattern: [Double]?
    var dashPhase: Double?
    var trimStart: Double?
    var trimEnd: Double?
    var trimOffset: Double?
    
    // Visual Effects
    var blurRadius: Double?
    var brightness: Double?
    var contrast: Double?
    var saturation: Double?
    var hueRotation: Double?
    var grayscale: Double?
    var blendMode: String?
    var shadowColor: ColorParameters?
    var shadowRadius: Double?
    var shadowOffsetX: Double?
    var shadowOffsetY: Double?
    var colorInvert: Bool?
    
    // Layering
    var zIndex: Int?
    var layer: Int? // Alias for zIndex
    
    // Animation parameters
    var animationType: String?
    var animation: String? // Alias for animationType
    var duration: Double?
    var delay: Double?
    var easing: String?
    var startTime: Double?
    var repeatCount: Int?
    var `repeat`: Bool? // Alternative to repeatCount
    var autoReverse: Bool?
    var loop: Bool? // Another alternative
    var infinite: Bool? // Another alternative
    
    // Presets / layout helpers
    var presetName: String?
    var preset: String? // Alias
    var intensity: Double?
    var gridPadding: Double?
    var gridColumns: Int?
    var gridStartX: Double?
    var gridStartY: Double?
    
    // Animation values - flexible to accept numbers or objects
    var fromValue: FlexibleValue?
    var toValue: FlexibleValue?
    var from: FlexibleValue? // Alias
    var to: FlexibleValue? // Alias
    var keyframes: [KeyframeParameter]?
    
    // Scene parameters
    var canvasWidth: Double?
    var canvasHeight: Double?
    var backgroundColor: ColorParameters?
    var background: ColorParameters? // Alias
    var sceneDuration: Double?
    var hex: String? // Direct hex color value (often used for setBackgroundColor)
    
    // Multi-scene parameters
    var sceneName: String?           // Name for new scene / scene to switch to
    var sceneId: String?             // Scene ID to target
    var transitionType: String?      // Transition type: "crossfade", "slideLeft", etc.
    var transitionDuration: Double?  // Transition duration in seconds
    var fromSceneId: String?         // Transition source scene (ID)
    var toSceneId: String?           // Transition destination scene (ID)
    var fromSceneName: String?       // Transition source scene (name fallback)
    var toSceneName: String?         // Transition destination scene (name fallback)
    var sceneOrder: [String]?        // Array of scene IDs for reordering
    
    // Procedural Effect parameters (for applyEffect action)
    var effectType: String?              // "particleBurst", "splash", "shatter", "trail", "motionPath", "spring", "pathMorph"
    var effectCount: Int?                // Particle/fragment count
    var effectSpread: Double?            // Spread angle in degrees
    var effectDirection: Double?         // Direction angle in degrees
    var effectVelocityMin: Double?
    var effectVelocityMax: Double?
    var effectGravity: Double?
    var effectLifetime: Double?
    var effectParticleSize: Double?
    var effectParticleShape: String?     // "circle", "star", "diamond", or any ShapePreset name
    var effectSpin: Bool?
    var effectStiffness: Double?         // Spring stiffness
    var effectDamping: Double?           // Spring damping
    var effectArcHeight: Double?         // Arc motion path height
    var targetShapePreset: String?       // Target shape for pathMorph
    var controlPoints: [[String: Double]]?  // Motion path control points [{x, y, time}]
    
    // GPU Particle System (set programmatically, not from LLM)
    var particleSystemData: ParticleSystemData?
    
    // Extra fields from flat format
    var id: String? // Used as name alias
    var targetId: String? // Used as target reference
    
    init() {}
    
    // Custom decoder to handle flexible color formats
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Object creation
        objectType = try? container.decode(String.self, forKey: .objectType)
        type = try? container.decode(String.self, forKey: .type)
        name = try? container.decode(String.self, forKey: .name)
        id = try? container.decode(String.self, forKey: .id)
        targetId = try? container.decode(String.self, forKey: .targetId)
        
        // Position & Transform
        x = try? container.decode(Double.self, forKey: .x)
        y = try? container.decode(Double.self, forKey: .y)
        width = try? container.decode(Double.self, forKey: .width)
        height = try? container.decode(Double.self, forKey: .height)
        size = try? container.decode(Double.self, forKey: .size)
        rotation = try? container.decode(Double.self, forKey: .rotation)
        scaleX = try? container.decode(Double.self, forKey: .scaleX)
        scaleY = try? container.decode(Double.self, forKey: .scaleY)
        scale = try? container.decode(Double.self, forKey: .scale)
        
        // Appearance - handle flexible color formats
        fillColor = Self.decodeFlexibleColor(from: container, forKey: .fillColor)
        strokeColor = Self.decodeFlexibleColor(from: container, forKey: .strokeColor)
        color = Self.decodeFlexibleColor(from: container, forKey: .color)
        strokeWidth = try? container.decode(Double.self, forKey: .strokeWidth)
        opacity = try? container.decode(Double.self, forKey: .opacity)
        cornerRadius = try? container.decode(Double.self, forKey: .cornerRadius)
        radius = try? container.decode(Double.self, forKey: .radius)
        
        // Text properties
        text = try? container.decode(String.self, forKey: .text)
        content = try? container.decode(String.self, forKey: .content)
        fontSize = try? container.decode(Double.self, forKey: .fontSize)
        fontName = try? container.decode(String.self, forKey: .fontName)
        font = try? container.decode(String.self, forKey: .font)
        fontWeight = try? container.decode(String.self, forKey: .fontWeight)
        weight = try? container.decode(String.self, forKey: .weight)
        textAlignment = try? container.decode(String.self, forKey: .textAlignment)
        alignment = try? container.decode(String.self, forKey: .alignment)
        
        // Icon properties
        iconName = try? container.decode(String.self, forKey: .iconName)
        icon = try? container.decode(String.self, forKey: .icon)
        symbol = try? container.decode(String.self, forKey: .symbol)
        iconSize = try? container.decode(Double.self, forKey: .iconSize)
        
        // Image properties
        imageData = try? container.decode(String.self, forKey: .imageData)
        imageUrl = try? container.decode(String.self, forKey: .imageUrl)
        attachmentIndex = try? container.decode(Int.self, forKey: .attachmentIndex)
        attachmentId = try? container.decode(String.self, forKey: .attachmentId)
        
        // 3D Model properties
        modelAssetId = try? container.decode(String.self, forKey: .modelAssetId)
        modelFilePath = try? container.decode(String.self, forKey: .modelFilePath)
        rotationX = try? container.decode(Double.self, forKey: .rotationX)
        rotationY = try? container.decode(Double.self, forKey: .rotationY)
        rotationZ = try? container.decode(Double.self, forKey: .rotationZ)
        scaleZ = try? container.decode(Double.self, forKey: .scaleZ)
        cameraDistance = try? container.decode(Double.self, forKey: .cameraDistance)
        cameraAngleX = try? container.decode(Double.self, forKey: .cameraAngleX)
        cameraAngleY = try? container.decode(Double.self, forKey: .cameraAngleY)
        cameraTargetX = try? container.decode(Double.self, forKey: .cameraTargetX)
        cameraTargetY = try? container.decode(Double.self, forKey: .cameraTargetY)
        cameraTargetZ = try? container.decode(Double.self, forKey: .cameraTargetZ)
        environmentLighting = try? container.decode(String.self, forKey: .environmentLighting)
        
        // Shader
        shaderCode = try? container.decode(String.self, forKey: .shaderCode)
        shaderParam1 = try? container.decode(Double.self, forKey: .shaderParam1)
        shaderParam2 = try? container.decode(Double.self, forKey: .shaderParam2)
        shaderParam3 = try? container.decode(Double.self, forKey: .shaderParam3)
        shaderParam4 = try? container.decode(Double.self, forKey: .shaderParam4)
        
        // Polygon
        sides = try? container.decode(Int.self, forKey: .sides)
        
        // Path / custom shape
        pathData = try? container.decode([PathCommand].self, forKey: .pathData)
        closePath = try? container.decode(Bool.self, forKey: .closePath)
        lineCap = try? container.decode(String.self, forKey: .lineCap)
        lineJoin = try? container.decode(String.self, forKey: .lineJoin)
        dashPattern = try? container.decode([Double].self, forKey: .dashPattern)
        dashPhase = try? container.decode(Double.self, forKey: .dashPhase)
        trimStart = try? container.decode(Double.self, forKey: .trimStart)
        trimEnd = try? container.decode(Double.self, forKey: .trimEnd)
        trimOffset = try? container.decode(Double.self, forKey: .trimOffset)
        
        // Visual Effects
        blurRadius = try? container.decode(Double.self, forKey: .blurRadius)
        brightness = try? container.decode(Double.self, forKey: .brightness)
        contrast = try? container.decode(Double.self, forKey: .contrast)
        saturation = try? container.decode(Double.self, forKey: .saturation)
        hueRotation = try? container.decode(Double.self, forKey: .hueRotation)
        grayscale = try? container.decode(Double.self, forKey: .grayscale)
        blendMode = try? container.decode(String.self, forKey: .blendMode)
        shadowColor = Self.decodeFlexibleColor(from: container, forKey: .shadowColor)
        shadowRadius = try? container.decode(Double.self, forKey: .shadowRadius)
        shadowOffsetX = try? container.decode(Double.self, forKey: .shadowOffsetX)
        shadowOffsetY = try? container.decode(Double.self, forKey: .shadowOffsetY)
        colorInvert = try? container.decode(Bool.self, forKey: .colorInvert)
        
        // Layering
        zIndex = try? container.decode(Int.self, forKey: .zIndex)
        layer = try? container.decode(Int.self, forKey: .layer)
        
        // Animation parameters
        animationType = try? container.decode(String.self, forKey: .animationType)
        animation = try? container.decode(String.self, forKey: .animation)
        duration = try? container.decode(Double.self, forKey: .duration)
        delay = try? container.decode(Double.self, forKey: .delay)
        easing = try? container.decode(String.self, forKey: .easing)
        startTime = try? container.decode(Double.self, forKey: .startTime)
        repeatCount = try? container.decode(Int.self, forKey: .repeatCount)
        `repeat` = try? container.decode(Bool.self, forKey: .repeat)
        autoReverse = try? container.decode(Bool.self, forKey: .autoReverse)
        loop = try? container.decode(Bool.self, forKey: .loop)
        infinite = try? container.decode(Bool.self, forKey: .infinite)
        
        // Presets / layout helpers
        presetName = try? container.decode(String.self, forKey: .presetName)
        preset = try? container.decode(String.self, forKey: .preset)
        intensity = try? container.decode(Double.self, forKey: .intensity)
        gridPadding = try? container.decode(Double.self, forKey: .gridPadding)
        gridColumns = try? container.decode(Int.self, forKey: .gridColumns)
        gridStartX = try? container.decode(Double.self, forKey: .gridStartX)
        gridStartY = try? container.decode(Double.self, forKey: .gridStartY)
        
        // Animation values
        fromValue = try? container.decode(FlexibleValue.self, forKey: .fromValue)
        toValue = try? container.decode(FlexibleValue.self, forKey: .toValue)
        from = try? container.decode(FlexibleValue.self, forKey: .from)
        to = try? container.decode(FlexibleValue.self, forKey: .to)
        keyframes = try? container.decode([KeyframeParameter].self, forKey: .keyframes)
        
        // Scene parameters
        canvasWidth = try? container.decode(Double.self, forKey: .canvasWidth)
        canvasHeight = try? container.decode(Double.self, forKey: .canvasHeight)
        backgroundColor = Self.decodeFlexibleColor(from: container, forKey: .backgroundColor)
        background = Self.decodeFlexibleColor(from: container, forKey: .background)
        sceneDuration = try? container.decode(Double.self, forKey: .sceneDuration)
        hex = try? container.decode(String.self, forKey: .hex)
        
        // Multi-scene parameters
        sceneName = try? container.decode(String.self, forKey: .sceneName)
        sceneId = try? container.decode(String.self, forKey: .sceneId)
        transitionType = try? container.decode(String.self, forKey: .transitionType)
        transitionDuration = try? container.decode(Double.self, forKey: .transitionDuration)
        fromSceneId = try? container.decode(String.self, forKey: .fromSceneId)
        toSceneId = try? container.decode(String.self, forKey: .toSceneId)
        fromSceneName = try? container.decode(String.self, forKey: .fromSceneName)
        toSceneName = try? container.decode(String.self, forKey: .toSceneName)
        sceneOrder = try? container.decode([String].self, forKey: .sceneOrder)
        
        // Shape presets
        shapePreset = try? container.decode(String.self, forKey: .shapePreset)
        shapePresetPoints = try? container.decode(Int.self, forKey: .shapePresetPoints)
        
        // Procedural effect parameters
        effectType = try? container.decode(String.self, forKey: .effectType)
        effectCount = try? container.decode(Int.self, forKey: .effectCount)
        effectSpread = try? container.decode(Double.self, forKey: .effectSpread)
        effectDirection = try? container.decode(Double.self, forKey: .effectDirection)
        effectVelocityMin = try? container.decode(Double.self, forKey: .effectVelocityMin)
        effectVelocityMax = try? container.decode(Double.self, forKey: .effectVelocityMax)
        effectGravity = try? container.decode(Double.self, forKey: .effectGravity)
        effectLifetime = try? container.decode(Double.self, forKey: .effectLifetime)
        effectParticleSize = try? container.decode(Double.self, forKey: .effectParticleSize)
        effectParticleShape = try? container.decode(String.self, forKey: .effectParticleShape)
        effectSpin = try? container.decode(Bool.self, forKey: .effectSpin)
        effectStiffness = try? container.decode(Double.self, forKey: .effectStiffness)
        effectDamping = try? container.decode(Double.self, forKey: .effectDamping)
        effectArcHeight = try? container.decode(Double.self, forKey: .effectArcHeight)
        targetShapePreset = try? container.decode(String.self, forKey: .targetShapePreset)
        controlPoints = try? container.decode([[String: Double]].self, forKey: .controlPoints)
    }
    
    /// Decode color that could be a string hex or a ColorParameters object
    private static func decodeFlexibleColor(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> ColorParameters? {
        // Try as ColorParameters object first
        if let colorParams = try? container.decode(ColorParameters.self, forKey: key) {
            return colorParams
        }
        // Try as string hex value
        if let hexString = try? container.decode(String.self, forKey: key) {
            return ColorParameters(hex: hexString)
        }
        return nil
    }
    
    private enum CodingKeys: String, CodingKey {
        case objectType, type, name, id, targetId
        case x, y, width, height, size, rotation, scaleX, scaleY, scale
        case fillColor, strokeColor, color, strokeWidth, opacity, cornerRadius, radius
        case text, content, fontSize, fontName, font, fontWeight, weight, textAlignment, alignment
        case iconName, icon, symbol, iconSize
        case imageData, imageUrl, attachmentIndex, attachmentId
        case modelAssetId, modelFilePath, rotationX, rotationY, rotationZ, scaleZ
        case cameraDistance, cameraAngleX, cameraAngleY, cameraTargetX, cameraTargetY, cameraTargetZ, environmentLighting
        case shaderCode, shaderParam1, shaderParam2, shaderParam3, shaderParam4
        case sides
        case pathData, closePath, lineCap, lineJoin, dashPattern, dashPhase, trimStart, trimEnd, trimOffset
        case blurRadius, brightness, contrast, saturation, hueRotation, grayscale
        case blendMode, shadowColor, shadowRadius, shadowOffsetX, shadowOffsetY, colorInvert
        case zIndex, layer
        case animationType, animation, duration, delay, easing, startTime, repeatCount, `repeat`, autoReverse, loop, infinite
        case fromValue, toValue, from, to, keyframes
        case canvasWidth, canvasHeight, backgroundColor, background, sceneDuration, hex
        case presetName, preset, intensity, gridPadding, gridColumns, gridStartX, gridStartY
        case sceneName, sceneId, transitionType, transitionDuration, fromSceneId, toSceneId, fromSceneName, toSceneName, sceneOrder
        case shapePreset, shapePresetPoints
        case effectType, effectCount, effectSpread, effectDirection
        case effectVelocityMin, effectVelocityMax, effectGravity, effectLifetime
        case effectParticleSize, effectParticleShape, effectSpin
        case effectStiffness, effectDamping, effectArcHeight
        case targetShapePreset, controlPoints
    }
    
    // MARK: - Computed Properties (resolve aliases)
    
    var effectiveObjectType: String? {
        let normalized = Self.normalizeObjectType(objectType) ?? Self.normalizeObjectType(type)
        return normalized
    }
    
    var effectiveName: String? {
        name ?? id ?? targetId
    }

    var effectiveSceneDuration: Double? {
        sceneDuration ?? duration
    }
    
    var effectiveWidth: Double? {
        width ?? size
    }
    
    var effectiveHeight: Double? {
        height ?? size
    }
    
    var effectiveFillColor: ColorParameters? {
        fillColor ?? color
    }
    
    var effectiveText: String? {
        text ?? content
    }
    
    var effectiveFontName: String? {
        fontName ?? font
    }
    
    var effectiveFontWeight: String? {
        fontWeight ?? weight
    }
    
    var effectiveTextAlignment: String? {
        textAlignment ?? alignment
    }
    
    var effectiveAnimationType: String? {
        // Check explicit animation type fields first
        if let at = animationType { return at }
        if let anim = animation { return anim }
        
        // Check if 'type' field is an animation type (LLMs often use this)
        if let t = type {
            let lower = t.lowercased()
            // List of known animation types that 'type' might contain
            let animationTypes = [
                "fadein", "fadeout", "fade", "scale", "move", "movex", "movey",
                "rotate", "bounce", "pulse", "shake", "slide", "slidein", "slideout",
                "charbychar", "wordbyword", "typewriter", "glitch", "breathe",
                "scramble", "scramblemorph", "neonpulse", "wave", "elastic",
                "spring", "spin", "flip", "grow", "shrink", "blink", "wobble",
                "position", "opacity", "color", "blur", "glow",
                "rotate3dx", "rotate3dy", "rotate3dz", "orbit3d", "turntable",
                "wobble3d", "flip3d", "float3d", "cradle", "springbounce3d",
                "elasticspin", "swing3d", "breathe3d", "headnod", "headshake",
                "rockandroll", "scaleup3d", "scaledown3d", "slamdown3d",
                "revolveslow", "tumble", "barrelroll", "corkscrew", "figureeight",
                "boomerang3d", "levitate", "magnetpull", "magnetpush", "zigzagdrop",
                "rubberband", "jelly3d", "anticipatespin", "popin3d", "glitchjitter3d",
                "heartbeat3d", "tornado", "unwrap", "dropandsettle",
                "camerazoom", "camerapan", "cameraorbit",
                "spiralzoom", "dollyzoom", "camerarise", "cameradive",
                "camerawhippan", "cameraslide", "cameraarc", "camerapedestal",
                "cameratruck", "camerapushpull", "cameradutchtilt",
                "camerahelicopter", "camerarocket", "camerashake", "materialfade"
            ]
            if animationTypes.contains(lower) || lower.contains("fade") || lower.contains("move") || lower.contains("scale") {
                return t
            }
        }
        
        return nil
    }
    
    var effectiveIconName: String? {
        iconName ?? icon ?? symbol
    }
    
    var effectiveZIndex: Int? {
        zIndex ?? layer
    }
    
    var effectivePresetName: String? {
        presetName ?? preset
    }
    
    var effectiveFromValue: FlexibleValue? {
        fromValue ?? from
    }
    
    var effectiveToValue: FlexibleValue? {
        toValue ?? to
    }
    
    var effectiveBackgroundColor: ColorParameters? {
        // Check for direct hex value first (common LLM pattern)
        if let hexValue = hex {
            return ColorParameters(hex: hexValue)
        }
        return backgroundColor ?? background ?? color
    }
    
    var effectiveRepeatCount: Int {
        if let count = repeatCount { return count }
        if `repeat` == true || loop == true || infinite == true { return -1 }
        return 0
    }
    
    var effectiveCornerRadius: Double? {
        cornerRadius ?? radius
    }
    
    var effectiveSceneName: String? {
        sceneName ?? name ?? id
    }
    
    var effectiveSceneId: String? {
        sceneId ?? id ?? targetId
    }
    
    var effectiveTransitionType: TransitionType? {
        guard let raw = transitionType?.lowercased() else { return nil }
        return TransitionType(rawValue: raw)
    }
    
    // MARK: - Helpers
    
    private static func normalizeObjectType(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        
        let lower = raw.lowercased()
        
        // Ignore action types being mistaken as object types
        let actionTypeNames: Set<String> = [
            "createobject", "deleteobject", "duplicateobject", "setproperty", "updateproperties",
            "addanimation", "removeanimation", "updateanimation", "clearscene", "setcanvassize",
            "setbackgroundcolor", "setduration"
        ]
        if actionTypeNames.contains(lower) { return nil }
        
        // Map common aliases
        switch lower {
        case "rect", "rectangle", "box", "square":
            return "rectangle"
        case "circle", "round":
            return "circle"
        case "ellipse", "oval":
            return "ellipse"
        case "polygon", "poly":
            return "polygon"
        case "text", "title", "label", "type":
            return "text"
        case "line", "rule", "divider":
            return "line"
        case "icon", "symbol", "sf", "sfsymbol":
            return "icon"
        case "image", "img", "photo", "picture", "bitmap", "png", "jpg", "jpeg", "webp":
            return "image"
        case "path", "shape", "custom", "custompath", "custom_path", "bezier", "curve", "freeform":
            return "path"
        case "model3d", "3dmodel", "3d_model", "3d", "mesh", "model":
            return "model3D"
        case "shader", "metalshader", "metal_shader", "metal", "effect", "shadereffect", "shader_effect":
            return "shader"
        default:
            return nil
        }
    }
}

// MARK: - Flexible Value (accepts number or AnimationValue object)

enum FlexibleValue: Codable {
    case number(Double)
    case animationValue(AnimationValue)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // Try decoding as a number first
        if let doubleValue = try? container.decode(Double.self) {
            self = .number(doubleValue)
            return
        }
        
        // Try decoding as AnimationValue object
        if let animValue = try? container.decode(AnimationValue.self) {
            self = .animationValue(animValue)
            return
        }
        
        // Default to 0
        self = .number(0)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let value):
            try container.encode(value)
        case .animationValue(let value):
            try container.encode(value)
        }
    }
    
    var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        case .animationValue(let animValue):
            if let d = animValue.doubleValue { return d }
            return nil
        }
    }
}

// MARK: - Color Parameters

struct ColorParameters: Codable {
    var red: Double?
    var green: Double?
    var blue: Double?
    var alpha: Double?
    var hex: String?
    var name: String? // "red", "blue", etc.
    
    func toCodableColor() -> CodableColor {
        // If hex is provided
        if let hex = hex {
            return CodableColor.fromHex(hex)
        }
        
        // If named color
        if let name = name?.lowercased() {
            switch name {
            case "red": return .red
            case "green": return .green
            case "blue": return .blue
            case "white": return .white
            case "black": return .black
            case "yellow": return .yellow
            case "orange": return .orange
            case "purple": return .purple
            case "pink": return .pink
            case "cyan": return .cyan
            case "clear": return .clear
            default: break
            }
        }
        
        // Use RGB values
        return CodableColor(
            red: red ?? 1,
            green: green ?? 1,
            blue: blue ?? 1,
            alpha: alpha ?? 1
        )
    }
}

// MARK: - Animation Value

struct AnimationValue: Codable {
    var doubleValue: Double?
    var pointX: Double?
    var pointY: Double?
    var scaleX: Double?
    var scaleY: Double?
    var color: ColorParameters?
}

// MARK: - Keyframe Parameter

struct KeyframeParameter: Codable {
    var time: Double
    var value: AnimationValue
}

// MARK: - CodableColor Extension for Hex

extension CodableColor {
    static func fromHex(_ hex: String) -> CodableColor {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        return CodableColor(red: r, green: g, blue: b)
    }
}
