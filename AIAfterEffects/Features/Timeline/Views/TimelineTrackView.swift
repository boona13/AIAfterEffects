//
//  TimelineTrackView.swift
//  AIAfterEffects
//
//  After Effects-style layer bar and animation sub-tracks.
//
//  LayerBarView: One solid bar per object spanning its full animation range.
//  AnimationSubtrackView: Expanded sub-row showing one animation's bar + keyframes.
//
//  Gesture priority (highest → lowest):
//    1. Resize handles  (highPriorityGesture)
//    2. Keyframe diamonds (highPriorityGesture, small fixed frame)
//    3. Bar body move   (.gesture on background)
//

import SwiftUI

// MARK: - Layer Bar View (main object row — single bar spanning all animations)

struct LayerBarView: View {
    let object: SceneObject
    @ObservedObject var viewModel: CanvasViewModel
    let pixelsPerSecond: CGFloat
    let rowHeight: CGFloat
    
    @State private var isHovering = false
    
    /// Earliest animation start
    private var rangeStart: Double {
        guard !object.animations.isEmpty else { return 0 }
        return object.animations.map { $0.startTime + $0.delay }.min() ?? 0
    }
    
    /// Latest animation end
    private var rangeEnd: Double {
        guard !object.animations.isEmpty else { return viewModel.sceneState.duration }
        return object.animations.map { $0.startTime + $0.delay + $0.duration }.max() ?? viewModel.sceneState.duration
    }
    
    private var barX: CGFloat {
        CGFloat(rangeStart) * pixelsPerSecond
    }
    
    private var barWidth: CGFloat {
        max(CGFloat(rangeEnd - rangeStart) * pixelsPerSecond, 12)
    }
    
    private var barColor: Color {
        layerColor(for: object.type)
    }
    
    private let barHeight: CGFloat = 20
    
    var body: some View {
        ZStack(alignment: .leading) {
            // ── The solid layer bar ──
            RoundedRectangle(cornerRadius: 4)
                .fill(barColor.opacity(isHovering ? 0.5 : 0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(barColor.opacity(0.6), lineWidth: 1)
                )
            
            // ── Object name label ──
            if barWidth > 40 {
                Text(object.name)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
            }
            
            // ── Keyframe summary diamonds on the main bar ──
            ForEach(object.animations) { anim in
                ForEach(anim.keyframes) { kf in
                    let absoluteTime = anim.startTime + anim.delay + kf.time * anim.duration
                    let relativeX = CGFloat(absoluteTime - rangeStart) * pixelsPerSecond
                    
                    Diamond()
                        .fill(animationCategoryColor(anim.type).opacity(0.8))
                        .frame(width: 7, height: 7)
                        .position(x: relativeX, y: barHeight / 2)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(width: barWidth, height: barHeight)
        .position(x: barX + barWidth / 2, y: rowHeight / 2)
        .help("\(object.name) — \(String(format: "%.1f", rangeStart))s to \(String(format: "%.1f", rangeEnd))s — \(object.animations.count) animation(s)")
        .onHover { hovering in isHovering = hovering }
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectedKeyframeId = nil
            viewModel.selectObject(object.id)
        }
    }
    
    private func layerColor(for type: SceneObjectType) -> Color {
        switch type {
        case .rectangle, .circle, .ellipse, .polygon: return Color(hex: "4A90D9")
        case .line, .path: return Color(hex: "2ECC71")
        case .text: return Color(hex: "F5A623")
        case .icon: return Color(hex: "F8E71C")
        case .image: return Color(hex: "E74C8B")
        case .model3D: return Color(hex: "9B59B6")
        case .shader: return Color(hex: "1ABC9C")
        case .particleSystem: return Color.pink
        }
    }
}

// MARK: - Animation Sub-track View (expanded row — one animation bar + keyframes)
//
// Structure (bottom → top in ZStack):
//   Layer 1: Bar body (RoundedRectangle) — move gesture
//   Layer 2: Label — no hit testing
//   Layer 3: Keyframe diamonds — each with fixed frame + offset, highPriority drag
//   Layer 4: Left & right resize handles — highPriority drag

struct AnimationSubtrackView: View {
    let animation: AnimationDefinition
    let objectId: UUID
    @ObservedObject var viewModel: CanvasViewModel
    let pixelsPerSecond: CGFloat
    let rowHeight: CGFloat
    
    // Separate drag state flags — avoids the "originalValue == 0" init bug
    @State private var isDraggingBar = false
    @State private var isDraggingLeft = false
    @State private var isDraggingRight = false
    @State private var dragOrigStartTime: Double = 0
    @State private var dragOrigDuration: Double = 0
    @State private var isHovering = false
    
    private var barX: CGFloat {
        CGFloat(animation.startTime + animation.delay) * pixelsPerSecond
    }
    
    private var barWidth: CGFloat {
        max(CGFloat(animation.duration) * pixelsPerSecond, 8)
    }
    
    private var barColor: Color {
        animationCategoryColor(animation.type)
    }
    
    private let resizeHandleWidth: CGFloat = 8
    private let barHeight: CGFloat = 16
    private let diamondHitSize: CGFloat = 22  // invisible hit padding around each diamond
    
    /// Keyframes sorted by time so later ones render on top (ZStack ordering)
    private var sortedKeyframes: [Keyframe] {
        animation.keyframes.sorted(by: { $0.time < $1.time })
    }
    
    /// Whether this animation track is currently selected
    private var isAnimSelected: Bool {
        viewModel.selectedAnimationId == animation.id
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            // ── Layer 1: Bar background — move gesture + selection ──
            RoundedRectangle(cornerRadius: 3)
                .fill(barColor.opacity(isAnimSelected ? 0.75 : (isHovering ? 0.65 : 0.45)))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(isAnimSelected ? Color.white.opacity(0.8) : barColor.opacity(0.7), lineWidth: isAnimSelected ? 1.5 : 0.5)
                )
                .contentShape(Rectangle())
                .gesture(moveBarGesture)
                .onTapGesture {
                    // Select this animation track (and parent object)
                    viewModel.selectAnimation(animation.id, objectId: objectId)
                }
            
            // ── Layer 2: Animation type label — no interaction ──
            if barWidth > 50 {
                Text(animation.type.rawValue)
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .allowsHitTesting(false)
            }
            
            // ── Layer 3: Keyframe diamonds ──
            // Each diamond has a fixed frame (diamondHitSize × barHeight) and is
            // positioned via .offset() so its hit area is limited to its visual area.
            // Sorted by time so the rightmost diamond is on top in the ZStack,
            // preventing the leftmost one from stealing clicks.
            ForEach(sortedKeyframes) { keyframe in
                KeyframeDiamondView(
                    keyframe: keyframe,
                    animationId: animation.id,
                    objectId: objectId,
                    viewModel: viewModel,
                    barWidth: barWidth,
                    rowHeight: barHeight,
                    pixelsPerSecond: pixelsPerSecond,
                    animationStartTime: animation.startTime + animation.delay,
                    animationDuration: animation.duration
                )
                .frame(width: diamondHitSize, height: barHeight)
                .offset(x: CGFloat(keyframe.time) * barWidth - diamondHitSize / 2)
            }
            
            // ── Layer 4: Resize handles (highest gesture priority) ──
            
            // Left resize handle
            Rectangle()
                .fill(isHovering ? barColor.opacity(0.4) : Color.clear)
                .frame(width: resizeHandleWidth, height: barHeight)
                .contentShape(Rectangle())
                .cursor(.resizeLeftRight)
                .highPriorityGesture(leftResizeGesture)
            
            // Right resize handle (offset to far right edge)
            Rectangle()
                .fill(isHovering ? barColor.opacity(0.4) : Color.clear)
                .frame(width: resizeHandleWidth, height: barHeight)
                .contentShape(Rectangle())
                .cursor(.resizeLeftRight)
                .highPriorityGesture(rightResizeGesture)
                .offset(x: barWidth - resizeHandleWidth)
        }
        .frame(width: barWidth, height: barHeight)
        .position(x: barX + barWidth / 2, y: rowHeight / 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("\(animation.type.rawValue) — \(String(format: "%.1f", animation.startTime + animation.delay))s → \(String(format: "%.1f", animation.startTime + animation.delay + animation.duration))s\nDrag center to move · Drag edges to resize · Click to select")
        .onHover { hovering in isHovering = hovering }
        .contextMenu {
            Button("Delete Animation", role: .destructive) {
                viewModel.deleteAnimation(objectId, animationId: animation.id)
                if viewModel.selectedAnimationId == animation.id {
                    viewModel.selectedAnimationId = nil
                }
            }
            
            Divider()
            
            Text("Type: \(animation.type.rawValue)")
            Text("Start: \(String(format: "%.2f", animation.startTime))s")
            Text("Duration: \(String(format: "%.2f", animation.duration))s")
            Text("Easing: \(animation.easing.rawValue)")
            if !animation.keyframes.isEmpty {
                Text("Keyframes: \(animation.keyframes.count)")
            }
        }
    }
    
    // MARK: - Move Bar Gesture (drag the entire animation in time)
    
    private var moveBarGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                if !isDraggingBar {
                    isDraggingBar = true
                    dragOrigStartTime = animation.startTime
                    dragOrigDuration = animation.duration
                    viewModel.beginTimelineHistoryTransaction()
                }
                let deltaTime = Double(value.translation.width) / Double(pixelsPerSecond)
                let newStart = max(0, dragOrigStartTime + deltaTime)
                viewModel.updateAnimation(objectId, animationId: animation.id, startTime: newStart)
            }
            .onEnded { _ in
                isDraggingBar = false
                viewModel.endTimelineHistoryTransaction()
            }
    }
    
    // MARK: - Left Resize Gesture (change start time + duration, keeping end fixed)
    
    private var leftResizeGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                if !isDraggingLeft {
                    isDraggingLeft = true
                    dragOrigStartTime = animation.startTime
                    dragOrigDuration = animation.duration
                    viewModel.beginTimelineHistoryTransaction()
                }
                let deltaTime = Double(value.translation.width) / Double(pixelsPerSecond)
                let originalEnd = dragOrigStartTime + dragOrigDuration
                let newStart = min(originalEnd - 0.05, max(0, dragOrigStartTime + deltaTime))
                let newDuration = originalEnd - newStart
                viewModel.updateAnimation(objectId, animationId: animation.id, startTime: newStart, duration: newDuration)
            }
            .onEnded { _ in
                isDraggingLeft = false
                viewModel.endTimelineHistoryTransaction()
            }
    }
    
    // MARK: - Right Resize Gesture (change duration, keeping start fixed)
    
    private var rightResizeGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                if !isDraggingRight {
                    isDraggingRight = true
                    dragOrigStartTime = animation.startTime
                    dragOrigDuration = animation.duration
                    viewModel.beginTimelineHistoryTransaction()
                }
                let deltaTime = Double(value.translation.width) / Double(pixelsPerSecond)
                let newDuration = max(0.05, dragOrigDuration + deltaTime)
                viewModel.updateAnimation(objectId, animationId: animation.id, duration: newDuration)
            }
            .onEnded { _ in
                isDraggingRight = false
                viewModel.endTimelineHistoryTransaction()
            }
    }
}

// MARK: - Shared Animation Color Helper

func animationCategoryColor(_ type: AnimationType) -> Color {
    switch type {
    // Position / movement
    case .moveX, .moveY, .move, .slideIn, .slideOut, .dropIn, .riseUp, .swingIn, .whipIn, .snapIn,
         .drift, .float, .sway, .jitter, .orbit2D, .lemniscate, .pendulum:
        return Color(hex: "4A90D9")  // Blue
    // Opacity / visibility
    case .fadeIn, .fadeOut, .fade, .flicker, .flash, .neonFlicker, .materialFade:
        return Color(hex: "50C878")  // Green
    // Scale / rotation
    case .scale, .scaleX, .scaleY, .rotate, .spin, .grow, .shrink, .pop, .bounce,
         .pulse, .wiggle, .breathe, .elasticIn, .elasticOut, .morphPulse:
        return Color(hex: "F5A623")  // Orange
    // Text effects
    case .typewriter, .wave, .charByChar, .wordByWord, .lineByLine, .scramble, .glitchText,
         .tracking, .textWave, .textRainbow, .textBounceIn, .textElasticIn:
        return Color(hex: "BD10E0")  // Purple
    // 3D transforms
    case .rotate3DX, .rotate3DY, .rotate3DZ, .orbit3D, .turntable, .wobble3D, .flip3D, .float3D,
         .cradle, .springBounce3D, .elasticSpin, .swing3D, .breathe3D, .tumble, .barrelRoll,
         .corkscrew, .figureEight, .boomerang3D, .levitate, .tornado,
         .scaleUp3D, .scaleDown3D, .slamDown3D, .popIn3D, .dropAndSettle, .unwrap,
         .headNod, .headShake, .rockAndRoll, .revolveSlow, .magnetPull, .magnetPush,
         .zigzagDrop, .rubberBand, .jelly3D, .anticipateSpin, .glitchJitter3D, .heartbeat3D:
        return Color(hex: "E67E22")  // Dark orange
    // Camera
    case .cameraZoom, .cameraPan, .cameraOrbit, .spiralZoom, .dollyZoom,
         .cameraRise, .cameraDive, .cameraWhipPan, .cameraSlide, .cameraArc,
         .cameraPedestal, .cameraTruck, .cameraPushPull, .cameraDutchTilt,
         .cameraHelicopter, .cameraRocket, .cameraShake:
        return Color(hex: "E74C3C")  // Red
    // Visual effects
    case .blur, .blurIn, .blurOut, .brightnessAnim, .contrastAnim, .saturationAnim,
         .hueRotate, .grayscaleAnim, .shadowAnim, .glitch, .colorChange, .glowPulse:
        return Color(hex: "1ABC9C")  // Teal
    // Path animations
    case .trimPath, .trimPathStart, .trimPathEnd, .trimPathOffset, .strokeWidthAnim, .dashOffset:
        return Color(hex: "2ECC71")  // Emerald
    // Default
    default:
        return Color(hex: "95A5A6")  // Gray
    }
}

// MARK: - Cursor Extension

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { hovering in
            if hovering { cursor.push() }
            else { NSCursor.pop() }
        }
    }
}
