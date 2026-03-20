//
//  CanvasView.swift
//  AIAfterEffects
//
//  Main canvas view for rendering animations with clean, minimal styling
//

import SwiftUI

struct CanvasView: View {
    @ObservedObject var viewModel: CanvasViewModel
    @StateObject private var canvasControls = CanvasControlsState()
    @StateObject private var gizmoVM = GizmoViewModel()
    @State private var containerSize: CGSize = CGSize(width: 800, height: 600)
    
    var body: some View {
        VStack(spacing: 0) {
            // ── Compact Top Bar: Playback + Zoom + Scenes + Gizmo Toolbar ──
            CompactTopBar(
                viewModel: viewModel,
                gizmoVM: gizmoVM,
                controls: canvasControls,
                containerSize: containerSize
            )
            
            ThemedDivider()
            
            // ── Canvas Area (fills all remaining space) ──
            GeometryReader { geometry in
                InteractiveCanvasView(
                    viewModel: viewModel,
                    gizmoVM: gizmoVM,
                    controls: canvasControls,
                    containerSize: geometry.size
                )
                .onAppear {
                    containerSize = geometry.size
                    gizmoVM.canvasViewModel = viewModel
                }
                .onChange(of: geometry.size) { _, newSize in
                    containerSize = newSize
                }
            }
        }
        .background(AppTheme.Colors.surface)
        .onAppear {
            gizmoVM.canvasViewModel = viewModel
        }
        .onChange(of: viewModel.selectedObjectId) { _, newId in
            // Auto-enter/exit 3D edit mode based on selection
            if let id = newId,
               let obj = viewModel.sceneState.objects.first(where: { $0.id == id }),
               obj.type == .model3D {
                // Auto-enter 3D mode when a 3D model is selected
                if !gizmoVM.is3DEditMode {
                    gizmoVM.enter3DEditMode()
                }
            } else {
                // Exit 3D mode when switching to a non-3D object or deselecting
                if gizmoVM.is3DEditMode {
                    gizmoVM.exit3DEditMode()
                }
            }
        }
    }
}

// MARK: - Canvas Controls State

class CanvasControlsState: ObservableObject {
    @Published var zoom: CGFloat = 1.0
    @Published var offset: CGSize = .zero
    @Published var isPanning: Bool = false
    
    // Zoom limits
    let minZoom: CGFloat = 0.1
    let maxZoom: CGFloat = 5.0
    
    // Preset zoom levels
    let zoomPresets: [CGFloat] = [0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0]
    
    var zoomPercentage: Int {
        Int(zoom * 100)
    }
    
    func zoomIn() {
        let newZoom = min(zoom * 1.25, maxZoom)
        withAnimation(AppTheme.Animation.smooth) {
            zoom = newZoom
        }
    }
    
    func zoomOut() {
        let newZoom = max(zoom / 1.25, minZoom)
        withAnimation(AppTheme.Animation.smooth) {
            zoom = newZoom
        }
    }
    
    func setZoom(_ value: CGFloat) {
        let clampedZoom = min(max(value, minZoom), maxZoom)
        withAnimation(AppTheme.Animation.smooth) {
            zoom = clampedZoom
        }
    }
    
    func resetView() {
        withAnimation(AppTheme.Animation.smooth) {
            zoom = 1.0
            offset = .zero
        }
    }
    
    func fitToView(canvasSize: CGSize, containerSize: CGSize) {
        let horizontalScale = (containerSize.width - 60) / canvasSize.width
        let verticalScale = (containerSize.height - 60) / canvasSize.height
        let fitZoom = min(horizontalScale, verticalScale, 1.0)
        
        withAnimation(AppTheme.Animation.smooth) {
            zoom = fitZoom
            offset = .zero
        }
    }
    
    func fillView(canvasSize: CGSize, containerSize: CGSize) {
        let horizontalScale = containerSize.width / canvasSize.width
        let verticalScale = containerSize.height / canvasSize.height
        let fillZoom = max(horizontalScale, verticalScale)
        
        withAnimation(AppTheme.Animation.smooth) {
            zoom = min(fillZoom, maxZoom)
            offset = .zero
        }
    }
}

// MARK: - Compact Top Bar (Playback + Scenes + Zoom — all in one)

struct CompactTopBar: View {
    @ObservedObject var viewModel: CanvasViewModel
    @ObservedObject var gizmoVM: GizmoViewModel
    @ObservedObject var controls: CanvasControlsState
    let containerSize: CGSize
    @State private var isExportHovering = false
    @State private var showCustomDimensions = false
    @State private var customWidth: String = ""
    @State private var customHeight: String = ""
    @State private var renamingSceneId: String?
    @State private var renamingSceneName: String = ""
    
    private var canvasSize: CGSize {
        CGSize(width: viewModel.sceneState.canvasWidth, height: viewModel.sceneState.canvasHeight)
    }
    
    private var scenes: [SceneFile] {
        viewModel.currentProject?.orderedScenes ?? []
    }
    
    /// The unique ID of the currently active scene — used instead of index to avoid
    /// highlighting multiple pills when scenes share the same name.
    private var currentSceneId: String? {
        let ordered = scenes
        let idx = viewModel.currentSceneIndex
        guard idx >= 0, idx < ordered.count else { return nil }
        return ordered[idx].id
    }
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // ── Left: Playback controls ──
            HStack(spacing: AppTheme.Spacing.sm) {
                PlaybackButton(icon: "backward.end.fill", size: 11) {
                    viewModel.restart()
                }
                
                PlaybackButton(
                    icon: viewModel.isPlaying ? "pause.fill" : "play.fill",
                    size: 13,
                    isAccent: true
                ) {
                    viewModel.togglePlayback()
                }
                .keyboardShortcut(.space, modifiers: [])
                
                PlaybackButton(icon: "stop.fill", size: 11) {
                    if viewModel.playbackMode == .allScenes {
                        viewModel.stopAllScenes()
                    } else {
                        viewModel.stop()
                    }
                }
            }
            
            Rectangle()
                .fill(AppTheme.Colors.border)
                .frame(width: 1, height: 18)
            
            // Gizmo toolbar (Move / Rotate / Scale)
            GizmoToolbar(gizmoVM: gizmoVM, canvasVM: viewModel)
            
            Rectangle()
                .fill(AppTheme.Colors.border)
                .frame(width: 1, height: 18)
            
            // Time
            Text(formatTime(viewModel.currentTime))
                .font(AppTheme.Typography.mono)
                .foregroundColor(AppTheme.Colors.textSecondary)
                .frame(width: 55)
            
            // Mini progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.full)
                        .fill(AppTheme.Colors.backgroundSecondary)
                        .frame(height: 4)
                    
                    RoundedRectangle(cornerRadius: AppTheme.Radius.full)
                        .fill(AppTheme.Colors.primary)
                        .frame(
                            width: geometry.size.width * (viewModel.currentTime / max(viewModel.sceneState.duration, 0.1)),
                            height: 4
                        )
                }
                .frame(maxHeight: .infinity)
            }
            .frame(width: 80, height: 16)
            
            Text(formatTime(viewModel.sceneState.duration))
                .font(AppTheme.Typography.mono)
                .foregroundColor(AppTheme.Colors.textTertiary)
                .frame(width: 55)
            
            Rectangle()
                .fill(AppTheme.Colors.border)
                .frame(width: 1, height: 18)
            
            // ── Center: Scene pills ──
            scenePills
            
            Rectangle()
                .fill(AppTheme.Colors.border)
                .frame(width: 1, height: 18)
            
            // ── Right: Canvas info + Zoom + Export ──
            HStack(spacing: AppTheme.Spacing.sm) {
                // Dimension badge
                Menu {
                    dimensionPickerMenu
                } label: {
                    Text("\(Int(viewModel.sceneState.canvasWidth))×\(Int(viewModel.sceneState.canvasHeight))")
                        .font(AppTheme.Typography.mono)
                        .foregroundColor(AppTheme.Colors.textTertiary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .popover(isPresented: $showCustomDimensions) {
                    customDimensionPopover
                }
                
                Rectangle()
                    .fill(AppTheme.Colors.border)
                    .frame(width: 1, height: 18)
                
                // Fit to view
                CanvasControlButton(icon: "arrow.up.left.and.arrow.down.right", tooltip: "Fit to View") {
                    controls.fitToView(canvasSize: canvasSize, containerSize: containerSize)
                }
                
                Rectangle()
                    .fill(AppTheme.Colors.border)
                    .frame(width: 1, height: 18)
                
                // Zoom controls (compact)
                CanvasControlButton(icon: "minus", tooltip: "Zoom Out") {
                    controls.zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)
                
                Menu {
                    ForEach(controls.zoomPresets, id: \.self) { preset in
                        Button("\(Int(preset * 100))%") { controls.setZoom(preset) }
                    }
                    Divider()
                    Button("Fit to View") { controls.fitToView(canvasSize: canvasSize, containerSize: containerSize) }
                    Button("Actual Size") { controls.setZoom(1.0) }
                } label: {
                    Text("\(controls.zoomPercentage)%")
                        .font(AppTheme.Typography.mono)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                        .frame(width: 40)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 48)
                
                CanvasControlButton(icon: "plus", tooltip: "Zoom In") {
                    controls.zoomIn()
                }
                .keyboardShortcut("=", modifiers: .command)
                
                CanvasControlButton(icon: "arrow.counterclockwise", tooltip: "Reset View") {
                    controls.resetView()
                }
                .keyboardShortcut("0", modifiers: .command)
            }
            
            Rectangle()
                .fill(AppTheme.Colors.border)
                .frame(width: 1, height: 18)
            
            // Export
            exportButton
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.xs)
        .background(AppTheme.Colors.surface)
    }
    
    // MARK: - Scene Pills
    
    private var scenePills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.xxs) {
                ForEach(Array(scenes.enumerated()), id: \.element.id) { index, scene in
                    let isActive = scene.id == currentSceneId
                    
                    if renamingSceneId == scene.id {
                        // Inline rename field
                        TextField("Scene name", text: $renamingSceneName, onCommit: {
                            if !renamingSceneName.trimmingCharacters(in: .whitespaces).isEmpty {
                                viewModel.projectManager?.renameScene(withId: scene.id, to: renamingSceneName)
                            }
                            renamingSceneId = nil
                        })
                        .textFieldStyle(.plain)
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                        .frame(width: 80)
                        .padding(.horizontal, AppTheme.Spacing.sm)
                        .padding(.vertical, AppTheme.Spacing.xxs)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.full)
                                .fill(AppTheme.Colors.backgroundSecondary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.full)
                                .strokeBorder(AppTheme.Colors.primary.opacity(0.4), lineWidth: 1)
                        )
                        .onExitCommand { renamingSceneId = nil }
                        .id("rename-\(scene.id)")
                    } else {
                        Button(action: { viewModel.switchScene(to: index) }) {
                            Text(scene.name)
                                .font(AppTheme.Typography.caption)
                                .foregroundColor(isActive ? AppTheme.Colors.textPrimary : AppTheme.Colors.textTertiary)
                                .padding(.horizontal, AppTheme.Spacing.sm)
                                .padding(.vertical, AppTheme.Spacing.xxs)
                                .background(
                                    RoundedRectangle(cornerRadius: AppTheme.Radius.full)
                                        .fill(isActive ? AppTheme.Colors.backgroundSecondary : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                        .id("pill-\(scene.id)")
                        .contextMenu {
                            Button("Rename") {
                                renamingSceneName = scene.name
                                renamingSceneId = scene.id
                            }
                            Button("Duplicate") {
                                _ = viewModel.projectManager?.duplicateScene(withId: scene.id)
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                viewModel.deleteScene(withId: scene.id)
                            }
                            .disabled(scenes.count <= 1)
                        }
                    }
                }
                
                // Add scene
                Button(action: { let _ = viewModel.addNewScene() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(AppTheme.Colors.textTertiary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Add Scene")
            }
        }
    }
    
    // MARK: - Export Button
    
    @ViewBuilder
    private var exportButton: some View {
        if viewModel.isExporting {
            HStack(spacing: AppTheme.Spacing.xs) {
                if let progress = viewModel.exportService.progress, progress.totalFrames > 0 {
                    ProgressView(value: progress.percentage)
                        .progressViewStyle(.linear)
                        .tint(AppTheme.Colors.primary)
                        .frame(width: 60)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.5)
                        .tint(AppTheme.Colors.primary)
                }
                
                Button(action: { viewModel.cancelExport() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(AppTheme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        } else {
            Button(action: { viewModel.startExport() }) {
                HStack(spacing: AppTheme.Spacing.xxs) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 10, weight: .medium))
                    Text("Export")
                        .font(AppTheme.Typography.captionMedium)
                }
                .foregroundColor(viewModel.sceneState.objects.isEmpty ? AppTheme.Colors.textTertiary : .white)
                .padding(.horizontal, AppTheme.Spacing.sm)
                .padding(.vertical, AppTheme.Spacing.xxs)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.full)
                        .fill(viewModel.sceneState.objects.isEmpty ? AppTheme.Colors.backgroundSecondary : AppTheme.Colors.primary)
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.sceneState.objects.isEmpty)
        }
    }
    
    // MARK: - Dimension Picker Menu (reused from old CanvasHeaderView)
    
    @ViewBuilder
    private var dimensionPickerMenu: some View {
        let currentW = Int(viewModel.sceneState.canvasWidth)
        let currentH = Int(viewModel.sceneState.canvasHeight)
        
        Section("Video") {
            dimensionButton("1920 × 1080", w: 1920, h: 1080, label: "Full HD 16:9", currentW: currentW, currentH: currentH)
            dimensionButton("3840 × 2160", w: 3840, h: 2160, label: "4K UHD", currentW: currentW, currentH: currentH)
            dimensionButton("1280 × 720", w: 1280, h: 720, label: "HD 720p", currentW: currentW, currentH: currentH)
        }
        
        Section("Social — Landscape") {
            dimensionButton("1920 × 1080", w: 1920, h: 1080, label: "YouTube / LinkedIn", currentW: currentW, currentH: currentH)
            dimensionButton("1200 × 628", w: 1200, h: 628, label: "Facebook / Twitter", currentW: currentW, currentH: currentH)
        }
        
        Section("Social — Portrait") {
            dimensionButton("1080 × 1920", w: 1080, h: 1920, label: "Reels / TikTok / Story", currentW: currentW, currentH: currentH)
            dimensionButton("1080 × 1350", w: 1080, h: 1350, label: "Instagram Post 4:5", currentW: currentW, currentH: currentH)
        }
        
        Section("Social — Square") {
            dimensionButton("1080 × 1080", w: 1080, h: 1080, label: "Instagram / Facebook", currentW: currentW, currentH: currentH)
        }
        
        Divider()
        
        Button {
            customWidth = "\(currentW)"
            customHeight = "\(currentH)"
            showCustomDimensions = true
        } label: {
            Label("Custom Size...", systemImage: "pencil.and.ruler")
        }
    }
    
    private func dimensionButton(_ size: String, w: Int, h: Int, label: String, currentW: Int, currentH: Int) -> some View {
        Button {
            viewModel.setCanvasDimensions(width: Double(w), height: Double(h))
            controls.fitToView(canvasSize: CGSize(width: w, height: h), containerSize: containerSize)
        } label: {
            HStack {
                Text(size)
                Spacer()
                Text(label)
                    .foregroundColor(.secondary)
                if currentW == w && currentH == h {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
    
    private var customDimensionPopover: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Text("Custom Dimensions")
                .font(AppTheme.Typography.headline)
            
            HStack(spacing: AppTheme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Width").font(AppTheme.Typography.caption)
                    TextField("Width", text: $customWidth)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                Text("×").foregroundColor(AppTheme.Colors.textTertiary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Height").font(AppTheme.Typography.caption)
                    TextField("Height", text: $customHeight)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
            }
            
            Button("Apply") {
                if let w = Double(customWidth), let h = Double(customHeight), w > 0, h > 0 {
                    viewModel.setCanvasDimensions(width: w, height: h)
                    controls.fitToView(canvasSize: CGSize(width: w, height: h), containerSize: containerSize)
                }
                showCustomDimensions = false
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 260)
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let frames = Int((time.truncatingRemainder(dividingBy: 1)) * 60)
        return String(format: "%d:%02d:%02d", minutes, seconds, frames)
    }
}

// MARK: - Interactive Canvas View

struct InteractiveCanvasView: View {
    @ObservedObject var viewModel: CanvasViewModel
    @ObservedObject var gizmoVM: GizmoViewModel
    @ObservedObject var controls: CanvasControlsState
    let containerSize: CGSize
    
    // Gesture states
    @State private var lastDragOffset: CGSize = .zero
    @GestureState private var isDragging: Bool = false
    
    var body: some View {
        ZStack {
            // Background grid (static, doesn't move)
            CanvasBackgroundView()
            
            // Transformable canvas container
            ZStack {
                // Canvas border/shadow frame
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .fill(Color.clear)
                    .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                            .strokeBorder(AppTheme.Colors.border, lineWidth: 1)
                    )
                
                // Outgoing scene layer (visible during transition)
                if let outgoing = viewModel.outgoingSceneState {
                    outgoingSceneLayer(outgoing: outgoing)
                }
                
                // Incoming / current scene layer
                incomingSceneLayer()
                
                // 2D Gizmo overlay (on top of objects, in canvas coordinate space)
                if gizmoVM.shouldShow2DGizmo {
                    Gizmo2DOverlayView(
                        gizmoVM: gizmoVM,
                        canvasVM: viewModel,
                        zoom: controls.zoom
                    )
                    .allowsHitTesting(!viewModel.isPlaying)
                }
                
                // 3D Edit Mode overlay
                if gizmoVM.shouldShow3DGizmo {
                    Gizmo3DEnvironmentView(
                        gizmoVM: gizmoVM,
                        canvasVM: viewModel
                    )
                }
            }
            // Constrain coordinate space so .position() matches the canvas dimensions
            .frame(
                width: viewModel.sceneState.canvasWidth,
                height: viewModel.sceneState.canvasHeight
            )
            .clipped()
            .scaleEffect(controls.zoom)
            .offset(controls.offset)
            .gesture(gizmoVM.isDragging ? nil : panGesture)
            .onTapGesture(count: 2) {
                // Double-tap on 3D model: enter 3D edit mode
                if gizmoVM.isSelected3DModel && !gizmoVM.is3DEditMode {
                    gizmoVM.enter3DEditMode()
                    return
                }
                // Double tap to fit
                controls.fitToView(
                    canvasSize: CGSize(
                        width: viewModel.sceneState.canvasWidth,
                        height: viewModel.sceneState.canvasHeight
                    ),
                    containerSize: containerSize
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .onGestures(
            scroll: { event in
                handleScrollWheel(event: event)
            },
            magnify: { event in
                handlePinchZoom(event: event)
            }
        )
        .background(AppTheme.Colors.canvasBackground)
        .onKeyPress("w") {
            gizmoVM.setMode(.move)
            return .handled
        }
        .onKeyPress("e") {
            gizmoVM.setMode(.rotate)
            return .handled
        }
        .onKeyPress("r") {
            gizmoVM.setMode(.scale)
            return .handled
        }
        .onKeyPress(.escape) {
            if gizmoVM.isDragging {
                gizmoVM.cancelDrag()
                return .handled
            }
            if gizmoVM.is3DEditMode {
                gizmoVM.exit3DEditMode()
                return .handled
            }
            return .ignored
        }
    }
    
    // MARK: - Gestures
    
    private var panGesture: some Gesture {
        DragGesture()
            .updating($isDragging) { _, state, _ in
                state = true
            }
            .onChanged { value in
                controls.offset = CGSize(
                    width: lastDragOffset.width + value.translation.width,
                    height: lastDragOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastDragOffset = controls.offset
            }
    }
    
    // MARK: - Zoom to Cursor
    
    private func zoomToCursor(zoomDelta: CGFloat, cursorLocation: CGPoint) {
        let oldZoom = controls.zoom
        let newZoom = min(max(oldZoom * zoomDelta, controls.minZoom), controls.maxZoom)
        
        // Calculate the center of the container
        let centerX = containerSize.width / 2
        let centerY = containerSize.height / 2
        
        // Calculate cursor position relative to center
        let cursorFromCenterX = cursorLocation.x - centerX
        let cursorFromCenterY = cursorLocation.y - centerY
        
        // Calculate the canvas point under cursor before zoom
        let canvasPointX = (cursorFromCenterX - controls.offset.width) / oldZoom
        let canvasPointY = (cursorFromCenterY - controls.offset.height) / oldZoom
        
        // Calculate new offset to keep the same canvas point under cursor
        let newOffsetX = cursorFromCenterX - canvasPointX * newZoom
        let newOffsetY = cursorFromCenterY - canvasPointY * newZoom
        
        // Apply the new zoom and offset
        controls.zoom = newZoom
        controls.offset = CGSize(width: newOffsetX, height: newOffsetY)
        lastDragOffset = controls.offset
    }
    
    // MARK: - Scroll Wheel Zoom
    
    private func handleScrollWheel(event: ZoomEvent) {
        let sensitivity: CGFloat = 0.02
        let zoomDelta = 1.0 + (event.delta * sensitivity)
        zoomToCursor(zoomDelta: zoomDelta, cursorLocation: event.location)
    }
    
    // MARK: - Pinch to Zoom (Trackpad)
    
    private func handlePinchZoom(event: ZoomEvent) {
        let sensitivity: CGFloat = 1.5
        let zoomDelta = 1.0 + (event.delta * sensitivity)
        zoomToCursor(zoomDelta: zoomDelta, cursorLocation: event.location)
    }
    
    // MARK: - Transition Rendering
    
    /// Renders the outgoing scene during a transition
    @ViewBuilder
    private func outgoingSceneLayer(outgoing: SceneState) -> some View {
        let progress = viewModel.transitionProgress
        let transitionType = viewModel.activeTransitionType
        let canvasW = viewModel.sceneState.canvasWidth
        let canvasH = viewModel.sceneState.canvasHeight
        
        ZStack {
            Rectangle()
                .fill(outgoing.backgroundColor.color)
            ForEach(outgoing.objects.filter(\.isVisible).sorted(by: { $0.zIndex < $1.zIndex })) { object in
                ObjectRendererView(
                    object: object,
                    currentTime: outgoing.duration, // frozen at final frame
                    sceneState: outgoing,
                    isPlaying: true
                )
            }
        }
        .modifier(OutgoingTransitionModifier(
            transitionType: transitionType,
            progress: progress,
            canvasWidth: canvasW,
            canvasHeight: canvasH
        ))
        .allowsHitTesting(false)
    }
    
    /// Renders the incoming (current) scene during a transition
    @ViewBuilder
    private func incomingSceneLayer() -> some View {
        let progress = viewModel.transitionProgress
        let transitionType = viewModel.activeTransitionType
        let isTransitioning = viewModel.isTransitioning
        let canvasW = viewModel.sceneState.canvasWidth
        let canvasH = viewModel.sceneState.canvasHeight
        
        ZStack {
            Rectangle()
                .fill(viewModel.sceneState.backgroundColor.color)
                .contentShape(Rectangle())
                .onTapGesture {
                    viewModel.selectObject(nil)
                }
            ForEach(viewModel.sceneState.objects.filter(\.isVisible).sorted(by: { $0.zIndex < $1.zIndex })) { object in
                ObjectRendererView(
                    object: object,
                    currentTime: viewModel.currentTime,
                    sceneState: viewModel.sceneState,
                    timingOffset: viewModel.resolvedTimingOffsets[object.id] ?? 0,
                    isSelected: viewModel.selectedObjectId == object.id,
                    isPlaying: viewModel.isPlaying
                )
                .allowsHitTesting(true)
                .onTapGesture {
                    if !object.isLocked {
                        viewModel.selectObject(object.id)
                        // Auto-enter 3D edit mode when selecting a 3D model
                        if object.type == .model3D && !gizmoVM.is3DEditMode {
                            gizmoVM.enter3DEditMode()
                        }
                    }
                }
            }
        }
        .modifier(IncomingTransitionModifier(
            transitionType: transitionType,
            progress: progress,
            isTransitioning: isTransitioning,
            canvasWidth: canvasW,
            canvasHeight: canvasH
        ))
    }
}

// MARK: - Transition Modifiers

/// Modifier applied to the OUTGOING scene during a transition
struct OutgoingTransitionModifier: ViewModifier {
    let transitionType: TransitionType
    let progress: Double      // 0 → 1
    let canvasWidth: CGFloat
    let canvasHeight: CGFloat
    
    func body(content: Content) -> some View {
        switch transitionType {
        case .crossfade, .dissolve:
            content.opacity(1.0 - progress)
            
        case .slideLeft:
            content.offset(x: -canvasWidth * progress)
            
        case .slideRight:
            content.offset(x: canvasWidth * progress)
            
        case .slideUp:
            content.offset(y: -canvasHeight * progress)
            
        case .slideDown:
            content.offset(y: canvasHeight * progress)
            
        case .wipe:
            // Horizontal wipe: clip outgoing from right edge
            content
                .clipShape(
                    HorizontalClipShape(fraction: 1.0 - progress)
                )
            
        case .zoom:
            content
                .scaleEffect(1.0 + progress * 0.3) // zoom out slightly
                .opacity(1.0 - progress)
            
        case .none:
            // No transition: outgoing disappears immediately at start
            content.opacity(progress > 0 ? 0 : 1)
        }
    }
}

/// Modifier applied to the INCOMING scene during a transition
struct IncomingTransitionModifier: ViewModifier {
    let transitionType: TransitionType
    let progress: Double      // 0 → 1
    let isTransitioning: Bool
    let canvasWidth: CGFloat
    let canvasHeight: CGFloat
    
    func body(content: Content) -> some View {
        if !isTransitioning {
            content
        } else {
            switch transitionType {
            case .crossfade, .dissolve:
                content.opacity(progress)
                
            case .slideLeft:
                content.offset(x: canvasWidth * (1.0 - progress))
                
            case .slideRight:
                content.offset(x: -canvasWidth * (1.0 - progress))
                
            case .slideUp:
                content.offset(y: canvasHeight * (1.0 - progress))
                
            case .slideDown:
                content.offset(y: -canvasHeight * (1.0 - progress))
                
            case .wipe:
                // Horizontal wipe: reveal incoming from left edge
                content
                    .clipShape(
                        HorizontalClipShape(fraction: progress, fromLeading: true)
                    )
                
            case .zoom:
                content
                    .scaleEffect(0.7 + progress * 0.3) // zoom in from smaller
                    .opacity(progress)
                
            case .none:
                // No transition: incoming appears immediately
                content
            }
        }
    }
}

/// A clip shape that reveals a horizontal fraction of the view
struct HorizontalClipShape: Shape {
    var fraction: CGFloat
    var fromLeading: Bool = false
    
    var animatableData: CGFloat {
        get { fraction }
        set { fraction = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        if fromLeading {
            // Reveal from left edge
            path.addRect(CGRect(
                x: 0,
                y: 0,
                width: rect.width * fraction,
                height: rect.height
            ))
        } else {
            // Keep from left edge (clip from right)
            path.addRect(CGRect(
                x: 0,
                y: 0,
                width: rect.width * fraction,
                height: rect.height
            ))
        }
        return path
    }
}

// MARK: - Gesture Handling NSView

struct ZoomEvent {
    let delta: CGFloat
    let location: CGPoint
}

struct GestureHandlingModifier: ViewModifier {
    let onScroll: (ZoomEvent) -> Void
    let onMagnify: (ZoomEvent) -> Void
    
    func body(content: Content) -> some View {
        content
            .background(
                GestureHandlingView(onScroll: onScroll, onMagnify: onMagnify)
            )
    }
}

struct GestureHandlingView: NSViewRepresentable {
    let onScroll: (ZoomEvent) -> Void
    let onMagnify: (ZoomEvent) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = GestureHandlingNSView()
        view.onScroll = onScroll
        view.onMagnify = onMagnify
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? GestureHandlingNSView {
            view.onScroll = onScroll
            view.onMagnify = onMagnify
        }
    }
}

class GestureHandlingNSView: NSView {
    var onScroll: ((ZoomEvent) -> Void)?
    var onMagnify: ((ZoomEvent) -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func scrollWheel(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let flippedLocation = CGPoint(x: location.x, y: bounds.height - location.y)
        
        let zoomEvent = ZoomEvent(
            delta: event.scrollingDeltaY,
            location: flippedLocation
        )
        onScroll?(zoomEvent)
    }
    
    override func magnify(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let flippedLocation = CGPoint(x: location.x, y: bounds.height - location.y)
        
        let zoomEvent = ZoomEvent(
            delta: event.magnification,
            location: flippedLocation
        )
        onMagnify?(zoomEvent)
    }
}

extension View {
    func onGestures(scroll: @escaping (ZoomEvent) -> Void, magnify: @escaping (ZoomEvent) -> Void) -> some View {
        modifier(GestureHandlingModifier(onScroll: scroll, onMagnify: magnify))
    }
}

// MARK: - Canvas Header

struct CanvasHeaderView: View {
    @ObservedObject var viewModel: CanvasViewModel
    @ObservedObject var controls: CanvasControlsState
    let containerSize: CGSize
    @State private var showCustomDimensions = false
    @State private var customWidth: String = ""
    @State private var customHeight: String = ""
    
    private var canvasSize: CGSize {
        CGSize(
            width: viewModel.sceneState.canvasWidth,
            height: viewModel.sceneState.canvasHeight
        )
    }
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.lg) {
            // Title and info
            HStack(spacing: AppTheme.Spacing.md) {
                Text("Canvas")
                    .font(AppTheme.Typography.headline)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                
                // Canvas size badge — clickable with dimension picker
                Menu {
                    dimensionPickerMenu
                } label: {
                    HStack(spacing: AppTheme.Spacing.xxs) {
                        Text("\(Int(viewModel.sceneState.canvasWidth)) × \(Int(viewModel.sceneState.canvasHeight))")
                            .font(AppTheme.Typography.mono)
                            .foregroundColor(AppTheme.Colors.textSecondary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(AppTheme.Colors.textTertiary)
                    }
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, AppTheme.Spacing.xxs)
                    .background(AppTheme.Colors.backgroundSecondary)
                    .cornerRadius(AppTheme.Radius.full)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .popover(isPresented: $showCustomDimensions) {
                    customDimensionPopover
                }
                
                // Objects count
                HStack(spacing: AppTheme.Spacing.xxs) {
                    Circle()
                        .fill(viewModel.sceneState.objects.isEmpty ? AppTheme.Colors.textTertiary : AppTheme.Colors.success)
                        .frame(width: 6, height: 6)
                    
                    Text("\(viewModel.sceneState.objects.count) objects")
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.textTertiary)
                }
            }
            
            Spacer()
            
            // Zoom Controls
            HStack(spacing: AppTheme.Spacing.sm) {
                // Fit button
                CanvasControlButton(icon: "arrow.up.left.and.arrow.down.right", tooltip: "Fit to View") {
                    controls.fitToView(canvasSize: canvasSize, containerSize: containerSize)
                }
                
                Rectangle()
                    .fill(AppTheme.Colors.border)
                    .frame(width: 1, height: 16)
                
                // Zoom out
                CanvasControlButton(icon: "minus", tooltip: "Zoom Out (⌘-)") {
                    controls.zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)
                
                // Zoom percentage with menu
                Menu {
                    ForEach(controls.zoomPresets, id: \.self) { preset in
                        Button("\(Int(preset * 100))%") {
                            controls.setZoom(preset)
                        }
                    }
                    
                    Divider()
                    
                    Button("Fit to View") {
                        controls.fitToView(canvasSize: canvasSize, containerSize: containerSize)
                    }
                    
                    Button("Fill View") {
                        controls.fillView(canvasSize: canvasSize, containerSize: containerSize)
                    }
                    
                    Button("Actual Size (100%)") {
                        controls.setZoom(1.0)
                    }
                } label: {
                    Text("\(controls.zoomPercentage)%")
                        .font(AppTheme.Typography.mono)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                        .frame(width: 50)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 60)
                
                // Zoom in
                CanvasControlButton(icon: "plus", tooltip: "Zoom In (⌘+)") {
                    controls.zoomIn()
                }
                .keyboardShortcut("=", modifiers: .command)
                
                Rectangle()
                    .fill(AppTheme.Colors.border)
                    .frame(width: 1, height: 16)
                
                // Reset view
                CanvasControlButton(icon: "arrow.counterclockwise", tooltip: "Reset View (⌘0)") {
                    controls.resetView()
                }
                .keyboardShortcut("0", modifiers: .command)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.xs)
            .background(AppTheme.Colors.backgroundSecondary)
            .cornerRadius(AppTheme.Radius.full)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(AppTheme.Colors.surface)
    }
    
    // MARK: - Dimension Picker Menu
    
    @ViewBuilder
    private var dimensionPickerMenu: some View {
        let currentW = Int(viewModel.sceneState.canvasWidth)
        let currentH = Int(viewModel.sceneState.canvasHeight)
        
        Section("Video") {
            dimensionButton("1920 × 1080", w: 1920, h: 1080, label: "Full HD 16:9", currentW: currentW, currentH: currentH)
            dimensionButton("3840 × 2160", w: 3840, h: 2160, label: "4K UHD", currentW: currentW, currentH: currentH)
            dimensionButton("1280 × 720", w: 1280, h: 720, label: "HD 720p", currentW: currentW, currentH: currentH)
        }
        
        Section("Social — Landscape") {
            dimensionButton("1920 × 1080", w: 1920, h: 1080, label: "YouTube / LinkedIn", currentW: currentW, currentH: currentH)
            dimensionButton("1200 × 628", w: 1200, h: 628, label: "Facebook / Twitter", currentW: currentW, currentH: currentH)
        }
        
        Section("Social — Portrait") {
            dimensionButton("1080 × 1920", w: 1080, h: 1920, label: "Reels / TikTok / Story", currentW: currentW, currentH: currentH)
            dimensionButton("1080 × 1350", w: 1080, h: 1350, label: "Instagram Post 4:5", currentW: currentW, currentH: currentH)
        }
        
        Section("Social — Square") {
            dimensionButton("1080 × 1080", w: 1080, h: 1080, label: "Instagram / Facebook", currentW: currentW, currentH: currentH)
        }
        
        Section("Presentation") {
            dimensionButton("1920 × 1080", w: 1920, h: 1080, label: "Widescreen 16:9", currentW: currentW, currentH: currentH)
            dimensionButton("1024 × 768", w: 1024, h: 768, label: "Standard 4:3", currentW: currentW, currentH: currentH)
        }
        
        Divider()
        
        Button {
            customWidth = "\(currentW)"
            customHeight = "\(currentH)"
            showCustomDimensions = true
        } label: {
            Label("Custom Size...", systemImage: "pencil.and.ruler")
        }
    }
    
    private func dimensionButton(_ size: String, w: Int, h: Int, label: String, currentW: Int, currentH: Int) -> some View {
        Button {
            viewModel.setCanvasDimensions(width: Double(w), height: Double(h))
            controls.fitToView(canvasSize: CGSize(width: w, height: h), containerSize: containerSize)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                    Text("\(w) × \(h)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if currentW == w && currentH == h {
                    Image(systemName: "checkmark")
                        .foregroundColor(AppTheme.Colors.primary)
                }
            }
        }
    }
    
    // MARK: - Custom Dimension Popover
    
    private var customDimensionPopover: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("Custom Canvas Size")
                .font(AppTheme.Typography.headline)
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            HStack(spacing: AppTheme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Width")
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    TextField("Width", text: $customWidth)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                }
                
                Text("×")
                    .font(AppTheme.Typography.body)
                    .foregroundColor(AppTheme.Colors.textTertiary)
                    .padding(.top, 16)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Height")
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    TextField("Height", text: $customHeight)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                }
                
                Text("px")
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.textTertiary)
                    .padding(.top, 16)
            }
            
            HStack {
                Spacer()
                Button("Cancel") {
                    showCustomDimensions = false
                }
                .buttonStyle(.plain)
                .foregroundColor(AppTheme.Colors.textSecondary)
                
                Button("Apply") {
                    if let w = Double(customWidth), let h = Double(customHeight), w > 0, h > 0 {
                        viewModel.setCanvasDimensions(width: w, height: h)
                        controls.fitToView(canvasSize: CGSize(width: w, height: h), containerSize: containerSize)
                    }
                    showCustomDimensions = false
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.Colors.primary)
            }
        }
        .padding(AppTheme.Spacing.lg)
        .frame(width: 300)
    }
}

// MARK: - Canvas Control Button

struct CanvasControlButton: View {
    let icon: String
    var tooltip: String = ""
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isHovering ? AppTheme.Colors.textPrimary : AppTheme.Colors.textSecondary)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(isHovering ? AppTheme.Colors.backgroundSecondary : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { hovering in
            withAnimation(AppTheme.Animation.quick) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Canvas Background

struct CanvasBackgroundView: View {
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let gridSize: CGFloat = 24
                let columns = Int(size.width / gridSize) + 1
                let rows = Int(size.height / gridSize) + 1
                
                // Draw subtle dot grid (cleaner than lines)
                for col in 0...columns {
                    for row in 0...rows {
                        let x = CGFloat(col) * gridSize
                        let y = CGFloat(row) * gridSize
                        let isAccent = col % 5 == 0 && row % 5 == 0
                        let dotSize: CGFloat = isAccent ? 2.0 : 1.0
                        
                        var path = Path()
                        path.addEllipse(in: CGRect(x: x - dotSize/2, y: y - dotSize/2, width: dotSize, height: dotSize))
                        
                        context.fill(
                            path,
                            with: .color(isAccent ? AppTheme.Colors.gridLineAccent : AppTheme.Colors.gridLine)
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Playback Controls

struct PlaybackControlsView: View {
    @ObservedObject var viewModel: CanvasViewModel
    @State private var isExportHovering = false
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.xl) {
            // Time display
            TimeDisplay(time: viewModel.currentTime)
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: AppTheme.Radius.full)
                        .fill(AppTheme.Colors.backgroundSecondary)
                        .frame(height: 6)
                    
                    // Progress fill
                    RoundedRectangle(cornerRadius: AppTheme.Radius.full)
                        .fill(AppTheme.Colors.primary)
                        .frame(
                            width: geometry.size.width * (viewModel.currentTime / max(viewModel.sceneState.duration, 0.1)),
                            height: 6
                        )
                    
                    // Playhead
                    Circle()
                        .fill(AppTheme.Colors.primary)
                        .frame(width: 14, height: 14)
                        .shadow(color: Color.black.opacity(0.1), radius: 4)
                        .offset(x: geometry.size.width * (viewModel.currentTime / max(viewModel.sceneState.duration, 0.1)) - 7)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 24)
            
            // Duration display
            TimeDisplay(time: viewModel.sceneState.duration)
            
            Rectangle()
                .fill(AppTheme.Colors.border)
                .frame(width: 1, height: 24)
            
            // Control buttons
            HStack(spacing: AppTheme.Spacing.md) {
                // Restart
                PlaybackButton(icon: "backward.end.fill", size: 14) {
                    viewModel.restart()
                }
                
                // Play/Pause
                PlaybackButton(
                    icon: viewModel.isPlaying ? "pause.fill" : "play.fill",
                    size: 18,
                    isAccent: true
                ) {
                    viewModel.togglePlayback()
                }
                .keyboardShortcut(.space, modifiers: [])
                
                // Stop
                PlaybackButton(icon: "stop.fill", size: 14) {
                    if viewModel.playbackMode == .allScenes {
                        viewModel.stopAllScenes()
                    } else {
                        viewModel.stop()
                    }
                }
                
                // Play All Scenes
                if let project = viewModel.currentProject, project.sceneCount > 1 {
                    PlaybackButton(
                        icon: viewModel.playbackMode == .allScenes ? "play.rectangle.on.rectangle.fill" : "play.rectangle.on.rectangle",
                        size: 14,
                        isAccent: viewModel.playbackMode == .allScenes
                    ) {
                        if viewModel.playbackMode == .allScenes {
                            viewModel.stopAllScenes()
                        } else {
                            viewModel.playAllScenes()
                        }
                    }
                    .help("Play All Scenes")
                }
            }
            
            Rectangle()
                .fill(AppTheme.Colors.border)
                .frame(width: 1, height: 24)
            
            // Export button
            if viewModel.isExporting {
                HStack(spacing: AppTheme.Spacing.sm) {
                    // Progress bar
                    if let progress = viewModel.exportService.progress, progress.totalFrames > 0 {
                        ProgressView(value: progress.percentage)
                            .progressViewStyle(.linear)
                            .tint(AppTheme.Colors.primary)
                            .frame(width: 80)
                    } else {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.6)
                            .tint(AppTheme.Colors.primary)
                    }
                    
                    Text(viewModel.exportPhase)
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                    
                    // Cancel button
                    Button(action: {
                        viewModel.cancelExport()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button(action: {
                    viewModel.startExport()
                }) {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .medium))
                        Text("Export")
                            .font(AppTheme.Typography.captionMedium)
                    }
                    .foregroundColor(viewModel.sceneState.objects.isEmpty ? AppTheme.Colors.textTertiary : .white)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.full)
                            .fill(viewModel.sceneState.objects.isEmpty ? AppTheme.Colors.background : AppTheme.Colors.primary)
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.sceneState.objects.isEmpty)
                .onHover { hovering in
                    isExportHovering = hovering
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.xl)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(AppTheme.Colors.surface)
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let frames = Int((time.truncatingRemainder(dividingBy: 1)) * 60)
        return String(format: "%d:%02d:%02d", minutes, seconds, frames)
    }
}

// MARK: - Time Display

struct TimeDisplay: View {
    let time: Double
    
    var body: some View {
        Text(formatTime(time))
            .font(AppTheme.Typography.mono)
            .foregroundColor(AppTheme.Colors.textSecondary)
            .frame(width: 70)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.xxs)
            .background(AppTheme.Colors.backgroundSecondary)
            .cornerRadius(AppTheme.Radius.sm)
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let frames = Int((time.truncatingRemainder(dividingBy: 1)) * 60)
        return String(format: "%d:%02d:%02d", minutes, seconds, frames)
    }
}

// MARK: - Playback Button

struct PlaybackButton: View {
    let icon: String
    var size: CGFloat = 16
    var isAccent: Bool = false
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        isAccent 
                            ? (isHovering ? AppTheme.Colors.primary.opacity(0.15) : AppTheme.Colors.primary.opacity(0.1))
                            : (isHovering ? AppTheme.Colors.background : Color.clear)
                    )
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: size, weight: .semibold))
                    .foregroundColor(isAccent ? AppTheme.Colors.primary : AppTheme.Colors.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(AppTheme.Animation.quick) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Exportable Scene View (for video rendering)

struct ExportableSceneView: View {
    let sceneState: SceneState
    let currentTime: Double
    /// Pre-rendered 3D model snapshots keyed by object UUID.
    /// ImageRenderer cannot capture NSViewRepresentable (SceneKit) content,
    /// so 3D models are rendered offscreen via SCNRenderer and composited as images.
    var model3DSnapshots: [UUID: NSImage] = [:]
    /// Pre-rendered Metal shader snapshots keyed by object UUID.
    /// ImageRenderer cannot capture NSViewRepresentable (MTKView) content,
    /// so shaders are rendered offscreen via Metal and composited as images.
    var shaderSnapshots: [UUID: NSImage] = [:]
    
    var body: some View {
        ZStack {
            // Background
            Rectangle()
                .fill(sceneState.backgroundColor.color)
            
            // Render objects using the same ObjectRendererView
            ForEach(sceneState.objects.filter(\.isVisible).sorted(by: { $0.zIndex < $1.zIndex })) { object in
                ObjectRendererView(
                    object: object,
                    currentTime: currentTime,
                    sceneState: sceneState,
                    exportSnapshot: model3DSnapshots[object.id] ?? shaderSnapshots[object.id],
                    isPlaying: true
                )
            }
        }
        .frame(width: sceneState.canvasWidth, height: sceneState.canvasHeight)
        .clipped()
    }
}

// MARK: - Scene Navigator (Filmstrip)

struct SceneNavigatorView: View {
    @ObservedObject var viewModel: CanvasViewModel
    @State private var showAddScenePopover = false
    @State private var newSceneName = ""
    @State private var editingSceneId: String?
    @State private var editingName = ""
    
    private var scenes: [SceneFile] {
        viewModel.currentProject?.orderedScenes ?? []
    }
    
    private var currentIndex: Int {
        viewModel.currentSceneIndex
    }
    
    var body: some View {
        if scenes.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 0) {
                // Scene label
                HStack(spacing: AppTheme.Spacing.xs) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.Colors.textTertiary)
                    
                    Text("Scenes")
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.textTertiary)
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                
                Rectangle()
                    .fill(AppTheme.Colors.border)
                    .frame(width: 1, height: 28)
                
                // Scene thumbnails
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(Array(scenes.enumerated()), id: \.element.id) { index, scene in
                            SceneThumbnailView(
                                scene: scene,
                                index: index,
                                isActive: index == currentIndex,
                                isEditing: editingSceneId == scene.id,
                                editingName: $editingName,
                                onSelect: {
                                    viewModel.switchScene(to: index)
                                },
                                onRename: { newName in
                                    viewModel.projectManager?.renameScene(withId: scene.id, to: newName)
                                    editingSceneId = nil
                                },
                                onStartEditing: {
                                    editingSceneId = scene.id
                                    editingName = scene.name
                                },
                                onDelete: {
                                    if scenes.count > 1 {
                                        viewModel.deleteScene(withId: scene.id)
                                    }
                                },
                                onDuplicate: {
                                    viewModel.projectManager?.duplicateScene(withId: scene.id)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.sm)
                }
                
                Rectangle()
                    .fill(AppTheme.Colors.border)
                    .frame(width: 1, height: 28)
                
                // Add scene button
                Button(action: {
                    let _ = viewModel.addNewScene()
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                                .fill(AppTheme.Colors.background)
                        )
                }
                .buttonStyle(.plain)
                .help("Add Scene")
                .padding(.horizontal, AppTheme.Spacing.sm)
            }
            .frame(height: 44)
            .background(AppTheme.Colors.surface)
        }
    }
}

// MARK: - Scene Thumbnail

struct SceneThumbnailView: View {
    let scene: SceneFile
    let index: Int
    let isActive: Bool
    let isEditing: Bool
    @Binding var editingName: String
    let onSelect: () -> Void
    let onRename: (String) -> Void
    let onStartEditing: () -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: AppTheme.Spacing.xs) {
                // Scene number badge
                Text("\(index + 1)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(isActive ? AppTheme.Colors.primary : AppTheme.Colors.textTertiary)
                    .frame(width: 16, height: 16)
                    .background(
                        Circle()
                            .fill(isActive ? AppTheme.Colors.primary.opacity(0.1) : AppTheme.Colors.background)
                    )
                
                // Scene name
                if isEditing {
                    TextField("Name", text: $editingName, onCommit: {
                        onRename(editingName)
                    })
                    .textFieldStyle(.plain)
                    .font(AppTheme.Typography.captionMedium)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                    .frame(maxWidth: 100)
                } else {
                    Text(scene.name)
                        .font(AppTheme.Typography.captionMedium)
                        .foregroundColor(isActive ? AppTheme.Colors.textPrimary : AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                }
                
                // Duration
                Text(String(format: "%.1fs", scene.duration))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(AppTheme.Colors.textTertiary)
            }
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .fill(isActive ? AppTheme.Colors.primary.opacity(0.08) :
                          (isHovering ? AppTheme.Colors.background : AppTheme.Colors.surfaceHover))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .strokeBorder(isActive ? AppTheme.Colors.primary.opacity(0.3) : AppTheme.Colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(AppTheme.Animation.quick) {
                isHovering = hovering
            }
        }
        .contextMenu {
            Button("Rename") {
                onStartEditing()
            }
            Button("Duplicate") {
                onDuplicate()
            }
            Divider()
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    CanvasView(viewModel: CanvasViewModel())
        .frame(width: 900, height: 700)
}
