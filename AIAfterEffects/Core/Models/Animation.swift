//
//  Animation.swift
//  AIAfterEffects
//
//  Animation definitions and keyframe models
//

import Foundation

// MARK: - Animation Types

enum AnimationType: String, Codable, Equatable, CaseIterable {
    // Position
    case moveX
    case moveY
    case move
    
    // Transform
    case scale
    case scaleX
    case scaleY
    case rotate
    
    // Appearance
    case fadeIn
    case fadeOut
    case fade
    case colorChange
    case fillColorChange
    case strokeColorChange
    case blurIn
    case blurOut
    
    // Basic Combined
    case bounce
    case shake
    case pulse
    case slideIn
    case slideOut
    case typewriter
    case wave
    case spin
    case grow
    case shrink
    case pop
    case wiggle
    
    // Advanced - Disney Principles
    case anticipation      // Prep movement before main action
    case overshoot         // Go past target then settle back
    case followThrough     // Continue after main action settles
    case squashStretch     // Compress/extend for impact
    
    // Advanced - Text Animations
    case charByChar        // Animate each character with stagger
    case wordByWord        // Animate each word with stagger
    case lineByLine        // Animate each line with stagger
    case scramble          // Scramble characters then resolve
    case glitchText        // RGB split + position jitter on text
    
    // Advanced - Reveals & Masks
    case reveal            // Mask reveal from direction
    case wipeIn            // Wipe reveal
    case wipeOut           // Wipe hide
    case clipIn            // Clip from edge
    case splitReveal       // Split from center and reveal
    
    // Advanced - Impact Effects
    case glitch            // RGB channel split + distortion
    case flicker           // Rapid opacity flicker
    case flash             // Bright flash then settle
    case slam              // Fast in with impact shake
    case explode           // Scale out with opacity
    case implode           // Scale in from large
    
    // Advanced - Organic Motion
    case float             // Gentle floating motion
    case drift             // Slow directional drift
    case breathe           // Subtle scale breathing
    case sway              // Pendulum-like sway
    case jitter            // Micro random movement
    
    // Advanced - Kinetic Typography
    case dropIn            // Drop from above with bounce
    case riseUp            // Rise from below
    case swingIn           // Swing in from anchor point
    case elasticIn         // Elastic scale entrance
    case elasticOut        // Elastic scale exit
    case snapIn            // Quick snap into position
    case whipIn            // Fast whip from side
    case zoomBlur          // Zoom with motion blur feel
    case tracking          // Animate letter-spacing (kerning) from wide to normal
    
    // Visual Effects (animate filters & adjustments)
    case blur              // Animate blur radius
    case brightnessAnim    // Animate brightness
    case contrastAnim      // Animate contrast
    case saturationAnim    // Animate saturation
    case hueRotate         // Animate hue rotation
    case grayscaleAnim     // Animate grayscale amount
    case shadowAnim        // Animate shadow radius
    
    // Path Animations (After Effects-style)
    case trimPath          // Trim path start/end (draw-on stroke reveal)
    case trimPathStart     // Animate trim start only (0→1)
    case trimPathEnd       // Animate trim end only (0→1)
    case trimPathOffset    // Animate trim offset (shift where trim begins)
    case strokeWidthAnim   // Animate stroke width
    case dashOffset        // Animate dash pattern offset (marching ants)
    
    // 3D Transform Animations (for model3D objects)
    case rotate3DX         // Rotate around X axis
    case rotate3DY         // Rotate around Y axis
    case rotate3DZ         // Rotate around Z axis
    case orbit3D           // Orbit around a point in 3D space
    case turntable         // Classic product showcase spin (Y-axis)
    case wobble3D          // Gentle rocking motion in 3D
    case flip3D            // Flip 180/360 on an axis
    case float3D           // Gentle up/down floating in 3D space
    case cradle            // Pendulum swing on Y axis with damping (C4D-inspired)
    case springBounce3D    // Drop from height with spring physics bounce
    case elasticSpin       // Spin with elastic overshoot that settles (GSAP-inspired)
    case swing3D           // Pendulum rotation on Z axis (Three.js-inspired)
    case breathe3D         // Rhythmic scale pulse on all axes (Blender MoGraph)
    case headNod           // Tilt forward/back on X axis (character nod)
    case headShake         // Quick shake on Y axis (character "no")
    case rockAndRoll       // Combined X+Z rotation rocking (C4D vibrate)
    case scaleUp3D         // Scale from 0 to full with overshoot
    case scaleDown3D       // Scale from full to 0 with anticipation
    case slamDown3D        // Fast drop from above with impact squash
    case revolveSlow       // Ultra-slow elegant partial turn (product showcase)
    case tumble            // Chaotic multi-axis tumble like tossed in air (Houdini-inspired)
    case barrelRoll        // 360° roll on Z axis while maintaining position
    case corkscrew         // Helical upward spiral (position + rotation combined)
    case figureEight       // Infinity loop path in 3D space (Lissajous)
    case boomerang3D       // Fling out and curve back to origin (AE expression-inspired)
    case levitate          // Zero-gravity float upward with gentle drift (product trend 2025)
    case magnetPull        // Accelerating pull toward camera (Houdini force field)
    case magnetPush        // Decelerating push away from camera
    case zigzagDrop        // Zigzag descent like a falling leaf
    case rubberBand        // Stretch on one axis, snap back elastic (GSAP CustomBounce)
    case jelly3D           // Squash/stretch wobble on all axes simultaneously (Disney principle)
    case anticipateSpin    // Pull back slightly, then whip spin (AE anticipation + spin)
    case popIn3D           // Scale 0→overshoot→settle with rotation burst
    case glitchJitter3D    // Rapid micro random position + rotation jitter (glitch aesthetic)
    case heartbeat3D       // Double-beat scale pulse like a heartbeat (ba-dum... ba-dum)
    case tornado           // Vortex: fast spin + rising + scaling (Houdini tornado)
    case unwrap            // Rotate from flat (90° X) to face camera (0°) — like unfolding
    case dropAndSettle     // Fall with realistic gravity curve + micro bounce (C4D Delay Effector)
    
    // 3D Camera Animations
    case cameraZoom        // Dolly camera in/out
    case cameraPan         // Pan camera around model
    case cameraOrbit       // Orbit camera around model
    case spiralZoom        // Camera spirals inward toward model (dolly + orbit)
    case dollyZoom         // Hitchcock vertigo — dolly in while zooming out
    case cameraRise        // Camera rises vertically (crane shot)
    case cameraDive        // Camera dives downward dramatically
    case cameraWhipPan     // Ultra-fast camera pan with settle
    case cameraSlide       // Camera slides laterally (dolly track)
    case cameraArc         // Cinematic arc shot — semicircle around model at angle
    case cameraPedestal    // Camera moves straight up/down (pedestal/boom)
    case cameraTruck       // Camera moves laterally parallel to model (truck shot)
    case cameraPushPull    // Dramatic push-in then pull-out in one shot
    case cameraDutchTilt   // Camera rolls to dutch angle and back
    case cameraHelicopter  // Overhead descending spiral (helicopter shot)
    case cameraRocket      // Fast upward camera launch from ground level
    case cameraShake       // Cinematic camera shake (earthquake/impact feel)
    
    // 3D Position Keyframe Tracks
    case move3DX           // Keyframe track for 3D X position
    case move3DY           // Keyframe track for 3D Y position
    case move3DZ           // Keyframe track for 3D Z position
    case scale3DZ          // Keyframe track for independent Z-axis scale
    
    // 3D Material/Appearance
    case materialFade      // Fade 3D model opacity
    
    // Text Property Tracks
    case textSizeChange    // Keyframe track for font size
    
    // Anime.js-Inspired: Stagger-Based (group effects)
    case staggerFadeIn     // Cascading fade in across group
    case staggerSlideUp    // Cascading slide up across group
    case staggerScaleIn    // Cascading scale in across group
    case ripple            // Radial stagger from center
    case cascade           // Waterfall stagger effect
    case domino            // Sequential topple effect
    
    // Anime.js-Inspired: Combo Entrances (multi-property)
    case scaleRotateIn     // Scale from 0 + rotate in
    case blurSlideIn       // Blur clears as it slides in
    case flipReveal        // 3D flip entrance revealing content
    case elasticSlideIn    // Slide with elastic overshoot
    case spiralIn          // Spiral inward to final position
    case unfold            // Unfold from flat line to full size
    
    // Anime.js-Inspired: Combo Exits (multi-property)
    case scaleRotateOut    // Scale to 0 + rotate out
    case blurSlideOut      // Slide out while blurring
    case flipHide          // 3D flip exit hiding content
    case spiralOut         // Spiral outward from position
    case foldUp            // Fold to flat line
    
    // Anime.js-Inspired: Continuous/Loop Effects
    case pendulum          // Smooth pendulum swing (sine-based)
    case orbit2D           // Circular orbit in 2D plane
    case lemniscate        // Figure-8 / infinity loop in 2D
    case morphPulse        // Alternating scaleX/scaleY squash-stretch
    case neonFlicker       // Random opacity flicker like a neon sign
    case glowPulse         // Shadow/glow radius pulsing
    case oscillate         // Generic sine wave oscillation
    
    // Anime.js-Inspired: Text Effects
    case textWave          // Wave motion across characters
    case textRainbow       // Per-character hue rotation
    case textBounceIn      // Characters bounce in from above
    case textElasticIn     // Characters elastic scale in
    
    // Path Morphing
    case pathMorph         // Interpolate between two sets of PathCommands
    
    // Inspector Keyframe (user-inserted keyframes from inspector edits)
    case propertyChange    // Generic property change keyframe (for properties without a dedicated type)
    
    // MARK: - Property-to-AnimationType Mapping
    
    /// Returns the appropriate AnimationType for a given property name when inserting keyframes from the inspector.
    static func animationType(forProperty property: String) -> AnimationType {
        switch property {
        case "x":           return .moveX
        case "y":           return .moveY
        case "opacity":     return .fade
        case "fillColor":   return .fillColorChange
        case "strokeColor": return .strokeColorChange
        case "rotation":    return .rotate
        case "scaleX":      return .scaleX
        case "scaleY":      return .scaleY
        case "blurRadius":  return .blur
        case "brightness":  return .brightnessAnim
        case "contrast":    return .contrastAnim
        case "saturation":  return .saturationAnim
        case "hueRotation": return .hueRotate
        case "grayscale":   return .grayscaleAnim
        case "strokeWidth": return .strokeWidthAnim
        case "trimStart":   return .trimPathStart
        case "trimEnd":     return .trimPathEnd
        case "trimOffset":  return .trimPathOffset
        case "dashPhase":   return .dashOffset
        case "shadowRadius": return .shadowAnim
        case "position3DX": return .move3DX
        case "position3DY": return .move3DY
        case "position3DZ": return .move3DZ
        case "scaleZ":      return .scale3DZ
        case "fontSize":    return .textSizeChange
        case "rotationX":   return .rotate3DX
        case "rotationY":   return .rotate3DY
        case "rotationZ":   return .rotate3DZ
        case "cameraDistance": return .cameraZoom
        case "cameraAngleX": return .cameraRise
        case "cameraAngleY": return .cameraPan
        default:            return .propertyChange
        }
    }
    
    /// Whether this animation type uses `.double` keyframe values (single numeric property).
    var usesDoubleKeyframes: Bool {
        switch self {
        case .fade, .fadeIn, .fadeOut,
             .moveX, .moveY,
             .rotate, .spin,
             .scaleX, .scaleY,
             .blur, .blurIn, .blurOut,
             .brightnessAnim, .contrastAnim, .saturationAnim,
             .hueRotate, .grayscaleAnim, .shadowAnim,
             .move3DX, .move3DY, .move3DZ,
             .scale3DZ, .textSizeChange,
             .strokeWidthAnim, .trimPathStart, .trimPathEnd,
             .trimPathOffset, .dashOffset,
             .propertyChange:
            return true
        default:
            return false
        }
    }
}

// MARK: - Easing Types

enum EasingType: Equatable {
    // Basic
    case linear
    case easeIn
    case easeOut
    case easeInOut
    
    // Quadratic (smooth)
    case easeInQuad
    case easeOutQuad
    case easeInOutQuad
    
    // Cubic (smoother)
    case easeInCubic
    case easeOutCubic
    case easeInOutCubic
    
    // Quartic (even smoother)
    case easeInQuart
    case easeOutQuart
    case easeInOutQuart
    
    // Quintic (Anime.js-inspired)
    case easeInQuint
    case easeOutQuint
    case easeInOutQuint
    
    // Sine (Anime.js-inspired)
    case easeInSine
    case easeOutSine
    case easeInOutSine
    
    // Circular (Anime.js-inspired)
    case easeInCirc
    case easeOutCirc
    case easeInOutCirc
    
    // Exponential (dramatic)
    case easeInExpo
    case easeOutExpo
    case easeInOutExpo
    
    // Back (overshoot)
    case easeInBack
    case easeOutBack      // Goes past then settles - great for pop-in
    case easeInOutBack
    
    // Physics-based
    case spring           // Springy settle
    case bounce           // Bouncing settle
    case elastic          // Elastic wobble
    
    // Special
    case anticipate       // Pull back then go
    case overshootSettle  // Overshoot then ease back
    case snapBack         // Quick snap with micro bounce
    case smooth           // Extra smooth bezier
    case sharp            // Sharp acceleration
    case punch            // Fast start, quick stop
    
    // Advanced parametric (Anime.js-inspired)
    case cubicBezier(x1: Double, y1: Double, x2: Double, y2: Double)
    case steps(Int)
    case springCustom(stiffness: Double, damping: Double, mass: Double)
}

// MARK: - EasingType Backward-Compatible Raw Value

extension EasingType {
    /// Backward-compatible string identifier (matches old String raw value)
    var rawValue: String {
        switch self {
        case .linear: return "linear"
        case .easeIn: return "easeIn"
        case .easeOut: return "easeOut"
        case .easeInOut: return "easeInOut"
        case .easeInQuad: return "easeInQuad"
        case .easeOutQuad: return "easeOutQuad"
        case .easeInOutQuad: return "easeInOutQuad"
        case .easeInCubic: return "easeInCubic"
        case .easeOutCubic: return "easeOutCubic"
        case .easeInOutCubic: return "easeInOutCubic"
        case .easeInQuart: return "easeInQuart"
        case .easeOutQuart: return "easeOutQuart"
        case .easeInOutQuart: return "easeInOutQuart"
        case .easeInQuint: return "easeInQuint"
        case .easeOutQuint: return "easeOutQuint"
        case .easeInOutQuint: return "easeInOutQuint"
        case .easeInSine: return "easeInSine"
        case .easeOutSine: return "easeOutSine"
        case .easeInOutSine: return "easeInOutSine"
        case .easeInCirc: return "easeInCirc"
        case .easeOutCirc: return "easeOutCirc"
        case .easeInOutCirc: return "easeInOutCirc"
        case .easeInExpo: return "easeInExpo"
        case .easeOutExpo: return "easeOutExpo"
        case .easeInOutExpo: return "easeInOutExpo"
        case .easeInBack: return "easeInBack"
        case .easeOutBack: return "easeOutBack"
        case .easeInOutBack: return "easeInOutBack"
        case .spring: return "spring"
        case .bounce: return "bounce"
        case .elastic: return "elastic"
        case .anticipate: return "anticipate"
        case .overshootSettle: return "overshootSettle"
        case .snapBack: return "snapBack"
        case .smooth: return "smooth"
        case .sharp: return "sharp"
        case .punch: return "punch"
        case .cubicBezier: return "cubicBezier"
        case .steps: return "steps"
        case .springCustom: return "springCustom"
        }
    }
    
    /// Backward-compatible initializer from string
    init?(rawValue: String) {
        switch rawValue {
        case "linear": self = .linear
        case "easeIn": self = .easeIn
        case "easeOut": self = .easeOut
        case "easeInOut": self = .easeInOut
        case "easeInQuad": self = .easeInQuad
        case "easeOutQuad": self = .easeOutQuad
        case "easeInOutQuad": self = .easeInOutQuad
        case "easeInCubic": self = .easeInCubic
        case "easeOutCubic": self = .easeOutCubic
        case "easeInOutCubic": self = .easeInOutCubic
        case "easeInQuart": self = .easeInQuart
        case "easeOutQuart": self = .easeOutQuart
        case "easeInOutQuart": self = .easeInOutQuart
        case "easeInQuint": self = .easeInQuint
        case "easeOutQuint": self = .easeOutQuint
        case "easeInOutQuint": self = .easeInOutQuint
        case "easeInSine": self = .easeInSine
        case "easeOutSine": self = .easeOutSine
        case "easeInOutSine": self = .easeInOutSine
        case "easeInCirc": self = .easeInCirc
        case "easeOutCirc": self = .easeOutCirc
        case "easeInOutCirc": self = .easeInOutCirc
        case "easeInExpo": self = .easeInExpo
        case "easeOutExpo": self = .easeOutExpo
        case "easeInOutExpo": self = .easeInOutExpo
        case "easeInBack": self = .easeInBack
        case "easeOutBack": self = .easeOutBack
        case "easeInOutBack": self = .easeInOutBack
        case "spring": self = .spring
        case "bounce": self = .bounce
        case "elastic": self = .elastic
        case "anticipate": self = .anticipate
        case "overshootSettle": self = .overshootSettle
        case "snapBack": self = .snapBack
        case "smooth": self = .smooth
        case "sharp": self = .sharp
        case "punch": self = .punch
        default: return nil
        }
    }
}

// MARK: - EasingType CaseIterable

extension EasingType: CaseIterable {
    static var allCases: [EasingType] {
        [
            .linear, .easeIn, .easeOut, .easeInOut,
            .easeInQuad, .easeOutQuad, .easeInOutQuad,
            .easeInCubic, .easeOutCubic, .easeInOutCubic,
            .easeInQuart, .easeOutQuart, .easeInOutQuart,
            .easeInQuint, .easeOutQuint, .easeInOutQuint,
            .easeInSine, .easeOutSine, .easeInOutSine,
            .easeInCirc, .easeOutCirc, .easeInOutCirc,
            .easeInExpo, .easeOutExpo, .easeInOutExpo,
            .easeInBack, .easeOutBack, .easeInOutBack,
            .spring, .bounce, .elastic,
            .anticipate, .overshootSettle, .snapBack, .smooth, .sharp, .punch
        ]
    }
}

// MARK: - EasingType Codable

extension EasingType: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, x1, y1, x2, y2, count, stiffness, damping, mass
    }
    
    init(from decoder: Decoder) throws {
        // Try string first (backward compat with String raw value encoding)
        if let container = try? decoder.singleValueContainer(),
           let rawString = try? container.decode(String.self),
           let easing = EasingType(rawValue: rawString) {
            self = easing
            return
        }
        
        // Try keyed container for parametric types
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "cubicBezier":
            self = .cubicBezier(
                x1: try container.decode(Double.self, forKey: .x1),
                y1: try container.decode(Double.self, forKey: .y1),
                x2: try container.decode(Double.self, forKey: .x2),
                y2: try container.decode(Double.self, forKey: .y2)
            )
        case "steps":
            self = .steps(try container.decode(Int.self, forKey: .count))
        case "springCustom":
            self = .springCustom(
                stiffness: try container.decode(Double.self, forKey: .stiffness),
                damping: try container.decode(Double.self, forKey: .damping),
                mass: try container.decode(Double.self, forKey: .mass)
            )
        default:
            if let easing = EasingType(rawValue: type) {
                self = easing
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .type, in: container,
                    debugDescription: "Unknown easing type: \(type)"
                )
            }
        }
    }
    
    func encode(to encoder: Encoder) throws {
        switch self {
        case .cubicBezier(let x1, let y1, let x2, let y2):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("cubicBezier", forKey: .type)
            try container.encode(x1, forKey: .x1)
            try container.encode(y1, forKey: .y1)
            try container.encode(x2, forKey: .x2)
            try container.encode(y2, forKey: .y2)
        case .steps(let count):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("steps", forKey: .type)
            try container.encode(count, forKey: .count)
        case .springCustom(let stiffness, let damping, let mass):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("springCustom", forKey: .type)
            try container.encode(stiffness, forKey: .stiffness)
            try container.encode(damping, forKey: .damping)
            try container.encode(mass, forKey: .mass)
        default:
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }
}

// MARK: - Animation Definition

struct AnimationDefinition: Identifiable, Codable, Equatable {
    let id: UUID
    var type: AnimationType
    var startTime: Double // Start time in seconds
    var duration: Double // Duration in seconds
    var easing: EasingType
    var keyframes: [Keyframe]
    var repeatCount: Int // 0 = no repeat, -1 = infinite
    var autoReverse: Bool
    var delay: Double
    /// Target path data for pathMorph animations (the shape to morph INTO)
    var targetPathData: [PathCommand]?
    
    init(
        id: UUID = UUID(),
        type: AnimationType,
        startTime: Double = 0,
        duration: Double = 1.0,
        easing: EasingType = .easeInOut,
        keyframes: [Keyframe] = [],
        repeatCount: Int = 0,
        autoReverse: Bool = false,
        delay: Double = 0,
        targetPathData: [PathCommand]? = nil
    ) {
        self.id = id
        self.type = type
        self.startTime = startTime
        self.duration = duration
        self.easing = easing
        self.keyframes = keyframes
        self.repeatCount = repeatCount
        self.autoReverse = autoReverse
        self.delay = delay
        self.targetPathData = targetPathData
    }
}

// MARK: - Keyframe

struct Keyframe: Identifiable, Codable, Equatable {
    let id: UUID
    var time: Double // 0.0 to 1.0 (normalized within animation duration)
    var value: KeyframeValue
    
    init(id: UUID = UUID(), time: Double, value: KeyframeValue) {
        self.id = id
        self.time = time
        self.value = value
    }
}

// MARK: - Keyframe Value

enum KeyframeValue: Codable, Equatable {
    case double(Double)
    case point(x: Double, y: Double)
    case color(CodableColor)
    case scale(x: Double, y: Double)
    
    // Custom encoding/decoding
    enum CodingKeys: String, CodingKey {
        case type
        case doubleValue
        case pointX, pointY
        case color
        case scaleX, scaleY
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "double":
            let value = try container.decode(Double.self, forKey: .doubleValue)
            self = .double(value)
        case "point":
            let x = try container.decode(Double.self, forKey: .pointX)
            let y = try container.decode(Double.self, forKey: .pointY)
            self = .point(x: x, y: y)
        case "color":
            let color = try container.decode(CodableColor.self, forKey: .color)
            self = .color(color)
        case "scale":
            let x = try container.decode(Double.self, forKey: .scaleX)
            let y = try container.decode(Double.self, forKey: .scaleY)
            self = .scale(x: x, y: y)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown keyframe value type"
            )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .double(let value):
            try container.encode("double", forKey: .type)
            try container.encode(value, forKey: .doubleValue)
        case .point(let x, let y):
            try container.encode("point", forKey: .type)
            try container.encode(x, forKey: .pointX)
            try container.encode(y, forKey: .pointY)
        case .color(let color):
            try container.encode("color", forKey: .type)
            try container.encode(color, forKey: .color)
        case .scale(let x, let y):
            try container.encode("scale", forKey: .type)
            try container.encode(x, forKey: .scaleX)
            try container.encode(y, forKey: .scaleY)
        }
    }
}

// MARK: - KeyframeValue Helpers

extension KeyframeValue {
    var doubleVal: Double {
        switch self {
        case .double(let v): return v
        case .point(let x, _): return x
        case .scale(let x, _): return x
        case .color: return 0
        }
    }
}

// MARK: - Animation Preset

struct AnimationPreset {
    let name: String
    let description: String
    let createAnimation: () -> AnimationDefinition
    
    static let fadeIn = AnimationPreset(
        name: "Fade In",
        description: "Gradually appear from transparent"
    ) {
        AnimationDefinition(
            type: .fadeIn,
            duration: 0.5,
            easing: .easeOut,
            keyframes: [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(1))
            ]
        )
    }
    
    static let fadeOut = AnimationPreset(
        name: "Fade Out",
        description: "Gradually disappear to transparent"
    ) {
        AnimationDefinition(
            type: .fadeOut,
            duration: 0.5,
            easing: .easeIn,
            keyframes: [
                Keyframe(time: 0, value: .double(1)),
                Keyframe(time: 1, value: .double(0))
            ]
        )
    }
    
    static let bounce = AnimationPreset(
        name: "Bounce",
        description: "Bouncing animation effect"
    ) {
        AnimationDefinition(
            type: .bounce,
            duration: 1.0,
            easing: .bounce,
            keyframes: [
                Keyframe(time: 0, value: .point(x: 0, y: -100)),
                Keyframe(time: 0.5, value: .point(x: 0, y: 0)),
                Keyframe(time: 0.75, value: .point(x: 0, y: -30)),
                Keyframe(time: 1, value: .point(x: 0, y: 0))
            ]
        )
    }
    
    static let pulse = AnimationPreset(
        name: "Pulse",
        description: "Pulsing scale effect"
    ) {
        AnimationDefinition(
            type: .pulse,
            duration: 0.8,
            easing: .easeInOut,
            keyframes: [
                Keyframe(time: 0, value: .scale(x: 1, y: 1)),
                Keyframe(time: 0.5, value: .scale(x: 1.1, y: 1.1)),
                Keyframe(time: 1, value: .scale(x: 1, y: 1))
            ],
            repeatCount: -1
        )
    }
    
    static let spin = AnimationPreset(
        name: "Spin",
        description: "360 degree rotation"
    ) {
        AnimationDefinition(
            type: .spin,
            duration: 1.0,
            easing: .linear,
            keyframes: [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(360))
            ]
        )
    }
}
