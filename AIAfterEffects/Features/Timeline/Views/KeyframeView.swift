//
//  KeyframeView.swift
//  AIAfterEffects
//
//  Diamond-shaped keyframe indicator within an animation sub-track.
//  Drag to reposition — the bar auto-resizes when a diamond is moved
//  past the current animation boundaries (like After Effects).
//
//  Uses global-coordinate translation and computes delta in absolute
//  seconds (via pixelsPerSecond) so the drag remains stable even when
//  the bar changes size underneath.
//

import SwiftUI

struct KeyframeDiamondView: View {
    let keyframe: Keyframe
    let animationId: UUID
    let objectId: UUID
    @ObservedObject var viewModel: CanvasViewModel
    /// Current bar width in pixels (used only for positioning, not for drag math)
    let barWidth: CGFloat
    let rowHeight: CGFloat
    /// Pixels per second — needed to convert drag pixels → absolute seconds
    let pixelsPerSecond: CGFloat
    /// Animation start time in seconds — needed to compute absolute keyframe time
    let animationStartTime: Double
    /// Animation duration in seconds
    let animationDuration: Double
    
    @State private var isDragging = false
    @State private var originalAbsoluteTime: Double = 0
    @State private var isHovering = false
    
    private let diamondSize: CGFloat = 10
    /// Invisible hit area around each diamond — prevents mis-clicks
    private let hitPadding: CGFloat = 6
    
    /// Whether this keyframe is currently selected
    private var isSelected: Bool {
        viewModel.selectedKeyframeId == keyframe.id
    }
    
    var body: some View {
        // Invisible enlarged hit area
        Rectangle()
            .fill(Color.clear)
            .frame(width: diamondSize + hitPadding * 2, height: rowHeight)
            .contentShape(Rectangle())
            // Visual diamond centered inside
            .overlay(
                ZStack {
                    // Selection glow ring (behind diamond)
                    if isSelected {
                        Diamond()
                            .fill(Color.yellow.opacity(0.35))
                            .frame(width: diamondSize + 6, height: diamondSize + 6)
                    }
                    
                    Diamond()
                        .fill(isSelected ? Color.yellow : (isHovering ? Color.white : Color.white.opacity(0.9)))
                        .overlay(
                            Diamond()
                                .strokeBorder(isSelected ? Color.orange : Color.black.opacity(0.3), lineWidth: isSelected ? 1.5 : 0.5)
                        )
                        .frame(width: diamondSize, height: diamondSize)
                        .shadow(color: isSelected ? .yellow.opacity(0.5) : .black.opacity(0.2), radius: isSelected ? 3 : 1, y: isSelected ? 0 : 1)
                }
            )
            .onHover { hovering in
                isHovering = hovering
            }
            // CLICK TO SELECT: single tap selects the keyframe + moves playhead
            .onTapGesture {
                viewModel.selectKeyframe(
                    keyframe.id,
                    animationId: animationId,
                    objectId: objectId
                )
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            viewModel.beginTimelineHistoryTransaction()
                            // Auto-select on drag start
                            viewModel.selectKeyframe(
                                keyframe.id,
                                animationId: animationId,
                                objectId: objectId
                            )
                            // Capture the keyframe's absolute time at drag start
                            originalAbsoluteTime = animationStartTime + keyframe.time * animationDuration
                        }
                        // Convert pixel drag to seconds
                        let deltaSeconds = Double(value.translation.width) / Double(pixelsPerSecond)
                        let newAbsoluteTime = max(0, originalAbsoluteTime + deltaSeconds)
                        
                        // This method auto-resizes the bar when the diamond
                        // goes past the current animation boundaries
                        viewModel.moveKeyframeToAbsoluteTime(
                            objectId,
                            animationId: animationId,
                            keyframeId: keyframe.id,
                            newAbsoluteTime: newAbsoluteTime
                        )
                    }
                    .onEnded { _ in
                        isDragging = false
                        viewModel.endTimelineHistoryTransaction()
                    }
            )
            .contextMenu {
                Button("Delete Keyframe", role: .destructive) {
                    viewModel.deleteKeyframe(objectId, animationId: animationId, keyframeId: keyframe.id)
                    if viewModel.selectedKeyframeId == keyframe.id {
                        viewModel.selectedKeyframeId = nil
                    }
                }
                
                Divider()
                
                let absTime = animationStartTime + keyframe.time * animationDuration
                Text("Time: \(String(format: "%.2f", absTime))s")
                Text(keyframeValueDescription)
            }
    }
    
    private var keyframeValueDescription: String {
        switch keyframe.value {
        case .double(let v):
            return "Value: \(String(format: "%.2f", v))"
        case .point(let x, let y):
            return "Point: (\(String(format: "%.1f", x)), \(String(format: "%.1f", y)))"
        case .scale(let x, let y):
            return "Scale: (\(String(format: "%.2f", x)), \(String(format: "%.2f", y)))"
        case .color(let c):
            return "Color: R\(String(format: "%.0f", c.red * 255)) G\(String(format: "%.0f", c.green * 255)) B\(String(format: "%.0f", c.blue * 255))"
        }
    }
}

// MARK: - Diamond Shape

struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let halfW = rect.width / 2
        let halfH = rect.height / 2
        
        path.move(to: CGPoint(x: center.x, y: center.y - halfH))
        path.addLine(to: CGPoint(x: center.x + halfW, y: center.y))
        path.addLine(to: CGPoint(x: center.x, y: center.y + halfH))
        path.addLine(to: CGPoint(x: center.x - halfW, y: center.y))
        path.closeSubpath()
        
        return path
    }
}

// MARK: - Diamond InsettableShape conformance

extension Diamond: InsettableShape {
    func inset(by amount: CGFloat) -> some InsettableShape {
        InsetDiamond(insetAmount: amount)
    }
}

struct InsetDiamond: InsettableShape {
    var insetAmount: CGFloat
    
    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        return Diamond().path(in: insetRect)
    }
    
    func inset(by amount: CGFloat) -> InsetDiamond {
        InsetDiamond(insetAmount: insetAmount + amount)
    }
}
