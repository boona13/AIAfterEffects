//
//  Gizmo2DOverlayView.swift
//  AIAfterEffects
//
//  2D transform gizmo overlay: move, scale, and rotate handles
//  drawn on top of the selected object in canvas space.
//

import SwiftUI

// MARK: - 2D Gizmo Overlay

struct Gizmo2DOverlayView: View {
    @ObservedObject var gizmoVM: GizmoViewModel
    @ObservedObject var canvasVM: CanvasViewModel
    let zoom: CGFloat
    
    /// Handle size in screen pixels (constant regardless of zoom)
    private let handleScreenSize: CGFloat = 8
    /// Rotation handle distance from top edge in canvas units
    private let rotationHandleOffset: CGFloat = 35
    
    /// Handle size adjusted for zoom so it appears constant on screen
    private var handleSize: CGFloat { handleScreenSize / zoom }
    /// Line width adjusted for zoom
    private var lineWidth: CGFloat { 1.5 / zoom }
    /// The selection accent color
    private let accentColor = Color(hex: "007AFF")
    
    /// Hit radius for handles (in canvas units) — how close a click must be to grab a handle
    private var handleHitRadius: CGFloat { max(handleSize * 1.8, 12 / zoom) }
    
    var body: some View {
        if let object = gizmoVM.selectedObject, gizmoVM.shouldShow2DGizmo {
            let props = currentProperties(for: object)
            
            ZStack {
                // Visual layers (no gestures on them)
                boundingBox(props: props)
                scaleHandlesVisual(props: props)
                rotationHandleVisual(props: props)
            }
            // Hit-testable shape = object body + handle areas
            .contentShape(
                GizmoHitShape(
                    props: props,
                    handlePositions: gizmoVM.handlePositions(for: props),
                    handleHitRadius: handleHitRadius
                )
            )
            // Single unified gesture for all gizmo interactions
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .local)
                    .onChanged { value in
                        if !gizmoVM.isDragging {
                            let handle = hitTestHandle(
                                at: value.startLocation,
                                props: props
                            )
                            gizmoVM.beginDrag2D(handle: handle, canvasPoint: value.startLocation)
                        }
                        gizmoVM.updateDrag2D(canvasPoint: value.location)
                    }
                    .onEnded { _ in
                        gizmoVM.endDrag2D()
                    }
            )
        }
    }
    
    // MARK: - Hit Testing
    
    /// Determine which handle (or body) the user clicked on.
    /// Priority: rotation handle > corner handles > edge handles > body
    private func hitTestHandle(at point: CGPoint, props: ObjectProperties) -> GizmoHandle2D {
        let positions = gizmoVM.handlePositions(for: props)
        let hitRadius = handleHitRadius
        
        // 1. Check rotation handle first (highest priority)
        if let rotPos = positions[.rotationHandle] {
            if distance(point, rotPos) <= hitRadius {
                return .rotationHandle
            }
        }
        
        // 2. Check corner handles (higher priority than edges)
        let corners: [GizmoHandle2D] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        for handle in corners {
            if let pos = positions[handle], distance(point, pos) <= hitRadius {
                return handle
            }
        }
        
        // 3. Check edge handles
        let edges: [GizmoHandle2D] = [.top, .bottom, .left, .right]
        for handle in edges {
            if let pos = positions[handle], distance(point, pos) <= hitRadius {
                return handle
            }
        }
        
        // 4. Default to body move
        return .body
    }
    
    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }
    
    // MARK: - Current Properties
    
    /// Get the current display properties for the object.
    /// During drag, use the live scene state; otherwise use base properties.
    private func currentProperties(for object: SceneObject) -> ObjectProperties {
        if let liveObj = canvasVM.sceneState.objects.first(where: { $0.id == object.id }) {
            return liveObj.properties
        }
        return object.properties
    }
    
    // MARK: - Bounding Box
    
    private func boundingBox(props: ObjectProperties) -> some View {
        let corners = boxCorners(props: props)
        return Path { path in
            guard corners.count == 4 else { return }
            path.move(to: corners[0])
            path.addLine(to: corners[1])
            path.addLine(to: corners[2])
            path.addLine(to: corners[3])
            path.closeSubpath()
        }
        .stroke(accentColor, lineWidth: lineWidth)
        .allowsHitTesting(false)
    }
    
    // MARK: - Scale Handles (visual only)
    
    private func scaleHandlesVisual(props: ObjectProperties) -> some View {
        let positions = gizmoVM.handlePositions(for: props)
        let scaleHandleTypes: [GizmoHandle2D] = [
            .topLeft, .topRight, .bottomLeft, .bottomRight,
            .top, .bottom, .left, .right
        ]
        
        return ForEach(scaleHandleTypes, id: \.self) { handle in
            if let pos = positions[handle] {
                ScaleHandleView(
                    position: pos,
                    size: handleSize,
                    lineWidth: lineWidth,
                    isCorner: handle.isCorner,
                    isHovered: gizmoVM.hoveredHandle2D == handle,
                    accentColor: accentColor
                )
                .allowsHitTesting(false)
            }
        }
    }
    
    // MARK: - Rotation Handle (visual only)
    
    private func rotationHandleVisual(props: ObjectProperties) -> some View {
        let positions = gizmoVM.handlePositions(for: props)
        let topCenter = positions[.top] ?? .zero
        let rotPos = positions[.rotationHandle] ?? .zero
        
        return ZStack {
            // Connecting line from top center to rotation handle
            Path { path in
                path.move(to: topCenter)
                path.addLine(to: rotPos)
            }
            .stroke(accentColor.opacity(0.6), lineWidth: lineWidth * 0.8)
            
            // Rotation handle circle
            Circle()
                .fill(Color.white)
                .frame(width: handleSize * 1.4, height: handleSize * 1.4)
                .overlay(
                    Circle()
                        .stroke(accentColor, lineWidth: lineWidth)
                )
                .overlay(
                    Image(systemName: "rotate.right")
                        .font(.system(size: max(6, handleSize * 0.7)))
                        .foregroundColor(accentColor)
                )
                .position(rotPos)
        }
        .allowsHitTesting(false)
    }
    
    // MARK: - Geometry Helpers
    
    /// Get the 4 corners of the bounding box in canvas space (rotated)
    private func boxCorners(props: ObjectProperties) -> [CGPoint] {
        let cx = props.x
        let cy = props.y
        let halfW = props.width / 2
        let halfH = props.height / 2
        let center = CGPoint(x: cx, y: cy)
        let angle = props.rotation
        
        let tl = gizmoVM.rotatePoint(CGPoint(x: cx - halfW, y: cy - halfH), around: center, angle: angle)
        let tr = gizmoVM.rotatePoint(CGPoint(x: cx + halfW, y: cy - halfH), around: center, angle: angle)
        let br = gizmoVM.rotatePoint(CGPoint(x: cx + halfW, y: cy + halfH), around: center, angle: angle)
        let bl = gizmoVM.rotatePoint(CGPoint(x: cx - halfW, y: cy + halfH), around: center, angle: angle)
        
        return [tl, tr, br, bl]
    }
}

// MARK: - Hit Shape

/// Custom shape that defines the hit-testable area of the gizmo overlay:
/// the object bounding box plus circles around each handle position.
/// This ensures clicks outside the gizmo pass through to the canvas.
struct GizmoHitShape: Shape {
    let props: ObjectProperties
    let handlePositions: [GizmoHandle2D: CGPoint]
    let handleHitRadius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Object body (axis-aligned rectangle, then we approximate rotated)
        let cx = props.x
        let cy = props.y
        let halfW = props.width / 2 + handleHitRadius
        let halfH = props.height / 2 + handleHitRadius
        let rotation = CGFloat(props.rotation * .pi / 180)
        
        // Rotated rectangle corners
        let corners = [
            CGPoint(x: -halfW, y: -halfH),
            CGPoint(x: halfW, y: -halfH),
            CGPoint(x: halfW, y: halfH),
            CGPoint(x: -halfW, y: halfH)
        ].map { local -> CGPoint in
            let rx = local.x * Darwin.cos(rotation) - local.y * Darwin.sin(rotation)
            let ry = local.x * Darwin.sin(rotation) + local.y * Darwin.cos(rotation)
            return CGPoint(x: cx + rx, y: cy + ry)
        }
        
        if let first = corners.first {
            path.move(to: first)
            for corner in corners.dropFirst() {
                path.addLine(to: corner)
            }
            path.closeSubpath()
        }
        
        // Handle hit circles (including rotation handle which extends beyond the body)
        for (_, pos) in handlePositions {
            path.addEllipse(in: CGRect(
                x: pos.x - handleHitRadius,
                y: pos.y - handleHitRadius,
                width: handleHitRadius * 2,
                height: handleHitRadius * 2
            ))
        }
        
        return path
    }
}

// MARK: - Scale Handle View (visual only)

private struct ScaleHandleView: View {
    let position: CGPoint
    let size: CGFloat
    let lineWidth: CGFloat
    let isCorner: Bool
    let isHovered: Bool
    let accentColor: Color
    
    var body: some View {
        let displaySize = isCorner ? size : size * 0.8
        
        RoundedRectangle(cornerRadius: isCorner ? size * 0.15 : size * 0.5)
            .fill(isHovered ? accentColor : Color.white)
            .frame(width: displaySize, height: displaySize)
            .overlay(
                RoundedRectangle(cornerRadius: isCorner ? size * 0.15 : size * 0.5)
                    .stroke(accentColor, lineWidth: lineWidth)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 1, x: 0, y: 1)
            .position(position)
    }
}

// MARK: - Angle Tooltip (shown during rotation drag)

struct GizmoAngleTooltip: View {
    let angle: Double
    let position: CGPoint
    
    var body: some View {
        Text(String(format: "%.1f°", angle))
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.75))
            )
            .position(x: position.x + 40, y: position.y - 20)
    }
}
