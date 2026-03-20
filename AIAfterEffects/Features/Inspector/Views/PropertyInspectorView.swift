//
//  PropertyInspectorView.swift
//  AIAfterEffects
//
//  Property inspector panel showing all JSON properties of the selected object
//  with editable fields grouped into collapsible sections. Changes are applied
//  to the scene and persisted to project.json on "Apply".
//

import SwiftUI
import AppKit

// MARK: - Property Inspector View

struct PropertyInspectorView: View {
    @ObservedObject var viewModel: CanvasViewModel
    
    /// Local draft of properties being edited (isolated from scene until Apply)
    @State private var draft: ObjectProperties = ObjectProperties()
    @State private var draftName: String = ""
    @State private var draftZIndex: String = "0"
    /// Tracks whether the draft has unsaved changes
    @State private var isDirty: Bool = false
    /// Baseline snapshot for robust dirty-state recomputation
    @State private var baselineDraft: ObjectProperties = ObjectProperties()
    @State private var baselineName: String = ""
    @State private var baselineZIndex: Int = 0
    /// Which object this draft was loaded from
    @State private var loadedObjectId: UUID? = nil
    /// Suppresses auto-reload while user is actively editing
    @State private var isUserEditing: Bool = false
    /// Suppresses markDirty() during programmatic draft loads
    @State private var isLoadingDraft: Bool = false
    
    // Section expand/collapse state
    @State private var showTransform = true
    @State private var showAppearance = true
    @State private var showEffects = false
    @State private var showTypeSpecific = true
    @State private var showAnimations = false
    @State private var showMeta = false
    
    /// Whether we're at a non-zero time (showing animated values)
    private var isAtAnimatedTime: Bool {
        viewModel.currentTime > 0.001
    }
    
    /// Whether inspector is scoped to a selected animation track.
    private var isAnimationMode: Bool {
        viewModel.selectedAnimationId != nil
    }
    
    private var showObjectModeKeyButtons: Bool {
        isAtAnimatedTime && !isAnimationMode
    }
    
    /// True when the selected keyframe is on the current playhead frame.
    private var isUpdatingSelectedKeyframe: Bool {
        viewModel.isSelectedKeyframeAtCurrentTime()
    }
    
    private var applyButtonTitle: String {
        guard isAtAnimatedTime, isAnimationMode else { return "Apply" }
        return isUpdatingSelectedKeyframe ? "Update Keyframe" : "Add Keyframe"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            inspectorHeader
            ThemedDivider()
            
            // Time indicator when scrubbing
            if isAtAnimatedTime, viewModel.selectedObject != nil {
                timeIndicatorBar
            }
            
            if let object = viewModel.selectedObject {
                // Two modes: Animation-scoped vs Full Object
                if let selAnimId = viewModel.selectedAnimationId,
                   let selAnim = object.animations.first(where: { $0.id == selAnimId }) {
                    // ── ANIMATION MODE: show only properties relevant to this animation ──
                    animationInspectorContent(object: object, animation: selAnim)
                } else {
                    // ── OBJECT MODE: show all properties ──
                    objectInspectorContent(object: object)
                }
            } else {
                noSelectionView
            }
        }
        .background(AppTheme.Colors.surface)
    }
    
    // MARK: - Object Inspector (full properties)
    
    private func objectInspectorContent(object: SceneObject) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                metaSection(object)
                transformSection(object)
                appearanceSection(object)
                typeSpecificSection(object)
                effectsSection(object)
                animationsSection(object)
                actionButtons(object)
            }
            .padding(.bottom, AppTheme.Spacing.xl)
        }
        .onChange(of: viewModel.selectedObjectId) { _, newId in
            loadDraft(for: newId)
        }
        .onChange(of: viewModel.currentTime) { _, _ in
            if !isUserEditing {
                loadDraft(for: viewModel.selectedObjectId)
            }
        }
        .onChange(of: viewModel.selectedAnimationId) { _, _ in
            // When switching from animation mode back to object mode, reload
            loadDraft(for: viewModel.selectedObjectId)
        }
        .onChange(of: viewModel.gizmoPropertyChangeCounter) { _, _ in
            // Live-update the inspector while the user drags gizmo handles
            if !isUserEditing {
                loadDraft(for: viewModel.selectedObjectId)
            }
        }
        .onAppear {
            loadDraft(for: viewModel.selectedObjectId)
        }
    }
    
    // MARK: - Animation Inspector (scoped to selected animation track)
    
    private func animationInspectorContent(object: SceneObject, animation: AnimationDefinition) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                // Animation header
                animationHeaderSection(animation)
                
                // Keyframe list for this animation
                keyframeListSection(object: object, animation: animation)
                
                // Only show the properties this animation controls
                let controlledProps = CanvasViewModel.propertiesControlledBy(animation.type)
                if controlledProps.isEmpty {
                    // Fallback: show all editable properties
                    transformSection(object)
                    appearanceSection(object)
                } else {
                    animationScopedProperties(controlledProps)
                }
                
                // Apply / Revert buttons
                actionButtons(object)
            }
            .padding(.bottom, AppTheme.Spacing.xl)
        }
        .onChange(of: viewModel.selectedObjectId) { _, newId in
            loadDraft(for: newId)
        }
        .onChange(of: viewModel.selectedAnimationId) { _, newId in
            loadDraft(for: viewModel.selectedObjectId)
        }
        .onChange(of: viewModel.currentTime) { _, _ in
            if !isUserEditing {
                loadDraft(for: viewModel.selectedObjectId)
            }
        }
        .onChange(of: viewModel.selectedKeyframeId) { _, _ in
            if !isUserEditing {
                loadDraft(for: viewModel.selectedObjectId)
            }
        }
        .onChange(of: viewModel.gizmoPropertyChangeCounter) { _, _ in
            // Live-update the inspector while the user drags gizmo handles
            if !isUserEditing {
                loadDraft(for: viewModel.selectedObjectId)
            }
        }
        .onAppear {
            loadDraft(for: viewModel.selectedObjectId)
        }
    }
    
    // MARK: - Animation Header
    
    private func animationHeaderSection(_ animation: AnimationDefinition) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: AppTheme.Spacing.xs) {
                Circle()
                    .fill(animationColor(animation.type))
                    .frame(width: 8, height: 8)
                
                Text(animation.type.rawValue)
                    .font(AppTheme.Typography.captionMedium)
                    .foregroundColor(AppTheme.Colors.primary)
                
                Spacer()
                
                // Back to object mode button
                Button(action: {
                    viewModel.selectedAnimationId = nil
                    viewModel.selectedKeyframeId = nil
                }) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 8, weight: .bold))
                        Text("Object")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(AppTheme.Colors.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppTheme.Colors.backgroundSecondary)
                    .cornerRadius(AppTheme.Radius.xs)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(AppTheme.Colors.primary.opacity(0.08))
            
            // Animation timing info
            HStack(spacing: AppTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start").font(.system(size: 8)).foregroundColor(AppTheme.Colors.textTertiary)
                    Text(String(format: "%.2fs", animation.startTime))
                        .font(AppTheme.Typography.mono)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Duration").font(.system(size: 8)).foregroundColor(AppTheme.Colors.textTertiary)
                    Text(String(format: "%.2fs", animation.duration))
                        .font(AppTheme.Typography.mono)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Easing").font(.system(size: 8)).foregroundColor(AppTheme.Colors.textTertiary)
                    Text(animation.easing.rawValue)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.xs)
            
            ThemedDivider()
        }
    }
    
    // MARK: - Keyframe List
    
    private func keyframeListSection(object: SceneObject, animation: AnimationDefinition) -> some View {
        InspectorSection(title: "Keyframes (\(animation.keyframes.count))", icon: "diamond", isExpanded: .constant(true)) {
            if animation.keyframes.isEmpty {
                Text("No keyframes — scrub to a time and edit a property to add one")
                    .font(.system(size: 9))
                    .foregroundColor(AppTheme.Colors.textTertiary)
                    .padding(.vertical, AppTheme.Spacing.xs)
            } else {
                VStack(spacing: 2) {
                    ForEach(animation.keyframes.sorted(by: { $0.time < $1.time })) { kf in
                        let absoluteTime = animation.startTime + animation.delay + kf.time * animation.duration
                        let isKfSelected = viewModel.selectedKeyframeId == kf.id
                        
                        HStack(spacing: AppTheme.Spacing.xs) {
                            // Diamond icon
                            Image(systemName: "diamond.fill")
                                .font(.system(size: 7))
                                .foregroundColor(isKfSelected ? .yellow : .white.opacity(0.6))
                            
                            // Time
                            Text(String(format: "%.2fs", absoluteTime))
                                .font(AppTheme.Typography.mono)
                                .foregroundColor(isKfSelected ? AppTheme.Colors.primary : AppTheme.Colors.textSecondary)
                            
                            Spacer()
                            
                            // Value
                            Text(keyframeValueLabel(kf.value))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(AppTheme.Colors.textTertiary)
                                .lineLimit(1)
                            
                            // Delete button
                            Button(action: {
                                viewModel.deleteKeyframe(object.id, animationId: animation.id, keyframeId: kf.id)
                                if viewModel.selectedKeyframeId == kf.id {
                                    viewModel.selectedKeyframeId = nil
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(AppTheme.Colors.textTertiary.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, AppTheme.Spacing.xs)
                        .padding(.vertical, 3)
                        .background(isKfSelected ? AppTheme.Colors.primary.opacity(0.12) : Color.clear)
                        .cornerRadius(AppTheme.Radius.xs)
                        .onTapGesture {
                            viewModel.selectKeyframe(kf.id, animationId: animation.id, objectId: object.id)
                        }
                    }
                }
            }
        }
    }
    
    private func keyframeValueLabel(_ value: KeyframeValue) -> String {
        switch value {
        case .double(let v): return String(format: "%.2f", v)
        case .point(let x, let y): return "(\(String(format: "%.1f", x)), \(String(format: "%.1f", y)))"
        case .scale(let x, let y): return "S(\(String(format: "%.2f", x)), \(String(format: "%.2f", y)))"
        case .color(let c): return "RGB(\(Int(c.red*255)),\(Int(c.green*255)),\(Int(c.blue*255)))"
        }
    }
    
    // MARK: - Animation-Scoped Properties
    
    /// Shows only the property fields that the selected animation controls
    private func animationScopedProperties(_ props: Set<String>) -> some View {
        InspectorSection(title: "Animated Properties", icon: "slider.horizontal.3", isExpanded: .constant(true)) {
            VStack(spacing: AppTheme.Spacing.xs) {
                if props.contains("opacity") {
                    NumberField(label: "Opacity", value: $draft.opacity, onChange: markDirty)
                }
                if props.contains("fillColor") {
                    InspectorRow(label: "Fill") {
                        ColorPicker("", selection: Binding(
                            get: { draft.fillColor.color },
                            set: { newColor in
                                if let components = NSColor(newColor).usingColorSpace(.sRGB) {
                                    draft.fillColor = CodableColor(
                                        red: Double(components.redComponent),
                                        green: Double(components.greenComponent),
                                        blue: Double(components.blueComponent),
                                        alpha: Double(components.alphaComponent)
                                    )
                                    markDirty()
                                }
                            }
                        ))
                        .labelsHidden()
                    }
                }
                if props.contains("strokeColor") {
                    InspectorRow(label: "Stroke") {
                        ColorPicker("", selection: Binding(
                            get: { draft.strokeColor.color },
                            set: { newColor in
                                if let components = NSColor(newColor).usingColorSpace(.sRGB) {
                                    draft.strokeColor = CodableColor(
                                        red: Double(components.redComponent),
                                        green: Double(components.greenComponent),
                                        blue: Double(components.blueComponent),
                                        alpha: Double(components.alphaComponent)
                                    )
                                    markDirty()
                                }
                            }
                        ))
                        .labelsHidden()
                    }
                }
                if props.contains("x") {
                    NumberField(label: "X", value: $draft.x, onChange: markDirty)
                }
                if props.contains("y") {
                    NumberField(label: "Y", value: $draft.y, onChange: markDirty)
                }
                if props.contains("scaleX") {
                    NumberField(label: "ScaleX", value: $draft.scaleX, onChange: markDirty)
                }
                if props.contains("scaleY") {
                    NumberField(label: "ScaleY", value: $draft.scaleY, onChange: markDirty)
                }
                if props.contains("rotation") {
                    NumberField(label: "Rot", value: $draft.rotation, onChange: markDirty)
                }
                if props.contains("blurRadius") {
                    NumberField(label: "Blur", value: $draft.blurRadius, onChange: markDirty)
                }
                if props.contains("strokeWidth") {
                    NumberField(label: "Stroke W", value: $draft.strokeWidth, onChange: markDirty)
                }
                if props.contains("trimStart") {
                    OptionalNumberField(label: "Trim Start", value: $draft.trimStart, onChange: markDirty)
                }
                if props.contains("trimEnd") {
                    OptionalNumberField(label: "Trim End", value: $draft.trimEnd, onChange: markDirty)
                }
                if props.contains("trimOffset") {
                    OptionalNumberField(label: "Trim Ofs", value: $draft.trimOffset, onChange: markDirty)
                }
                if props.contains("dashPhase") {
                    OptionalNumberField(label: "Dash Ofs", value: $draft.dashPhase, onChange: markDirty)
                }
                if props.contains("brightness") {
                    NumberField(label: "Bright", value: $draft.brightness, onChange: markDirty)
                }
                if props.contains("contrast") {
                    NumberField(label: "Contrast", value: $draft.contrast, onChange: markDirty)
                }
                if props.contains("saturation") {
                    NumberField(label: "Satur.", value: $draft.saturation, onChange: markDirty)
                }
                if props.contains("hueRotation") {
                    NumberField(label: "Hue", value: $draft.hueRotation, onChange: markDirty)
                }
                if props.contains("grayscale") {
                    NumberField(label: "Gray", value: $draft.grayscale, onChange: markDirty)
                }
                if props.contains("shadowRadius") {
                    NumberField(label: "Shd.R", value: $draft.shadowRadius, onChange: markDirty)
                }
                if props.contains("position3DX") {
                    OptionalNumberField(label: "Pos X", value: $draft.position3DX, onChange: markDirty)
                }
                if props.contains("position3DY") {
                    OptionalNumberField(label: "Pos Y", value: $draft.position3DY, onChange: markDirty)
                }
                if props.contains("position3DZ") {
                    OptionalNumberField(label: "Pos Z", value: $draft.position3DZ, onChange: markDirty)
                }
                if props.contains("rotationX") {
                    OptionalNumberField(label: "RotX", value: $draft.rotationX, onChange: markDirty)
                }
                if props.contains("rotationY") {
                    OptionalNumberField(label: "RotY", value: $draft.rotationY, onChange: markDirty)
                }
                if props.contains("rotationZ") {
                    OptionalNumberField(label: "RotZ", value: $draft.rotationZ, onChange: markDirty)
                }
                if props.contains("cameraDistance") {
                    OptionalNumberField(label: "Cam Dist", value: $draft.cameraDistance, onChange: markDirty)
                }
                if props.contains("cameraAngleX") {
                    OptionalNumberField(label: "Cam AngX", value: $draft.cameraAngleX, onChange: markDirty)
                }
                if props.contains("cameraAngleY") {
                    OptionalNumberField(label: "Cam AngY", value: $draft.cameraAngleY, onChange: markDirty)
                }
                if props.contains("scaleZ") {
                    OptionalNumberField(label: "Scale Z", value: $draft.scaleZ, onChange: markDirty)
                }
                if props.contains("fontSize") {
                    OptionalNumberField(label: "Size", value: $draft.fontSize, onChange: markDirty)
                }
            }
        }
    }
    
    // MARK: - Time Indicator
    
    private var timeIndicatorBar: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: "clock")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(AppTheme.Colors.warning)
            
            Text("@ \(String(format: "%.2f", viewModel.currentTime))s")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(AppTheme.Colors.warning)
            
            Spacer()
            
            Text(isDirty ? (isAnimationMode ? "Edit → Apply to keyframe" : "Edit → Apply to object") : "Showing animated values")
                .font(.system(size: 9))
                .foregroundColor(AppTheme.Colors.textTertiary)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, 4)
        .background(AppTheme.Colors.warning.opacity(0.08))
    }
    
    // MARK: - Header
    
    private var inspectorHeader: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: viewModel.selectedAnimationId != nil ? "waveform.path" : "slider.horizontal.3")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(viewModel.selectedAnimationId != nil ? AppTheme.Colors.primary : AppTheme.Colors.textTertiary)
            
            Text(viewModel.selectedAnimationId != nil ? "Animation Inspector" : "Inspector")
                .font(AppTheme.Typography.captionMedium)
                .foregroundColor(viewModel.selectedAnimationId != nil ? AppTheme.Colors.primary : AppTheme.Colors.textSecondary)
            
            Spacer()
            
            if viewModel.selectedKeyframeId != nil {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 7))
                    .foregroundColor(.yellow)
                    .help("Keyframe selected")
            }
            
            if isDirty {
                Circle()
                    .fill(AppTheme.Colors.warning)
                    .frame(width: 6, height: 6)
                    .help("Unsaved changes")
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
    }
    
    // MARK: - No Selection
    
    private var noSelectionView: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Spacer()
            Image(systemName: "cursorarrow.click.2")
                .font(.system(size: 24))
                .foregroundColor(AppTheme.Colors.textTertiary)
            Text("No Selection")
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.Colors.textTertiary)
            Text("Select an object on the canvas\nor in the timeline")
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.Colors.textTertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Load Draft
    
    private func loadDraft(for objectId: UUID?) {
        guard let id = objectId,
              let object = viewModel.sceneState.objects.first(where: { $0.id == id }) else {
            loadedObjectId = nil
            return
        }
        
        // Suppress markDirty() calls from NumberField onChange chains
        isLoadingDraft = true
        
        // If at a non-zero time, show animated (interpolated) values
        if viewModel.currentTime > 0.001,
           let animated = viewModel.computeAnimatedProperties(for: id, at: viewModel.currentTime) {
            draft = animated
        } else {
            draft = object.properties
        }
        
        // In animation/keyframe edit mode, prefer the selected keyframe's raw value for
        // opacity channels. This avoids showing a composited value from other opacity
        // animations (which makes the field appear to "snap back" after update).
        applySelectedKeyframeDraftOverrides()
        
        draftName = object.name
        draftZIndex = "\(object.zIndex)"
        baselineDraft = draft
        baselineName = draftName
        baselineZIndex = object.zIndex
        loadedObjectId = id
        isDirty = false
        isUserEditing = false
        
        // Re-enable markDirty after SwiftUI processes the binding updates
        DispatchQueue.main.async {
            isLoadingDraft = false
        }
    }
    
    private func applySelectedKeyframeDraftOverrides() {
        guard let anim = viewModel.selectedAnimation,
              let kf = viewModel.selectedKeyframe else { return }
        
        // Opacity-style tracks store absolute opacity values in keyframes.
        let opacityTracks: Set<AnimationType> = [.fadeIn, .fadeOut, .fade, .flicker, .flash, .neonFlicker, .materialFade]
        if opacityTracks.contains(anim.type),
           case .double(let v) = kf.value {
            draft.opacity = max(0, min(1, v))
        }
    }
    
    private func markDirty() {
        // Don't mark dirty during programmatic draft loads
        guard !isLoadingDraft else { return }
        recomputeDirtyState()
        isUserEditing = isDirty
    }
    
    private func recomputeDirtyState() {
        let propertiesChanged = draft != baselineDraft
        let nameChanged = draftName != baselineName
        let zChanged: Bool = {
            guard let parsed = Int(draftZIndex) else { return true } // invalid value should remain dirty
            return parsed != baselineZIndex
        }()
        
        isDirty = propertiesChanged || nameChanged || zChanged
    }
    
    private func objectModeKeyframeAction(
        _ object: SceneObject,
        property: String,
        value: @escaping () -> Double
    ) -> (() -> Void)? {
        guard showObjectModeKeyButtons, !object.isLocked else { return nil }
        return {
            NSApp.keyWindow?.makeFirstResponder(nil)
            viewModel.addKeyframeForProperty(object.id, property: property, value: value(), at: viewModel.currentTime)
            loadDraft(for: object.id)
        }
    }
    
    private func objectModeOptionalKeyframeAction(
        _ object: SceneObject,
        property: String,
        value: @escaping () -> Double?
    ) -> (() -> Void)? {
        guard showObjectModeKeyButtons, !object.isLocked else { return nil }
        return {
            guard let resolvedValue = value() else { return }
            NSApp.keyWindow?.makeFirstResponder(nil)
            viewModel.addKeyframeForProperty(object.id, property: property, value: resolvedValue, at: viewModel.currentTime)
            loadDraft(for: object.id)
        }
    }
    
    private func objectModeKeyButtonState(_ object: SceneObject, property: String) -> (show: Bool, enabled: Bool) {
        guard showObjectModeKeyButtons else { return (false, false) }
        let enabled = !object.isLocked && viewModel.canKeyframeProperty(property, for: object)
        return (true, enabled)
    }
    
    // MARK: - Meta Section
    
    private func metaSection(_ object: SceneObject) -> some View {
        InspectorSection(title: "Object", icon: "info.circle", isExpanded: $showMeta) {
            VStack(spacing: AppTheme.Spacing.xs) {
                InspectorRow(label: "ID") {
                    Text(object.id.uuidString.prefix(8) + "...")
                        .font(AppTheme.Typography.mono)
                        .foregroundColor(AppTheme.Colors.textTertiary)
                        .lineLimit(1)
                }
                
                InspectorRow(label: "Type") {
                    Text(object.type.rawValue)
                        .font(AppTheme.Typography.mono)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                
                InspectorRow(label: "Name") {
                    TextField("Name", text: $draftName)
                        .textFieldStyle(.plain)
                        .font(AppTheme.Typography.caption)
                        .onChange(of: draftName) { _, _ in markDirty() }
                }
                
                InspectorRow(label: "Z-Index") {
                    TextField("0", text: $draftZIndex)
                        .textFieldStyle(.plain)
                        .font(AppTheme.Typography.mono)
                        .frame(width: 50)
                        .onChange(of: draftZIndex) { _, _ in markDirty() }
                }
            }
        }
    }
    
    // MARK: - Transform Section
    
    private func transformSection(_ object: SceneObject) -> some View {
        let xKf = objectModeKeyButtonState(object, property: "x")
        let yKf = objectModeKeyButtonState(object, property: "y")
        let wKf = objectModeKeyButtonState(object, property: "width")
        let hKf = objectModeKeyButtonState(object, property: "height")
        let rotKf = objectModeKeyButtonState(object, property: "rotation")
        let sxKf = objectModeKeyButtonState(object, property: "scaleX")
        let syKf = objectModeKeyButtonState(object, property: "scaleY")
        let axKf = objectModeKeyButtonState(object, property: "anchorX")
        let ayKf = objectModeKeyButtonState(object, property: "anchorY")
        return InspectorSection(title: "Transform", icon: "arrow.up.and.down.and.arrow.left.and.right", isExpanded: $showTransform) {
            VStack(spacing: AppTheme.Spacing.xs) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    NumberField(label: "X", value: $draft.x, onChange: markDirty, onAddKeyframe: objectModeKeyframeAction(object, property: "x", value: { draft.x }), showKeyframeButton: xKf.show, isKeyframeEnabled: xKf.enabled)
                    NumberField(label: "Y", value: $draft.y, onChange: markDirty, onAddKeyframe: objectModeKeyframeAction(object, property: "y", value: { draft.y }), showKeyframeButton: yKf.show, isKeyframeEnabled: yKf.enabled)
                }
                HStack(spacing: AppTheme.Spacing.sm) {
                    NumberField(label: "W", value: $draft.width, onChange: markDirty, showKeyframeButton: wKf.show, isKeyframeEnabled: wKf.enabled)
                    NumberField(label: "H", value: $draft.height, onChange: markDirty, showKeyframeButton: hKf.show, isKeyframeEnabled: hKf.enabled)
                }
                HStack(spacing: AppTheme.Spacing.sm) {
                    NumberField(label: "Rot", value: $draft.rotation, onChange: markDirty, onAddKeyframe: objectModeKeyframeAction(object, property: "rotation", value: { draft.rotation }), showKeyframeButton: rotKf.show, isKeyframeEnabled: rotKf.enabled)
                    NumberField(label: "SX", value: $draft.scaleX, onChange: markDirty, onAddKeyframe: objectModeKeyframeAction(object, property: "scaleX", value: { draft.scaleX }), showKeyframeButton: sxKf.show, isKeyframeEnabled: sxKf.enabled)
                }
                HStack(spacing: AppTheme.Spacing.sm) {
                    NumberField(label: "SY", value: $draft.scaleY, onChange: markDirty, onAddKeyframe: objectModeKeyframeAction(object, property: "scaleY", value: { draft.scaleY }), showKeyframeButton: syKf.show, isKeyframeEnabled: syKf.enabled)
                    NumberField(label: "AX", value: $draft.anchorX, onChange: markDirty, showKeyframeButton: axKf.show, isKeyframeEnabled: axKf.enabled)
                }
                NumberField(label: "AY", value: $draft.anchorY, onChange: markDirty, showKeyframeButton: ayKf.show, isKeyframeEnabled: ayKf.enabled)
            }
        }
    }
    
    // MARK: - Appearance Section
    
    private func appearanceSection(_ object: SceneObject) -> some View {
        let fillKf = objectModeKeyButtonState(object, property: "fillColor")
        let strokeKf = objectModeKeyButtonState(object, property: "strokeColor")
        let strokeWKf = objectModeKeyButtonState(object, property: "strokeWidth")
        let opacityKf = objectModeKeyButtonState(object, property: "opacity")
        let radiusKf = objectModeKeyButtonState(object, property: "cornerRadius")
        return InspectorSection(title: "Appearance", icon: "paintpalette", isExpanded: $showAppearance) {
            VStack(spacing: AppTheme.Spacing.xs) {
                InspectorRow(label: "Fill") {
                    HStack(spacing: 6) {
                        ColorPicker("", selection: Binding(
                            get: { draft.fillColor.color },
                            set: { newColor in
                                if let components = NSColor(newColor).usingColorSpace(.sRGB) {
                                    draft.fillColor = CodableColor(
                                        red: Double(components.redComponent),
                                        green: Double(components.greenComponent),
                                        blue: Double(components.blueComponent),
                                        alpha: Double(components.alphaComponent)
                                    )
                                    markDirty()
                                }
                            }
                        ))
                        .labelsHidden()
                        
                        if fillKf.show {
                            Button(action: {
                                NSApp.keyWindow?.makeFirstResponder(nil)
                                viewModel.addKeyframeForColorProperty(object.id, property: "fillColor", value: draft.fillColor, at: viewModel.currentTime)
                                loadDraft(for: object.id)
                            }) {
                                Image(systemName: "diamond.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(fillKf.enabled ? AppTheme.Colors.warning : AppTheme.Colors.textTertiary.opacity(0.5))
                                    .frame(width: 16, height: 16)
                            }
                            .buttonStyle(.plain)
                            .disabled(!fillKf.enabled)
                            .help(fillKf.enabled ? "Add keyframe for Fill" : "Keyframing is not available for Fill yet")
                        }
                    }
                }
                
                InspectorRow(label: "Stroke") {
                    HStack(spacing: 6) {
                        ColorPicker("", selection: Binding(
                            get: { draft.strokeColor.color },
                            set: { newColor in
                                if let components = NSColor(newColor).usingColorSpace(.sRGB) {
                                    draft.strokeColor = CodableColor(
                                        red: Double(components.redComponent),
                                        green: Double(components.greenComponent),
                                        blue: Double(components.blueComponent),
                                        alpha: Double(components.alphaComponent)
                                    )
                                    markDirty()
                                }
                            }
                        ))
                        .labelsHidden()
                        
                        if strokeKf.show {
                            Button(action: {
                                NSApp.keyWindow?.makeFirstResponder(nil)
                                viewModel.addKeyframeForColorProperty(object.id, property: "strokeColor", value: draft.strokeColor, at: viewModel.currentTime)
                                loadDraft(for: object.id)
                            }) {
                                Image(systemName: "diamond.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(strokeKf.enabled ? AppTheme.Colors.warning : AppTheme.Colors.textTertiary.opacity(0.5))
                                    .frame(width: 16, height: 16)
                            }
                            .buttonStyle(.plain)
                            .disabled(!strokeKf.enabled)
                            .help(strokeKf.enabled ? "Add keyframe for Stroke" : "Keyframing is not available for Stroke yet")
                        }
                    }
                }
                
                NumberField(label: "Stroke W", value: $draft.strokeWidth, onChange: markDirty, onAddKeyframe: objectModeKeyframeAction(object, property: "strokeWidth", value: { draft.strokeWidth }), showKeyframeButton: strokeWKf.show, isKeyframeEnabled: strokeWKf.enabled)
                
                HStack(spacing: AppTheme.Spacing.sm) {
                    NumberField(label: "Opacity", value: $draft.opacity, onChange: markDirty, onAddKeyframe: objectModeKeyframeAction(object, property: "opacity", value: { draft.opacity }), showKeyframeButton: opacityKf.show, isKeyframeEnabled: opacityKf.enabled)
                    NumberField(label: "Radius", value: $draft.cornerRadius, onChange: markDirty, showKeyframeButton: radiusKf.show, isKeyframeEnabled: radiusKf.enabled)
                }
            }
        }
    }
    
    // MARK: - Effects Section
    
    private func effectsSection(_ object: SceneObject) -> some View {
        let blurKf = objectModeKeyButtonState(object, property: "blurRadius")
        let brightKf = objectModeKeyButtonState(object, property: "brightness")
        let contrastKf = objectModeKeyButtonState(object, property: "contrast")
        let satKf = objectModeKeyButtonState(object, property: "saturation")
        let hueKf = objectModeKeyButtonState(object, property: "hueRotation")
        let grayKf = objectModeKeyButtonState(object, property: "grayscale")
        let shdRKf = objectModeKeyButtonState(object, property: "shadowRadius")
        let shdXKf = objectModeKeyButtonState(object, property: "shadowOffsetX")
        let shdYKf = objectModeKeyButtonState(object, property: "shadowOffsetY")
        return InspectorSection(title: "Visual Effects", icon: "wand.and.stars", isExpanded: $showEffects) {
            VStack(spacing: AppTheme.Spacing.xs) {
                NumberField(label: "Blur", value: $draft.blurRadius, onChange: markDirty, onAddKeyframe: objectModeKeyframeAction(object, property: "blurRadius", value: { draft.blurRadius }), showKeyframeButton: blurKf.show, isKeyframeEnabled: blurKf.enabled)
                HStack(spacing: AppTheme.Spacing.sm) {
                    NumberField(label: "Bright", value: $draft.brightness, onChange: markDirty, onAddKeyframe: objectModeKeyframeAction(object, property: "brightness", value: { draft.brightness }), showKeyframeButton: brightKf.show, isKeyframeEnabled: brightKf.enabled)
                    NumberField(label: "Contrast", value: $draft.contrast, onChange: markDirty, onAddKeyframe: objectModeKeyframeAction(object, property: "contrast", value: { draft.contrast }), showKeyframeButton: contrastKf.show, isKeyframeEnabled: contrastKf.enabled)
                }
                HStack(spacing: AppTheme.Spacing.sm) {
                    NumberField(label: "Satur.", value: $draft.saturation, onChange: markDirty, onAddKeyframe: objectModeKeyframeAction(object, property: "saturation", value: { draft.saturation }), showKeyframeButton: satKf.show, isKeyframeEnabled: satKf.enabled)
                    NumberField(label: "Hue", value: $draft.hueRotation, onChange: markDirty, onAddKeyframe: objectModeKeyframeAction(object, property: "hueRotation", value: { draft.hueRotation }), showKeyframeButton: hueKf.show, isKeyframeEnabled: hueKf.enabled)
                }
                HStack(spacing: AppTheme.Spacing.sm) {
                    NumberField(label: "Gray", value: $draft.grayscale, onChange: markDirty, onAddKeyframe: objectModeKeyframeAction(object, property: "grayscale", value: { draft.grayscale }), showKeyframeButton: grayKf.show, isKeyframeEnabled: grayKf.enabled)
                    NumberField(label: "Shd.R", value: $draft.shadowRadius, onChange: markDirty, onAddKeyframe: objectModeKeyframeAction(object, property: "shadowRadius", value: { draft.shadowRadius }), showKeyframeButton: shdRKf.show, isKeyframeEnabled: shdRKf.enabled)
                }
                HStack(spacing: AppTheme.Spacing.sm) {
                    NumberField(label: "Shd.X", value: $draft.shadowOffsetX, onChange: markDirty, showKeyframeButton: shdXKf.show, isKeyframeEnabled: shdXKf.enabled)
                    NumberField(label: "Shd.Y", value: $draft.shadowOffsetY, onChange: markDirty, showKeyframeButton: shdYKf.show, isKeyframeEnabled: shdYKf.enabled)
                }
                
                InspectorRow(label: "Invert") {
                    Toggle("", isOn: Binding(
                        get: { draft.colorInvert },
                        set: { draft.colorInvert = $0; markDirty() }
                    ))
                    .toggleStyle(.switch)
                    .scaleEffect(0.7)
                }
            }
        }
    }
    
    // MARK: - Type-Specific Section
    
    @ViewBuilder
    private func typeSpecificSection(_ object: SceneObject) -> some View {
        switch object.type {
        case .text:
            let sizeKf = objectModeKeyButtonState(object, property: "fontSize")
            InspectorSection(title: "Text", icon: "textformat", isExpanded: $showTypeSpecific) {
                VStack(spacing: AppTheme.Spacing.xs) {
                    InspectorRow(label: "Text") {
                        TextField("Text", text: Binding(
                            get: { draft.text ?? "" },
                            set: { draft.text = $0; markDirty() }
                        ))
                        .textFieldStyle(.plain)
                        .font(AppTheme.Typography.caption)
                    }
                    OptionalNumberField(label: "Size", value: $draft.fontSize, onChange: markDirty, onAddKeyframe: objectModeOptionalKeyframeAction(object, property: "fontSize", value: { draft.fontSize }), showKeyframeButton: sizeKf.show, isKeyframeEnabled: sizeKf.enabled)
                    InspectorRow(label: "Font") {
                        TextField("Font", text: Binding(
                            get: { draft.fontName ?? "" },
                            set: { draft.fontName = $0.isEmpty ? nil : $0; markDirty() }
                        ))
                        .textFieldStyle(.plain)
                        .font(AppTheme.Typography.caption)
                    }
                    InspectorRow(label: "Weight") {
                        TextField("regular", text: Binding(
                            get: { draft.fontWeight ?? "" },
                            set: { draft.fontWeight = $0.isEmpty ? nil : $0; markDirty() }
                        ))
                        .textFieldStyle(.plain)
                        .font(AppTheme.Typography.caption)
                    }
                    InspectorRow(label: "Align") {
                        TextField("center", text: Binding(
                            get: { draft.textAlignment ?? "" },
                            set: { draft.textAlignment = $0.isEmpty ? nil : $0; markDirty() }
                        ))
                        .textFieldStyle(.plain)
                        .font(AppTheme.Typography.caption)
                    }
                }
            }
            
        case .polygon:
            let sidesKf = objectModeKeyButtonState(object, property: "sides")
            InspectorSection(title: "Polygon", icon: "pentagon", isExpanded: $showTypeSpecific) {
                OptionalIntField(label: "Sides", value: $draft.sides, onChange: markDirty, showKeyframeButton: sidesKf.show, isKeyframeEnabled: sidesKf.enabled)
            }
            
        case .model3D:
            let posXKf = objectModeKeyButtonState(object, property: "position3DX")
            let posYKf = objectModeKeyButtonState(object, property: "position3DY")
            let posZKf = objectModeKeyButtonState(object, property: "position3DZ")
            let rotXKf = objectModeKeyButtonState(object, property: "rotationX")
            let rotYKf = objectModeKeyButtonState(object, property: "rotationY")
            let rotZKf = objectModeKeyButtonState(object, property: "rotationZ")
            let scaleZKf = objectModeKeyButtonState(object, property: "scaleZ")
            let camDistKf = objectModeKeyButtonState(object, property: "cameraDistance")
            let camXKf = objectModeKeyButtonState(object, property: "cameraAngleX")
            let camYKf = objectModeKeyButtonState(object, property: "cameraAngleY")
            InspectorSection(title: "3D Model", icon: "cube", isExpanded: $showTypeSpecific) {
                VStack(spacing: AppTheme.Spacing.xs) {
                    InspectorRow(label: "Asset") {
                        Text(draft.modelAssetId ?? "none")
                            .font(AppTheme.Typography.mono)
                            .foregroundColor(AppTheme.Colors.textTertiary)
                            .lineLimit(1)
                    }
                    OptionalNumberField(label: "Pos X", value: $draft.position3DX, onChange: markDirty, onAddKeyframe: objectModeOptionalKeyframeAction(object, property: "position3DX", value: { draft.position3DX }), showKeyframeButton: posXKf.show, isKeyframeEnabled: posXKf.enabled)
                    OptionalNumberField(label: "Pos Y", value: $draft.position3DY, onChange: markDirty, onAddKeyframe: objectModeOptionalKeyframeAction(object, property: "position3DY", value: { draft.position3DY }), showKeyframeButton: posYKf.show, isKeyframeEnabled: posYKf.enabled)
                    OptionalNumberField(label: "Pos Z", value: $draft.position3DZ, onChange: markDirty, onAddKeyframe: objectModeOptionalKeyframeAction(object, property: "position3DZ", value: { draft.position3DZ }), showKeyframeButton: posZKf.show, isKeyframeEnabled: posZKf.enabled)
                    OptionalNumberField(label: "Rot X", value: $draft.rotationX, onChange: markDirty, onAddKeyframe: objectModeOptionalKeyframeAction(object, property: "rotationX", value: { draft.rotationX }), showKeyframeButton: rotXKf.show, isKeyframeEnabled: rotXKf.enabled)
                    OptionalNumberField(label: "Rot Y", value: $draft.rotationY, onChange: markDirty, onAddKeyframe: objectModeOptionalKeyframeAction(object, property: "rotationY", value: { draft.rotationY }), showKeyframeButton: rotYKf.show, isKeyframeEnabled: rotYKf.enabled)
                    OptionalNumberField(label: "Rot Z", value: $draft.rotationZ, onChange: markDirty, onAddKeyframe: objectModeOptionalKeyframeAction(object, property: "rotationZ", value: { draft.rotationZ }), showKeyframeButton: rotZKf.show, isKeyframeEnabled: rotZKf.enabled)
                    OptionalNumberField(label: "Scale Z", value: $draft.scaleZ, onChange: markDirty, onAddKeyframe: objectModeOptionalKeyframeAction(object, property: "scaleZ", value: { draft.scaleZ }), showKeyframeButton: scaleZKf.show, isKeyframeEnabled: scaleZKf.enabled)
                    OptionalNumberField(label: "Cam Dist", value: $draft.cameraDistance, onChange: markDirty, onAddKeyframe: objectModeOptionalKeyframeAction(object, property: "cameraDistance", value: { draft.cameraDistance }), showKeyframeButton: camDistKf.show, isKeyframeEnabled: camDistKf.enabled)
                    OptionalNumberField(label: "Cam X", value: $draft.cameraAngleX, onChange: markDirty, onAddKeyframe: objectModeOptionalKeyframeAction(object, property: "cameraAngleX", value: { draft.cameraAngleX }), showKeyframeButton: camXKf.show, isKeyframeEnabled: camXKf.enabled)
                    OptionalNumberField(label: "Cam Y", value: $draft.cameraAngleY, onChange: markDirty, onAddKeyframe: objectModeOptionalKeyframeAction(object, property: "cameraAngleY", value: { draft.cameraAngleY }), showKeyframeButton: camYKf.show, isKeyframeEnabled: camYKf.enabled)
                    OptionalNumberField(label: "Cam Pan X", value: $draft.cameraTargetX, onChange: markDirty)
                    OptionalNumberField(label: "Cam Pan Y", value: $draft.cameraTargetY, onChange: markDirty)
                    OptionalNumberField(label: "Cam Pan Z", value: $draft.cameraTargetZ, onChange: markDirty)
                    InspectorRow(label: "Lighting") {
                        TextField("studio", text: Binding(
                            get: { draft.environmentLighting ?? "" },
                            set: { draft.environmentLighting = $0.isEmpty ? nil : $0; markDirty() }
                        ))
                        .textFieldStyle(.plain)
                        .font(AppTheme.Typography.caption)
                    }
                }
            }
            
        case .shader:
            let p1Kf = objectModeKeyButtonState(object, property: "shaderParam1")
            let p2Kf = objectModeKeyButtonState(object, property: "shaderParam2")
            let p3Kf = objectModeKeyButtonState(object, property: "shaderParam3")
            let p4Kf = objectModeKeyButtonState(object, property: "shaderParam4")
            InspectorSection(title: "Shader", icon: "sparkles", isExpanded: $showTypeSpecific) {
                VStack(spacing: AppTheme.Spacing.xs) {
                    InspectorRow(label: "Code") {
                        Text(draft.shaderCode != nil ? "\(draft.shaderCode!.count) chars" : "none")
                            .font(AppTheme.Typography.mono)
                            .foregroundColor(AppTheme.Colors.textTertiary)
                    }
                    OptionalNumberField(label: "Param 1", value: $draft.shaderParam1, onChange: markDirty, showKeyframeButton: p1Kf.show, isKeyframeEnabled: p1Kf.enabled)
                    OptionalNumberField(label: "Param 2", value: $draft.shaderParam2, onChange: markDirty, showKeyframeButton: p2Kf.show, isKeyframeEnabled: p2Kf.enabled)
                    OptionalNumberField(label: "Param 3", value: $draft.shaderParam3, onChange: markDirty, showKeyframeButton: p3Kf.show, isKeyframeEnabled: p3Kf.enabled)
                    OptionalNumberField(label: "Param 4", value: $draft.shaderParam4, onChange: markDirty, showKeyframeButton: p4Kf.show, isKeyframeEnabled: p4Kf.enabled)
                }
            }
            
        case .path, .line:
            let trimSKf = objectModeKeyButtonState(object, property: "trimStart")
            let trimEKf = objectModeKeyButtonState(object, property: "trimEnd")
            let trimOKf = objectModeKeyButtonState(object, property: "trimOffset")
            let dashKf = objectModeKeyButtonState(object, property: "dashPhase")
            InspectorSection(title: object.type == .path ? "Path" : "Line", icon: "point.topleft.down.to.point.bottomright.curvepath", isExpanded: $showTypeSpecific) {
                VStack(spacing: AppTheme.Spacing.xs) {
                    OptionalNumberField(label: "Trim Start", value: $draft.trimStart, onChange: markDirty, onAddKeyframe: objectModeOptionalKeyframeAction(object, property: "trimStart", value: { draft.trimStart }), showKeyframeButton: trimSKf.show, isKeyframeEnabled: trimSKf.enabled)
                    OptionalNumberField(label: "Trim End", value: $draft.trimEnd, onChange: markDirty, onAddKeyframe: objectModeOptionalKeyframeAction(object, property: "trimEnd", value: { draft.trimEnd }), showKeyframeButton: trimEKf.show, isKeyframeEnabled: trimEKf.enabled)
                    OptionalNumberField(label: "Trim Offset", value: $draft.trimOffset, onChange: markDirty, onAddKeyframe: objectModeOptionalKeyframeAction(object, property: "trimOffset", value: { draft.trimOffset }), showKeyframeButton: trimOKf.show, isKeyframeEnabled: trimOKf.enabled)
                    OptionalNumberField(label: "Dash Offset", value: $draft.dashPhase, onChange: markDirty, onAddKeyframe: objectModeOptionalKeyframeAction(object, property: "dashPhase", value: { draft.dashPhase }), showKeyframeButton: dashKf.show, isKeyframeEnabled: dashKf.enabled)
                    if object.type == .path {
                        InspectorRow(label: "Close") {
                            Toggle("", isOn: Binding(
                                get: { draft.closePath ?? false },
                                set: { draft.closePath = $0; markDirty() }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                        }
                    }
                    InspectorRow(label: "Cap") {
                        TextField("round", text: Binding(
                            get: { draft.lineCap ?? "" },
                            set: { draft.lineCap = $0.isEmpty ? nil : $0; markDirty() }
                        ))
                        .textFieldStyle(.plain)
                        .font(AppTheme.Typography.caption)
                    }
                    InspectorRow(label: "Join") {
                        TextField("round", text: Binding(
                            get: { draft.lineJoin ?? "" },
                            set: { draft.lineJoin = $0.isEmpty ? nil : $0; markDirty() }
                        ))
                        .textFieldStyle(.plain)
                        .font(AppTheme.Typography.caption)
                    }
                }
            }
            
        case .icon:
            InspectorSection(title: "Icon", icon: "star.fill", isExpanded: $showTypeSpecific) {
                VStack(spacing: AppTheme.Spacing.xs) {
                    InspectorRow(label: "Name") {
                        TextField("star.fill", text: Binding(
                            get: { draft.iconName ?? "" },
                            set: { draft.iconName = $0.isEmpty ? nil : $0; markDirty() }
                        ))
                        .textFieldStyle(.plain)
                        .font(AppTheme.Typography.caption)
                    }
                    OptionalNumberField(label: "Size", value: $draft.iconSize, onChange: markDirty)
                }
            }
            
        case .image:
            InspectorSection(title: "Image", icon: "photo", isExpanded: $showTypeSpecific) {
                InspectorRow(label: "Data") {
                    Text(draft.imageData != nil ? "attached" : "none")
                        .font(AppTheme.Typography.mono)
                        .foregroundColor(AppTheme.Colors.textTertiary)
                }
            }
            
        default:
            EmptyView()
        }
    }
    
    // MARK: - Animations Summary
    
    private func animationsSection(_ object: SceneObject) -> some View {
        InspectorSection(title: "Animations (\(object.animations.count))", icon: "waveform.path", isExpanded: $showAnimations) {
            if object.animations.isEmpty {
                Text("No animations")
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.textTertiary)
                    .padding(.vertical, AppTheme.Spacing.xs)
            } else {
                VStack(spacing: AppTheme.Spacing.xxs) {
                    ForEach(object.animations) { anim in
                        HStack(spacing: AppTheme.Spacing.xs) {
                            Circle()
                                .fill(animationColor(anim.type))
                                .frame(width: 6, height: 6)
                            
                            Text(anim.type.rawValue)
                                .font(AppTheme.Typography.caption)
                                .foregroundColor(AppTheme.Colors.textSecondary)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text(String(format: "%.1fs", anim.startTime))
                                .font(AppTheme.Typography.mono)
                                .foregroundColor(AppTheme.Colors.textTertiary)
                            
                            Text(String(format: "%.1fs", anim.duration))
                                .font(AppTheme.Typography.mono)
                                .foregroundColor(AppTheme.Colors.textTertiary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }
    
    private func animationColor(_ type: AnimationType) -> Color {
        switch type {
        case .moveX, .moveY, .move, .slideIn, .slideOut, .dropIn, .riseUp:
            return .blue
        case .fadeIn, .fadeOut, .fade, .colorChange:
            return .green
        case .scale, .scaleX, .scaleY, .rotate, .spin, .grow, .shrink:
            return .orange
        default:
            return .purple
        }
    }
    
    // MARK: - Action Buttons
    
    private func actionButtons(_ object: SceneObject) -> some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            ThemedDivider()
            
            HStack(spacing: AppTheme.Spacing.sm) {
                // Revert button
                Button(action: {
                    loadDraft(for: object.id)
                }) {
                    Text("Revert")
                        .font(AppTheme.Typography.captionMedium)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.sm)
                        .background(AppTheme.Colors.backgroundSecondary)
                        .cornerRadius(AppTheme.Radius.sm)
                }
                .buttonStyle(.plain)
                .disabled(!isDirty)
                .opacity(isDirty ? 1 : 0.5)
                
                // Apply button (shows keyframe context when at animated time)
                Button(action: {
                    // Commit any active text edits and release field focus so
                    // timeline keyboard shortcuts (e.g. Delete keyframe) work immediately.
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    applyChanges(to: object.id)
                }) {
                    HStack(spacing: 4) {
                        if isAtAnimatedTime && isAnimationMode {
                            Image(systemName: "diamond.fill")
                                .font(.system(size: 8))
                        }
                        Text(applyButtonTitle)
                            .font(AppTheme.Typography.captionMedium)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.sm)
                    .background(isDirty ? ((isAtAnimatedTime && isAnimationMode) ? AppTheme.Colors.warning : AppTheme.Colors.primary) : AppTheme.Colors.textTertiary)
                    .cornerRadius(AppTheme.Radius.sm)
                }
                .buttonStyle(.plain)
                .disabled(!isDirty || object.isLocked)
                .opacity(isDirty && !object.isLocked ? 1 : 0.5)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.sm)
            
            if object.isLocked {
                HStack(spacing: AppTheme.Spacing.xxs) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                    Text("Object is locked")
                        .font(AppTheme.Typography.caption)
                }
                .foregroundColor(AppTheme.Colors.warning)
                .padding(.bottom, AppTheme.Spacing.sm)
            }
        }
    }
    
    // MARK: - Apply Changes
    
    private func applyChanges(to objectId: UUID) {
        // In animation mode, apply edits to keyframes.
        // In object mode, apply base properties only; per-property diamonds handle keyframing.
        if isAtAnimatedTime && isAnimationMode {
            viewModel.smartApplyProperties(objectId, draft: draft, at: viewModel.currentTime)
        } else {
            viewModel.applyObjectProperties(objectId, properties: draft)
        }
        
        // Apply name if changed
        if let object = viewModel.sceneState.objects.first(where: { $0.id == objectId }),
           object.name != draftName {
            viewModel.renameObject(objectId, to: draftName)
        }
        
        // Apply zIndex if changed
        if let newZ = Int(draftZIndex) {
            viewModel.reorderObject(objectId, toZIndex: newZ)
        }
        
        isDirty = false
        isUserEditing = false
    }
}

// MARK: - Inspector Section (Collapsible)

struct InspectorSection<Content: View>: View {
    let title: String
    let icon: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(spacing: 0) {
            // Section header
            Button(action: {
                withAnimation(AppTheme.Animation.quick) { isExpanded.toggle() }
            }) {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppTheme.Colors.textTertiary)
                        .frame(width: 14)
                    
                    Text(title)
                        .font(AppTheme.Typography.captionMedium)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(AppTheme.Colors.textTertiary)
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)
                .background(AppTheme.Colors.backgroundSecondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            
            // Content
            if isExpanded {
                VStack(spacing: AppTheme.Spacing.xs) {
                    content
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)
            }
            
            ThemedDivider(opacity: 0.5)
        }
    }
}

// MARK: - Inspector Row

struct InspectorRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text(label)
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.Colors.textTertiary)
                .frame(width: 55, alignment: .trailing)
            
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Number Field

struct NumberField: View {
    let label: String
    @Binding var value: Double
    var onChange: () -> Void = {}
    var onAddKeyframe: (() -> Void)? = nil
    var showKeyframeButton: Bool = false
    var isKeyframeEnabled: Bool = true
    
    @State private var text: String = ""
    private let labelWidth: CGFloat = 44
    
    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.Colors.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: labelWidth, alignment: .trailing)
            
            TextField("0", text: $text)
                .textFieldStyle(.plain)
                .font(AppTheme.Typography.mono)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(AppTheme.Colors.backgroundSecondary)
                .cornerRadius(AppTheme.Radius.xs)
                .onAppear { text = formatNumber(value) }
                .onChange(of: value) { _, newVal in text = formatNumber(newVal) }
                .onChange(of: text) { _, newText in
                    if let parsed = Double(newText), parsed != value {
                        value = parsed
                        onChange()
                    }
                }
            
            if showKeyframeButton {
                Button(action: { onAddKeyframe?() }) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 9))
                        .foregroundColor(isKeyframeEnabled ? AppTheme.Colors.warning : AppTheme.Colors.textTertiary.opacity(0.5))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .disabled(!isKeyframeEnabled)
                .help("Add keyframe for \(label)")
            }
        }
    }
    
    private func formatNumber(_ v: Double) -> String {
        if v == v.rounded() { return String(format: "%.0f", v) }
        return String(format: "%.2f", v)
    }
}

// MARK: - Optional Number Field

struct OptionalNumberField: View {
    let label: String
    @Binding var value: Double?
    var onChange: () -> Void = {}
    var onAddKeyframe: (() -> Void)? = nil
    var showKeyframeButton: Bool = false
    var isKeyframeEnabled: Bool = true
    
    @State private var text: String = ""
    private let labelWidth: CGFloat = 55
    
    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.Colors.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: labelWidth, alignment: .trailing)
            
            TextField("--", text: $text)
                .textFieldStyle(.plain)
                .font(AppTheme.Typography.mono)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(AppTheme.Colors.backgroundSecondary)
                .cornerRadius(AppTheme.Radius.xs)
                .onAppear { text = value.map { formatNumber($0) } ?? "" }
                .onChange(of: value) { _, newVal in text = newVal.map { formatNumber($0) } ?? "" }
                .onChange(of: text) { _, newText in
                    if newText.isEmpty {
                        if value != nil { value = nil; onChange() }
                    } else if let parsed = Double(newText), parsed != value {
                        value = parsed
                        onChange()
                    }
                }
            
            if showKeyframeButton {
                Button(action: { onAddKeyframe?() }) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 9))
                        .foregroundColor(isKeyframeEnabled ? AppTheme.Colors.warning : AppTheme.Colors.textTertiary.opacity(0.5))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .disabled(!isKeyframeEnabled)
                .help("Add keyframe for \(label)")
            }
        }
    }
    
    private func formatNumber(_ v: Double) -> String {
        if v == v.rounded() { return String(format: "%.0f", v) }
        return String(format: "%.2f", v)
    }
}

// MARK: - Optional Int Field

struct OptionalIntField: View {
    let label: String
    @Binding var value: Int?
    var onChange: () -> Void = {}
    var showKeyframeButton: Bool = false
    var isKeyframeEnabled: Bool = true
    
    @State private var text: String = ""
    private let labelWidth: CGFloat = 55
    
    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.Colors.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: labelWidth, alignment: .trailing)
            
            TextField("--", text: $text)
                .textFieldStyle(.plain)
                .font(AppTheme.Typography.mono)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(AppTheme.Colors.backgroundSecondary)
                .cornerRadius(AppTheme.Radius.xs)
                .onAppear { text = value.map { "\($0)" } ?? "" }
                .onChange(of: value) { _, newVal in text = newVal.map { "\($0)" } ?? "" }
                .onChange(of: text) { _, newText in
                    if newText.isEmpty {
                        if value != nil { value = nil; onChange() }
                    } else if let parsed = Int(newText), parsed != value {
                        value = parsed
                        onChange()
                    }
                }
            
            if showKeyframeButton {
                Button(action: {}) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 9))
                        .foregroundColor(isKeyframeEnabled ? AppTheme.Colors.warning : AppTheme.Colors.textTertiary.opacity(0.5))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .disabled(true)
                .help("Keyframing is not available for \(label) yet")
            }
        }
    }
}
