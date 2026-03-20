//
//  GizmoViewModel.swift
//  AIAfterEffects
//
//  Manages gizmo state, coordinate conversion, and property updates
//  for 2D and 3D transform gizmos on the canvas.
//

import SwiftUI
import Combine

// MARK: - Gizmo Mode

enum GizmoMode: String, CaseIterable {
    case move
    case scale
    case rotate
    
    var icon: String {
        switch self {
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        case .scale: return "arrow.up.left.and.arrow.down.right"
        case .rotate: return "rotate.right"
        }
    }
    
    var label: String {
        switch self {
        case .move: return "Move (W)"
        case .scale: return "Scale (R)"
        case .rotate: return "Rotate (E)"
        }
    }
    
    var shortcutKey: Character {
        switch self {
        case .move: return "w"
        case .scale: return "r"
        case .rotate: return "e"
        }
    }
}

// MARK: - 2D Gizmo Handle

enum GizmoHandle2D: Hashable {
    // Move
    case body
    // Scale — corners
    case topLeft, topRight, bottomLeft, bottomRight
    // Scale — edges
    case top, bottom, left, right
    // Rotate
    case rotationHandle
    
    var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return true
        default: return false
        }
    }
    
    var isEdge: Bool {
        switch self {
        case .top, .bottom, .left, .right: return true
        default: return false
        }
    }
    
    /// Returns the cursor for this handle type
    var cursor: NSCursor {
        switch self {
        case .body: return .openHand
        case .topLeft, .bottomRight: return .crosshair
        case .topRight, .bottomLeft: return .crosshair
        case .top, .bottom: return .resizeUpDown
        case .left, .right: return .resizeLeftRight
        case .rotationHandle: return .crosshair
        }
    }
}

// MARK: - 3D Gizmo Handle

enum GizmoHandle3D: String, Equatable {
    // Translation axes
    case axisX, axisY, axisZ
    // Translation planes
    case planeXY, planeXZ, planeYZ
    // Center (free move / uniform scale)
    case center
    // Rotation rings
    case ringX, ringY, ringZ, trackball
    // Scale axes
    case scaleX, scaleY, scaleZ
}

// MARK: - Gizmo ViewModel

@MainActor
class GizmoViewModel: ObservableObject {
    // MARK: - Published State
    
    @Published var activeMode: GizmoMode = .move
    @Published var isDragging: Bool = false
    @Published var activeHandle2D: GizmoHandle2D? = nil
    @Published var activeHandle3D: GizmoHandle3D? = nil
    @Published var is3DEditMode: Bool = false
    @Published var hoveredHandle2D: GizmoHandle2D? = nil
    
    // MARK: - Drag State
    
    /// The canvas-space point where the drag started
    var dragStartCanvasPoint: CGPoint = .zero
    /// The current canvas-space point during drag
    var dragCurrentCanvasPoint: CGPoint = .zero
    /// Snapshot of the object properties at drag start (for relative deltas)
    var dragStartProperties: ObjectProperties? = nil
    /// Snapshot for undo transaction
    private var transactionSnapshot: ObjectProperties? = nil
    
    // MARK: - References
    
    weak var canvasViewModel: CanvasViewModel?
    
    // MARK: - Computed Properties
    
    /// The currently selected object (convenience)
    var selectedObject: SceneObject? {
        canvasViewModel?.selectedObject
    }
    
    /// Whether we should show 2D gizmos (non-3D object selected, not in 3D edit mode)
    var shouldShow2DGizmo: Bool {
        guard let obj = selectedObject else { return false }
        return obj.type != .model3D && !is3DEditMode && !obj.isLocked
    }
    
    /// Whether we should show 3D gizmo environment
    var shouldShow3DGizmo: Bool {
        guard let obj = selectedObject else { return false }
        return obj.type == .model3D && is3DEditMode && !obj.isLocked
    }
    
    /// Whether the selected object is a 3D model
    var isSelected3DModel: Bool {
        selectedObject?.type == .model3D
    }
    
    // MARK: - Mode Switching
    
    func setMode(_ mode: GizmoMode) {
        activeMode = mode
    }
    
    func cycleMode() {
        let modes = GizmoMode.allCases
        guard let currentIndex = modes.firstIndex(of: activeMode) else { return }
        let nextIndex = (currentIndex + 1) % modes.count
        activeMode = modes[nextIndex]
    }
    
    // MARK: - 3D Edit Mode
    
    func enter3DEditMode() {
        guard isSelected3DModel else { return }
        is3DEditMode = true
    }
    
    func exit3DEditMode() {
        is3DEditMode = false
    }
    
    // MARK: - Coordinate Conversion
    
    /// Convert a screen point to canvas coordinate space
    /// accounting for zoom and pan offset.
    static func screenToCanvas(
        screenPoint: CGPoint,
        containerSize: CGSize,
        zoom: CGFloat,
        offset: CGSize
    ) -> CGPoint {
        let centerX = containerSize.width / 2
        let centerY = containerSize.height / 2
        return CGPoint(
            x: (screenPoint.x - centerX - offset.width) / zoom,
            y: (screenPoint.y - centerY - offset.height) / zoom
        )
    }
    
    /// Convert a canvas point to screen coordinate space
    static func canvasToScreen(
        canvasPoint: CGPoint,
        containerSize: CGSize,
        zoom: CGFloat,
        offset: CGSize
    ) -> CGPoint {
        let centerX = containerSize.width / 2
        let centerY = containerSize.height / 2
        return CGPoint(
            x: canvasPoint.x * zoom + centerX + offset.width,
            y: canvasPoint.y * zoom + centerY + offset.height
        )
    }
    
    // MARK: - 2D Gizmo Drag Handling
    
    /// Begin a 2D gizmo drag operation
    func beginDrag2D(handle: GizmoHandle2D, canvasPoint: CGPoint) {
        guard let obj = selectedObject else { return }
        isDragging = true
        activeHandle2D = handle
        dragStartCanvasPoint = canvasPoint
        dragCurrentCanvasPoint = canvasPoint
        dragStartProperties = obj.properties
        
        // Start undo transaction
        transactionSnapshot = obj.properties
    }
    
    /// Update during a 2D gizmo drag
    func updateDrag2D(canvasPoint: CGPoint) {
        guard isDragging, let startProps = dragStartProperties,
              let objectId = selectedObject?.id,
              let vm = canvasViewModel else { return }
        
        dragCurrentCanvasPoint = canvasPoint
        let delta = CGSize(
            width: canvasPoint.x - dragStartCanvasPoint.x,
            height: canvasPoint.y - dragStartCanvasPoint.y
        )
        
        var newProps = startProps
        
        switch activeHandle2D {
        case .body:
            applyMoveDelta(delta: delta, startProps: startProps, to: &newProps)
            
        case .topLeft, .topRight, .bottomLeft, .bottomRight,
             .top, .bottom, .left, .right:
            applyScaleDelta(
                handle: activeHandle2D!,
                canvasPoint: canvasPoint,
                startProps: startProps,
                to: &newProps
            )
            
        case .rotationHandle:
            applyRotationDelta(
                canvasPoint: canvasPoint,
                startProps: startProps,
                to: &newProps
            )
            
        case nil:
            break
        }
        
        // Apply to the actual object (real-time, no undo per frame)
        vm.applyGizmoProperties(objectId, properties: newProps)
    }
    
    /// End a 2D gizmo drag operation
    func endDrag2D() {
        guard isDragging, let objectId = selectedObject?.id,
              let vm = canvasViewModel,
              let snapshot = transactionSnapshot else {
            cleanup()
            return
        }
        
        // Record undo step if properties changed
        let currentProps = vm.sceneState.objects.first(where: { $0.id == objectId })?.properties
        if let current = currentProps, current != snapshot {
            vm.recordGizmoUndo(objectId: objectId, oldProperties: snapshot)
        }
        
        cleanup()
    }
    
    /// Cancel current drag (e.g. Escape key)
    func cancelDrag() {
        guard isDragging, let objectId = selectedObject?.id,
              let vm = canvasViewModel,
              let snapshot = transactionSnapshot else {
            cleanup()
            return
        }
        
        // Restore original properties
        vm.applyGizmoProperties(objectId, properties: snapshot)
        cleanup()
    }
    
    private func cleanup() {
        isDragging = false
        activeHandle2D = nil
        activeHandle3D = nil
        dragStartProperties = nil
        transactionSnapshot = nil
    }
    
    // MARK: - Move Transform
    
    private func applyMoveDelta(delta: CGSize, startProps: ObjectProperties, to props: inout ObjectProperties) {
        props.x = startProps.x + delta.width
        props.y = startProps.y + delta.height
    }
    
    // MARK: - Scale Transform
    
    private func applyScaleDelta(
        handle: GizmoHandle2D,
        canvasPoint: CGPoint,
        startProps: ObjectProperties,
        to props: inout ObjectProperties
    ) {
        let cx = startProps.x
        let cy = startProps.y
        let w = startProps.width
        let h = startProps.height
        let halfW = w / 2
        let halfH = h / 2
        
        // Object bounds in canvas space (before rotation)
        let left = cx - halfW
        let right = cx + halfW
        let top = cy - halfH
        let bottom = cy + halfH
        
        // Un-rotate the canvas point around the object center to work in object-local space
        let localPoint = unrotatePoint(canvasPoint, around: CGPoint(x: cx, y: cy), angle: startProps.rotation)
        
        switch handle {
        case .topLeft:
            let newLeft = min(localPoint.x, right - 10)
            let newTop = min(localPoint.y, bottom - 10)
            let newW = right - newLeft
            let newH = bottom - newTop
            props.width = max(10, newW)
            props.height = max(10, newH)
            props.x = newLeft + props.width / 2
            props.y = newTop + props.height / 2
            
        case .topRight:
            let newRight = max(localPoint.x, left + 10)
            let newTop = min(localPoint.y, bottom - 10)
            let newW = newRight - left
            let newH = bottom - newTop
            props.width = max(10, newW)
            props.height = max(10, newH)
            props.x = left + props.width / 2
            props.y = newTop + props.height / 2
            
        case .bottomLeft:
            let newLeft = min(localPoint.x, right - 10)
            let newBottom = max(localPoint.y, top + 10)
            let newW = right - newLeft
            let newH = newBottom - top
            props.width = max(10, newW)
            props.height = max(10, newH)
            props.x = newLeft + props.width / 2
            props.y = top + props.height / 2
            
        case .bottomRight:
            let newRight = max(localPoint.x, left + 10)
            let newBottom = max(localPoint.y, top + 10)
            let newW = newRight - left
            let newH = newBottom - top
            props.width = max(10, newW)
            props.height = max(10, newH)
            props.x = left + props.width / 2
            props.y = top + props.height / 2
            
        case .top:
            let newTop = min(localPoint.y, bottom - 10)
            props.height = max(10, bottom - newTop)
            props.y = newTop + props.height / 2
            
        case .bottom:
            let newBottom = max(localPoint.y, top + 10)
            props.height = max(10, newBottom - top)
            props.y = top + props.height / 2
            
        case .left:
            let newLeft = min(localPoint.x, right - 10)
            props.width = max(10, right - newLeft)
            props.x = newLeft + props.width / 2
            
        case .right:
            let newRight = max(localPoint.x, left + 10)
            props.width = max(10, newRight - left)
            props.x = left + props.width / 2
            
        default:
            break
        }
    }
    
    // MARK: - Rotation Transform
    
    private func applyRotationDelta(
        canvasPoint: CGPoint,
        startProps: ObjectProperties,
        to props: inout ObjectProperties
    ) {
        let center = CGPoint(x: startProps.x, y: startProps.y)
        
        // Angle from center to current mouse position
        let dx = canvasPoint.x - center.x
        let dy = canvasPoint.y - center.y
        let angle = atan2(dy, dx) * 180 / .pi
        
        // Angle from center to drag start
        let sdx = dragStartCanvasPoint.x - center.x
        let sdy = dragStartCanvasPoint.y - center.y
        let startAngle = atan2(sdy, sdx) * 180 / .pi
        
        let deltaAngle = angle - startAngle
        props.rotation = startProps.rotation + deltaAngle
    }
    
    // MARK: - Geometry Helpers
    
    /// Rotate a point around another point by a given angle (in degrees), then return the un-rotated point
    func unrotatePoint(_ point: CGPoint, around center: CGPoint, angle: Double) -> CGPoint {
        let radians = CGFloat(-angle * .pi / 180)  // Negative to un-rotate
        let dx = point.x - center.x
        let dy = point.y - center.y
        let rotatedX = dx * Darwin.cos(radians) - dy * Darwin.sin(radians)
        let rotatedY = dx * Darwin.sin(radians) + dy * Darwin.cos(radians)
        return CGPoint(x: center.x + rotatedX, y: center.y + rotatedY)
    }
    
    /// Rotate a point around a center by a given angle (in degrees)
    func rotatePoint(_ point: CGPoint, around center: CGPoint, angle: Double) -> CGPoint {
        let radians = CGFloat(angle * .pi / 180)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let rotatedX = dx * Darwin.cos(radians) - dy * Darwin.sin(radians)
        let rotatedY = dx * Darwin.sin(radians) + dy * Darwin.cos(radians)
        return CGPoint(x: center.x + rotatedX, y: center.y + rotatedY)
    }
    
    /// Get the 8 handle positions for a 2D object in canvas space (rotated)
    func handlePositions(for props: ObjectProperties) -> [GizmoHandle2D: CGPoint] {
        let cx = props.x
        let cy = props.y
        let halfW = props.width / 2
        let halfH = props.height / 2
        let angle = props.rotation
        let center = CGPoint(x: cx, y: cy)
        
        // Local positions (before rotation)
        let positions: [GizmoHandle2D: CGPoint] = [
            .topLeft: CGPoint(x: cx - halfW, y: cy - halfH),
            .topRight: CGPoint(x: cx + halfW, y: cy - halfH),
            .bottomLeft: CGPoint(x: cx - halfW, y: cy + halfH),
            .bottomRight: CGPoint(x: cx + halfW, y: cy + halfH),
            .top: CGPoint(x: cx, y: cy - halfH),
            .bottom: CGPoint(x: cx, y: cy + halfH),
            .left: CGPoint(x: cx - halfW, y: cy),
            .right: CGPoint(x: cx + halfW, y: cy),
        ]
        
        // Apply rotation
        var rotated: [GizmoHandle2D: CGPoint] = [:]
        for (handle, point) in positions {
            rotated[handle] = rotatePoint(point, around: center, angle: angle)
        }
        
        // Add rotation handle above top center
        let rotHandleLocal = CGPoint(x: cx, y: cy - halfH - 35)
        rotated[.rotationHandle] = rotatePoint(rotHandleLocal, around: center, angle: angle)
        
        return rotated
    }
}
