//
//  ObjectRendererView.swift
//  AIAfterEffects
//
//  Renders individual scene objects with their animations
//

import SwiftUI
import AppKit

// MARK: - Conditional View Modifier

private extension View {
    @ViewBuilder
    func `if`(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

struct ObjectRendererView: View {
    let object: SceneObject
    let currentTime: Double
    let sceneState: SceneState
    /// Pre-rendered snapshot for model3D objects during video export.
    /// When set, replaces the NSViewRepresentable SceneKit view with an Image.
    let exportSnapshot: NSImage?
    /// Timing offset from dependency resolver. Added to animation startTimes at evaluation.
    let timingOffset: Double
    /// Whether this object is currently selected in the editor
    let isSelected: Bool
    /// Whether playback is active. When false (editing), objects show base properties
    /// instead of being hidden by entrance-animation logic at time 0.
    let isPlaying: Bool
    
    @State private var animatedProperties: AnimatedProperties
    
    init(object: SceneObject, currentTime: Double, sceneState: SceneState, exportSnapshot: NSImage? = nil, timingOffset: Double = 0, isSelected: Bool = false, isPlaying: Bool = false) {
        self.object = object
        self.currentTime = currentTime
        self.sceneState = sceneState
        self.exportSnapshot = exportSnapshot
        self.timingOffset = timingOffset
        self.isSelected = isSelected
        self.isPlaying = isPlaying
        self._animatedProperties = State(initialValue: AnimatedProperties(from: object.properties))
    }
    
    var body: some View {
        Group {
            switch object.type {
            case .rectangle:
                RectangleShape(properties: animatedProperties, cornerRadius: object.properties.cornerRadius)
                
            case .circle:
                CircleShape(properties: animatedProperties)
                
            case .ellipse:
                EllipseShape(properties: animatedProperties)
                
            case .polygon:
                PolygonShape(properties: animatedProperties, sides: object.properties.sides ?? 6)
                
            case .text:
                TextShape(
                    properties: animatedProperties,
                    objectProperties: object.properties,
                    animationState: makeTextAnimationState(at: currentTime),
                    currentTime: currentTime,
                    tracking: animatedProperties.tracking
                )
                
            case .line:
                LineShape(properties: animatedProperties, objectProperties: object.properties)
                
            case .icon:
                IconShape(properties: animatedProperties, objectProperties: object.properties)
                
            case .image:
                ImageShape(properties: animatedProperties, objectProperties: object.properties)
                
            case .path:
                PathShapeView(
                    properties: animatedProperties,
                    objectProperties: object.properties,
                    morphedPathData: animatedProperties.morphedPathData
                )
                
            case .particleSystem:
                if let psData = object.properties.particleSystemData {
                    if let snapshot = exportSnapshot {
                        Image(nsImage: snapshot)
                            .resizable()
                            .frame(width: animatedProperties.width, height: animatedProperties.height)
                    } else {
                        MetalParticleView(
                            particleData: psData,
                            currentTime: currentTime,
                            size: CGSize(width: animatedProperties.width, height: animatedProperties.height)
                        )
                        .frame(width: animatedProperties.width, height: animatedProperties.height)
                    }
                }
                
            case .model3D:
                if let snapshot = exportSnapshot {
                    // During video export: use pre-rendered SceneKit snapshot
                    // (ImageRenderer can't capture NSViewRepresentable)
                    Image(nsImage: snapshot)
                        .resizable()
                        .frame(
                            width: object.properties.width,
                            height: object.properties.height
                        )
                } else {
                    // Normal rendering: use live SceneKit view
                    Model3DRendererView(
                        sceneObject: object,
                        currentTime: currentTime,
                        timingOffset: timingOffset
                    )
                }
                
            case .shader:
                if let snapshot = exportSnapshot {
                    // During video export: use pre-rendered Metal snapshot
                    // (ImageRenderer can't capture NSViewRepresentable/MTKView)
                    Image(nsImage: snapshot)
                        .resizable()
                        .frame(
                            width: object.properties.width,
                            height: object.properties.height
                        )
                } else if let shaderCode = object.properties.shaderCode, !shaderCode.isEmpty {
                    // Normal rendering: use live Metal shader view
                    MetalShaderView(
                        shaderCode: shaderCode,
                        currentTime: currentTime,
                        size: CGSize(width: animatedProperties.width, height: animatedProperties.height),
                        color1: object.properties.fillColor,
                        color2: object.properties.strokeColor,
                        param1: Float(object.properties.shaderParam1 ?? 1.0),
                        param2: Float(object.properties.shaderParam2 ?? 1.0),
                        param3: Float(object.properties.shaderParam3 ?? 0.0),
                        param4: Float(object.properties.shaderParam4 ?? 0.0)
                    )
                    .frame(
                        width: animatedProperties.width,
                        height: animatedProperties.height
                    )
                } else {
                    ShaderErrorView(
                        error: "No shader code provided",
                        size: CGSize(width: animatedProperties.width, height: animatedProperties.height)
                    )
                }
            }
        }
        .opacity(animatedProperties.opacity)
        // Visual effects
        .blur(radius: animatedProperties.blurRadius)
        .brightness(animatedProperties.brightness)
        .contrast(animatedProperties.contrast)
        .saturation(animatedProperties.saturation)
        .hueRotation(.degrees(animatedProperties.hueRotation))
        .grayscale(animatedProperties.grayscale)
        .if(animatedProperties.colorInvert) { $0.colorInvert() }
        .if(animatedProperties.shadowRadius > 0) { view in
            view.shadow(
                color: animatedProperties.shadowColor.color,
                radius: animatedProperties.shadowRadius,
                x: animatedProperties.shadowOffsetX,
                y: animatedProperties.shadowOffsetY
            )
        }
        .blendMode(Self.resolveBlendMode(animatedProperties.blendMode))
        .rotationEffect(.degrees(animatedProperties.rotation))
        .scaleEffect(x: animatedProperties.scaleX, y: animatedProperties.scaleY)
        // Selection is now indicated by the gizmo overlay (Gizmo2DOverlayView)
        // instead of the old dashed border.
        .position(x: animatedProperties.x, y: animatedProperties.y)
        .onChange(of: currentTime) { _, newTime in
            updateAnimatedProperties(at: newTime)
        }
        .onChange(of: object.properties) { _, _ in
            updateAnimatedProperties(at: currentTime)
        }
        .onChange(of: object.isVisible) { _, _ in
            updateAnimatedProperties(at: currentTime)
        }
        .onChange(of: object.animations) { _, _ in
            updateAnimatedProperties(at: currentTime)
        }
        .onChange(of: isPlaying) { _, _ in
            updateAnimatedProperties(at: currentTime)
        }
        .onAppear {
            updateAnimatedProperties(at: currentTime)
        }
    }
    
    static func resolveBlendMode(_ mode: String?) -> BlendMode {
        guard let mode = mode?.lowercased() else { return .normal }
        switch mode {
        case "multiply": return .multiply
        case "screen": return .screen
        case "overlay": return .overlay
        case "softlight", "soft_light": return .softLight
        case "hardlight", "hard_light": return .hardLight
        case "colordodge", "color_dodge": return .colorDodge
        case "colorburn", "color_burn": return .colorBurn
        case "darken": return .darken
        case "lighten": return .lighten
        case "difference": return .difference
        case "exclusion": return .exclusion
        case "hue": return .hue
        case "saturation": return .saturation
        case "color": return .color
        case "luminosity": return .luminosity
        case "plusdarker": return .plusDarker
        case "pluslighter": return .plusLighter
        default: return .normal
        }
    }
    
    private func updateAnimatedProperties(at time: Double) {
        var props = AnimatedProperties(from: object.properties)
        let baseOpacity = max(0, min(1, object.properties.opacity))
        
        // Treat animation opacity as a multiplier channel (default 1.0),
        // then apply the object's configured opacity as the final cap.
        // This preserves user-set opacity (e.g. 0.25) even when animations
        // temporarily force opacity to 1.0 for entrance/visibility logic.
        props.opacity = 1.0
        
        // If the object has entrance-style animations, hide it until the FIRST entrance starts.
        // When editing (not playing) at time 0 (the idle resting state), show all objects
        // at their base properties so the user can see and select them.
        // When scrubbing the timeline (time > 0) or during playback/export, respect animation timing.
        let isIdleEditing = !isPlaying && exportSnapshot == nil && time <= 0.001
        if !isIdleEditing {
            if shouldHideBeforeFirstAnimation(object: object, currentTime: time) {
                props.opacity = 0
            }
        }
        
        // Flash/flicker animations directly control absolute opacity (e.g. a flash overlay
        // with baseOpacity=0 should still pulse to full brightness). Track whether any
        // flash/flicker animation has set the opacity so we can bypass baseOpacity multiplication.
        var flashControlsOpacity = false
        
        for animation in object.animations {
            let animTime = calculateAnimationTime(animation: animation, currentTime: time)
            
            guard animTime >= 0 else { continue }
            
            let progress = min(animTime / animation.duration, 1.0)
            let easedProgress = applyEasing(progress: progress, type: animation.easing)
            
            if animation.type == .flash || animation.type == .flicker {
                flashControlsOpacity = true
            }
            
            // Path morphing requires access to the full animation definition
            if animation.type == .pathMorph,
               let sourcePath = object.properties.pathData,
               let targetPath = animation.targetPathData {
                props.morphedPathData = PathMorpher.interpolate(
                    from: sourcePath, to: targetPath, progress: easedProgress
                )
                continue
            }
            
            applyAnimation(
                type: animation.type,
                progress: easedProgress,
                keyframes: animation.keyframes,
                to: &props
            )
        }
        
        if flashControlsOpacity {
            props.opacity = max(0, min(1, props.opacity))
        } else {
            props.opacity = max(0, min(1, props.opacity * baseOpacity))
        }
        
        animatedProperties = props
    }

    private func estimateTextSize(text: String, fontSize: Double) -> (width: Double, height: Double) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let maxLineLength = lines.map { $0.count }.max() ?? 0
        
        let width = max(1, Double(maxLineLength)) * fontSize * 0.6
        let height = max(1, Double(lines.count)) * fontSize * 1.2
        
        return (width, height)
    }

    private func shouldHideBeforeFirstAnimation(object: SceneObject, currentTime: Double) -> Bool {
        guard !object.animations.isEmpty else { return false }
        
        // For model3D objects: scale-based hiding is already handled by Model3DRendererView
        // (it sets SceneKit scale to 0 for scaleUp3D, popIn3D, tornado before they start).
        // Here we only need to handle OPACITY-based hiding for materialFade and position-based
        // entrance animations (slamDown3D, springBounce3D, etc.) that need the model hidden
        // until they start (to prevent the model flashing at origin then jumping off-screen).
        
        // 3D entrance types whose hiding is already handled by Model3DRendererView via scale=0
        // We still list them as entrances so the earliest-start logic works, but we split them
        // to avoid redundant double-hiding on the opacity side.
        let scaleHandled3DEntrances: Set<AnimationType> = [.scaleUp3D, .popIn3D, .tornado]
        
        let entranceTypes: Set<AnimationType> = [
            // 2D entrance animations
            .fadeIn, .slideIn, .pop, .grow, .scale, .scaleX, .scaleY,
            .dropIn, .riseUp, .swingIn, .elasticIn, .snapIn, .whipIn, .zoomBlur,
            .reveal, .wipeIn, .clipIn, .splitReveal,
            .typewriter, .charByChar, .wordByWord, .lineByLine,
            // Path draw-on entrances
            .trimPathEnd, .trimPathStart, .trimPath,
            // 3D entrance animations (all of them — opacity & scale & position based)
            .scaleUp3D, .popIn3D, .tornado, .materialFade,
            .springBounce3D, .slamDown3D, .dropAndSettle, .corkscrew, .zigzagDrop, .unwrap,
            // Anime.js-inspired entrances
            .staggerFadeIn, .staggerSlideUp, .staggerScaleIn,
            .ripple, .cascade, .domino,
            .scaleRotateIn, .blurSlideIn, .flipReveal, .elasticSlideIn,
            .spiralIn, .unfold, .textBounceIn, .textElasticIn
        ]
        
        // Get all entrance animations for this object
        let entranceAnimations = object.animations.filter { entranceTypes.contains($0.type) }
        guard !entranceAnimations.isEmpty else { return false }
        
        // Find the EARLIEST entrance animation's start time
        let earliestEntrance = entranceAnimations.min(by: { ($0.startTime + $0.delay) < ($1.startTime + $1.delay) })
        guard let earliest = earliestEntrance else { return false }
        let earliestStart = earliest.startTime + earliest.delay
        
        // For model3D objects: if the ONLY entrance type is a scale-based one (scaleUp3D, popIn3D,
        // tornado), Model3DRendererView already handles hiding via scale=0. Don't double-hide
        // with opacity=0 — this prevents timing mismatches between the two systems.
        if object.type == .model3D {
            let nonScaleEntrances = entranceAnimations.filter { !scaleHandled3DEntrances.contains($0.type) }
            if nonScaleEntrances.isEmpty {
                // All entrances are scale-based → Model3DRendererView handles hiding
                return false
            }
            
            // Safety cap: if the earliest entrance for a 3D model is more than 3 seconds away,
            // only hide via materialFade (which explicitly controls opacity). Don't hide based
            // on position-based entrances that are very late — the model should be visible sooner.
            if earliestStart > 3.0 {
                // Check if there's a materialFade — that explicitly controls opacity
                let materialFadeEntrance = entranceAnimations
                    .filter { $0.type == .materialFade }
                    .min(by: { ($0.startTime + $0.delay) < ($1.startTime + $1.delay) })
                
                if let matFade = materialFadeEntrance {
                    let matFadeStart = matFade.startTime + matFade.delay
                    return currentTime < matFadeStart
                }
                
                // No materialFade and entrance is very late — don't hide the model for that long.
                // Let it be visible; the entrance animation will still play when it starts.
                return false
            }
        }
        
        // Standard behavior: hide until the earliest entrance starts
        return currentTime < earliestStart
    }
    
    private func isExitAnimationActive(object: SceneObject, currentTime: Double) -> Bool {
        let exitTypes: Set<AnimationType> = [
            .fadeOut, .slideOut, .wipeOut, .explode, .elasticOut, .shrink,
            // Anime.js-inspired exits
            .scaleRotateOut, .blurSlideOut, .flipHide, .spiralOut, .foldUp
        ]
        
        for animation in object.animations where exitTypes.contains(animation.type) {
            let start = animation.startTime + animation.delay
            let end = start + animation.duration
            if currentTime >= start && currentTime <= end {
                return true
            }
        }
        
        // Keep slideOut treated as exit after it starts (prevents clamp snapping back)
        for animation in object.animations where animation.type == .slideOut {
            let start = animation.startTime + animation.delay
            if currentTime >= start {
                return true
            }
        }
        
        for animation in object.animations {
            if !isMovementExit(animation: animation, object: object, currentTime: currentTime) {
                continue
            }
            return true
        }
        
        return false
    }

    private func isMovementExit(animation: AnimationDefinition, object: SceneObject, currentTime: Double) -> Bool {
        guard animation.type == .moveX || animation.type == .moveY || animation.type == .move else {
            return false
        }
        
        let start = animation.startTime + animation.delay
        guard currentTime >= start else {
            return false
        }
        
        guard let finalKeyframe = animation.keyframes.max(by: { $0.time < $1.time }) else {
            return false
        }
        
        var targetX = object.properties.x
        var targetY = object.properties.y
        
        switch (animation.type, finalKeyframe.value) {
        case (.moveX, .double(let dx)):
            targetX += dx
        case (.moveY, .double(let dy)):
            targetY += dy
        case (.move, .point(let dx, let dy)):
            targetX += dx
            targetY += dy
        default:
            return false
        }
        
        let size = effectiveObjectSize(object)
        let halfWidth = max(1, size.width) / 2
        let halfHeight = max(1, size.height) / 2
        
        let minX = -halfWidth
        let maxX = sceneState.canvasWidth + halfWidth
        let minY = -halfHeight
        let maxY = sceneState.canvasHeight + halfHeight
        
        return targetX < minX || targetX > maxX || targetY < minY || targetY > maxY
    }

    private func effectiveObjectSize(_ object: SceneObject) -> CGSize {
        if object.type == .text {
            let text = object.properties.text ?? ""
            let fontSize = object.properties.fontSize ?? 48
            let estimated = estimateTextSize(text: text, fontSize: fontSize)
            return CGSize(
                width: estimated.width * abs(object.properties.scaleX),
                height: estimated.height * abs(object.properties.scaleY)
            )
        }
        
        return CGSize(
            width: object.properties.width * abs(object.properties.scaleX),
            height: object.properties.height * abs(object.properties.scaleY)
        )
    }
    
    /// Animations that are continuous rotations/cycles — should wrap, NOT ping-pong.
    private static let continuousAnimationTypes: Set<AnimationType> = [
        .turntable, .spin, .rotate, .rotate3DX, .rotate3DY, .rotate3DZ,
        .cameraOrbit, .orbit3D, .hueRotate, .tumble, .figureEight,
        .trimPathOffset, .dashOffset
    ]
    
    private func calculateAnimationTime(animation: AnimationDefinition, currentTime: Double) -> Double {
        let startTime = animation.startTime + animation.delay + timingOffset
        var animTime = currentTime - startTime
        
        if animTime < 0 {
            return -1 // Animation hasn't started
        }
        
        // Handle repeating animations
        if animation.repeatCount != 0 {
            let totalDuration = animation.duration
            let cycles = animTime / totalDuration
            
            if animation.repeatCount > 0 && cycles >= Double(animation.repeatCount + 1) {
                return animation.duration
            }
            
            let isContinuous = Self.continuousAnimationTypes.contains(animation.type)
            let shouldPingPong = !isContinuous && !animation.autoReverse
            
            let cycleIndex = Int(cycles)
            animTime = animTime.truncatingRemainder(dividingBy: totalDuration)
            
            if shouldPingPong && cycleIndex % 2 == 1 {
                // Auto ping-pong for non-continuous animations
                animTime = totalDuration - animTime
            } else if animation.autoReverse && cycleIndex % 2 == 1 {
                animTime = totalDuration - animTime
            }
        }
        
        return animTime
    }

    private func makeTextAnimationState(at time: Double) -> TextAnimationState {
        var state = TextAnimationState()
        
        for animation in object.animations where TextAnimationState.supportedTypes.contains(animation.type) {
            guard let effect = makeTextAnimationEffect(for: animation, at: time) else { continue }
            state.update(effect: effect, for: animation.type)
        }
        
        return state
    }
    
    private func makeTextAnimationEffect(
        for animation: AnimationDefinition,
        at time: Double
    ) -> TextAnimationEffect? {
        let animTime = calculateAnimationTime(animation: animation, currentTime: time)
        guard animTime >= 0 else { return nil }
        
        let safeDuration = max(animation.duration, 0.0001)
        let rawProgress = min(animTime / safeDuration, 1.0)
        let easedProgress = applyEasing(progress: rawProgress, type: animation.easing)
        
        var intensity = easedProgress
        if let value = interpolateKeyframes(keyframes: animation.keyframes, progress: easedProgress),
           case .double(let keyframeValue) = value {
            intensity = keyframeValue
        }
        if !intensity.isFinite {
            intensity = easedProgress
        }
        
        return TextAnimationEffect(
            progress: easedProgress,
            rawProgress: rawProgress,
            intensity: intensity,
            duration: animation.duration
        )
    }
    
    private func applyEasing(progress: Double, type: EasingType) -> Double {
        EasingHelper.apply(type, to: progress)
    }
    
    private func applyAnimation(
        type: AnimationType,
        progress: Double,
        keyframes: [Keyframe],
        to props: inout AnimatedProperties
    ) {
        switch type {
        case .fadeIn:
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress),
               case .double(let opacity) = value {
                props.opacity = opacity
            } else {
                props.opacity = interpolateDouble(from: 0, to: 1, progress: progress)
            }
            
        case .fadeOut:
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress),
               case .double(let opacity) = value {
                props.opacity = opacity
            } else {
                props.opacity = interpolateDouble(from: 1, to: 0, progress: progress)
            }
            
        case .fade:
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let opacity) = value {
                    props.opacity = opacity
                }
            }
            
        case .moveX:
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let x) = value {
                    props.x = object.properties.x + x
                }
            }
            
        case .moveY:
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let y) = value {
                    props.y = object.properties.y + y
                }
            }
            
        case .move:
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .point(let x, let y) = value {
                    props.x = object.properties.x + x
                    props.y = object.properties.y + y
                }
            }
            
        case .scale:
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .scale(let sx, let sy) = value {
                    props.scaleX = sx
                    props.scaleY = sy
                } else if case .double(let s) = value {
                    props.scaleX = s
                    props.scaleY = s
                }
            }
            
        case .scaleX:
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let sx) = value {
                    props.scaleX = sx
                }
            }
            
        case .scaleY:
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let sy) = value {
                    props.scaleY = sy
                }
            }
            
        case .rotate, .spin:
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let rotation) = value {
                    props.rotation = rotation
                }
            }
            
        case .bounce:
            // Bounce animation on Y axis
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .point(_, let y) = value {
                    props.y = object.properties.y + y
                } else if case .double(let y) = value {
                    props.y = object.properties.y + y
                }
            }
            
        case .shake, .wiggle:
            let shakeAmount = sin(progress * .pi * 8) * 10 * (1 - progress)
            props.x = object.properties.x + shakeAmount
            
        case .pulse:
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .scale(let sx, let sy) = value {
                    props.scaleX = sx
                    props.scaleY = sy
                }
            } else {
                // Default pulse
                let scale = 1 + 0.1 * sin(progress * .pi * 2)
                props.scaleX = scale
                props.scaleY = scale
            }
            
        case .slideIn:
            let startX = -object.properties.width
            props.x = interpolateDouble(from: startX, to: object.properties.x, progress: progress)
            
        case .slideOut:
            let endX = sceneState.canvasWidth + object.properties.width
            props.x = interpolateDouble(from: object.properties.x, to: endX, progress: progress)
            
        case .grow:
            props.scaleX = interpolateDouble(from: 0, to: 1, progress: progress)
            props.scaleY = interpolateDouble(from: 0, to: 1, progress: progress)
            
        case .shrink:
            props.scaleX = interpolateDouble(from: 1, to: 0, progress: progress)
            props.scaleY = interpolateDouble(from: 1, to: 0, progress: progress)
            
        case .pop:
            // Pop in with slight overshoot
            let popScale = 1 + 0.2 * sin(progress * .pi)
            props.scaleX = progress < 1 ? popScale * progress : 1
            props.scaleY = progress < 1 ? popScale * progress : 1
            props.opacity = progress
            
        case .colorChange, .fillColorChange:
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress),
               case .color(let c) = value {
                props.fillColor = c
            }
            
        case .strokeColorChange:
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress),
               case .color(let c) = value {
                props.strokeColor = c
            }
            
        case .typewriter, .wave:
            // These need special handling - simplified for now
            break
            
        // MARK: - Advanced Opacity
        case .blurIn, .blurOut:
            // Real Gaussian blur animation
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let blur) = value {
                    props.blurRadius = max(0, blur)
                }
            }
            
        // MARK: - Disney Principles
        case .anticipation:
            // Pull back then forward motion
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let offset) = value {
                    props.x = object.properties.x + offset
                }
            }
            
        case .overshoot:
            // Overshoot then settle
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let offset) = value {
                    props.x = object.properties.x + offset
                }
            }
            
        case .followThrough:
            // Continue motion then settle
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let offset) = value {
                    props.x = object.properties.x + offset
                }
            }
            
        case .squashStretch:
            // Squash and stretch effect
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .scale(let sx, let sy) = value {
                    props.scaleX = sx
                    props.scaleY = sy
                }
            }
            
        // MARK: - Text Animations
        case .charByChar, .wordByWord, .lineByLine:
            // Character/word reveal - handled via opacity
            props.opacity = progress
            
        case .scramble:
            // Scramble effect - simplified to opacity
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let reveal) = value {
                    props.opacity = reveal
                }
            }
            
        case .glitchText:
            // Glitch text with position jitter
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let intensity) = value {
                    let jitterX = sin(progress * .pi * 20) * intensity
                    let jitterY = cos(progress * .pi * 15) * intensity * 0.3
                    props.x = object.properties.x + jitterX
                    props.y = object.properties.y + jitterY
                }
            }
            
        // MARK: - Reveals & Masks
        case .reveal, .wipeIn, .clipIn, .splitReveal:
            // Reveal animations - handled via opacity and scale for now
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let revealProgress) = value {
                    props.opacity = revealProgress
                    props.scaleX = 0.8 + 0.2 * revealProgress
                }
            }
            
        case .wipeOut:
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let revealProgress) = value {
                    props.opacity = revealProgress
                }
            }
            
        // MARK: - Impact Effects
        case .glitch:
            // RGB split effect - simulated with position offset
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let splitAmount) = value {
                    let offset = sin(progress * .pi * 10) * splitAmount
                    props.x = object.properties.x + offset
                }
            }
            
        case .flicker:
            // Rapid opacity flicker
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let opacity) = value {
                    props.opacity = opacity
                }
            }
            
        case .flash:
            // Bright flash effect
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let brightness) = value {
                    props.opacity = min(brightness, 1.0)
                }
            }
            
        case .slam:
            // Fast scale in with impact
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .scale(let sx, let sy) = value {
                    props.scaleX = sx
                    props.scaleY = sy
                }
            }
            
        case .explode:
            // Scale out with fade
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .scale(let sx, let sy) = value {
                    props.scaleX = sx
                    props.scaleY = sy
                    props.opacity = max(0, 1 - progress)
                }
            }
            
        case .implode:
            // Scale in from large
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .scale(let sx, let sy) = value {
                    props.scaleX = sx
                    props.scaleY = sy
                    props.opacity = progress
                }
            }
            
        // MARK: - Organic Motion
        case .float:
            // Gentle floating on Y axis
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let offset) = value {
                    props.y = object.properties.y + offset
                }
            }
            
        case .drift:
            // Slow directional drift
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .point(let x, let y) = value {
                    props.x = object.properties.x + x
                    props.y = object.properties.y + y
                }
            }
            
        case .breathe:
            // Subtle scale breathing
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .scale(let sx, let sy) = value {
                    props.scaleX = sx
                    props.scaleY = sy
                }
            }
            
        case .sway:
            // Pendulum rotation
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let rotation) = value {
                    props.rotation = rotation
                }
            }
            
        case .jitter:
            // Micro random movement
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .point(let x, let y) = value {
                    props.x = object.properties.x + x
                    props.y = object.properties.y + y
                }
            }
            
        // MARK: - Kinetic Typography
        case .dropIn:
            // Drop from above with bounce
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let offset) = value {
                    props.y = object.properties.y + offset
                }
            }
            props.opacity = min(1, progress * 2)
            
        case .riseUp:
            // Rise from below
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let offset) = value {
                    props.y = object.properties.y + offset
                }
            }
            props.opacity = min(1, progress * 2)
            
        case .swingIn:
            // Swing rotation entrance
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let rotation) = value {
                    props.rotation = rotation
                }
            }
            props.opacity = min(1, progress * 1.5)
            
        case .elasticIn:
            // Elastic scale entrance
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .scale(let sx, let sy) = value {
                    props.scaleX = sx
                    props.scaleY = sy
                }
            }
            
        case .elasticOut:
            // Elastic scale exit
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .scale(let sx, let sy) = value {
                    props.scaleX = sx
                    props.scaleY = sy
                }
            }
            
        case .snapIn:
            // Quick snap entrance
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .scale(let sx, let sy) = value {
                    props.scaleX = sx
                    props.scaleY = sy
                }
            }
            props.opacity = progress > 0.1 ? 1 : progress * 10
            
        case .whipIn:
            // Fast whip from side
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let offset) = value {
                    props.x = object.properties.x + offset
                }
            }
            props.opacity = min(1, progress * 3)
            
        case .zoomBlur:
            // Zoom with blur feel
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .scale(let sx, let sy) = value {
                    props.scaleX = sx
                    props.scaleY = sy
                }
            }
            props.opacity = min(1, progress * 2)
            
        case .tracking:
            // Animate letter-spacing (kerning): wide → normal
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let kerning) = value {
                    props.tracking = kerning
                }
            }
            
        // MARK: Visual Effects Animations
        case .blur:
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let r) = value { props.blurRadius = max(0, r) }
            }
        case .brightnessAnim:
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let b) = value { props.brightness = b }
            }
        case .contrastAnim:
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let c) = value { props.contrast = max(0, c) }
            }
        case .saturationAnim:
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let s) = value { props.saturation = max(0, s) }
            }
        case .hueRotate:
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let h) = value { props.hueRotation = h }
            }
        case .grayscaleAnim:
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let g) = value { props.grayscale = min(1, max(0, g)) }
            }
        case .shadowAnim:
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let r) = value { props.shadowRadius = max(0, r) }
            }
            
        // MARK: Path Animations
        case .trimPath:
            // Animate both trimStart and trimEnd together via a point value
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .point(let start, let end) = value {
                    props.trimStart = max(0, min(1, start))
                    props.trimEnd = max(0, min(1, end))
                } else if case .double(let end) = value {
                    // Single value: animate trimEnd (draw-on effect)
                    props.trimEnd = max(0, min(1, end))
                }
            }
        case .trimPathStart:
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let v) = value { props.trimStart = max(0, min(1, v)) }
            }
        case .trimPathEnd:
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let v) = value { props.trimEnd = max(0, min(1, v)) }
            }
        case .trimPathOffset:
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let v) = value { props.trimOffset = v.truncatingRemainder(dividingBy: 1.0) }
            }
        case .strokeWidthAnim:
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let w) = value { props.strokeWidth = max(0, w) }
            }
        case .dashOffset:
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let d) = value { props.dashPhase = d }
            }
            
        // MARK: - Anime.js-Inspired: Stagger-Based
        case .staggerFadeIn:
            // Simple fade in (stagger timing handled by startTime offsets)
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let opacity) = value {
                    props.opacity = opacity
                }
            }
            
        case .staggerSlideUp:
            // Slide up from below (stagger timing handled by startTime offsets)
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let offset) = value {
                    props.y = object.properties.y + offset
                }
            }
            props.opacity = min(1, progress * 2)
            
        case .staggerScaleIn:
            // Scale in (stagger timing handled by startTime offsets)
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .scale(let sx, let sy) = value {
                    props.scaleX = sx
                    props.scaleY = sy
                }
            }
            props.opacity = min(1, progress * 2)
            
        case .ripple:
            // Radial scale-in with overshoot (stagger from center)
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .scale(let sx, let sy) = value {
                    props.scaleX = sx
                    props.scaleY = sy
                }
            }
            props.opacity = min(1, progress * 2.5)
            
        case .cascade:
            // Waterfall slide down + fade
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let offset) = value {
                    props.y = object.properties.y + offset
                }
            }
            props.opacity = min(1, progress * 2)
            
        case .domino:
            // Sequential topple rotation + fade
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let rotation) = value {
                    props.rotation = rotation
                }
            }
            props.opacity = min(1, progress * 2)
            
        // MARK: - Anime.js-Inspired: Combo Entrances
        case .scaleRotateIn:
            // Scale + rotate entrance
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .scale(let sx, let sy) = value {
                    props.scaleX = sx
                    props.scaleY = sy
                }
            }
            props.rotation = (1 - progress) * 180
            props.opacity = min(1, progress * 2)
            
        case .blurSlideIn:
            // Slide from left with blur clearing
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let offset) = value {
                    props.x = object.properties.x + offset
                }
            }
            props.blurRadius = max(0, (1 - progress) * 15)
            props.opacity = min(1, progress * 2)
            
        case .flipReveal:
            // Y-axis rotation entrance (simulated with scaleX)
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let rotation) = value {
                    // Simulate 3D flip by using scaleX to mimic perspective
                    let normalizedAngle = abs(rotation) / 90.0
                    props.scaleX = max(0.01, 1 - normalizedAngle * 0.8)
                    props.rotation = rotation * 0.1 // Slight tilt
                }
            }
            props.opacity = progress > 0.3 ? 1 : progress / 0.3
            
        case .elasticSlideIn:
            // Slide with elastic overshoot
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let offset) = value {
                    props.x = object.properties.x + offset
                }
            }
            props.opacity = min(1, progress * 3)
            
        case .spiralIn:
            // Spiral inward: rotation + scale + position
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let p) = value {
                    let angle = (1 - p) * 720 // Two full rotations
                    let radius = (1 - p) * 100  // Shrinking radius
                    props.x = object.properties.x + cos(angle * .pi / 180) * radius
                    props.y = object.properties.y + sin(angle * .pi / 180) * radius
                    props.rotation = angle.truncatingRemainder(dividingBy: 360)
                    props.scaleX = p
                    props.scaleY = p
                }
            }
            props.opacity = min(1, progress * 2)
            
        case .unfold:
            // Unfold from flat line (scaleY 0→1)
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .scale(let sx, let sy) = value {
                    props.scaleX = sx
                    props.scaleY = sy
                }
            }
            props.opacity = progress > 0.1 ? 1 : progress * 10
            
        // MARK: - Anime.js-Inspired: Combo Exits
        case .scaleRotateOut:
            // Scale + rotate exit
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .scale(let sx, let sy) = value {
                    props.scaleX = sx
                    props.scaleY = sy
                }
            }
            props.rotation = progress * 180
            props.opacity = max(0, 1 - progress * 1.5)
            
        case .blurSlideOut:
            // Slide out with blur
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let offset) = value {
                    props.x = object.properties.x + offset
                }
            }
            props.blurRadius = progress * 15
            props.opacity = max(0, 1 - progress)
            
        case .flipHide:
            // Y-axis rotation exit (simulated with scaleX)
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let rotation) = value {
                    let normalizedAngle = abs(rotation) / 90.0
                    props.scaleX = max(0.01, 1 - normalizedAngle * 0.8)
                }
            }
            props.opacity = progress < 0.7 ? 1 : max(0, 1 - (progress - 0.7) / 0.3)
            
        case .spiralOut:
            // Spiral outward: rotation + scale + position
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let p) = value {
                    let angle = p * 720
                    let radius = p * 100
                    props.x = object.properties.x + cos(angle * .pi / 180) * radius
                    props.y = object.properties.y + sin(angle * .pi / 180) * radius
                    props.rotation = angle.truncatingRemainder(dividingBy: 360)
                    props.scaleX = 1 - p
                    props.scaleY = 1 - p
                }
            }
            props.opacity = max(0, 1 - progress)
            
        case .foldUp:
            // Fold to flat line (scaleY 1→0)
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .scale(let sx, let sy) = value {
                    props.scaleX = sx
                    props.scaleY = sy
                }
            }
            props.opacity = progress < 0.8 ? 1 : max(0, 1 - (progress - 0.8) / 0.2)
            
        // MARK: - Anime.js-Inspired: Continuous/Loop Effects
        case .pendulum:
            // Smooth pendulum rotation
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let rotation) = value {
                    props.rotation = rotation
                }
            }
            
        case .orbit2D:
            // Circular orbit in 2D
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let p) = value {
                    let angle = p * 2 * .pi
                    let radius = 50.0 // Default orbit radius
                    props.x = object.properties.x + cos(angle) * radius
                    props.y = object.properties.y + sin(angle) * radius
                }
            }
            
        case .lemniscate:
            // Figure-8 / infinity loop
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let p) = value {
                    let t = p * 2 * .pi
                    let scale = 40.0
                    // Lemniscate of Bernoulli parametric form
                    props.x = object.properties.x + scale * cos(t) / (1 + sin(t) * sin(t))
                    props.y = object.properties.y + scale * sin(t) * cos(t) / (1 + sin(t) * sin(t))
                }
            }
            
        case .morphPulse:
            // Alternating squash-stretch
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .scale(let sx, let sy) = value {
                    props.scaleX = sx
                    props.scaleY = sy
                }
            }
            
        case .neonFlicker:
            // Neon sign opacity flicker
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let opacity) = value {
                    props.opacity = opacity
                }
            }
            
        case .glowPulse:
            // Shadow radius pulsing
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let radius) = value {
                    props.shadowRadius = max(0, radius)
                }
            }
            
        case .oscillate:
            // Sine wave oscillation on Y axis
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let offset) = value {
                    props.y = object.properties.y + offset
                }
            }
            
        // MARK: - Anime.js-Inspired: Text Effects
        case .textWave, .textRainbow, .textBounceIn, .textElasticIn:
            // Text effects: handled via TextAnimationState (similar to charByChar)
            // The progress drives per-character effects in AnimatedTextView
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let v) = value {
                    // For textBounceIn: apply as Y offset with fade
                    if type == .textBounceIn {
                        props.y = object.properties.y + v
                        props.opacity = min(1, progress * 2)
                    }
                } else if case .scale(let sx, let sy) = value {
                    // For textElasticIn: apply as scale with fade
                    if type == .textElasticIn {
                        props.scaleX = sx
                        props.scaleY = sy
                        props.opacity = min(1, progress * 2)
                    }
                }
            }
            // For textWave and textRainbow, the primary effect is per-character
            // (handled by AnimatedTextView), so just ensure visibility
            if type == .textWave || type == .textRainbow {
                props.opacity = 1
            }
            
        // 3D animations are handled by Model3DRendererView directly
        case .materialFade:
            // materialFade controls opacity for 3D models - apply it as SwiftUI opacity
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let opacity) = value {
                    props.opacity = opacity
                }
            }
            
        case .propertyChange:
            // Generic property change - apply keyframe values directly
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let v) = value {
                    props.opacity = v
                }
            }
            
        case .textSizeChange:
            if let value = interpolateKeyframes(keyframes: keyframes, progress: progress) {
                if case .double(let size) = value {
                    props.fontSize = size
                }
            }
            
        case .rotate3DX, .rotate3DY, .rotate3DZ, .orbit3D, .turntable,
             .wobble3D, .flip3D, .float3D, .cradle, .springBounce3D,
             .elasticSpin, .swing3D, .breathe3D, .headNod, .headShake,
             .rockAndRoll, .scaleUp3D, .scaleDown3D, .slamDown3D,
             .revolveSlow, .tumble, .barrelRoll, .corkscrew, .figureEight,
             .boomerang3D, .levitate, .magnetPull, .magnetPush, .zigzagDrop,
             .rubberBand, .jelly3D, .anticipateSpin, .popIn3D, .glitchJitter3D,
             .heartbeat3D, .tornado, .unwrap, .dropAndSettle,
             .move3DX, .move3DY, .move3DZ, .scale3DZ,
             .cameraZoom, .cameraPan, .cameraOrbit,
             .spiralZoom, .dollyZoom, .cameraRise, .cameraDive,
             .cameraWhipPan, .cameraSlide, .cameraArc, .cameraPedestal,
             .cameraTruck, .cameraPushPull, .cameraDutchTilt,
             .cameraHelicopter, .cameraRocket, .cameraShake:
            break // No-op in 2D renderer - handled by Model3DRendererView
        
        case .pathMorph:
            break // Handled in the animation loop before applyAnimation
        }
    }
    
    private func interpolateDouble(from: Double, to: Double, progress: Double) -> Double {
        from + (to - from) * progress
    }
    
    private func interpolateKeyframes(keyframes: [Keyframe], progress: Double) -> KeyframeValue? {
        guard !keyframes.isEmpty else { return nil }
        let sortedKeyframes = keyframes.sorted(by: { $0.time < $1.time })
        
        if sortedKeyframes.count == 1 {
            return sortedKeyframes[0].value
        }
        
        // Find surrounding keyframes
        var prevKeyframe = sortedKeyframes[0]
        var nextKeyframe = sortedKeyframes[sortedKeyframes.count - 1]
        
        for i in 0..<sortedKeyframes.count - 1 {
            if progress >= sortedKeyframes[i].time && progress <= sortedKeyframes[i + 1].time {
                prevKeyframe = sortedKeyframes[i]
                nextKeyframe = sortedKeyframes[i + 1]
                break
            }
        }
        
        // Calculate local progress between keyframes
        let keyframeDuration = nextKeyframe.time - prevKeyframe.time
        let localProgress = keyframeDuration > 0
            ? (progress - prevKeyframe.time) / keyframeDuration
            : 1.0
        
        // Interpolate values
        return interpolateValues(from: prevKeyframe.value, to: nextKeyframe.value, progress: localProgress)
    }
    
    private func interpolateValues(from: KeyframeValue, to: KeyframeValue, progress: Double) -> KeyframeValue {
        switch (from, to) {
        case (.double(let fromVal), .double(let toVal)):
            return .double(interpolateDouble(from: fromVal, to: toVal, progress: progress))
            
        case (.point(let fx, let fy), .point(let tx, let ty)):
            return .point(
                x: interpolateDouble(from: fx, to: tx, progress: progress),
                y: interpolateDouble(from: fy, to: ty, progress: progress)
            )
            
        case (.scale(let fx, let fy), .scale(let tx, let ty)):
            return .scale(
                x: interpolateDouble(from: fx, to: tx, progress: progress),
                y: interpolateDouble(from: fy, to: ty, progress: progress)
            )
            
        case (.color(let fromColor), .color(let toColor)):
            return .color(CodableColor(
                red: interpolateDouble(from: fromColor.red, to: toColor.red, progress: progress),
                green: interpolateDouble(from: fromColor.green, to: toColor.green, progress: progress),
                blue: interpolateDouble(from: fromColor.blue, to: toColor.blue, progress: progress),
                alpha: interpolateDouble(from: fromColor.alpha, to: toColor.alpha, progress: progress)
            ))
            
        default:
            return to
        }
    }
}

// MARK: - Animated Properties

struct AnimatedProperties {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var rotation: Double
    var scaleX: Double
    var scaleY: Double
    var opacity: Double
    var fillColor: CodableColor
    var strokeColor: CodableColor
    var tracking: Double       // Letter-spacing / kerning (0 = normal)
    
    // Visual effects (animatable)
    var blurRadius: Double
    var brightness: Double     // -1.0 to 1.0  (0 = normal)
    var contrast: Double       //  0.0 to 3.0  (1 = normal)
    var saturation: Double     //  0.0 to 3.0  (1 = normal)
    var hueRotation: Double    // degrees
    var grayscale: Double      // 0.0 to 1.0
    var shadowRadius: Double
    var shadowOffsetX: Double
    var shadowOffsetY: Double
    var shadowColor: CodableColor
    var blendMode: String?
    var colorInvert: Bool
    
    // Text
    var fontSize: Double       // Animatable font size
    
    // Path animations (After Effects-style)
    var trimStart: Double      // 0.0 to 1.0 — skip this fraction from path start
    var trimEnd: Double        // 0.0 to 1.0 — draw up to this fraction of path
    var trimOffset: Double     // 0.0 to 1.0 — shifts the trim window along the path
    var strokeWidth: Double    // Animatable stroke width
    var dashPhase: Double      // Animatable dash offset (marching ants)
    var morphedPathData: [PathCommand]?  // Overrides objectProperties.pathData when pathMorph is active
    
    init(from props: ObjectProperties) {
        self.x = props.x
        self.y = props.y
        self.width = props.width
        self.height = props.height
        self.rotation = props.rotation
        self.scaleX = props.scaleX
        self.scaleY = props.scaleY
        self.opacity = props.opacity
        self.fillColor = props.fillColor
        self.strokeColor = props.strokeColor
        self.tracking = 0
        self.fontSize = props.fontSize ?? 48
        self.blurRadius = props.blurRadius
        self.brightness = props.brightness
        self.contrast = props.contrast
        self.saturation = props.saturation
        self.hueRotation = props.hueRotation
        self.grayscale = props.grayscale
        self.shadowRadius = props.shadowRadius
        self.shadowOffsetX = props.shadowOffsetX
        self.shadowOffsetY = props.shadowOffsetY
        self.shadowColor = props.shadowColor ?? .clear
        self.blendMode = props.blendMode
        self.colorInvert = props.colorInvert
        self.trimStart = props.trimStart ?? 0
        self.trimEnd = props.trimEnd ?? 1
        self.trimOffset = props.trimOffset ?? 0
        self.strokeWidth = props.strokeWidth
        self.dashPhase = props.dashPhase ?? 0
    }
}

// MARK: - Shape Views

struct RectangleShape: View {
    let properties: AnimatedProperties
    let cornerRadius: Double
    
    var body: some View {
        let hasFill = properties.fillColor.alpha > 0.001
        let hasStroke = properties.strokeColor.alpha > 0.001 && properties.strokeWidth > 0
        ZStack {
            if hasFill {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(properties.fillColor.color)
            }
            if hasStroke {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(properties.strokeColor.color, lineWidth: properties.strokeWidth)
            }
        }
        .frame(width: properties.width, height: properties.height)
    }
}

struct CircleShape: View {
    let properties: AnimatedProperties
    
    var body: some View {
        let hasFill = properties.fillColor.alpha > 0.001
        let hasStroke = properties.strokeColor.alpha > 0.001 && properties.strokeWidth > 0
        ZStack {
            if hasFill {
                Circle().fill(properties.fillColor.color)
            }
            if hasStroke {
                Circle().stroke(properties.strokeColor.color, lineWidth: properties.strokeWidth)
            }
        }
        .frame(width: properties.width, height: properties.width)
    }
}

struct EllipseShape: View {
    let properties: AnimatedProperties
    
    var body: some View {
        let hasFill = properties.fillColor.alpha > 0.001
        let hasStroke = properties.strokeColor.alpha > 0.001 && properties.strokeWidth > 0
        ZStack {
            if hasFill {
                Ellipse().fill(properties.fillColor.color)
            }
            if hasStroke {
                Ellipse().stroke(properties.strokeColor.color, lineWidth: properties.strokeWidth)
            }
        }
        .frame(width: properties.width, height: properties.height)
    }
}

struct PolygonShape: View {
    let properties: AnimatedProperties
    let sides: Int
    
    var body: some View {
        let hasFill = properties.fillColor.alpha > 0.001
        let hasStroke = properties.strokeColor.alpha > 0.001 && properties.strokeWidth > 0
        ZStack {
            if hasFill {
                RegularPolygon(sides: sides).fill(properties.fillColor.color)
            }
            if hasStroke {
                RegularPolygon(sides: sides).stroke(properties.strokeColor.color, lineWidth: properties.strokeWidth)
            }
        }
        .frame(width: properties.width, height: properties.height)
    }
}

struct LineShape: View {
    let properties: AnimatedProperties
    let objectProperties: ObjectProperties
    
    var body: some View {
        let angle = objectProperties.rotation
        let lineWidth = properties.strokeWidth > 0 ? properties.strokeWidth : 2.0
        Path { path in
            if abs(angle) < 0.01 {
                path.move(to: CGPoint(x: 0, y: properties.height / 2))
                path.addLine(to: CGPoint(x: properties.width, y: properties.height / 2))
            } else {
                let cx = properties.width / 2
                let cy = properties.height / 2
                let length = min(properties.width, properties.height) / 2
                let rad = angle * .pi / 180
                path.move(to: CGPoint(x: cx - cos(rad) * length, y: cy - sin(rad) * length))
                path.addLine(to: CGPoint(x: cx + cos(rad) * length, y: cy + sin(rad) * length))
            }
        }
        .stroke(properties.strokeColor.color, style: StrokeStyle(
            lineWidth: lineWidth,
            lineCap: .round
        ))
        .frame(width: properties.width, height: properties.height)
    }
}

struct TextShape: View {
    let properties: AnimatedProperties
    let objectProperties: ObjectProperties
    let animationState: TextAnimationState
    let currentTime: Double
    var tracking: Double = 0
    
    /// Effective object properties with animated fontSize applied
    private var effectiveObjProps: ObjectProperties {
        var props = objectProperties
        let baseFontSize = objectProperties.fontSize ?? 48
        if abs(properties.fontSize - baseFontSize) > 0.01 {
            props.fontSize = properties.fontSize
        }
        return props
    }
    
    var body: some View {
        AnimatedTextView(
            properties: properties,
            objectProperties: effectiveObjProps,
            animationState: animationState,
            currentTime: currentTime,
            tracking: tracking
        )
    }
}

struct IconShape: View {
    let properties: AnimatedProperties
    let objectProperties: ObjectProperties
    
    var body: some View {
        let size = objectProperties.iconSize ?? min(properties.width, properties.height)
        Image(systemName: objectProperties.iconName ?? "star.fill")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundColor(properties.fillColor.color)
    }
}

struct ImageShape: View {
    let properties: AnimatedProperties
    let objectProperties: ObjectProperties
    
    private var image: NSImage? {
        guard let dataURL = objectProperties.imageData,
              let data = dataFromDataURL(dataURL) else { return nil }
        return NSImage(data: data)
    }
    
    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: properties.width, height: properties.height)
        } else {
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .fill(AppTheme.Colors.surface)
                .frame(width: properties.width, height: properties.height)
                .overlay(
                    Image(systemName: "photo")
                        .foregroundColor(AppTheme.Colors.textTertiary)
                )
        }
    }
    
    private func dataFromDataURL(_ dataURL: String) -> Data? {
        if dataURL.hasPrefix("data:") {
            guard let base64Range = dataURL.range(of: "base64,") else {
                return nil
            }
            let base64 = String(dataURL[base64Range.upperBound...])
            return Data(base64Encoded: base64)
        }
        return Data(base64Encoded: dataURL)
    }
}

// MARK: - Path Shape View

struct PathShapeView: View {
    let properties: AnimatedProperties
    let objectProperties: ObjectProperties
    var morphedPathData: [PathCommand]? = nil
    
    var body: some View {
        let commands = morphedPathData ?? objectProperties.pathData ?? []
        let shouldClose = objectProperties.closePath ?? false
        let hasFill = properties.fillColor.alpha > 0.001
        let hasStroke = properties.strokeColor.alpha > 0.001 || properties.strokeWidth > 0
        let strokeWidth = properties.strokeWidth > 0 ? properties.strokeWidth : 2.0
        let dashPattern = (objectProperties.dashPattern ?? []).map { CGFloat($0) }
        let needsTrim = properties.trimStart > 0.001 || properties.trimEnd < 0.999
        
        ZStack {
            // Fill layer
            if hasFill {
                CustomPath(commands: commands, closePath: shouldClose)
                    .trim(from: effectiveTrimStart, to: effectiveTrimEnd)
                    .fill(properties.fillColor.color)
                    .frame(width: properties.width, height: properties.height)
            }
            
            // Stroke layer
            if hasStroke {
                CustomPath(commands: commands, closePath: shouldClose)
                    .trim(from: effectiveTrimStart, to: effectiveTrimEnd)
                    .stroke(
                        properties.strokeColor.color,
                        style: StrokeStyle(
                            lineWidth: strokeWidth,
                            lineCap: resolveLineCap(objectProperties.lineCap),
                            lineJoin: resolveLineJoin(objectProperties.lineJoin),
                            dash: dashPattern,
                            dashPhase: properties.dashPhase
                        )
                    )
                    .frame(width: properties.width, height: properties.height)
            }
        }
    }
    
    /// Compute effective trim start/end with offset applied
    private var effectiveTrimStart: CGFloat {
        let offset = properties.trimOffset
        let start = properties.trimStart + offset
        // Wrap around 0-1
        return start.truncatingRemainder(dividingBy: 1.0)
    }
    
    private var effectiveTrimEnd: CGFloat {
        let offset = properties.trimOffset
        let end = properties.trimEnd + offset
        return min(1.0, max(0.0, end))
    }
    
    private func resolveLineCap(_ cap: String?) -> CGLineCap {
        switch cap?.lowercased() {
        case "round": return .round
        case "square": return .square
        default: return .butt
        }
    }
    
    private func resolveLineJoin(_ join: String?) -> CGLineJoin {
        switch join?.lowercased() {
        case "round": return .round
        case "bevel": return .bevel
        default: return .miter
        }
    }
}

// MARK: - Custom Path Shape

/// Renders an array of `PathCommand` values.
/// Coordinates are normalized: (-0.5, -0.5) = top-left, (0.5, 0.5) = bottom-right,
/// (0, 0) = center of the object's bounding rect.
struct CustomPath: Shape {
    let commands: [PathCommand]
    let closePath: Bool
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let cx = rect.midX
        let cy = rect.midY
        
        for cmd in commands {
            switch cmd.command.lowercased() {
            case "move", "moveto", "m":
                let pt = point(cmd.x, cmd.y, cx: cx, cy: cy, w: w, h: h)
                path.move(to: pt)
                
            case "line", "lineto", "l":
                let pt = point(cmd.x, cmd.y, cx: cx, cy: cy, w: w, h: h)
                path.addLine(to: pt)
                
            case "quadcurve", "quad", "q":
                let pt = point(cmd.x, cmd.y, cx: cx, cy: cy, w: w, h: h)
                let cp = point(cmd.cx1, cmd.cy1, cx: cx, cy: cy, w: w, h: h)
                path.addQuadCurve(to: pt, control: cp)
                
            case "curve", "cubic", "c":
                let pt = point(cmd.x, cmd.y, cx: cx, cy: cy, w: w, h: h)
                let cp1 = point(cmd.cx1, cmd.cy1, cx: cx, cy: cy, w: w, h: h)
                let cp2 = point(cmd.cx2, cmd.cy2, cx: cx, cy: cy, w: w, h: h)
                path.addCurve(to: pt, control1: cp1, control2: cp2)
                
            case "arc":
                let center = point(cmd.x, cmd.y, cx: cx, cy: cy, w: w, h: h)
                let radius = (cmd.rx ?? 0.25) * min(w, h)
                let startAngle = Angle.degrees(cmd.startAngle ?? 0)
                let endAngle = Angle.degrees(cmd.endAngle ?? 360)
                let clockwise = cmd.clockwise ?? false
                path.addArc(center: center, radius: radius,
                           startAngle: startAngle, endAngle: endAngle,
                           clockwise: clockwise)
                
            case "close":
                path.closeSubpath()
                
            default:
                break
            }
        }
        
        if closePath {
            path.closeSubpath()
        }
        
        return path
    }
    
    /// Convert normalized coordinates to actual points.
    /// x/y of 0 = center, -0.5 = left/top edge, 0.5 = right/bottom edge.
    private func point(_ x: Double?, _ y: Double?,
                       cx: Double, cy: Double,
                       w: Double, h: Double) -> CGPoint {
        CGPoint(
            x: cx + (x ?? 0) * w,
            y: cy + (y ?? 0) * h
        )
    }
}

// MARK: - Regular Polygon Shape

struct RegularPolygon: Shape {
    let sides: Int
    
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        
        var path = Path()
        
        for i in 0..<sides {
            let angle = CGFloat(i) / CGFloat(sides) * 2 * .pi - .pi / 2
            let point = CGPoint(
                x: center.x + radius * Darwin.cos(angle),
                y: center.y + radius * Darwin.sin(angle)
            )
            
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        
        path.closeSubpath()
        return path
    }
}
