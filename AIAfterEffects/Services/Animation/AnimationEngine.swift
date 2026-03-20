//
//  AnimationEngine.swift
//  AIAfterEffects
//
//  Core animation engine for generating default keyframes and handling animation logic
//

import Foundation

class AnimationEngine {
    
    // MARK: - Default Keyframes
    
    /// Generate default keyframes for a given animation type
    func defaultKeyframes(for type: AnimationType) -> [Keyframe] {
        switch type {
            
        // MARK: Basic Opacity
        case .fadeIn:
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(1))
            ]
            
        case .fadeOut:
            return [
                Keyframe(time: 0, value: .double(1)),
                Keyframe(time: 1, value: .double(0))
            ]
            
        case .fade:
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.5, value: .double(1)),
                Keyframe(time: 1, value: .double(0))
            ]
            
        case .blurIn:
            return [
                Keyframe(time: 0, value: .double(20)),  // Blur amount
                Keyframe(time: 1, value: .double(0))
            ]
            
        case .blurOut:
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(20))
            ]
            
        // MARK: Basic Position
        case .moveX:
            return [
                Keyframe(time: 0, value: .double(-100)),
                Keyframe(time: 1, value: .double(0))
            ]
            
        case .moveY:
            return [
                Keyframe(time: 0, value: .double(-100)),
                Keyframe(time: 1, value: .double(0))
            ]
            
        case .move:
            return [
                Keyframe(time: 0, value: .point(x: -100, y: -100)),
                Keyframe(time: 1, value: .point(x: 0, y: 0))
            ]
            
        // MARK: Basic Scale
        case .scale:
            return [
                Keyframe(time: 0, value: .scale(x: 0, y: 0)),
                Keyframe(time: 1, value: .scale(x: 1, y: 1))
            ]
            
        case .scaleX:
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(1))
            ]
            
        case .scaleY:
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(1))
            ]
            
        // MARK: Basic Rotation
        case .rotate:
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(180))
            ]
            
        case .spin:
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(360))
            ]
            
        // MARK: Combined Effects
        case .bounce:
            return [
                Keyframe(time: 0, value: .double(-200)),
                Keyframe(time: 0.4, value: .double(0)),
                Keyframe(time: 0.55, value: .double(-60)),
                Keyframe(time: 0.7, value: .double(0)),
                Keyframe(time: 0.8, value: .double(-20)),
                Keyframe(time: 0.9, value: .double(0)),
                Keyframe(time: 1, value: .double(0))
            ]
            
        case .shake, .wiggle:
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.1, value: .double(-10)),
                Keyframe(time: 0.2, value: .double(10)),
                Keyframe(time: 0.3, value: .double(-10)),
                Keyframe(time: 0.4, value: .double(10)),
                Keyframe(time: 0.5, value: .double(-10)),
                Keyframe(time: 0.6, value: .double(10)),
                Keyframe(time: 0.7, value: .double(-10)),
                Keyframe(time: 0.8, value: .double(10)),
                Keyframe(time: 0.9, value: .double(-5)),
                Keyframe(time: 1, value: .double(0))
            ]
            
        case .pulse:
            return [
                Keyframe(time: 0, value: .scale(x: 1, y: 1)),
                Keyframe(time: 0.5, value: .scale(x: 1.15, y: 1.15)),
                Keyframe(time: 1, value: .scale(x: 1, y: 1))
            ]
            
        case .slideIn:
            return [
                Keyframe(time: 0, value: .double(-500)),
                Keyframe(time: 1, value: .double(0))
            ]
            
        case .slideOut:
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(500))
            ]
            
        case .grow:
            return [
                Keyframe(time: 0, value: .scale(x: 0, y: 0)),
                Keyframe(time: 1, value: .scale(x: 1, y: 1))
            ]
            
        case .shrink:
            return [
                Keyframe(time: 0, value: .scale(x: 1, y: 1)),
                Keyframe(time: 1, value: .scale(x: 0, y: 0))
            ]
            
        case .pop:
            // Overshoot then settle - classic pop effect
            return [
                Keyframe(time: 0, value: .scale(x: 0, y: 0)),
                Keyframe(time: 0.5, value: .scale(x: 1.25, y: 1.25)),
                Keyframe(time: 0.75, value: .scale(x: 0.95, y: 0.95)),
                Keyframe(time: 1, value: .scale(x: 1, y: 1))
            ]
            
        case .typewriter, .wave:
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(1))
            ]
            
        case .colorChange:
            return [
                Keyframe(time: 0, value: .color(.white)),
                Keyframe(time: 1, value: .color(.blue))
            ]
        
        case .fillColorChange, .strokeColorChange:
            return [
                Keyframe(time: 0, value: .color(.white)),
                Keyframe(time: 1, value: .color(.blue))
            ]
            
        // MARK: Disney Principles
        case .anticipation:
            // Pull back before going forward
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.25, value: .double(-30)),   // Pull back
                Keyframe(time: 1, value: .double(100))       // Forward
            ]
            
        case .overshoot:
            // Go past then settle
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.7, value: .double(120)),    // Overshoot
                Keyframe(time: 0.85, value: .double(95)),    // Settle back
                Keyframe(time: 1, value: .double(100))       // Final
            ]
            
        case .followThrough:
            // Continue past then return
            return [
                Keyframe(time: 0, value: .double(-100)),
                Keyframe(time: 0.5, value: .double(0)),
                Keyframe(time: 0.7, value: .double(15)),     // Follow through
                Keyframe(time: 1, value: .double(0))
            ]
            
        case .squashStretch:
            // Squash on impact, stretch during motion
            return [
                Keyframe(time: 0, value: .scale(x: 1, y: 1.3)),    // Stretched
                Keyframe(time: 0.4, value: .scale(x: 1.3, y: 0.7)), // Squashed on impact
                Keyframe(time: 0.6, value: .scale(x: 0.9, y: 1.1)), // Recovery
                Keyframe(time: 1, value: .scale(x: 1, y: 1))        // Normal
            ]
            
        // MARK: Text Animations
        case .charByChar, .wordByWord, .lineByLine:
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(1))
            ]
            
        case .scramble:
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.7, value: .double(0.5)),  // Scrambling
                Keyframe(time: 1, value: .double(1))      // Resolved
            ]
            
        case .glitchText:
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.1, value: .double(15)),   // Glitch intensity
                Keyframe(time: 0.2, value: .double(0)),
                Keyframe(time: 0.3, value: .double(10)),
                Keyframe(time: 0.5, value: .double(0)),
                Keyframe(time: 0.6, value: .double(8)),
                Keyframe(time: 0.7, value: .double(0)),
                Keyframe(time: 1, value: .double(0))
            ]
            
        // MARK: Reveals & Masks
        case .reveal, .wipeIn, .clipIn:
            return [
                Keyframe(time: 0, value: .double(0)),     // 0% revealed
                Keyframe(time: 1, value: .double(1))     // 100% revealed
            ]
            
        case .wipeOut:
            return [
                Keyframe(time: 0, value: .double(1)),
                Keyframe(time: 1, value: .double(0))
            ]
            
        case .splitReveal:
            // Split from center
            return [
                Keyframe(time: 0, value: .double(0)),     // Closed
                Keyframe(time: 0.3, value: .double(0)),   // Hold closed
                Keyframe(time: 1, value: .double(1))     // Fully open
            ]
            
        // MARK: Impact Effects
        case .glitch:
            // RGB split amount
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.15, value: .double(20)),
                Keyframe(time: 0.2, value: .double(0)),
                Keyframe(time: 0.35, value: .double(15)),
                Keyframe(time: 0.4, value: .double(0)),
                Keyframe(time: 0.55, value: .double(25)),
                Keyframe(time: 0.6, value: .double(0)),
                Keyframe(time: 1, value: .double(0))
            ]
            
        case .flicker:
            return [
                Keyframe(time: 0, value: .double(1)),
                Keyframe(time: 0.1, value: .double(0)),
                Keyframe(time: 0.15, value: .double(1)),
                Keyframe(time: 0.2, value: .double(0.3)),
                Keyframe(time: 0.25, value: .double(1)),
                Keyframe(time: 0.4, value: .double(0)),
                Keyframe(time: 0.45, value: .double(1)),
                Keyframe(time: 0.5, value: .double(0.5)),
                Keyframe(time: 0.55, value: .double(1)),
                Keyframe(time: 1, value: .double(1))
            ]
            
        case .flash:
            // Flash effect: invisible → instant bright flash → sharp decay
            // A true flash that appears briefly and disappears.
            // Presets that need content to stay visible after a flash add a separate fadeIn animation.
            return [
                Keyframe(time: 0, value: .double(0)),      // Start invisible
                Keyframe(time: 0.1, value: .double(1)),    // Instant peak
                Keyframe(time: 0.35, value: .double(0.05)),// Sharp decay
                Keyframe(time: 1, value: .double(0))       // Gone
            ]
            
        case .slam:
            // Fast scale with impact shake at end
            return [
                Keyframe(time: 0, value: .scale(x: 3, y: 3)),
                Keyframe(time: 0.2, value: .scale(x: 0.9, y: 0.9)),  // Impact compress
                Keyframe(time: 0.3, value: .scale(x: 1.05, y: 1.05)),
                Keyframe(time: 0.4, value: .scale(x: 0.98, y: 0.98)),
                Keyframe(time: 1, value: .scale(x: 1, y: 1))
            ]
            
        case .explode:
            return [
                Keyframe(time: 0, value: .scale(x: 1, y: 1)),
                Keyframe(time: 0.5, value: .scale(x: 2, y: 2)),
                Keyframe(time: 1, value: .scale(x: 3, y: 3))
            ]
            
        case .implode:
            return [
                Keyframe(time: 0, value: .scale(x: 4, y: 4)),
                Keyframe(time: 0.7, value: .scale(x: 0.8, y: 0.8)),
                Keyframe(time: 1, value: .scale(x: 1, y: 1))
            ]
            
        // MARK: Organic Motion
        case .float:
            // Gentle up and down floating
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.25, value: .double(-15)),
                Keyframe(time: 0.5, value: .double(0)),
                Keyframe(time: 0.75, value: .double(15)),
                Keyframe(time: 1, value: .double(0))
            ]
            
        case .drift:
            return [
                Keyframe(time: 0, value: .point(x: 0, y: 0)),
                Keyframe(time: 1, value: .point(x: 30, y: -20))
            ]
            
        case .breathe:
            // Subtle scale breathing
            return [
                Keyframe(time: 0, value: .scale(x: 1, y: 1)),
                Keyframe(time: 0.5, value: .scale(x: 1.03, y: 1.03)),
                Keyframe(time: 1, value: .scale(x: 1, y: 1))
            ]
            
        case .sway:
            // Pendulum-like rotation
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.25, value: .double(-8)),
                Keyframe(time: 0.5, value: .double(0)),
                Keyframe(time: 0.75, value: .double(8)),
                Keyframe(time: 1, value: .double(0))
            ]
            
        case .jitter:
            // Micro random movements
            return [
                Keyframe(time: 0, value: .point(x: 0, y: 0)),
                Keyframe(time: 0.1, value: .point(x: 2, y: -1)),
                Keyframe(time: 0.2, value: .point(x: -1, y: 2)),
                Keyframe(time: 0.3, value: .point(x: 1, y: 1)),
                Keyframe(time: 0.4, value: .point(x: -2, y: -1)),
                Keyframe(time: 0.5, value: .point(x: 1, y: -2)),
                Keyframe(time: 0.6, value: .point(x: -1, y: 1)),
                Keyframe(time: 0.7, value: .point(x: 2, y: 0)),
                Keyframe(time: 0.8, value: .point(x: 0, y: 2)),
                Keyframe(time: 0.9, value: .point(x: -1, y: -1)),
                Keyframe(time: 1, value: .point(x: 0, y: 0))
            ]
            
        // MARK: Kinetic Typography
        case .dropIn:
            // Drop from above with bounce
            return [
                Keyframe(time: 0, value: .double(-300)),
                Keyframe(time: 0.5, value: .double(20)),
                Keyframe(time: 0.7, value: .double(-10)),
                Keyframe(time: 0.85, value: .double(5)),
                Keyframe(time: 1, value: .double(0))
            ]
            
        case .riseUp:
            // Rise from below
            return [
                Keyframe(time: 0, value: .double(200)),
                Keyframe(time: 0.7, value: .double(-10)),
                Keyframe(time: 1, value: .double(0))
            ]
            
        case .swingIn:
            // Swing in from rotation
            return [
                Keyframe(time: 0, value: .double(-90)),
                Keyframe(time: 0.5, value: .double(15)),
                Keyframe(time: 0.75, value: .double(-8)),
                Keyframe(time: 1, value: .double(0))
            ]
            
        case .elasticIn:
            // Elastic scale in
            return [
                Keyframe(time: 0, value: .scale(x: 0, y: 0)),
                Keyframe(time: 0.5, value: .scale(x: 1.2, y: 1.2)),
                Keyframe(time: 0.65, value: .scale(x: 0.9, y: 0.9)),
                Keyframe(time: 0.8, value: .scale(x: 1.05, y: 1.05)),
                Keyframe(time: 1, value: .scale(x: 1, y: 1))
            ]
            
        case .elasticOut:
            return [
                Keyframe(time: 0, value: .scale(x: 1, y: 1)),
                Keyframe(time: 0.2, value: .scale(x: 1.1, y: 1.1)),
                Keyframe(time: 0.5, value: .scale(x: 0.8, y: 0.8)),
                Keyframe(time: 1, value: .scale(x: 0, y: 0))
            ]
            
        case .snapIn:
            // Quick snap with micro-overshoot
            return [
                Keyframe(time: 0, value: .scale(x: 0, y: 0)),
                Keyframe(time: 0.6, value: .scale(x: 1.08, y: 1.08)),
                Keyframe(time: 1, value: .scale(x: 1, y: 1))
            ]
            
        case .whipIn:
            // Fast whip from side
            return [
                Keyframe(time: 0, value: .double(-800)),
                Keyframe(time: 0.4, value: .double(30)),
                Keyframe(time: 0.6, value: .double(-15)),
                Keyframe(time: 1, value: .double(0))
            ]
            
        case .zoomBlur:
            // Zoom with motion blur feel
            return [
                Keyframe(time: 0, value: .scale(x: 5, y: 5)),
                Keyframe(time: 0.3, value: .scale(x: 0.95, y: 0.95)),
                Keyframe(time: 1, value: .scale(x: 1, y: 1))
            ]
            
        case .tracking:
            // Cinematic letter-spacing: start wide, settle to normal (0)
            return [
                Keyframe(time: 0, value: .double(30)),   // Wide kerning
                Keyframe(time: 1, value: .double(0))     // Normal spacing
            ]
            
        // MARK: Visual Effects
        case .blur:
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(15))
            ]
        case .brightnessAnim:
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.5, value: .double(0.3)),
                Keyframe(time: 1, value: .double(0))
            ]
        case .contrastAnim:
            return [
                Keyframe(time: 0, value: .double(1)),
                Keyframe(time: 0.5, value: .double(1.5)),
                Keyframe(time: 1, value: .double(1))
            ]
        case .saturationAnim:
            return [
                Keyframe(time: 0, value: .double(0)),     // Grayscale
                Keyframe(time: 1, value: .double(1))      // Full color
            ]
        case .hueRotate:
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(360))    // Full rotation
            ]
        case .grayscaleAnim:
            return [
                Keyframe(time: 0, value: .double(1)),     // Full grayscale
                Keyframe(time: 1, value: .double(0))      // Full color
            ]
        case .shadowAnim:
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.5, value: .double(20)),
                Keyframe(time: 1, value: .double(10))
            ]
            
        // MARK: Path Animations
        case .trimPath:
            // Draw-on effect: reveal full path from 0% to 100%
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(1))
            ]
        case .trimPathStart:
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(1))
            ]
        case .trimPathEnd:
            // Draw-on: end goes from 0 → 1
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(1))
            ]
        case .trimPathOffset:
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(1))
            ]
        case .strokeWidthAnim:
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(4))
            ]
        case .dashOffset:
            // Marching ants: continuous dash shift
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(50))
            ]
            
        // MARK: 3D Transform Animations
        case .rotate3DX:
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(360))
            ]
        case .rotate3DY:
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(360))
            ]
        case .rotate3DZ:
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(360))
            ]
        case .turntable:
            // Classic product showcase: full 360 Y rotation
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(360))
            ]
        case .orbit3D:
            // Orbit: animates a circular path in 3D
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(360))
            ]
        case .wobble3D:
            // Damped rocking — starts wide, settles to rest (not a perfect loop).
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.15, value: .double(22)),
                Keyframe(time: 0.35, value: .double(-15)),
                Keyframe(time: 0.55, value: .double(8)),
                Keyframe(time: 0.75, value: .double(-4)),
                Keyframe(time: 0.9, value: .double(1.5)),
                Keyframe(time: 1, value: .double(0))
            ]
        case .flip3D:
            // Full 180 or 360 flip
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.4, value: .double(90)),
                Keyframe(time: 0.6, value: .double(270)),
                Keyframe(time: 1, value: .double(360))
            ]
        case .float3D:
            // Graceful upward drift that settles — NOT a symmetric bounce.
            // Moves up with deceleration, ending at a higher resting position.
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.3, value: .double(-25)),
                Keyframe(time: 0.6, value: .double(-45)),
                Keyframe(time: 0.85, value: .double(-52)),
                Keyframe(time: 1, value: .double(-50))
            ]
            
        case .cradle:
            // C4D-inspired pendulum: big swing that damps to rest
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.1, value: .double(45)),
                Keyframe(time: 0.3, value: .double(-35)),
                Keyframe(time: 0.5, value: .double(22)),
                Keyframe(time: 0.65, value: .double(-14)),
                Keyframe(time: 0.78, value: .double(8)),
                Keyframe(time: 0.88, value: .double(-4)),
                Keyframe(time: 1, value: .double(0))
            ]
            
        case .springBounce3D:
            // Drop from above with spring physics bounce (inspired by Advance.js)
            // Values are Y position offset — starts high, bounces at ground (0)
            return [
                Keyframe(time: 0, value: .double(-200)),
                Keyframe(time: 0.35, value: .double(0)),
                Keyframe(time: 0.5, value: .double(-60)),
                Keyframe(time: 0.65, value: .double(0)),
                Keyframe(time: 0.77, value: .double(-20)),
                Keyframe(time: 0.87, value: .double(0)),
                Keyframe(time: 0.93, value: .double(-6)),
                Keyframe(time: 1, value: .double(0))
            ]
            
        case .elasticSpin:
            // GSAP-inspired: spin 360° then overshoot and elastically settle back
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.5, value: .double(360)),
                Keyframe(time: 0.65, value: .double(395)),   // overshoot +35°
                Keyframe(time: 0.78, value: .double(352)),   // bounce back -8°
                Keyframe(time: 0.88, value: .double(365)),   // micro overshoot +5°
                Keyframe(time: 1, value: .double(360))       // settle
            ]
            
        case .swing3D:
            // Three.js pendulum: rotation on Z axis, like a hanging sign
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.15, value: .double(35)),
                Keyframe(time: 0.35, value: .double(-28)),
                Keyframe(time: 0.5, value: .double(18)),
                Keyframe(time: 0.65, value: .double(-12)),
                Keyframe(time: 0.78, value: .double(6)),
                Keyframe(time: 0.88, value: .double(-3)),
                Keyframe(time: 1, value: .double(0))
            ]
            
        case .breathe3D:
            // Single organic expansion — swells up with overshoot and settles slightly larger.
            // NOT a symmetric inflate/deflate. Feels like one deep inhale.
            return [
                Keyframe(time: 0, value: .double(1.0)),
                Keyframe(time: 0.3, value: .double(1.12)),
                Keyframe(time: 0.55, value: .double(1.08)),
                Keyframe(time: 0.75, value: .double(1.05)),
                Keyframe(time: 1, value: .double(1.04))
            ]
            
        case .headNod:
            // Character animation: tilt forward/back like nodding "yes"
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.15, value: .double(18)),
                Keyframe(time: 0.3, value: .double(-5)),
                Keyframe(time: 0.45, value: .double(14)),
                Keyframe(time: 0.6, value: .double(-3)),
                Keyframe(time: 0.75, value: .double(8)),
                Keyframe(time: 1, value: .double(0))
            ]
            
        case .headShake:
            // Character animation: quick shake on Y axis like "no"
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.1, value: .double(-25)),
                Keyframe(time: 0.25, value: .double(22)),
                Keyframe(time: 0.38, value: .double(-18)),
                Keyframe(time: 0.52, value: .double(14)),
                Keyframe(time: 0.65, value: .double(-8)),
                Keyframe(time: 0.78, value: .double(4)),
                Keyframe(time: 0.88, value: .double(-2)),
                Keyframe(time: 1, value: .double(0))
            ]
            
        case .rockAndRoll:
            // C4D vibrate effector: combined X+Z rocking (value drives both axes via phase offset)
            // The value represents angle — renderer applies it to both X and Z with different phases
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.125, value: .double(20)),
                Keyframe(time: 0.25, value: .double(0)),
                Keyframe(time: 0.375, value: .double(-20)),
                Keyframe(time: 0.5, value: .double(0)),
                Keyframe(time: 0.625, value: .double(15)),
                Keyframe(time: 0.75, value: .double(0)),
                Keyframe(time: 0.875, value: .double(-15)),
                Keyframe(time: 1, value: .double(0))
            ]
            
        case .scaleUp3D:
            // Motion preset: scale from 0 to full with overshoot
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.5, value: .double(1.18)),
                Keyframe(time: 0.7, value: .double(0.92)),
                Keyframe(time: 0.85, value: .double(1.05)),
                Keyframe(time: 1, value: .double(1.0))
            ]
            
        case .scaleDown3D:
            // Motion preset: scale from full to 0 with anticipation windup
            return [
                Keyframe(time: 0, value: .double(1.0)),
                Keyframe(time: 0.2, value: .double(1.12)),   // anticipation: grow slightly first
                Keyframe(time: 0.5, value: .double(0.4)),
                Keyframe(time: 1, value: .double(0))
            ]
            
        case .slamDown3D:
            // After Effects impact: fast drop from above + squash on impact
            // Value is Y position, renderer also applies temporary scale squash
            return [
                Keyframe(time: 0, value: .double(-250)),
                Keyframe(time: 0.25, value: .double(0)),     // impact point
                Keyframe(time: 0.35, value: .double(8)),     // micro bounce
                Keyframe(time: 0.45, value: .double(0)),     // settle
                Keyframe(time: 0.55, value: .double(3)),     // tiny bounce
                Keyframe(time: 1, value: .double(0))         // rest
            ]
            
        case .revolveSlow:
            // Product showcase: elegant slow partial turn (0→45°)
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(45))
            ]
            
        case .tumble:
            // Chaotic multi-axis tumble — progress drives all 3 axes at different rates
            // Value is base angle; renderer multiplies by different factors per axis
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(720))  // Two full rotations worth of chaos
            ]
            
        case .barrelRoll:
            // Clean 360° roll on Z axis — like a fighter jet barrel roll
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(360))
            ]
            
        case .corkscrew:
            // Helical upward spiral — value is progress (0→1), renderer computes position + rotation
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(1))
            ]
            
        case .figureEight:
            // Infinity/figure-8 Lissajous path — value is progress (0→1)
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(1))
            ]
            
        case .boomerang3D:
            // Fling out fast, arc, and curve back to origin
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.15, value: .double(1.0)),   // peak outward velocity
                Keyframe(time: 0.5, value: .double(0.85)),    // distant arc point
                Keyframe(time: 0.75, value: .double(0.3)),    // curving back
                Keyframe(time: 1, value: .double(0))          // back to start
            ]
            
        case .levitate:
            // Graceful ascension — rises with deceleration and settles at hover height.
            // NOT a symmetric bounce. Ends elevated, like zero-gravity suspension.
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.2, value: .double(-20)),
                Keyframe(time: 0.45, value: .double(-48)),
                Keyframe(time: 0.7, value: .double(-60)),
                Keyframe(time: 0.9, value: .double(-64)),
                Keyframe(time: 1, value: .double(-65))       // stays elevated
            ]
            
        case .magnetPull:
            // Accelerating pull toward camera — starts slow, gets faster
            // Value is Z position offset (negative = toward camera)
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.3, value: .double(-5)),
                Keyframe(time: 0.6, value: .double(-20)),
                Keyframe(time: 0.8, value: .double(-55)),
                Keyframe(time: 0.95, value: .double(-90)),
                Keyframe(time: 1, value: .double(-100))
            ]
            
        case .magnetPush:
            // Decelerating push away — starts fast, slows to stop
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.15, value: .double(50)),
                Keyframe(time: 0.35, value: .double(78)),
                Keyframe(time: 0.55, value: .double(90)),
                Keyframe(time: 0.75, value: .double(96)),
                Keyframe(time: 1, value: .double(100))
            ]
            
        case .zigzagDrop:
            // Falling leaf zigzag descent — value is progress (0→1), renderer computes X+Y offsets
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(1))
            ]
            
        case .rubberBand:
            // Horizontal stretch and snap back (GSAP CustomBounce)
            // Value is scale multiplier for X axis
            return [
                Keyframe(time: 0, value: .double(1.0)),
                Keyframe(time: 0.15, value: .double(1.6)),    // stretch out
                Keyframe(time: 0.3, value: .double(0.7)),     // snap overshoot
                Keyframe(time: 0.45, value: .double(1.25)),   // bounce back
                Keyframe(time: 0.6, value: .double(0.88)),    // settle
                Keyframe(time: 0.75, value: .double(1.08)),   // micro bounce
                Keyframe(time: 1, value: .double(1.0))        // rest
            ]
            
        case .jelly3D:
            // Disney squash/stretch wobble — alternating axis deformation
            // Value drives a phase that alternates squash X/stretch Y and vice versa
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.12, value: .double(1.0)),    // squash Y / stretch X
                Keyframe(time: 0.25, value: .double(-0.8)),   // stretch Y / squash X
                Keyframe(time: 0.37, value: .double(0.6)),
                Keyframe(time: 0.5, value: .double(-0.45)),
                Keyframe(time: 0.62, value: .double(0.3)),
                Keyframe(time: 0.75, value: .double(-0.18)),
                Keyframe(time: 0.87, value: .double(0.08)),
                Keyframe(time: 1, value: .double(0))
            ]
            
        case .anticipateSpin:
            // Pull back -30° then whip forward +360°
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.25, value: .double(-35)),    // anticipation pullback
                Keyframe(time: 0.35, value: .double(-35)),    // hold
                Keyframe(time: 0.8, value: .double(360)),     // whip spin
                Keyframe(time: 0.9, value: .double(370)),     // overshoot
                Keyframe(time: 1, value: .double(360))        // settle
            ]
            
        case .popIn3D:
            // Scale 0→1.3→1 with burst of rotation
            // Value is scale factor; rotation is derived from progress in renderer
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.35, value: .double(1.35)),   // overshoot
                Keyframe(time: 0.55, value: .double(0.9)),    // undershoot
                Keyframe(time: 0.72, value: .double(1.08)),   // micro bounce
                Keyframe(time: 1, value: .double(1.0))        // settle
            ]
            
        case .glitchJitter3D:
            // Rapid random-like micro position + rotation jitter (all values pre-baked)
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.05, value: .double(8)),
                Keyframe(time: 0.1, value: .double(-12)),
                Keyframe(time: 0.15, value: .double(5)),
                Keyframe(time: 0.2, value: .double(-15)),
                Keyframe(time: 0.25, value: .double(10)),
                Keyframe(time: 0.3, value: .double(-6)),
                Keyframe(time: 0.35, value: .double(14)),
                Keyframe(time: 0.4, value: .double(-9)),
                Keyframe(time: 0.45, value: .double(11)),
                Keyframe(time: 0.5, value: .double(-13)),
                Keyframe(time: 0.55, value: .double(7)),
                Keyframe(time: 0.6, value: .double(-10)),
                Keyframe(time: 0.65, value: .double(12)),
                Keyframe(time: 0.7, value: .double(-8)),
                Keyframe(time: 0.75, value: .double(6)),
                Keyframe(time: 0.8, value: .double(-11)),
                Keyframe(time: 0.85, value: .double(9)),
                Keyframe(time: 0.9, value: .double(-5)),
                Keyframe(time: 0.95, value: .double(3)),
                Keyframe(time: 1, value: .double(0))
            ]
            
        case .heartbeat3D:
            // Double-beat pulse: ba-DUM ... ba-DUM — scale factor
            return [
                Keyframe(time: 0, value: .double(1.0)),
                Keyframe(time: 0.08, value: .double(1.15)),   // first beat up
                Keyframe(time: 0.16, value: .double(0.97)),   // relax
                Keyframe(time: 0.22, value: .double(1.25)),   // second beat (stronger)
                Keyframe(time: 0.35, value: .double(0.95)),   // relax
                Keyframe(time: 0.55, value: .double(1.0)),    // rest period
                Keyframe(time: 1, value: .double(1.0))        // rest until next cycle
            ]
            
        case .tornado:
            // Vortex: progress (0→1) drives rising spin + scale change
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(1))
            ]
            
        case .unwrap:
            // Unfolding from flat to face camera — X rotation from 90° to 0°
            return [
                Keyframe(time: 0, value: .double(90)),
                Keyframe(time: 0.6, value: .double(-8)),     // overshoot past flat
                Keyframe(time: 0.78, value: .double(4)),     // bounce
                Keyframe(time: 0.9, value: .double(-2)),     // micro settle
                Keyframe(time: 1, value: .double(0))         // face camera
            ]
            
        case .dropAndSettle:
            // Realistic gravity drop — position Y with realistic acceleration curve
            return [
                Keyframe(time: 0, value: .double(-180)),     // start above
                Keyframe(time: 0.18, value: .double(-150)),   // slow at first (gravity starts)
                Keyframe(time: 0.35, value: .double(-60)),    // accelerating
                Keyframe(time: 0.45, value: .double(0)),      // impact
                Keyframe(time: 0.55, value: .double(-25)),    // bounce
                Keyframe(time: 0.63, value: .double(0)),      // impact 2
                Keyframe(time: 0.72, value: .double(-8)),     // micro bounce
                Keyframe(time: 0.82, value: .double(0)),      // settle
                Keyframe(time: 0.9, value: .double(-2)),      // barely
                Keyframe(time: 1, value: .double(0))          // done
            ]
            
        // MARK: 3D Camera Animations
        case .cameraZoom:
            // Dolly in (one-directional — AI sets specific start/end values via keyframes)
            return [
                Keyframe(time: 0, value: .double(8)),  // Start far
                Keyframe(time: 1, value: .double(4))   // End close
            ]
        case .cameraPan:
            // Pan camera horizontally
            return [
                Keyframe(time: 0, value: .double(-30)),
                Keyframe(time: 1, value: .double(30))
            ]
        case .cameraOrbit:
            // Orbit camera around the model
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(360))
            ]
            
        case .spiralZoom:
            // Combined dolly-in + orbit: camera spirals inward toward model
            // Value controls the spiral progress (0→1), renderer computes both orbit angle and distance
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(1))
            ]
            
        case .dollyZoom:
            // Hitchcock vertigo effect: camera moves in while FOV widens (or vice versa)
            // Value controls the progress (0→1), renderer adjusts both distance and FOV
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(1))
            ]
            
        case .cameraRise:
            // Crane shot: camera rises vertically while looking at model
            // Value is the camera elevation angle (degrees)
            return [
                Keyframe(time: 0, value: .double(-10)),    // start slightly below eye level
                Keyframe(time: 1, value: .double(60))      // rise to dramatic high angle
            ]
            
        case .cameraDive:
            // Dramatic dive: camera plunges from above
            // Value is the camera elevation angle (degrees)
            return [
                Keyframe(time: 0, value: .double(70)),     // start high
                Keyframe(time: 1, value: .double(10))      // dive to near eye level
            ]
            
        case .cameraWhipPan:
            // Ultra-fast whip pan: camera Y angle whips with overshoot and settle
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.3, value: .double(110)),   // fast whip past target
                Keyframe(time: 0.5, value: .double(85)),    // bounce back
                Keyframe(time: 0.7, value: .double(95)),    // micro overshoot
                Keyframe(time: 1, value: .double(90))       // settle
            ]
            
        case .cameraSlide:
            // Dolly track: camera slides laterally while looking at model
            // Value is horizontal offset in scene units
            return [
                Keyframe(time: 0, value: .double(-3)),
                Keyframe(time: 1, value: .double(3))
            ]
            
        case .cameraArc:
            // Cinematic semicircle arc around model (0→180 degrees)
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(180))
            ]
            
        case .cameraPedestal:
            // Camera moves straight up (pedestal up)
            // Value is elevation angle in degrees
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(45))
            ]
            
        case .cameraTruck:
            // Camera moves laterally parallel to subject
            // Value is lateral offset in scene units
            return [
                Keyframe(time: 0, value: .double(-4)),
                Keyframe(time: 1, value: .double(4))
            ]
            
        case .cameraPushPull:
            // Push in then pull out — dramatic reveal and retreat
            // Value is camera distance
            return [
                Keyframe(time: 0, value: .double(8)),      // start far
                Keyframe(time: 0.45, value: .double(3.5)),  // push in close
                Keyframe(time: 0.55, value: .double(3.5)),  // hold close
                Keyframe(time: 1, value: .double(7))        // pull back out
            ]
            
        case .cameraDutchTilt:
            // Camera rolls to dutch angle and back — disorienting/dramatic
            // Value is roll angle in degrees
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.3, value: .double(18)),    // tilt into dutch
                Keyframe(time: 0.7, value: .double(18)),    // hold dutch
                Keyframe(time: 1, value: .double(0))        // return level
            ]
            
        case .cameraHelicopter:
            // Overhead descending spiral — helicopter landing shot
            // Value is progress (0→1), renderer computes angle + height + distance
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(1))
            ]
            
        case .cameraRocket:
            // Fast upward camera launch from ground level
            // Value is elevation angle — starts at 0 (ground), rockets up
            return [
                Keyframe(time: 0, value: .double(-5)),     // slightly below
                Keyframe(time: 0.4, value: .double(40)),    // fast rise
                Keyframe(time: 0.6, value: .double(68)),    // continuing
                Keyframe(time: 0.8, value: .double(78)),    // decelerating
                Keyframe(time: 1, value: .double(80))       // near top
            ]
            
        case .cameraShake:
            // Cinematic camera shake — earthquake/impact
            // Value is shake intensity offset applied to camera angle
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.05, value: .double(5)),
                Keyframe(time: 0.1, value: .double(-7)),
                Keyframe(time: 0.15, value: .double(6)),
                Keyframe(time: 0.2, value: .double(-8)),
                Keyframe(time: 0.25, value: .double(4)),
                Keyframe(time: 0.3, value: .double(-6)),
                Keyframe(time: 0.35, value: .double(5)),
                Keyframe(time: 0.4, value: .double(-4)),
                Keyframe(time: 0.5, value: .double(3)),
                Keyframe(time: 0.6, value: .double(-2)),
                Keyframe(time: 0.7, value: .double(1.5)),
                Keyframe(time: 0.8, value: .double(-1)),
                Keyframe(time: 0.9, value: .double(0.5)),
                Keyframe(time: 1, value: .double(0))
            ]
            
        // MARK: 3D Material/Appearance
        case .materialFade:
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(1))
            ]
            
        // MARK: 3D Position/Scale Keyframe Tracks
        case .move3DX, .move3DY, .move3DZ:
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(0))
            ]
        case .scale3DZ:
            return [
                Keyframe(time: 0, value: .double(1)),
                Keyframe(time: 1, value: .double(1))
            ]
        case .textSizeChange:
            return [
                Keyframe(time: 0, value: .double(48)),
                Keyframe(time: 1, value: .double(48))
            ]
            
        // MARK: Anime.js-Inspired: Stagger-Based
        case .staggerFadeIn:
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(1))
            ]
        case .staggerSlideUp:
            return [
                Keyframe(time: 0, value: .double(80)),    // Start 80px below
                Keyframe(time: 1, value: .double(0))
            ]
        case .staggerScaleIn:
            return [
                Keyframe(time: 0, value: .scale(x: 0, y: 0)),
                Keyframe(time: 0.6, value: .scale(x: 1.1, y: 1.1)),
                Keyframe(time: 1, value: .scale(x: 1, y: 1))
            ]
        case .ripple:
            return [
                Keyframe(time: 0, value: .scale(x: 0, y: 0)),
                Keyframe(time: 0.4, value: .scale(x: 1.15, y: 1.15)),
                Keyframe(time: 0.7, value: .scale(x: 0.95, y: 0.95)),
                Keyframe(time: 1, value: .scale(x: 1, y: 1))
            ]
        case .cascade:
            // Waterfall: slide down + fade in
            return [
                Keyframe(time: 0, value: .double(-60)),
                Keyframe(time: 0.6, value: .double(5)),
                Keyframe(time: 1, value: .double(0))
            ]
        case .domino:
            // Sequential topple: rotation from -90 to 0
            return [
                Keyframe(time: 0, value: .double(-90)),
                Keyframe(time: 0.5, value: .double(8)),
                Keyframe(time: 0.75, value: .double(-4)),
                Keyframe(time: 1, value: .double(0))
            ]
            
        // MARK: Anime.js-Inspired: Combo Entrances
        case .scaleRotateIn:
            // Scale from 0 + 180° rotation
            return [
                Keyframe(time: 0, value: .scale(x: 0, y: 0)),
                Keyframe(time: 0.6, value: .scale(x: 1.1, y: 1.1)),
                Keyframe(time: 1, value: .scale(x: 1, y: 1))
            ]
        case .blurSlideIn:
            // Slide from left + deblur (value is X offset)
            return [
                Keyframe(time: 0, value: .double(-200)),
                Keyframe(time: 0.7, value: .double(10)),
                Keyframe(time: 1, value: .double(0))
            ]
        case .flipReveal:
            // Rotation from 90° to 0° (Y-axis flip)
            return [
                Keyframe(time: 0, value: .double(90)),
                Keyframe(time: 0.6, value: .double(-8)),
                Keyframe(time: 0.8, value: .double(4)),
                Keyframe(time: 1, value: .double(0))
            ]
        case .elasticSlideIn:
            // Slide with elastic overshoot
            return [
                Keyframe(time: 0, value: .double(-400)),
                Keyframe(time: 0.4, value: .double(40)),
                Keyframe(time: 0.6, value: .double(-20)),
                Keyframe(time: 0.75, value: .double(10)),
                Keyframe(time: 0.85, value: .double(-5)),
                Keyframe(time: 1, value: .double(0))
            ]
        case .spiralIn:
            // Progress value: renderer computes spiral path
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(1))
            ]
        case .unfold:
            // ScaleY from 0 to 1 (unfold vertically)
            return [
                Keyframe(time: 0, value: .scale(x: 1, y: 0)),
                Keyframe(time: 0.6, value: .scale(x: 1, y: 1.08)),
                Keyframe(time: 1, value: .scale(x: 1, y: 1))
            ]
            
        // MARK: Anime.js-Inspired: Combo Exits
        case .scaleRotateOut:
            return [
                Keyframe(time: 0, value: .scale(x: 1, y: 1)),
                Keyframe(time: 0.3, value: .scale(x: 1.1, y: 1.1)),
                Keyframe(time: 1, value: .scale(x: 0, y: 0))
            ]
        case .blurSlideOut:
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(200))
            ]
        case .flipHide:
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(90))
            ]
        case .spiralOut:
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(1))
            ]
        case .foldUp:
            return [
                Keyframe(time: 0, value: .scale(x: 1, y: 1)),
                Keyframe(time: 0.4, value: .scale(x: 1, y: 1.05)),
                Keyframe(time: 1, value: .scale(x: 1, y: 0))
            ]
            
        // MARK: Anime.js-Inspired: Continuous/Loop Effects
        case .pendulum:
            // Smooth sine-based pendulum swing (rotation degrees)
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.25, value: .double(30)),
                Keyframe(time: 0.5, value: .double(0)),
                Keyframe(time: 0.75, value: .double(-30)),
                Keyframe(time: 1, value: .double(0))
            ]
        case .orbit2D:
            // Circular orbit progress (0→1)
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(1))
            ]
        case .lemniscate:
            // Figure-8 progress (0→1)
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(1))
            ]
        case .morphPulse:
            // Alternating squash-stretch: scaleX and scaleY alternate
            return [
                Keyframe(time: 0, value: .scale(x: 1, y: 1)),
                Keyframe(time: 0.25, value: .scale(x: 1.15, y: 0.88)),
                Keyframe(time: 0.5, value: .scale(x: 1, y: 1)),
                Keyframe(time: 0.75, value: .scale(x: 0.88, y: 1.15)),
                Keyframe(time: 1, value: .scale(x: 1, y: 1))
            ]
        case .neonFlicker:
            // Neon sign: random-feeling opacity flicker
            return [
                Keyframe(time: 0, value: .double(1)),
                Keyframe(time: 0.05, value: .double(0.4)),
                Keyframe(time: 0.1, value: .double(1)),
                Keyframe(time: 0.12, value: .double(0.2)),
                Keyframe(time: 0.18, value: .double(0.9)),
                Keyframe(time: 0.25, value: .double(1)),
                Keyframe(time: 0.5, value: .double(1)),
                Keyframe(time: 0.52, value: .double(0.3)),
                Keyframe(time: 0.55, value: .double(0.8)),
                Keyframe(time: 0.58, value: .double(1)),
                Keyframe(time: 0.8, value: .double(1)),
                Keyframe(time: 0.82, value: .double(0.5)),
                Keyframe(time: 0.85, value: .double(1)),
                Keyframe(time: 1, value: .double(1))
            ]
        case .glowPulse:
            // Shadow radius pulsing
            return [
                Keyframe(time: 0, value: .double(2)),
                Keyframe(time: 0.5, value: .double(20)),
                Keyframe(time: 1, value: .double(2))
            ]
        case .oscillate:
            // Smooth sine oscillation on Y axis
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 0.25, value: .double(-25)),
                Keyframe(time: 0.5, value: .double(0)),
                Keyframe(time: 0.75, value: .double(25)),
                Keyframe(time: 1, value: .double(0))
            ]
            
        // MARK: Anime.js-Inspired: Text Effects
        case .textWave:
            // Progress value for wave effect across characters
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(1))
            ]
        case .textRainbow:
            // Hue rotation progress (0→360)
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(360))
            ]
        case .textBounceIn:
            // Per-character Y offset bounce
            return [
                Keyframe(time: 0, value: .double(-200)),
                Keyframe(time: 0.5, value: .double(15)),
                Keyframe(time: 0.7, value: .double(-8)),
                Keyframe(time: 0.85, value: .double(4)),
                Keyframe(time: 1, value: .double(0))
            ]
        case .textElasticIn:
            // Per-character elastic scale
            return [
                Keyframe(time: 0, value: .scale(x: 0, y: 0)),
                Keyframe(time: 0.5, value: .scale(x: 1.25, y: 1.25)),
                Keyframe(time: 0.65, value: .scale(x: 0.9, y: 0.9)),
                Keyframe(time: 0.8, value: .scale(x: 1.06, y: 1.06)),
                Keyframe(time: 1, value: .scale(x: 1, y: 1))
            ]
            
        case .propertyChange:
            // Generic property change — default to simple 0→1 transition
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(1))
            ]
            
        case .pathMorph:
            // Path morphing uses progress 0→1; actual interpolation handled by PathMorpher
            return [
                Keyframe(time: 0, value: .double(0)),
                Keyframe(time: 1, value: .double(1))
            ]
        }
    }
    
    // MARK: - Animation Helpers
    
    /// Get recommended duration for animation type
    func recommendedDuration(for type: AnimationType) -> Double {
        switch type {
        // Quick animations
        case .fadeIn, .fadeOut, .snapIn:
            return 0.4
        case .pop, .flash:
            return 0.35
        case .slam, .whipIn:
            return 0.5
            
        // Medium animations
        case .slideIn, .slideOut, .clipIn, .reveal, .wipeIn, .wipeOut:
            return 0.6
        case .bounce, .dropIn, .riseUp:
            return 0.8
        case .elasticIn, .elasticOut, .swingIn:
            return 0.7
        case .overshoot, .anticipation, .followThrough:
            return 0.6
        case .zoomBlur, .implode:
            return 0.5
            
        // Longer animations
        case .shake, .wiggle, .glitch, .glitchText:
            return 0.8
        case .pulse, .breathe:
            return 1.2
        case .spin:
            return 1.0
        case .typewriter:
            return 2.0
        case .wave, .scramble:
            return 1.5
        case .float, .sway:
            return 2.5
        case .drift:
            return 3.0
        case .flicker:
            return 0.6
        case .explode, .splitReveal:
            return 0.8
        case .squashStretch:
            return 0.5
        case .jitter:
            return 1.0
        case .charByChar, .wordByWord, .lineByLine:
            return 1.5
        case .tracking:
            return 1.0
            
        case .blur, .brightnessAnim, .contrastAnim, .saturationAnim, .grayscaleAnim, .shadowAnim:
            return 1.0
        case .hueRotate:
            return 2.0
            
        // 3D Animations
        case .turntable, .cameraOrbit:
            return 4.0
        case .rotate3DX, .rotate3DY, .rotate3DZ:
            return 2.0
        case .orbit3D:
            return 6.0
        case .wobble3D:
            return 2.0
        case .flip3D:
            return 1.0
        case .float3D:
            return 3.0
        case .cradle:
            return 2.5
        case .springBounce3D:
            return 1.5
        case .elasticSpin:
            return 2.0
        case .swing3D:
            return 2.0
        case .breathe3D:
            return 2.5
        case .headNod:
            return 1.2
        case .headShake:
            return 1.0
        case .rockAndRoll:
            return 2.0
        case .scaleUp3D:
            return 1.0
        case .scaleDown3D:
            return 0.8
        case .slamDown3D:
            return 1.0
        case .revolveSlow:
            return 5.0
        case .tumble:
            return 2.0
        case .barrelRoll:
            return 1.5
        case .corkscrew:
            return 3.0
        case .figureEight:
            return 4.0
        case .boomerang3D:
            return 2.0
        case .levitate:
            return 3.0
        case .magnetPull:
            return 1.5
        case .magnetPush:
            return 1.5
        case .zigzagDrop:
            return 3.0
        case .rubberBand:
            return 1.2
        case .jelly3D:
            return 1.5
        case .anticipateSpin:
            return 2.0
        case .popIn3D:
            return 0.8
        case .glitchJitter3D:
            return 0.6
        case .heartbeat3D:
            return 1.2
        case .tornado:
            return 2.5
        case .unwrap:
            return 1.5
        case .dropAndSettle:
            return 1.5
        case .cameraZoom:
            return 3.0
        case .cameraPan:
            return 4.0
        case .spiralZoom:
            return 5.0
        case .dollyZoom:
            return 3.0
        case .cameraRise:
            return 4.0
        case .cameraDive:
            return 3.0
        case .cameraWhipPan:
            return 0.8
        case .cameraSlide:
            return 4.0
        case .cameraArc:
            return 5.0
        case .cameraPedestal:
            return 3.0
        case .cameraTruck:
            return 4.0
        case .cameraPushPull:
            return 4.0
        case .cameraDutchTilt:
            return 3.0
        case .cameraHelicopter:
            return 6.0
        case .cameraRocket:
            return 2.0
        case .cameraShake:
            return 0.8
        case .materialFade:
            return 1.0
        case .move3DX, .move3DY, .move3DZ:
            return 1.0
        case .scale3DZ:
            return 1.0
        case .textSizeChange:
            return 1.0
            
        // Anime.js-Inspired: Stagger-Based
        case .staggerFadeIn:
            return 0.5
        case .staggerSlideUp:
            return 0.6
        case .staggerScaleIn:
            return 0.5
        case .ripple:
            return 0.6
        case .cascade:
            return 0.7
        case .domino:
            return 0.6
            
        // Anime.js-Inspired: Combo Entrances
        case .scaleRotateIn:
            return 0.7
        case .blurSlideIn:
            return 0.6
        case .flipReveal:
            return 0.8
        case .elasticSlideIn:
            return 0.8
        case .spiralIn:
            return 1.0
        case .unfold:
            return 0.6
            
        // Anime.js-Inspired: Combo Exits
        case .scaleRotateOut:
            return 0.6
        case .blurSlideOut:
            return 0.5
        case .flipHide:
            return 0.6
        case .spiralOut:
            return 0.8
        case .foldUp:
            return 0.5
            
        // Anime.js-Inspired: Continuous/Loop
        case .pendulum:
            return 2.0
        case .orbit2D:
            return 3.0
        case .lemniscate:
            return 4.0
        case .morphPulse:
            return 1.5
        case .neonFlicker:
            return 2.0
        case .glowPulse:
            return 1.5
        case .oscillate:
            return 2.0
            
        // Anime.js-Inspired: Text Effects
        case .textWave:
            return 1.5
        case .textRainbow:
            return 2.0
        case .textBounceIn:
            return 0.8
        case .textElasticIn:
            return 0.7
            
        default:
            return 0.8
        }
    }
    
    /// Get recommended easing for animation type
    func recommendedEasing(for type: AnimationType) -> EasingType {
        switch type {
        // Entrances - use easeOut variants for smooth landing
        case .fadeIn, .slideIn, .reveal, .wipeIn, .clipIn:
            return .easeOutCubic
        case .dropIn, .riseUp:
            return .easeOutBack
        case .pop, .elasticIn, .snapIn:
            return .easeOutBack
        case .swingIn:
            return .easeOutQuart
        case .whipIn, .zoomBlur, .slam:
            return .easeOutExpo
        case .implode:
            return .easeOutBack
            
        // Exits - use easeIn variants for pickup
        case .fadeOut, .slideOut, .wipeOut, .elasticOut, .explode:
            return .easeInCubic
            
        // Bouncy/physics
        case .bounce:
            return .bounce
        case .overshoot:
            return .overshootSettle
        case .anticipation:
            return .anticipate
        case .squashStretch:
            return .easeInOutQuad
            
        // Organic/continuous
        case .pulse, .breathe:
            return .easeInOut
        case .float, .sway, .drift:
            return .easeInOutQuad
        case .jitter:
            return .linear
            
        // Constant speed
        case .spin:
            return .linear
        case .shake, .wiggle, .flicker, .glitch, .glitchText:
            return .linear
            
        // Text
        case .typewriter, .charByChar, .wordByWord, .lineByLine:
            return .easeOutQuad
        case .scramble:
            return .easeInOutCubic
        case .wave:
            return .easeInOutQuad
            
        // Impact
        case .flash:
            return .easeOutExpo
        case .splitReveal:
            return .easeOutCubic
        case .followThrough:
            return .easeOutQuad
            
        // Tracking
        case .tracking:
            return .easeOutCubic
            
        case .blur, .brightnessAnim, .contrastAnim, .saturationAnim, .grayscaleAnim, .shadowAnim:
            return .easeOutCubic
        case .hueRotate:
            return .linear
        
        // 3D Animations
        case .turntable, .orbit3D, .cameraOrbit:
            return .linear  // Must be linear for smooth continuous loops (easing causes stutter at loop boundary)
        case .rotate3DX, .rotate3DY, .rotate3DZ:
            return .easeInOutCubic
        case .wobble3D, .float3D:
            return .easeInOutQuad
        case .flip3D:
            return .easeInOutCubic
        case .cradle:
            return .easeOutQuad  // Natural pendulum damping
        case .springBounce3D:
            return .linear       // Keyframes encode the spring physics directly
        case .elasticSpin:
            return .linear       // Keyframes encode the elastic overshoot directly
        case .swing3D:
            return .easeOutQuad  // Damped pendulum
        case .breathe3D:
            return .easeInOutQuad // Smooth breathing
        case .headNod:
            return .easeInOutQuad
        case .headShake:
            return .linear       // Keyframes encode the shake directly
        case .rockAndRoll:
            return .easeInOutQuad // Smooth rocking
        case .scaleUp3D:
            return .linear       // Keyframes encode the overshoot
        case .scaleDown3D:
            return .easeInCubic
        case .slamDown3D:
            return .linear       // Keyframes encode the bounce physics
        case .revolveSlow:
            return .easeInOutCubic // Elegant slow-in slow-out
        case .tumble:
            return .linear         // Constant chaotic tumble
        case .barrelRoll:
            return .easeInOutCubic // Smooth roll
        case .corkscrew:
            return .easeInOutQuad  // Smooth helical rise
        case .figureEight:
            return .linear         // Continuous figure-8 loop
        case .boomerang3D:
            return .linear         // Keyframes encode the arc physics
        case .levitate:
            return .easeOutQuart   // Decelerating float
        case .magnetPull:
            return .linear         // Keyframes encode the acceleration
        case .magnetPush:
            return .linear         // Keyframes encode the deceleration
        case .zigzagDrop:
            return .linear         // Continuous zigzag
        case .rubberBand:
            return .linear         // Keyframes encode the elastic
        case .jelly3D:
            return .linear         // Keyframes encode the wobble
        case .anticipateSpin:
            return .linear         // Keyframes encode anticipation + whip
        case .popIn3D:
            return .linear         // Keyframes encode the overshoot
        case .glitchJitter3D:
            return .linear         // Must be linear for random feel
        case .heartbeat3D:
            return .linear         // Keyframes encode the heartbeat rhythm
        case .tornado:
            return .easeInQuart    // Accelerating vortex
        case .unwrap:
            return .linear         // Keyframes encode the bounce
        case .dropAndSettle:
            return .linear         // Keyframes encode gravity + bounce
        case .cameraZoom:
            return .easeInOutQuad
        case .cameraPan:
            return .easeInOutCubic
        case .spiralZoom:
            return .easeInOutCubic // Smooth spiral approach
        case .dollyZoom:
            return .easeInOutQuad  // Steady vertigo build
        case .cameraRise:
            return .easeInOutCubic // Smooth crane rise
        case .cameraDive:
            return .easeInOutQuart // Dramatic dive with weight
        case .cameraWhipPan:
            return .linear         // Keyframes encode the whip dynamics
        case .cameraSlide:
            return .easeInOutCubic // Smooth dolly track
        case .cameraArc:
            return .easeInOutCubic // Smooth arc
        case .cameraPedestal:
            return .easeInOutCubic // Smooth vertical
        case .cameraTruck:
            return .easeInOutCubic // Smooth lateral
        case .cameraPushPull:
            return .linear         // Keyframes encode the push-pull timing
        case .cameraDutchTilt:
            return .easeInOutQuad  // Smooth tilt
        case .cameraHelicopter:
            return .easeInOutCubic // Smooth descent
        case .cameraRocket:
            return .linear         // Keyframes encode the acceleration
        case .cameraShake:
            return .linear         // Must be linear for shake feel
        case .materialFade:
            return .easeOutCubic
        case .move3DX, .move3DY, .move3DZ:
            return .easeInOut
        case .scale3DZ:
            return .easeInOut
        case .textSizeChange:
            return .easeInOut
            
        // Anime.js-Inspired: Stagger-Based
        case .staggerFadeIn:
            return .easeOutCubic
        case .staggerSlideUp:
            return .easeOutBack
        case .staggerScaleIn:
            return .easeOutBack
        case .ripple:
            return .easeOutBack
        case .cascade:
            return .easeOutCubic
        case .domino:
            return .easeOutBack
            
        // Anime.js-Inspired: Combo Entrances
        case .scaleRotateIn:
            return .easeOutBack
        case .blurSlideIn:
            return .easeOutCubic
        case .flipReveal:
            return .easeOutCubic
        case .elasticSlideIn:
            return .linear       // Keyframes encode the elastic
        case .spiralIn:
            return .easeInOutCubic
        case .unfold:
            return .easeOutBack
            
        // Anime.js-Inspired: Combo Exits
        case .scaleRotateOut:
            return .easeInCubic
        case .blurSlideOut:
            return .easeInCubic
        case .flipHide:
            return .easeInCubic
        case .spiralOut:
            return .easeInOutCubic
        case .foldUp:
            return .easeInCubic
            
        // Anime.js-Inspired: Continuous/Loop
        case .pendulum:
            return .easeInOutSine
        case .orbit2D:
            return .linear
        case .lemniscate:
            return .linear
        case .morphPulse:
            return .easeInOutQuad
        case .neonFlicker:
            return .linear       // Keyframes encode the flicker
        case .glowPulse:
            return .easeInOutSine
        case .oscillate:
            return .easeInOutSine
            
        // Anime.js-Inspired: Text Effects
        case .textWave:
            return .easeInOutQuad
        case .textRainbow:
            return .linear
        case .textBounceIn:
            return .linear       // Keyframes encode the bounce
        case .textElasticIn:
            return .linear       // Keyframes encode the elastic
            
        default:
            return .easeOutCubic
        }
    }
    
    /// Determines if animation should repeat by default
    func shouldRepeatByDefault(for type: AnimationType) -> Int {
        switch type {
        case .pulse, .spin, .breathe, .float, .sway, .drift, .jitter:
            return -1 // Infinite
        case .dashOffset, .trimPathOffset:
            return -1 // Infinite loop for marching ants
        case .turntable, .orbit3D, .cameraOrbit, .wobble3D, .float3D, .breathe3D, .rockAndRoll,
             .figureEight, .heartbeat3D, .glitchJitter3D:
            return -1 // Infinite for 3D loops
        // Anime.js-inspired continuous loops
        case .pendulum, .orbit2D, .lemniscate, .morphPulse, .neonFlicker,
             .glowPulse, .oscillate, .textRainbow:
            return -1 // Infinite
        case .shake, .wiggle, .glitch, .glitchText, .flicker:
            return 0 // Once
        default:
            return 0
        }
    }
}
