//
//  TimelineView.swift
//  AIAfterEffects
//
//  After Effects-style timeline panel. Each object is one layer with a single bar
//  spanning its full animation range. Click the disclosure triangle to expand
//  sub-tracks for individual animations and keyframes.
//

import SwiftUI

// MARK: - Timeline View

struct TimelineView: View {
    @ObservedObject var viewModel: CanvasViewModel
    
    /// Pixels per second — controls horizontal zoom
    @State var pixelsPerSecond: CGFloat = 80
    /// Horizontal scroll offset in the track area
    @State var scrollOffset: CGFloat = 0
    /// Which objects have their sub-tracks expanded
    @State var expandedObjects: Set<UUID> = []
    
    /// Layer column width (wider to fit visibility/lock/delete controls)
    private let layerColumnWidth: CGFloat = 210
    private let mainRowHeight: CGFloat = 28
    private let subRowHeight: CGFloat = 22
    private let rulerHeight: CGFloat = 26
    
    /// Objects sorted by zIndex descending (top of stack = top of list)
    private var sortedObjects: [SceneObject] {
        viewModel.sceneState.objects.sorted(by: { $0.zIndex > $1.zIndex })
    }
    
    private var totalDuration: Double {
        viewModel.sceneState.duration
    }
    
    private var totalTrackWidth: CGFloat {
        CGFloat(totalDuration) * pixelsPerSecond
    }
    
    /// Compute total rows needed (main rows + expanded sub-rows)
    private var totalRowCount: Int {
        sortedObjects.reduce(0) { count, obj in
            count + 1 + (expandedObjects.contains(obj.id) ? obj.animations.count : 0)
        }
    }
    
    /// Total content height — must match left column exactly (including 1px dividers)
    private var totalContentHeight: CGFloat {
        sortedObjects.reduce(0) { height, obj in
            let main = mainRowHeight + 1 // row + ThemedDivider
            let animCount = expandedObjects.contains(obj.id) ? obj.animations.count : 0
            let subs = CGFloat(animCount) * (subRowHeight + 1) // sub-row + ThemedDivider
            return height + main + subs
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ThemedDivider()
            
            // Timeline header with zoom controls
            timelineHeader
            
            ThemedDivider()
            
            // Main timeline body
            GeometryReader { geometry in
                let trackAreaWidth = geometry.size.width - layerColumnWidth - 1
                
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        // ── Fixed top row: ruler corner + time ruler ──
                        HStack(spacing: 0) {
                            // Ruler corner (empty, above layer names)
                            Rectangle()
                                .fill(AppTheme.Colors.backgroundSecondary)
                                .frame(width: layerColumnWidth, height: rulerHeight)
                            
                            Rectangle()
                                .fill(AppTheme.Colors.border)
                                .frame(width: 1, height: rulerHeight)
                            
                            // Time ruler (horizontally scrollable)
                            ScrollView(.horizontal, showsIndicators: false) {
                                TimelineRulerView(
                                    duration: totalDuration,
                                    pixelsPerSecond: pixelsPerSecond,
                                    scrollOffset: scrollOffset,
                                    height: rulerHeight,
                                    viewWidth: trackAreaWidth,
                                    onTap: { time in
                                        viewModel.selectedKeyframeId = nil
                                        viewModel.currentTime = min(max(0, time), totalDuration)
                                    }
                                )
                            }
                            .frame(width: trackAreaWidth)
                        }
                        .frame(height: rulerHeight)
                        
                        ThemedDivider(opacity: 0.5)
                        
                        // ── Shared vertical scroll: layer names + track bars side by side ──
                        ScrollView(.vertical, showsIndicators: true) {
                            HStack(alignment: .top, spacing: 0) {
                                // Left: Layer names column
                                VStack(spacing: 0) {
                                    ForEach(sortedObjects) { object in
                                        let isExpanded = expandedObjects.contains(object.id)
                                        
                                        TimelineLayerRow(
                                            object: object,
                                            isSelected: viewModel.selectedObjectId == object.id,
                                            isExpanded: isExpanded,
                                            hasAnimations: !object.animations.isEmpty,
                                            onSelect: {
                                                viewModel.selectedKeyframeId = nil
                                                viewModel.selectObject(object.id)
                                            },
                                            onToggleExpand: { toggleExpand(object.id) },
                                            onToggleVisibility: { viewModel.toggleObjectVisibility(object.id) },
                                            onToggleLock: { viewModel.toggleObjectLock(object.id) },
                                            onDelete: { viewModel.deleteObjectById(object.id) },
                                            height: mainRowHeight
                                        )
                                        ThemedDivider(opacity: 0.3)
                                        
                                        if isExpanded {
                                            ForEach(object.animations) { anim in
                                                AnimationSubtrackLabel(
                                                    animation: anim,
                                                    objectId: object.id,
                                                    height: subRowHeight,
                                                    viewModel: viewModel
                                                )
                                                ThemedDivider(opacity: 0.15)
                                            }
                                        }
                                    }
                                }
                                .frame(width: layerColumnWidth)
                                
                                // Divider
                                Rectangle()
                                    .fill(AppTheme.Colors.border)
                                    .frame(width: 1)
                                
                                // Right: Track bars (horizontal scroll for time)
                                ScrollView(.horizontal, showsIndicators: true) {
                                    ZStack(alignment: .topLeading) {
                                        // Background grid
                                        TimelineGridView(
                                            duration: totalDuration,
                                            pixelsPerSecond: pixelsPerSecond,
                                            rowCount: totalRowCount,
                                            rowHeight: mainRowHeight
                                        )
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            viewModel.selectedKeyframeId = nil
                                        }
                                        
                                        // Layer bars and sub-tracks
                                        // Mirror the left column's divider structure so rows align exactly
                                        VStack(spacing: 0) {
                                            ForEach(sortedObjects) { object in
                                                let isExpanded = expandedObjects.contains(object.id)
                                                
                                                LayerBarView(
                                                    object: object,
                                                    viewModel: viewModel,
                                                    pixelsPerSecond: pixelsPerSecond,
                                                    rowHeight: mainRowHeight
                                                )
                                                .frame(height: mainRowHeight)
                                                Color.clear.frame(height: 1) // match ThemedDivider on left
                                                
                                                if isExpanded {
                                                    ForEach(object.animations) { animation in
                                                        AnimationSubtrackView(
                                                            animation: animation,
                                                            objectId: object.id,
                                                            viewModel: viewModel,
                                                            pixelsPerSecond: pixelsPerSecond,
                                                            rowHeight: subRowHeight
                                                        )
                                                        .frame(height: subRowHeight)
                                                        Color.clear.frame(height: 1) // match ThemedDivider on left
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .frame(
                                        width: max(totalTrackWidth, trackAreaWidth),
                                        height: totalContentHeight
                                    )
                                }
                                .frame(width: trackAreaWidth)
                            }
                        }
                    }
                    
                    // Playhead overlay (positioned over the track area)
                    TimelinePlayheadView(
                        currentTime: viewModel.currentTime,
                        duration: totalDuration,
                        pixelsPerSecond: pixelsPerSecond,
                        totalHeight: geometry.size.height,
                        rulerHeight: rulerHeight,
                        onDrag: { newTime in
                            viewModel.currentTime = min(max(0, newTime), totalDuration)
                        }
                    )
                    .offset(x: layerColumnWidth + 1) // shift right past the layer column
                }
            }
        }
        .background(AppTheme.Colors.surface)
    }
    
    // MARK: - Expand / Collapse
    
    private func toggleExpand(_ objectId: UUID) {
        if expandedObjects.contains(objectId) {
            expandedObjects.remove(objectId)
        } else {
            expandedObjects.insert(objectId)
        }
    }
    
    // MARK: - Timeline Header
    
    private var timelineHeader: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "timeline.selection")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.Colors.textTertiary)
            
            Text("Timeline")
                .font(AppTheme.Typography.captionMedium)
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            Spacer()
            
            // Current time display
            Text(formatTime(viewModel.currentTime))
                .font(AppTheme.Typography.mono)
                .foregroundColor(AppTheme.Colors.textSecondary)
                .padding(.horizontal, AppTheme.Spacing.sm)
                .padding(.vertical, 2)
                .background(AppTheme.Colors.backgroundSecondary)
                .cornerRadius(AppTheme.Radius.xs)
            
            Text("/")
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.Colors.textTertiary)
            
            Text(formatTime(totalDuration))
                .font(AppTheme.Typography.mono)
                .foregroundColor(AppTheme.Colors.textTertiary)
            
            Rectangle()
                .fill(AppTheme.Colors.border)
                .frame(width: 1, height: 14)
            
            // Zoom controls
            Button(action: { zoomOut() }) {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Zoom Out Timeline")
            
            Text("\(Int(pixelsPerSecond))px/s")
                .font(AppTheme.Typography.mono)
                .foregroundColor(AppTheme.Colors.textTertiary)
                .frame(width: 50)
            
            Button(action: { zoomIn() }) {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Zoom In Timeline")
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.xs)
    }
    
    // MARK: - Zoom
    
    private func zoomIn() {
        withAnimation(AppTheme.Animation.quick) {
            pixelsPerSecond = min(pixelsPerSecond * 1.5, 400)
        }
    }
    
    private func zoomOut() {
        withAnimation(AppTheme.Animation.quick) {
            pixelsPerSecond = max(pixelsPerSecond / 1.5, 20)
        }
    }
    
    // MARK: - Format
    
    private func formatTime(_ t: Double) -> String {
        let mins = Int(t) / 60
        let secs = Int(t) % 60
        let frames = Int((t.truncatingRemainder(dividingBy: 1)) * Double(viewModel.sceneState.fps))
        return String(format: "%d:%02d:%02d", mins, secs, frames)
    }
}

// MARK: - Timeline Layer Row (left column - main object row)
//
// Includes visibility toggle, lock toggle, and delete button
// (replaces the old separate Layer Panel).

struct TimelineLayerRow: View {
    let object: SceneObject
    let isSelected: Bool
    let isExpanded: Bool
    let hasAnimations: Bool
    let onSelect: () -> Void
    let onToggleExpand: () -> Void
    let onToggleVisibility: () -> Void
    let onToggleLock: () -> Void
    let onDelete: () -> Void
    let height: CGFloat
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 3) {
            // Disclosure triangle
            Button(action: onToggleExpand) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(hasAnimations ? AppTheme.Colors.textTertiary : AppTheme.Colors.textTertiary.opacity(0.2))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .disabled(!hasAnimations)
            
            // Visibility toggle (eye icon)
            Button(action: onToggleVisibility) {
                Image(systemName: object.isVisible ? "eye.fill" : "eye.slash")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(object.isVisible ? AppTheme.Colors.success : AppTheme.Colors.textTertiary.opacity(0.4))
                    .frame(width: 16, height: 14)
            }
            .buttonStyle(.plain)
            .help(object.isVisible ? "Hide Object" : "Show Object")
            
            // Lock toggle
            Button(action: onToggleLock) {
                Image(systemName: object.isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(object.isLocked ? AppTheme.Colors.warning : AppTheme.Colors.textTertiary.opacity(0.3))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .help(object.isLocked ? "Unlock Object" : "Lock Object")
            
            // Type icon
            Image(systemName: iconForType(object.type))
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(colorForType(object.type))
                .frame(width: 12)
            
            // Name
            Text(object.name)
                .font(AppTheme.Typography.caption)
                .foregroundColor(isSelected ? AppTheme.Colors.textPrimary : AppTheme.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            
            Spacer()
            
            // Delete button (shown on hover)
            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(AppTheme.Colors.error.opacity(0.7))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .help("Delete Object")
                .transition(.opacity)
            }
            
            // Animation count badge
            if hasAnimations && !isHovering {
                Text("\(object.animations.count)")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(AppTheme.Colors.textTertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(AppTheme.Colors.backgroundSecondary)
                    .cornerRadius(3)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.xs)
        .frame(height: height)
        .background(
            isSelected ? AppTheme.Colors.primary.opacity(0.08) :
            (isHovering ? AppTheme.Colors.surfaceHover : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { hovering in
            withAnimation(AppTheme.Animation.quick) { isHovering = hovering }
        }
        .contextMenu {
            Button(object.isVisible ? "Hide" : "Show") { onToggleVisibility() }
            Button(object.isLocked ? "Unlock" : "Lock") { onToggleLock() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }
    
    private func iconForType(_ type: SceneObjectType) -> String {
        switch type {
        case .rectangle: return "rectangle.fill"
        case .circle: return "circle.fill"
        case .ellipse: return "oval.fill"
        case .polygon: return "pentagon.fill"
        case .line: return "line.diagonal"
        case .text: return "textformat"
        case .icon: return "star.fill"
        case .image: return "photo"
        case .path: return "scribble.variable"
        case .model3D: return "cube.fill"
        case .shader: return "sparkles"
        case .particleSystem: return "sparkles"
        }
    }
    
    private func colorForType(_ type: SceneObjectType) -> Color {
        switch type {
        case .rectangle, .circle, .ellipse, .polygon: return Color.blue.opacity(0.7)
        case .line, .path: return Color.green.opacity(0.7)
        case .text: return Color.orange.opacity(0.7)
        case .icon: return Color.yellow.opacity(0.7)
        case .image: return Color.pink.opacity(0.7)
        case .model3D: return Color.purple.opacity(0.7)
        case .shader: return Color.cyan.opacity(0.7)
        case .particleSystem: return Color.red.opacity(0.7)
        }
    }
}

// MARK: - Animation Sub-track Label (left column - expanded animation row)

struct AnimationSubtrackLabel: View {
    let animation: AnimationDefinition
    let objectId: UUID
    let height: CGFloat
    @ObservedObject var viewModel: CanvasViewModel
    
    private var isSelected: Bool {
        viewModel.selectedAnimationId == animation.id
    }
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.xxs) {
            // Indent + color dot
            Spacer()
                .frame(width: 22)
            
            Circle()
                .fill(animationCategoryColor(animation.type))
                .frame(width: 5, height: 5)
            
            Text(animation.type.rawValue)
                .font(.system(size: 10, weight: isSelected ? .bold : .regular, design: .monospaced))
                .foregroundColor(isSelected ? AppTheme.Colors.primary : AppTheme.Colors.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
            
            Spacer()
            
            // Keyframe count badge
            if !animation.keyframes.isEmpty {
                Text("\(animation.keyframes.count) kf")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(AppTheme.Colors.textTertiary.opacity(0.5))
            }
            
            // Duration label
            Text(String(format: "%.1fs", animation.duration))
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundColor(AppTheme.Colors.textTertiary.opacity(0.6))
        }
        .padding(.horizontal, AppTheme.Spacing.xs)
        .frame(height: height)
        .background(isSelected ? AppTheme.Colors.primary.opacity(0.1) : AppTheme.Colors.surface.opacity(0.5))
        .onTapGesture {
            viewModel.selectAnimation(animation.id, objectId: objectId)
        }
    }
}
