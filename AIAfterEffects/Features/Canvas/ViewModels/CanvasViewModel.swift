//
//  CanvasViewModel.swift
//  AIAfterEffects
//
//  ViewModel for canvas and animation state
//

import Foundation
import SwiftUI
import Combine
import AppKit

/// Playback mode for the canvas
enum PlaybackMode {
    /// Play only the current scene (loops)
    case singleScene
    /// Play all scenes sequentially with transitions
    case allScenes
}

@MainActor
class CanvasViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var sceneState: SceneState
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var playbackSpeed: Double = 1.0
    
    /// Resolved timing offsets for objects with timing dependencies.
    /// Maps object UUID → effective start offset in seconds.
    @Published var resolvedTimingOffsets: [UUID: Double] = [:]
    
    // MARK: - Multi-Scene Playback
    
    /// Playback mode: play single scene or all scenes sequentially
    @Published var playbackMode: PlaybackMode = .singleScene
    /// During multi-scene playback, tracks the currently playing scene index
    @Published var playbackSceneIndex: Int = 0
    /// Crossfade progress: 0 = only outgoing visible, 1 = only incoming visible
    @Published var transitionProgress: Double = 1.0
    /// Whether a transition is currently active
    @Published var isTransitioning: Bool = false
    /// The outgoing scene's state during a crossfade transition
    @Published var outgoingSceneState: SceneState?
    /// The active transition type for rendering
    @Published var activeTransitionType: TransitionType = .crossfade
    /// Duration of the current transition in seconds
    private var transitionDuration: Double = 0.8
    
    // MARK: - Gizmo
    
    /// The active gizmo transform mode (move / scale / rotate)
    @Published var gizmoMode: GizmoMode = .move
    /// Whether the user is in 3D edit mode for a selected model3D object
    @Published var is3DEditMode: Bool = false
    /// Incremented every time a gizmo drag updates properties.
    /// Observers (e.g. PropertyInspector) can watch this to live-update.
    @Published var gizmoPropertyChangeCounter: Int = 0
    
    // MARK: - Selection & Editing
    
    /// Currently selected object in the canvas / layer panel / timeline
    @Published var selectedObjectId: UUID? = nil
    
    /// Currently selected animation track in the timeline (sub-track click)
    /// When set, the inspector shows only properties relevant to this animation.
    @Published var selectedAnimationId: UUID? = nil
    
    /// Currently selected keyframe diamond (click on diamond)
    /// When set, the inspector highlights this keyframe's value.
    @Published var selectedKeyframeId: UUID? = nil
    
    /// Timeline undo/redo availability (for menus and UI states).
    @Published private(set) var canUndoTimeline: Bool = false
    @Published private(set) var canRedoTimeline: Bool = false
    
    // MARK: - Export Properties
    
    @Published var isExporting: Bool = false
    @Published var exportProgress: Double = 0
    @Published var exportPhase: String = ""
    
    let exportService = VideoExportService()
    
    // MARK: - Animation Timer
    
    private var displayLink: CVDisplayLink?
    private var animationTimer: AnyCancellable?
    private var lastFrameTime: CFTimeInterval = 0
    
    // MARK: - Project Properties
    
    /// Reference to the project manager for multi-scene support
    weak var projectManager: ProjectManager?
    
    /// Current project (convenience accessor)
    var currentProject: Project? { projectManager?.currentProject }
    
    /// Current scene index
    var currentSceneIndex: Int { projectManager?.currentSceneIndex ?? 0 }
    
    // MARK: - Callbacks
    
    /// Called when canvas dimensions change from the UI (dimension picker)
    var onSceneStateChanged: ((SceneState) -> Void)?
    
    // Auto layout helpers (reset per command batch)
    private var autoTextIndex: Int = 0
    private var autoLayoutObjectNames: Set<String> = []
    private var commandAttachments: [ChatAttachment] = []
    
    // MARK: - Dependencies
    
    private let animationEngine: AnimationEngine
    private let lineAnimationService: LineAnimationServiceProtocol
    private let mathAnimationService: MathAnimationServiceProtocol
    
    // MARK: - Timeline History
    
    private struct TimelineHistorySnapshot: Equatable {
        var sceneState: SceneState
        var currentTime: Double
        var selectedObjectId: UUID?
        var selectedAnimationId: UUID?
        var selectedKeyframeId: UUID?
    }
    
    private var timelineUndoStack: [TimelineHistorySnapshot] = []
    private var timelineRedoStack: [TimelineHistorySnapshot] = []
    private var activeTimelineTransactionStart: TimelineHistorySnapshot?
    private let maxTimelineHistoryDepth: Int = 200
    
    // MARK: - Init
    
    init(
        sceneState: SceneState = SceneState(),
        animationEngine: AnimationEngine = AnimationEngine(),
        lineAnimationService: LineAnimationServiceProtocol = LineAnimationService.shared,
        mathAnimationService: MathAnimationServiceProtocol = MathAnimationService.shared
    ) {
        self.sceneState = sceneState
        self.animationEngine = animationEngine
        self.lineAnimationService = lineAnimationService
        self.mathAnimationService = mathAnimationService
    }
    
    // MARK: - Playback Controls
    
    func play() {
        guard !isPlaying else { return }
        isPlaying = true
        startAnimationLoop()
    }
    
    func pause() {
        isPlaying = false
        stopAnimationLoop()
    }
    
    func stop() {
        isPlaying = false
        stopAnimationLoop()
        currentTime = 0
    }
    
    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func restart() {
        currentTime = 0
        if !isPlaying {
            play()
        }
    }
    
    // MARK: - Animation Loop
    
    private func startAnimationLoop() {
        lastFrameTime = CACurrentMediaTime()
        
        // Use a timer for animation updates (60fps)
        animationTimer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateAnimation()
            }
    }
    
    private func stopAnimationLoop() {
        animationTimer?.cancel()
        animationTimer = nil
    }
    
    // MARK: - Export
    
    func startExport() {
        // Show save panel
        guard let outputURL = exportService.showSavePanel() else {
            return
        }
        
        // Stop playback during export
        pause()
        
        Task { @MainActor in
            isExporting = true
            exportPhase = "Loading fonts..."
            exportProgress = 0
            
            // Preload all fonts used in the scene before exporting
            await preloadAllFonts()
            
            // Give fonts a moment to register with the system
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            
            exportPhase = "Preparing..."
            
            let config = ExportConfiguration.fromScene(sceneState, outputURL: outputURL)
            
            // Dump the full scene JSON at render start for debugging
            dumpSceneJSON(reason: "export_start")
            
            // Observe export service progress to keep phase text in sync
            let progressObserver = exportService.objectWillChange.sink { [weak self] _ in
                Task { @MainActor in
                    guard let self = self, let p = self.exportService.progress else { return }
                    self.exportProgress = p.percentage
                    switch p.phase {
                    case .preparing:
                        self.exportPhase = "Preparing..."
                    case .rendering:
                        self.exportPhase = "Rendering \(p.currentFrame)/\(p.totalFrames)"
                    case .finishing:
                        self.exportPhase = "Finishing..."
                    case .completed:
                        self.exportPhase = "Completed!"
                    case .failed(let msg):
                        self.exportPhase = "Failed: \(msg)"
                    }
                }
            }
            
            do {
                // Export uses ImageRenderer to render the exact same SwiftUI
                // views shown on screen — pixel-perfect match guaranteed.
                // Metal-backed CIContext accelerates CGImage → pixel buffer.
                try await exportService.exportScene(
                    sceneState: sceneState,
                    config: config
                )
                
                exportPhase = "Completed!"
                exportProgress = 1.0
                
                // Open in Finder
                NSWorkspace.shared.selectFile(outputURL.path, inFileViewerRootedAtPath: outputURL.deletingLastPathComponent().path)
                
            } catch {
                exportPhase = "Failed: \(error.localizedDescription)"
                DebugLogger.shared.error("Export failed: \(error.localizedDescription)", category: .app)
            }
            
            progressObserver.cancel()
            
            // Reset after a delay
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            isExporting = false
            exportProgress = 0
            exportPhase = ""
        }
    }
    
    func cancelExport() {
        exportService.cancelExport()
    }
    
    private func dumpSceneJSON(reason: String) {
        let logger = DebugLogger.shared
        let fileManager = FileManager.default
        
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            logger.warning("Export JSON: Could not find documents directory", category: .app)
            return
        }
        
        let logsDirectory = documentsPath.appendingPathComponent("AIAfterEffects_Logs", isDirectory: true)
        if !fileManager.fileExists(atPath: logsDirectory.path) {
            try? fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let fileName = "export_scene_\(reason)_\(timestamp).json"
        let outputURL = logsDirectory.appendingPathComponent(fileName)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        do {
            let data = try encoder.encode(sceneState)
            try data.write(to: outputURL, options: .atomic)
            logger.success("Export JSON saved: \(outputURL.path)", category: .app)
        } catch {
            logger.error("Export JSON failed: \(error.localizedDescription)", category: .app)
        }
    }
    
    /// Preload all fonts used in the scene
    private func preloadAllFonts() async {
        let logger = DebugLogger.shared
        
        // Collect all unique font names and weights from the scene
        var fontRequests: [(family: String, weight: String)] = []
        
        for object in sceneState.objects {
            if object.type == .text, let fontName = object.properties.fontName {
                let weight = object.properties.fontWeight ?? "Regular"
                // Only add if not a system font
                if fontName.lowercased() != "sf pro" {
                    fontRequests.append((fontName, weight))
                }
            }
        }
        
        // Remove duplicates
        var seenFonts: Set<String> = []
        fontRequests = fontRequests.filter { request in
            let key = "\(request.family)-\(request.weight)"
            if seenFonts.contains(key) {
                return false
            }
            seenFonts.insert(key)
            return true
        }
        
        logger.info("Preloading \(fontRequests.count) fonts for export...", category: .fonts)
        
        // Load all fonts sequentially to avoid race conditions
        for request in fontRequests {
            await GoogleFontsService.shared.ensureFontLoaded(family: request.family, weight: request.weight)
        }
        
        // Verify fonts are available
        let fontManager = NSFontManager.shared
        for request in fontRequests {
            let available = fontManager.availableFontFamilies.contains { $0.caseInsensitiveCompare(request.family) == .orderedSame }
            if available {
                logger.debug("Font '\(request.family)' verified available for export", category: .fonts)
            } else {
                logger.warning("Font '\(request.family)' NOT available after loading - will use fallback", category: .fonts)
            }
        }
        
        logger.success("Font preloading complete", category: .fonts)
    }
    
    private func updateAnimation() {
        guard isPlaying else { return }
        
        let now = CACurrentMediaTime()
        let delta = now - lastFrameTime
        lastFrameTime = now
        
        // During a transition, advance the crossfade progress each frame
        if isTransitioning {
            transitionProgress += delta / transitionDuration
            if transitionProgress >= 1.0 {
                // Transition complete — clean up
                transitionProgress = 1.0
                isTransitioning = false
                outgoingSceneState = nil
            }
        }
        
        // Update current time
        currentTime += delta * playbackSpeed
        
        if playbackMode == .allScenes {
            updateMultiScenePlayback()
        } else {
            // Single scene: loop when reaching the end
            if currentTime >= sceneState.duration {
                currentTime = 0
            }
        }
        
        // Trigger UI update
        objectWillChange.send()
    }
    
    // MARK: - Multi-Scene Playback
    
    /// Start playing all scenes sequentially
    func playAllScenes() {
        guard let pm = projectManager, pm.currentProject.sceneCount > 0 else { return }
        
        // Save current scene state first
        syncToProjectManager()
        
        playbackMode = .allScenes
        playbackSceneIndex = 0
        currentTime = 0
        outgoingSceneState = nil
        isTransitioning = false
        transitionProgress = 1.0
        
        // Sync the scene explorer pill to the first scene
        pm.switchToScene(at: 0)
        
        // Load the first scene
        let firstScene = pm.currentProject.orderedScenes[0]
        let state = firstScene.toSceneState(canvas: pm.currentProject.canvas)
        self.sceneState = state
        resolveTimingDependencies()
        
        play()
    }
    
    /// Stop multi-scene playback and return to single-scene mode
    func stopAllScenes() {
        stop()
        playbackMode = .singleScene
        outgoingSceneState = nil
        isTransitioning = false
        transitionProgress = 1.0
        
        // Reload the current editor scene
        if let pm = projectManager {
            loadSceneFile(pm.currentScene, canvas: pm.currentProject.canvas)
        }
    }
    
    /// Called each frame during multi-scene playback
    private func updateMultiScenePlayback() {
        guard let pm = projectManager else { return }
        let scenes = pm.currentProject.orderedScenes
        guard playbackSceneIndex < scenes.count else {
            stopAllScenes()
            return
        }
        
        let currentSceneDuration = sceneState.duration
        
        // Check if we need to transition to the next scene
        if currentTime >= currentSceneDuration && !isTransitioning {
            let nextIndex = playbackSceneIndex + 1
            
            if nextIndex >= scenes.count {
                // Last scene finished — stop
                stopAllScenes()
                return
            }
            
            // Get transition info
            let currentSceneId = scenes[playbackSceneIndex].id
            let nextSceneId = scenes[nextIndex].id
            let transition = pm.currentProject.transition(from: currentSceneId, to: nextSceneId)
            transitionDuration = transition?.duration ?? 0.8
            activeTransitionType = transition?.type ?? .crossfade
            
            // Snapshot the outgoing scene
            outgoingSceneState = sceneState
            
            // Load the incoming scene
            let nextScene = scenes[nextIndex]
            let nextState = nextScene.toSceneState(canvas: pm.currentProject.canvas)
            self.sceneState = nextState
            resolveTimingDependencies()
            
            playbackSceneIndex = nextIndex
            currentTime = 0
            
            // Sync the scene explorer pill to the now-playing scene
            pm.switchToScene(at: nextIndex)
            
            // Start the crossfade (progress goes 0 → 1 over transitionDuration)
            transitionProgress = 0
            isTransitioning = true
        }
    }
    
    // MARK: - Scene Commands Processing
    
    func processCommands(_ commands: SceneCommands, attachments: [ChatAttachment] = []) {
        let logger = DebugLogger.shared
        
        guard let actions = commands.actions, !actions.isEmpty else {
            logger.warning("No actions to process in commands", category: .canvas)
            return
        }
        
        if !attachments.isEmpty {
            commandAttachments = attachments
        }
        
        // Reset auto-layout state for this batch
        autoTextIndex = 0
        autoLayoutObjectNames.removeAll()
        
        logger.info("Processing \(actions.count) scene actions...", category: .canvas)
        
        for (_, action) in actions.enumerated() {
            let paramsJson = action.parameters.map { try? JSONEncoder().encode($0) }.flatMap { $0 }.map { String(data: $0, encoding: .utf8) } ?? nil
            logger.logSceneCommand(
                action: action.type.rawValue,
                target: action.target,
                parameters: paramsJson ?? nil
            )
            processAction(action)
        }
        
        logger.success("Finished processing. Scene now has \(sceneState.objects.count) objects", category: .canvas)
        
        // Apply auto-layout (timeline rows for text, grid for others)
        applyAutoLayout()

        // Compact z-indices (preserves AI's intended order)
        normalizeZIndices()
        
        // Auto-calculate scene duration based on animations
        updateSceneDurationFromAnimations()
        
        // Resolve timing dependencies (auto-shifts downstream objects)
        resolveTimingDependencies()
        
        // Warn about 3D models with very late entrance animations
        validate3DModelTiming()
        
        // Force UI update
        objectWillChange.send()
    }
    
    /// Calculate and update scene duration based on the longest animation end time
    private func updateSceneDurationFromAnimations() {
        let logger = DebugLogger.shared
        
        var maxEndTime: Double = 0
        
        for object in sceneState.objects {
            for animation in object.animations {
                // Calculate when this animation ends
                // For infinite/repeating animations, just use one cycle
                let effectiveDuration: Double
                if animation.repeatCount == -1 {
                    // Infinite loop - use single cycle duration
                    effectiveDuration = animation.duration
                } else if animation.repeatCount > 0 {
                    // Finite repeat - calculate total duration
                    let repeatMultiplier = Double(animation.repeatCount + 1)
                    effectiveDuration = animation.duration * repeatMultiplier
                } else {
                    // No repeat
                    effectiveDuration = animation.duration
                }
                
                // If autoReverse is on, double the duration
                let finalDuration = animation.autoReverse ? effectiveDuration * 2 : effectiveDuration
                
                // End time = startTime + delay + duration
                let endTime = animation.startTime + animation.delay + finalDuration
                maxEndTime = max(maxEndTime, endTime)
            }
        }
        
        // Add a small buffer at the end (1 second)
        let buffer: Double = 1.0
        let calculatedDuration = maxEndTime + buffer
        
        // Only EXTEND the scene duration, never shrink it.
        // This respects durations explicitly set by the AI agent or user.
        // If animations need more time, we expand; if a longer duration was set intentionally, we keep it.
        if maxEndTime > 0 && calculatedDuration > sceneState.duration {
            let previousDuration = sceneState.duration
            sceneState.duration = calculatedDuration
            
            logger.info("Scene duration auto-updated: \(String(format: "%.1f", previousDuration))s → \(String(format: "%.1f", sceneState.duration))s (based on animations)", category: .canvas)
        }
    }
    
    /// Validate 3D model timing: warn and auto-fix if entrance animations start too late
    private func validate3DModelTiming() {
        let logger = DebugLogger.shared
        let entranceTypes: Set<AnimationType> = [
            .scaleUp3D, .popIn3D, .tornado, .materialFade,
            .slamDown3D, .springBounce3D, .dropAndSettle, .corkscrew, .zigzagDrop, .unwrap
        ]
        
        for (idx, object) in sceneState.objects.enumerated() {
            guard object.type == .model3D else { continue }
            
            let entranceAnimations = object.animations.filter { entranceTypes.contains($0.type) }
            guard !entranceAnimations.isEmpty else {
                // No entrance animation — model will show from time 0, that's fine
                continue
            }
            
            let earliestStart = entranceAnimations.map { $0.startTime + $0.delay }.min() ?? 0
            
            let sceneDuration = max(sceneState.duration, 10.0)
            let lateThreshold = sceneDuration * 0.6
            
            if earliestStart > lateThreshold {
                logger.warning("⚠️ 3D model '\(object.name)' entrance starts at \(String(format: "%.1f", earliestStart))s (>\(String(format: "%.0f", lateThreshold))s = 60% of scene) — likely a bug. Auto-fixing.", category: .animation)
                
                let shift = earliestStart
                for (animIdx, anim) in sceneState.objects[idx].animations.enumerated() {
                    if entranceTypes.contains(anim.type) {
                        sceneState.objects[idx].animations[animIdx].startTime = max(0, anim.startTime - shift)
                    }
                }
                
                let cameraTypes: Set<AnimationType> = [
                    .cameraZoom, .cameraPan, .cameraOrbit, .spiralZoom, .dollyZoom,
                    .cameraRise, .cameraDive, .cameraWhipPan, .cameraSlide, .cameraArc,
                    .cameraPedestal, .cameraTruck, .cameraPushPull, .cameraDutchTilt,
                    .cameraHelicopter, .cameraRocket, .cameraShake
                ]
                for (animIdx, anim) in sceneState.objects[idx].animations.enumerated() {
                    if cameraTypes.contains(anim.type) && anim.startTime >= earliestStart - 1.0 {
                        sceneState.objects[idx].animations[animIdx].startTime = max(0, anim.startTime - shift)
                    }
                }
                
                logger.info("Auto-shifted 3D model '\(object.name)' entrance to start at 0s", category: .animation)
            } else if earliestStart > 1.0 {
                logger.debug("3D model '\(object.name)' entrance at \(String(format: "%.1f", earliestStart))s — intentional creative delay, keeping as-is", category: .animation)
            }
        }
    }
    
    private func processAction(_ action: SceneAction) {
        switch action.type {
        case .createObject:
            createObject(with: action.parameters)
            
        case .deleteObject:
            deleteObject(named: action.target)
            
        case .duplicateObject:
            duplicateObject(named: action.target)
            
        case .setProperty, .updateProperties:
            updateObject(named: action.target, with: action.parameters)
            
        case .addAnimation:
            addAnimation(to: action.target, with: action.parameters)
            
        case .removeAnimation:
            removeAnimation(from: action.target, animationType: action.parameters?.effectiveAnimationType)
            
        case .updateAnimation:
            updateAnimation(for: action.target, with: action.parameters)
            
        case .applyPreset:
            applyPreset(to: action.target, with: action.parameters)
            
        case .clearAnimations:
            clearAnimations(from: action.target)
            
        case .replaceAllAnimations:
            clearAnimations(from: action.target)
            addAnimation(to: action.target, with: action.parameters)
            
        case .applyEffect:
            applyProceduralEffect(action)
            
        case .applyShaderEffect:
            // Treat as createObject with shader type
            createObject(with: action.parameters)
            
        case .removeShaderEffect:
            // Treat as deleteObject targeting the shader
            deleteObject(named: action.target)
            
        case .clearScene:
            clearScene()
            
        case .setCanvasSize:
            setCanvasSize(action.parameters)
            
        case .setBackgroundColor:
            setBackgroundColor(action.parameters)
            
        case .setDuration:
            if let duration = action.parameters?.effectiveSceneDuration {
                sceneState.duration = duration
            }
            
        // Multi-scene actions
        case .createScene:
            handleCreateScene(action.parameters)
            
        case .deleteScene:
            handleDeleteScene(action.parameters)
            
        case .switchScene:
            handleSwitchScene(action.parameters, target: action.target)
            
        case .renameScene:
            handleRenameScene(action.parameters)
            
        case .setTransition:
            handleSetTransition(action.parameters)
            
        case .reorderScenes:
            handleReorderScenes(action.parameters)
        }
    }
    
    // MARK: - Multi-Scene Action Handlers
    
    private func handleCreateScene(_ parameters: ActionParameters?) {
        let logger = DebugLogger.shared
        let name = parameters?.effectiveSceneName ?? "Scene \((currentProject?.sceneCount ?? 0) + 1)"
        
        if let newScene = addNewScene(name: name) {
            logger.success("Created new scene '\(name)' (\(newScene.id))", category: .canvas)
        } else {
            logger.warning("Failed to create scene '\(name)'", category: .canvas)
        }
    }
    
    private func handleDeleteScene(_ parameters: ActionParameters?) {
        let logger = DebugLogger.shared
        
        if let sceneId = parameters?.effectiveSceneId {
            deleteScene(withId: sceneId)
            logger.success("Deleted scene \(sceneId)", category: .canvas)
        } else if let sceneName = parameters?.effectiveSceneName {
            // Find by name
            if let scene = currentProject?.orderedScenes.first(where: {
                $0.name.lowercased() == sceneName.lowercased()
            }) {
                deleteScene(withId: scene.id)
                logger.success("Deleted scene '\(sceneName)'", category: .canvas)
            }
        }
    }
    
    private func handleSwitchScene(_ parameters: ActionParameters?, target: String?) {
        let logger = DebugLogger.shared
        
        // Try scene ID first
        if let sceneId = parameters?.effectiveSceneId {
            switchScene(withId: sceneId)
            logger.success("Switched to scene \(sceneId)", category: .canvas)
            return
        }
        
        // Try scene name
        let sceneName = parameters?.effectiveSceneName ?? target
        if let name = sceneName {
            switchScene(named: name)
            logger.success("Switched to scene '\(name)'", category: .canvas)
        }
    }
    
    private func handleRenameScene(_ parameters: ActionParameters?) {
        guard let newName = parameters?.effectiveSceneName,
              let sceneId = parameters?.effectiveSceneId ?? currentProject?.orderedScenes[safe: currentSceneIndex]?.id else { return }
        
        projectManager?.renameScene(withId: sceneId, to: newName)
    }
    
    private func handleSetTransition(_ parameters: ActionParameters?) {
        guard let params = parameters,
              let project = currentProject else { return }
        
        // Resolve "from" scene: try ID first, then name lookup, then default to current scene
        let fromId: String? = params.fromSceneId
            ?? resolveSceneId(name: params.fromSceneName, in: project)
            ?? { () -> String? in
                // If only two scenes exist, default "from" to the first scene
                let scenes = project.orderedScenes
                return scenes.count == 2 ? scenes[0].id : nil
            }()
        
        // Resolve "to" scene: try ID first, then name lookup, then default to next scene
        let toId: String? = params.toSceneId
            ?? resolveSceneId(name: params.toSceneName, in: project)
            ?? { () -> String? in
                // If only two scenes exist, default "to" to the second scene
                let scenes = project.orderedScenes
                return scenes.count == 2 ? scenes[1].id : nil
            }()
        
        guard let fromId, let toId else { return }
        
        let type = params.effectiveTransitionType ?? .crossfade
        let duration = params.transitionDuration ?? 0.8
        
        projectManager?.setTransition(from: fromId, to: toId, type: type, duration: duration)
    }
    
    /// Resolve a scene name (or partial name) to a scene ID within the project
    private func resolveSceneId(name: String?, in project: Project) -> String? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        
        let scenes = project.orderedScenes
        let lower = name.lowercased()
        
        // Exact match
        if let scene = scenes.first(where: { $0.name.lowercased() == lower }) {
            return scene.id
        }
        // Contains match
        if let scene = scenes.first(where: { $0.name.lowercased().contains(lower) || lower.contains($0.name.lowercased()) }) {
            return scene.id
        }
        // Numeric match: "scene 1", "1", "Scene 2" → index
        let digits = name.filter(\.isNumber)
        if let number = Int(digits), number >= 1, number <= scenes.count {
            return scenes[number - 1].id
        }
        // Maybe the name IS the ID already
        if let scene = scenes.first(where: { $0.id == name }) {
            return scene.id
        }
        return nil
    }
    
    private func handleReorderScenes(_ parameters: ActionParameters?) {
        guard let order = parameters?.sceneOrder else { return }
        projectManager?.reorderScenes(order)
    }
    
    // MARK: - Object Management
    
    private func createObject(with parameters: ActionParameters?) {
        let logger = DebugLogger.shared
        
        guard let params = parameters else {
            logger.warning("createObject: No parameters provided", category: .canvas)
            return
        }
        
        let resolvedTypeString = params.effectiveObjectType
            ?? (params.effectiveText != nil ? "text" : "rectangle")
        
        guard let type = SceneObjectType(rawValue: resolvedTypeString) else {
            logger.warning("createObject: Unknown object type '\(resolvedTypeString)'", category: .canvas)
            return
        }
        
        let name = params.effectiveName ?? "\(type.rawValue.capitalized) \(sceneState.objects.count + 1)"
        
        // Duplicate detection: if an object with this exact name already exists,
        // convert to an update instead of creating a duplicate
        if sceneState.objects.contains(where: { $0.name.lowercased() == name.lowercased() }) {
            logger.warning("createObject: Object '\(name)' already exists — converting to updateProperties to prevent duplicate", category: .canvas)
            updateObject(named: name, with: params)
            return
        }
        
        logger.info("Creating object: '\(name)' of type '\(type.rawValue)'", category: .canvas)
        
        var properties = ObjectProperties()
        
        let hasExplicitPosition = params.x != nil || params.y != nil
        if !hasExplicitPosition {
            autoLayoutObjectNames.insert(name)
        }
        
        // Position (default to center, with auto-layout for text)
        if !hasExplicitPosition && type == .text {
            let baseX = sceneState.canvasWidth / 2
            let baseY = sceneState.canvasHeight / 2
            let fontSize = params.fontSize ?? 48
            let spacing = max(40.0, fontSize * 1.2)
            
            let index = autoTextIndex
            autoTextIndex += 1
            
            let step = (index + 1) / 2
            let direction = (index % 2 == 0) ? 1.0 : -1.0
            let offsetY = Double(step) * spacing * direction
            
            properties.x = baseX
            properties.y = baseY + offsetY
        } else {
            properties.x = params.x ?? (sceneState.canvasWidth / 2)
            properties.y = params.y ?? (sceneState.canvasHeight / 2)
        }
        
        // Size (support size alias for both width and height)
        properties.width = params.effectiveWidth ?? 100
        properties.height = params.effectiveHeight ?? 100
        
        // Transform
        properties.rotation = params.rotation ?? 0
        properties.scaleX = params.scaleX ?? params.scale ?? 1
        properties.scaleY = params.scaleY ?? params.scale ?? 1
        
        // Appearance (use effective color which handles aliases)
        if let fillColor = params.effectiveFillColor {
            properties.fillColor = fillColor.toCodableColor()
        }
        if let strokeColor = params.strokeColor {
            properties.strokeColor = strokeColor.toCodableColor()
        }
        properties.strokeWidth = params.strokeWidth ?? 0
        
        let requestedOpacity = params.opacity ?? 1.0
        let opacityOverrideTypes: Set<SceneObjectType> = [.text, .image, .icon, .model3D]
        if requestedOpacity <= 0 && opacityOverrideTypes.contains(type) {
            DebugLogger.shared.warning(
                "createObject '\(name)': opacity=0 overridden to 1.0 for \(type.rawValue) — the rendering engine auto-hides content before entrance animations",
                category: .canvas
            )
            properties.opacity = 1.0
        } else {
            properties.opacity = requestedOpacity
        }
        
        properties.cornerRadius = params.effectiveCornerRadius ?? 0
        
        // Text properties (use effective text which handles aliases)
        if type == .text {
            properties.text = params.effectiveText ?? "Text"
            properties.fontSize = params.fontSize ?? 48
            properties.fontName = params.effectiveFontName ?? "SF Pro"
            properties.fontWeight = params.effectiveFontWeight ?? "regular"
            properties.textAlignment = params.effectiveTextAlignment ?? "center"
            
            // Estimate text size to help with layout and clamping
            let text = properties.text ?? ""
            let fontSize = properties.fontSize ?? 48
            let estimatedSize = estimateTextSize(text: text, fontSize: fontSize)
            properties.width = estimatedSize.width
            properties.height = estimatedSize.height
            
            // Only clamp if the AI didn't specify explicit positions
            if !hasExplicitPosition {
                clampPropertiesToCanvas(&properties)
            }
            
            // Load Google Font if requested
            if let fontName = properties.fontName, fontName.lowercased() != "sf pro" {
                let fontWeight = properties.fontWeight ?? "Regular"
                Task {
                    await GoogleFontsService.shared.ensureFontLoaded(family: fontName, weight: fontWeight)
                    await MainActor.run { [weak self] in
                        self?.objectWillChange.send()
                    }
                }
            }
        }
        
        // Icon properties
        if type == .icon {
            properties.iconName = params.effectiveIconName ?? "star.fill"
            properties.iconSize = params.iconSize ?? min(properties.width, properties.height)
            properties.width = properties.iconSize ?? 64
            properties.height = properties.iconSize ?? 64
        }
        
        // Image properties
        if type == .image {
            if let imageDataURL = resolveImageDataURL(from: params) {
                properties.imageData = imageDataURL
                
                if let imageSize = resolveImageSize(from: imageDataURL) {
                    let width = params.effectiveWidth
                    let height = params.effectiveHeight
                    
                    if let width, let height {
                        // AI specified both — use exactly as given
                        properties.width = width
                        properties.height = height
                    } else if let width {
                        let aspect = imageSize.height > 0 ? imageSize.width / imageSize.height : 1
                        properties.width = width
                        properties.height = width / aspect
                    } else if let height {
                        let aspect = imageSize.width > 0 ? imageSize.height / imageSize.width : 1
                        properties.height = height
                        properties.width = height / aspect
                    } else {
                        // No size specified — fit to canvas preserving aspect ratio
                        let scale = min(sceneState.canvasWidth / imageSize.width, sceneState.canvasHeight / imageSize.height, 1)
                        properties.width = imageSize.width * scale
                        properties.height = imageSize.height * scale
                    }
                }
            }
        }
        
        // 3D Model properties
        if type == .model3D {
            properties.modelAssetId = params.modelAssetId
            properties.modelFilePath = params.modelFilePath
            properties.rotationX = params.rotationX ?? 0
            properties.rotationY = params.rotationY ?? 0
            properties.rotationZ = params.rotationZ ?? 0
            properties.scaleZ = params.scaleZ ?? 1.0
            properties.cameraDistance = params.cameraDistance ?? 5.0
            properties.cameraAngleX = params.cameraAngleX ?? 15
            properties.cameraAngleY = params.cameraAngleY ?? 0
            properties.cameraTargetX = params.cameraTargetX ?? 0
            properties.cameraTargetY = params.cameraTargetY ?? 0
            properties.cameraTargetZ = params.cameraTargetZ ?? 0
            properties.environmentLighting = params.environmentLighting ?? "neutral"
            
            // Default 3D viewport to full canvas ONLY when the AI did not specify size/position.
            // This allows the AI to create multiple smaller 3D models positioned in a grid.
            if params.effectiveWidth == nil && params.effectiveHeight == nil {
                properties.width = sceneState.canvasWidth
                properties.height = sceneState.canvasHeight
            }
            if params.x == nil && params.y == nil {
                properties.x = sceneState.canvasWidth / 2
                properties.y = sceneState.canvasHeight / 2
            }
        }
        
        // GPU Particle System properties
        if type == .particleSystem {
            properties.particleSystemData = params.particleSystemData
            properties.width = sceneState.canvasWidth
            properties.height = sceneState.canvasHeight
            properties.x = sceneState.canvasWidth / 2
            properties.y = sceneState.canvasHeight / 2
        }
        
        // Metal Shader properties
        if type == .shader {
            properties.shaderCode = params.shaderCode
            properties.shaderParam1 = params.shaderParam1 ?? 1.0
            properties.shaderParam2 = params.shaderParam2 ?? 1.0
            properties.shaderParam3 = params.shaderParam3 ?? 0.0
            properties.shaderParam4 = params.shaderParam4 ?? 0.0
            
            // ALWAYS force shader viewport to fill entire canvas.
            // Shaders are GPU-rendered viewports (like 3D models) — they must match
            // the user-selected canvas aspect ratio exactly.
            properties.width = sceneState.canvasWidth
            properties.height = sceneState.canvasHeight
            properties.x = sceneState.canvasWidth / 2
            properties.y = sceneState.canvasHeight / 2
            
            if properties.shaderCode == nil || properties.shaderCode?.isEmpty == true {
                logger.warning("createObject: Shader object '\(name)' has no shaderCode — it will show an error", category: .canvas)
            }
        }
        
        // Polygon properties
        if type == .polygon {
            properties.sides = params.sides ?? 6
        }
        
        // Path properties
        if type == .path {
            // Resolve shape presets into PathCommand data
            if let presetName = params.shapePreset,
               let preset = ShapePreset(rawValue: presetName.lowercased()) {
                let points = params.shapePresetPoints ?? 5
                properties.pathData = preset.commands(points: points)
                properties.closePath = true
            } else {
                properties.pathData = params.pathData
            }
            properties.closePath = params.closePath ?? properties.closePath
            properties.lineCap = params.lineCap ?? "round"
            properties.lineJoin = params.lineJoin ?? "round"
            properties.dashPattern = params.dashPattern
            properties.dashPhase = params.dashPhase ?? 0
            properties.trimStart = params.trimStart ?? 0
            properties.trimEnd = params.trimEnd ?? 1
            properties.trimOffset = params.trimOffset ?? 0
            
            // Smart defaults for path rendering:
            // Paths are STROKE-ONLY by default (like a pen drawing).
            // Fill only applies when closePath is true AND strokeColor is explicitly set
            // (meaning the LLM intentionally wants both fill and stroke).
            let hasFillColor = params.effectiveFillColor != nil
            let hasStrokeColor = params.strokeColor != nil
            let hasStrokeWidth = params.strokeWidth != nil
            let isClosed = params.closePath == true
            
            if hasFillColor && !hasStrokeColor && !hasStrokeWidth {
                // LLM set a "color" but no stroke — treat it as stroke color, not fill
                // This prevents the solid-blob problem when drawing line art
                properties.strokeColor = params.effectiveFillColor?.toCodableColor() ?? .white
                properties.fillColor = .clear
                properties.strokeWidth = 3
            } else if !hasFillColor && !hasStrokeColor {
                // Nothing specified — default to white stroke
                properties.strokeColor = .white
                properties.fillColor = .clear
                properties.strokeWidth = 3
            } else if hasFillColor && hasStrokeColor {
                // Both explicitly set — respect both (intentional fill + stroke)
                // fillColor and strokeColor already set above via general appearance logic
            } else if hasFillColor && isClosed && (hasStrokeWidth || hasStrokeColor) {
                // Closed path with explicit fill AND stroke — this is a real filled shape
                // fillColor already set above via general appearance logic
            } else if !hasFillColor && (hasStrokeColor || hasStrokeWidth) {
                // Only stroke specified — stroke-only path
                properties.fillColor = .clear
                if !hasStrokeWidth {
                    properties.strokeWidth = 3
                }
            }
        }
        
        // Visual effects (applicable to ALL object types)
        if let blur = params.blurRadius { properties.blurRadius = blur }
        if let bright = params.brightness { properties.brightness = bright }
        if let cont = params.contrast { properties.contrast = cont }
        if let sat = params.saturation { properties.saturation = sat }
        if let hue = params.hueRotation { properties.hueRotation = hue }
        if let gray = params.grayscale { properties.grayscale = gray }
        if let blend = params.blendMode { properties.blendMode = blend }
        if let sc = params.shadowColor { properties.shadowColor = sc.toCodableColor() }
        if let sr = params.shadowRadius { properties.shadowRadius = sr }
        if let sx = params.shadowOffsetX { properties.shadowOffsetX = sx }
        if let sy = params.shadowOffsetY { properties.shadowOffsetY = sy }
        if let inv = params.colorInvert { properties.colorInvert = inv }
        
        let object = SceneObject(
            type: type,
            name: name,
            properties: properties,
            zIndex: params.effectiveZIndex ?? sceneState.objects.count
        )
        
        sceneState.objects.append(object)
        
        // Log creation with bounding box info
        let left = Int(properties.x - properties.width / 2)
        let right = Int(properties.x + properties.width / 2)
        let top = Int(properties.y - properties.height / 2)
        let bottom = Int(properties.y + properties.height / 2)
        logger.success("Created '\(name)' at (\(Int(properties.x)), \(Int(properties.y))) size \(Int(properties.width))x\(Int(properties.height)) bounds:[L:\(left) R:\(right) T:\(top) B:\(bottom)] z:\(object.zIndex)", category: .canvas)
        
        // Warn if object is clipped outside canvas
        let cw = Int(sceneState.canvasWidth)
        let ch = Int(sceneState.canvasHeight)
        if left < 0 || right > cw || top < 0 || bottom > ch {
            var clipSides: [String] = []
            if left < 0 { clipSides.append("left by \(-left)px") }
            if right > cw { clipSides.append("right by \(right - cw)px") }
            if top < 0 { clipSides.append("top by \(-top)px") }
            if bottom > ch { clipSides.append("bottom by \(bottom - ch)px") }
            logger.warning("⚠️ Object '\(name)' is CLIPPED outside canvas (\(cw)x\(ch)): \(clipSides.joined(separator: ", "))", category: .canvas)
        }
    }
    
    private func deleteObject(named name: String?) {
        let logger = DebugLogger.shared
        guard let name = name else {
            logger.warning("deleteObject: No name provided", category: .canvas)
            return
        }
        
        if let idx = resolveTargetIndex(for: name, parameters: nil) {
            let objectName = sceneState.objects[idx].name
            sceneState.objects.remove(at: idx)
            logger.info("Deleted object '\(objectName)'", category: .canvas)
        } else {
            logger.warning("deleteObject: Object '\(name)' not found — nothing to delete", category: .canvas)
        }
    }
    
    private func duplicateObject(named name: String?) {
        guard let name = name,
              let original = findObject(named: name) else { return }
        
        var copy = original
        copy = SceneObject(
            type: original.type,
            name: "\(original.name) Copy",
            properties: original.properties,
            animations: original.animations,
            zIndex: sceneState.objects.count
        )
        
        sceneState.objects.append(copy)
    }
    
    private func updateObject(named name: String?, with parameters: ActionParameters?) {
        let logger = DebugLogger.shared
        guard let params = parameters else {
            logger.warning("updateObject: No parameters provided", category: .canvas)
            return
        }
        
        // Use smart object lookup — fallback to last only if no name given
        guard let idx = resolveTargetIndex(for: name, parameters: params, allowFallback: name == nil) else {
            logger.warning("updateObject: Cannot find object '\(name ?? "unknown")' to update — skipping", category: .canvas)
            return
        }
        
        logger.info("Updating object '\(sceneState.objects[idx].name)'", category: .canvas)
        
        var obj = sceneState.objects[idx]
        
        // Update position
        if let x = params.x { obj.properties.x = x }
        if let y = params.y { obj.properties.y = y }
        if params.x != nil || params.y != nil {
            autoLayoutObjectNames.remove(obj.name)
        }
        
        // Update size
        if let width = params.width { obj.properties.width = width }
        if let height = params.height { obj.properties.height = height }
        
        // Update transform
        if let rotation = params.rotation { obj.properties.rotation = rotation }
        if let scaleX = params.scaleX { obj.properties.scaleX = scaleX }
        if let scaleY = params.scaleY { obj.properties.scaleY = scaleY }
        
        // Update appearance
        if let fillColor = params.fillColor {
            obj.properties.fillColor = fillColor.toCodableColor()
        }
        if let strokeColor = params.strokeColor {
            obj.properties.strokeColor = strokeColor.toCodableColor()
        }
        if let strokeWidth = params.strokeWidth { obj.properties.strokeWidth = strokeWidth }
        if let opacity = params.opacity { obj.properties.opacity = opacity }
        if let cornerRadius = params.cornerRadius { obj.properties.cornerRadius = cornerRadius }
        
        // Update text properties
        if let text = params.text { obj.properties.text = text }
        if let fontSize = params.fontSize { obj.properties.fontSize = fontSize }
        if let fontName = params.effectiveFontName { obj.properties.fontName = fontName }
        if let fontWeight = params.fontWeight { obj.properties.fontWeight = fontWeight }
        
        // Update icon properties
        if let iconName = params.effectiveIconName { obj.properties.iconName = iconName }
        if let iconSize = params.iconSize { obj.properties.iconSize = iconSize }
        
        // Update image properties
        if params.imageData != nil || params.imageUrl != nil || params.attachmentIndex != nil || params.attachmentId != nil {
            if let imageDataURL = resolveImageDataURL(from: params) {
                obj.properties.imageData = imageDataURL
            }
        }
        
        // Update path properties
        if let pathData = params.pathData { obj.properties.pathData = pathData }
        if let closePath = params.closePath { obj.properties.closePath = closePath }
        if let lineCap = params.lineCap { obj.properties.lineCap = lineCap }
        if let lineJoin = params.lineJoin { obj.properties.lineJoin = lineJoin }
        if let dashPattern = params.dashPattern { obj.properties.dashPattern = dashPattern }
        if let dashPhase = params.dashPhase { obj.properties.dashPhase = dashPhase }
        if let trimStart = params.trimStart { obj.properties.trimStart = trimStart }
        if let trimEnd = params.trimEnd { obj.properties.trimEnd = trimEnd }
        if let trimOffset = params.trimOffset { obj.properties.trimOffset = trimOffset }
        
        // Update visual effects
        if let blur = params.blurRadius { obj.properties.blurRadius = blur }
        if let bright = params.brightness { obj.properties.brightness = bright }
        if let cont = params.contrast { obj.properties.contrast = cont }
        if let sat = params.saturation { obj.properties.saturation = sat }
        if let hue = params.hueRotation { obj.properties.hueRotation = hue }
        if let gray = params.grayscale { obj.properties.grayscale = gray }
        if let blend = params.blendMode { obj.properties.blendMode = blend }
        if let sc = params.shadowColor { obj.properties.shadowColor = sc.toCodableColor() }
        if let sr = params.shadowRadius { obj.properties.shadowRadius = sr }
        if let sx = params.shadowOffsetX { obj.properties.shadowOffsetX = sx }
        if let sy = params.shadowOffsetY { obj.properties.shadowOffsetY = sy }
        if let inv = params.colorInvert { obj.properties.colorInvert = inv }
        
        // Update 3D model properties
        if let rx = params.rotationX { obj.properties.rotationX = rx }
        if let ry = params.rotationY { obj.properties.rotationY = ry }
        if let rz = params.rotationZ { obj.properties.rotationZ = rz }
        if let sz = params.scaleZ { obj.properties.scaleZ = sz }
        if let cd = params.cameraDistance { obj.properties.cameraDistance = cd }
        if let cx = params.cameraAngleX { obj.properties.cameraAngleX = cx }
        if let cy = params.cameraAngleY { obj.properties.cameraAngleY = cy }
        if let ctx = params.cameraTargetX { obj.properties.cameraTargetX = ctx }
        if let cty = params.cameraTargetY { obj.properties.cameraTargetY = cty }
        if let ctz = params.cameraTargetZ { obj.properties.cameraTargetZ = ctz }
        if let el = params.environmentLighting { obj.properties.environmentLighting = el }
        
        // Update shader properties
        if let code = params.shaderCode { obj.properties.shaderCode = code }
        if let p1 = params.shaderParam1 { obj.properties.shaderParam1 = p1 }
        if let p2 = params.shaderParam2 { obj.properties.shaderParam2 = p2 }
        if let p3 = params.shaderParam3 { obj.properties.shaderParam3 = p3 }
        if let p4 = params.shaderParam4 { obj.properties.shaderParam4 = p4 }
        
        // Force full-canvas viewport for shaders only.
        // Shaders are GPU-rendered fullscreen effects that must match canvas dimensions.
        // 3D models can now be freely positioned and sized to support grids / multi-model layouts.
        if obj.type == .shader {
            obj.properties.width = sceneState.canvasWidth
            obj.properties.height = sceneState.canvasHeight
            obj.properties.x = sceneState.canvasWidth / 2
            obj.properties.y = sceneState.canvasHeight / 2
        }
        
        sceneState.objects[idx] = obj
    }
    
    // MARK: - Animation Management
    
    private func addAnimation(to target: String?, with parameters: ActionParameters?) {
        let logger = DebugLogger.shared
        
        guard let params = parameters,
              let typeString = params.effectiveAnimationType else {
            logger.warning("addAnimation: Missing parameters or animationType", category: .animation)
            return
        }
        
        // Resolve LLM alias names to canonical AnimationType raw values
        let aliasMap: [String: String] = [
            "opacity": "fade",
            "position": "move",
            "moveTo": "move",
            "translateX": "moveX",
            "translateY": "moveY",
            "scaleUp": "grow",
            "scaleDown": "shrink",
            "rotateX": "rotate3DX",
            "rotateY": "rotate3DY",
            "rotateZ": "rotate3DZ",
            "shakeRumble": "cameraShake",
            "height": "scaleY",
            "width": "scaleX",
            "size": "scale",
            "updateProperties": "propertyChange",
            "setProperty": "propertyChange",
        ]
        let resolvedType = aliasMap[typeString] ?? typeString
        
        let normalizedType = resolvedType.replacingOccurrences(of: "-", with: "").lowercased()
        guard let type = AnimationType(rawValue: resolvedType) ?? 
              AnimationType.allCases.first(where: { $0.rawValue.lowercased() == normalizedType }) else {
            logger.warning("addAnimation: Unknown animation type '\(typeString)'", category: .animation)
            return
        }
        
        // Find target object using smart lookup — only fallback to last if no target specified
        let effectiveTarget = target ?? params.targetId ?? params.id ?? params.effectiveName
        
        guard let idx = resolveTargetIndex(for: effectiveTarget, parameters: params, allowFallback: effectiveTarget == nil) else {
            logger.warning("addAnimation: Object '\(effectiveTarget ?? "none")' not found — cannot add \(typeString) animation", category: .animation)
            return
        }
        
        logger.info("Adding \(type.rawValue) animation to '\(sceneState.objects[idx].name)'", category: .animation)
        
        // Parse easing (handle variations)
        let easing: EasingType
        if let easingString = params.easing {
            let normalizedEasing = easingString.replacingOccurrences(of: "-", with: "").lowercased()
            easing = EasingType(rawValue: easingString) ?? 
                     EasingType.allCases.first(where: { $0.rawValue.lowercased() == normalizedEasing }) ?? 
                     .easeInOut
        } else {
            easing = animationEngine.recommendedEasing(for: type)
        }
        
        var keyframes: [Keyframe] = []
        
        // Build keyframes based on animation type
        if let kfParams = params.keyframes {
            keyframes = kfParams.map { kf in
                Keyframe(
                    time: kf.time,
                    value: convertAnimationValue(kf.value)
                )
            }
        } else if let fromValue = params.effectiveFromValue, let toValue = params.effectiveToValue {
            // Build keyframes from fromValue/toValue
            keyframes = [
                Keyframe(time: 0, value: convertFlexibleValue(fromValue)),
                Keyframe(time: 1, value: convertFlexibleValue(toValue))
            ]
        } else {
            // Use default keyframes based on animation type
            keyframes = animationEngine.defaultKeyframes(for: type)
        }
        
        keyframes = normalizeAdditive3DKeyframesIfNeeded(keyframes, for: type)
        
        // For pathMorph, resolve target path data from params or preset name
        var targetPath: [PathCommand]?
        if type == .pathMorph {
            if let pathData = params.pathData, !pathData.isEmpty {
                targetPath = pathData
            } else if let presetName = params.targetShapePreset ?? params.shapePreset,
                      let preset = ShapePreset(rawValue: presetName.lowercased()) {
                targetPath = preset.commands(points: params.shapePresetPoints ?? 5)
            }
        }
        
        let animation = AnimationDefinition(
            type: type,
            startTime: params.startTime ?? 0,
            duration: params.duration ?? animationEngine.recommendedDuration(for: type),
            easing: easing,
            keyframes: keyframes,
            repeatCount: params.effectiveRepeatCount,
            autoReverse: params.autoReverse ?? false,
            delay: params.delay ?? 0,
            targetPathData: targetPath
        )
        
        sceneState.objects[idx].animations.append(animation)
        
        // Update scene duration if this animation extends past current duration
        let animEndTime = animation.startTime + animation.delay + animation.duration + 1.0 // +1s buffer
        if animEndTime > sceneState.duration {
            sceneState.duration = animEndTime
            DebugLogger.shared.debug("Extended scene duration to \(String(format: "%.1f", animEndTime))s", category: .animation)
        }
    }
    
    private func convertFlexibleValue(_ value: FlexibleValue) -> KeyframeValue {
        switch value {
        case .number(let d):
            return .double(d)
        case .animationValue(let animValue):
            return convertAnimationValue(animValue)
        }
    }
    
    private func removeAnimation(from target: String?, animationType: String?) {
        let logger = DebugLogger.shared
        
        guard let idx = resolveTargetIndex(for: target, parameters: nil, allowFallback: target == nil) else {
            logger.warning("removeAnimation: Object '\(target ?? "none")' not found — cannot remove animation", category: .animation)
            return
        }
        
        let beforeCount = sceneState.objects[idx].animations.count
        let objectName = sceneState.objects[idx].name
        
        if let typeString = animationType {
            let normalizedType = typeString.replacingOccurrences(of: "-", with: "").lowercased()
            if let type = AnimationType(rawValue: typeString) ?? 
               AnimationType.allCases.first(where: { $0.rawValue.lowercased() == normalizedType }) {
                sceneState.objects[idx].animations.removeAll { $0.type == type }
                logger.info("Removed \(type.rawValue) animations from '\(objectName)'", category: .animation)
            }
        } else {
            // Remove all animations
            sceneState.objects[idx].animations.removeAll()
            logger.info("Removed ALL animations from '\(objectName)'", category: .animation)
        }
        
        let afterCount = sceneState.objects[idx].animations.count
        logger.debug("Animation count: \(beforeCount) → \(afterCount)", category: .animation)
    }
    
    private func updateAnimation(for target: String?, with parameters: ActionParameters?) {
        let logger = DebugLogger.shared
        guard let params = parameters,
              let typeString = params.effectiveAnimationType else {
            logger.warning("updateAnimation: Missing parameters or animationType", category: .animation)
            // If no animation type specified, fall back to remove+re-add
            removeAnimation(from: target, animationType: parameters?.effectiveAnimationType)
            addAnimation(to: target, with: parameters)
            return
        }
        
        let aliasMap: [String: String] = [
            "opacity": "fade",
            "position": "move",
            "moveTo": "move",
            "translateX": "moveX",
            "translateY": "moveY",
            "scaleUp": "grow",
            "scaleDown": "shrink",
            "rotateX": "rotate3DX",
            "rotateY": "rotate3DY",
            "rotateZ": "rotate3DZ",
            "shakeRumble": "cameraShake",
            "height": "scaleY",
            "width": "scaleX",
            "size": "scale",
        ]
        let resolvedType = aliasMap[typeString] ?? typeString
        let normalizedType = resolvedType.replacingOccurrences(of: "-", with: "").lowercased()
        guard let type = AnimationType(rawValue: resolvedType) ??
              AnimationType.allCases.first(where: { $0.rawValue.lowercased() == normalizedType }) else {
            logger.warning("updateAnimation: Unknown animation type '\(typeString)'", category: .animation)
            return
        }
        
        guard let idx = resolveTargetIndex(for: target, parameters: params, allowFallback: target == nil) else {
            logger.warning("updateAnimation: Object '\(target ?? "none")' not found", category: .animation)
            return
        }
        
        // Find the existing animation of this type to patch it
        if let animIdx = sceneState.objects[idx].animations.firstIndex(where: { $0.type == type }) {
            logger.info("Patching existing \(type.rawValue) animation on '\(sceneState.objects[idx].name)'", category: .animation)
            
            // Patch only the provided fields, keeping existing values for the rest
            var anim = sceneState.objects[idx].animations[animIdx]
            if let duration = params.duration { anim.duration = duration }
            if let startTime = params.startTime { anim.startTime = startTime }
            if let delay = params.delay { anim.delay = delay }
            if let autoReverse = params.autoReverse { anim.autoReverse = autoReverse }
            if params.repeatCount != nil { anim.repeatCount = params.effectiveRepeatCount }
            
            if let easingStr = params.easing {
                let normalizedEasing = easingStr.replacingOccurrences(of: "-", with: "").lowercased()
                if let newEasing = EasingType(rawValue: easingStr) ??
                   EasingType.allCases.first(where: { $0.rawValue.lowercased() == normalizedEasing }) {
                    anim.easing = newEasing
                }
            }
            
            // Update keyframes if new ones are provided
            if let kfParams = params.keyframes {
                anim.keyframes = kfParams.map { kf in
                    Keyframe(time: kf.time, value: convertAnimationValue(kf.value))
                }
            } else if let fromValue = params.effectiveFromValue, let toValue = params.effectiveToValue {
                anim.keyframes = [
                    Keyframe(time: 0, value: convertFlexibleValue(fromValue)),
                    Keyframe(time: 1, value: convertFlexibleValue(toValue))
                ]
            }
            
            anim.keyframes = normalizeAdditive3DKeyframesIfNeeded(anim.keyframes, for: type)
            
            sceneState.objects[idx].animations[animIdx] = anim
        } else {
            // Animation of this type doesn't exist yet — add it as new
            logger.info("No existing \(type.rawValue) animation on '\(sceneState.objects[idx].name)' — adding as new", category: .animation)
            addAnimation(to: target, with: parameters)
        }
    }
    
    private func normalizeAdditive3DKeyframesIfNeeded(_ keyframes: [Keyframe], for type: AnimationType) -> [Keyframe] {
        guard additive3DDeltaAnimationTypes.contains(type),
              let firstKeyframe = keyframes.first,
              case .double(let firstValue) = firstKeyframe.value,
              abs(firstValue) > 0.0001 else {
            return keyframes
        }
        
        let normalized = keyframes.map { keyframe in
            guard case .double(let value) = keyframe.value else { return keyframe }
            return Keyframe(time: keyframe.time, value: .double(value - firstValue))
        }
        
        DebugLogger.shared.debug(
            "Normalized additive 3D animation '\(type.rawValue)' to zero-based deltas (first keyframe \(String(format: "%.3f", firstValue)) -> 0)",
            category: .animation
        )
        return normalized
    }
    
    private var additive3DDeltaAnimationTypes: Set<AnimationType> {
        [
            .rotate3DX, .rotate3DY, .rotate3DZ,
            .turntable, .revolveSlow, .wobble3D, .flip3D, .orbit3D,
            .float3D, .cradle, .springBounce3D, .elasticSpin, .swing3D,
            .headNod, .headShake, .rockAndRoll, .slamDown3D, .tumble,
            .barrelRoll, .boomerang3D, .levitate, .magnetPull, .magnetPush,
            .zigzagDrop, .anticipateSpin, .glitchJitter3D,
            .cameraPan, .cameraWhipPan, .cameraShake,
            .move3DX, .move3DY, .move3DZ
        ]
    }

    /// Remove ALL animations from a specific object
    private func clearAnimations(from target: String?) {
        let logger = DebugLogger.shared
        
        guard let idx = resolveTargetIndex(for: target, parameters: nil, allowFallback: false) else {
            logger.warning("clearAnimations: Object '\(target ?? "none")' not found", category: .animation)
            return
        }
        
        let count = sceneState.objects[idx].animations.count
        sceneState.objects[idx].animations.removeAll()
        logger.info("Cleared all \(count) animations from '\(sceneState.objects[idx].name)'", category: .animation)
    }
    
    // MARK: - Preset Animations
    
    private func applyPreset(to target: String?, with parameters: ActionParameters?) {
        let logger = DebugLogger.shared
        guard let params = parameters,
              let presetNameRaw = params.effectivePresetName?.lowercased() else {
            logger.warning("applyPreset: Missing preset name", category: .animation)
            return
        }
        
        let presetName = presetNameRaw.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "")
        
        // Scene-wide preset (layout)
        if presetName == "gridlayout" || presetName == "layoutgrid" {
            applyGridLayout(parameters: params, target: target)
            return
        }
        
        // Look-at preset
        if presetName == "lookat" || presetName == "lookattarget" {
            applyLookAtPreset(to: target, parameters: params)
            return
        }
        
        guard let idx = resolveTargetIndex(for: target, parameters: params) else {
            logger.warning("applyPreset: No object found for target '\(target ?? "none")'", category: .animation)
            return
        }
        
        let object = sceneState.objects[idx]
        let startTime = params.startTime ?? 0
        let intensity = params.intensity ?? 1.0
        
        var animations: [AnimationDefinition] = []
        
        switch presetName {
        case "kineticbounce":
            animations.append(makeAnimation(type: .bounce, startTime: startTime, duration: 1.2, easing: .bounce, intensity: intensity))
            animations.append(makeAnimation(type: .scale, startTime: startTime, duration: 0.6, easing: .easeOutBack, intensity: intensity))
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: 0.3, easing: .easeOut, intensity: intensity))
            
        case "elasticpop":
            animations.append(makeAnimation(type: .elasticIn, startTime: startTime, duration: 0.8, easing: .elastic, intensity: intensity))
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: 0.4, easing: .easeOut, intensity: intensity))
            
        case "scramblemorph", "textscramble", "decodetext", "decode":
            animations.append(makeAnimation(type: .scramble, startTime: startTime, duration: 1.0, easing: .easeInOutCubic, intensity: intensity))
            animations.append(makeAnimation(type: .charByChar, startTime: startTime + 0.1, duration: 1.2, easing: .easeOutQuad, intensity: intensity))
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: 0.3, easing: .easeOut, intensity: intensity))
            
        case "loopwiggle":
            animations.append(makeAnimation(type: .wiggle, startTime: startTime, duration: params.duration ?? 3.0, easing: .linear, intensity: intensity, repeatCount: -1))
            
        case "posterizemotion":
            animations.append(makeAnimation(type: .jitter, startTime: startTime, duration: params.duration ?? 1.5, easing: .linear, intensity: intensity, repeatCount: -1))
            
        case "trimrevealglow":
            animations.append(makeAnimation(type: .reveal, startTime: startTime, duration: 0.8, easing: .easeOutCubic, intensity: intensity))
            animations.append(makeAnimation(type: .flash, startTime: startTime + 0.1, duration: 0.2, easing: .easeOutExpo, intensity: intensity))
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: 0.4, easing: .easeOut, intensity: intensity))
            animations.append(makeAnimation(type: .pulse, startTime: startTime + 0.9, duration: 1.2, easing: .easeInOut, intensity: intensity, repeatCount: -1))
            
        case "impactslam":
            animations.append(makeAnimation(type: .slam, startTime: startTime, duration: 0.4, easing: .easeOutExpo, intensity: intensity))
            animations.append(makeAnimation(type: .shake, startTime: startTime + 0.2, duration: 0.5, easing: .linear, intensity: intensity))
            animations.append(makeAnimation(type: .flash, startTime: startTime, duration: 0.2, easing: .easeOutExpo, intensity: intensity))
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: 0.3, easing: .easeOut, intensity: intensity))
            
        case "typewriterstagger":
            animations.append(makeAnimation(type: .typewriter, startTime: startTime, duration: params.duration ?? 1.6, easing: .easeOutQuad, intensity: intensity))
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: 0.4, easing: .easeOut, intensity: intensity))

        case "kineticstagger", "kinetictype", "kineticwave":
            let revealDuration = max(0.8, params.duration ?? 1.4)
            animations.append(makeAnimation(type: .charByChar, startTime: startTime, duration: revealDuration, easing: .easeOutCubic, intensity: intensity))
            animations.append(makeAnimation(type: .wave, startTime: startTime + revealDuration * 0.35, duration: 2.0, easing: .easeInOutQuad, intensity: intensity, repeatCount: -1))
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: min(0.4, revealDuration * 0.4), easing: .easeOut, intensity: intensity))

        case "wordbounce", "wordrise", "wordstack":
            let revealDuration = max(0.9, params.duration ?? 1.5)
            animations.append(makeAnimation(type: .wordByWord, startTime: startTime, duration: revealDuration, easing: .easeOutBack, intensity: intensity))
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: min(0.35, revealDuration * 0.35), easing: .easeOut, intensity: intensity))

        case "linecascade", "linereveal", "linewipe":
            let revealDuration = max(0.9, params.duration ?? 1.6)
            animations.append(makeAnimation(type: .lineByLine, startTime: startTime, duration: revealDuration, easing: .easeOutCubic, intensity: intensity))
            animations.append(makeAnimation(type: .reveal, startTime: startTime, duration: min(0.6, revealDuration * 0.5), easing: .easeOutCubic, intensity: intensity))
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: min(0.3, revealDuration * 0.25), easing: .easeOut, intensity: intensity))

        case "scrambleglitch", "hackerglitch", "dataglitch":
            let revealDuration = max(0.9, params.duration ?? 1.4)
            animations.append(makeAnimation(type: .scramble, startTime: startTime, duration: revealDuration, easing: .easeInOutCubic, intensity: intensity))
            animations.append(makeAnimation(type: .glitchText, startTime: startTime + 0.05, duration: revealDuration * 0.9, easing: .linear, intensity: intensity))
            animations.append(makeAnimation(type: .flicker, startTime: startTime + 0.05, duration: min(0.6, revealDuration * 0.6), easing: .linear, intensity: intensity))
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: min(0.3, revealDuration * 0.25), easing: .easeOut, intensity: intensity))

        case "neonwave", "typewave", "waveglow":
            let loopDuration = params.duration ?? 2.6
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: 0.4, easing: .easeOut, intensity: intensity))
            animations.append(makeAnimation(type: .wave, startTime: startTime + 0.2, duration: loopDuration, easing: .easeInOutQuad, intensity: intensity, repeatCount: -1))
            animations.append(makeAnimation(type: .pulse, startTime: startTime + 0.3, duration: 1.4, easing: .easeInOut, intensity: intensity, repeatCount: -1))
            animations.append(makeAnimation(type: .flicker, startTime: startTime + 0.2, duration: 0.6, easing: .linear, intensity: intensity))

        case "typeslam", "typingslam", "impacttype":
            let revealDuration = max(0.7, params.duration ?? 1.2)
            animations.append(makeAnimation(type: .typewriter, startTime: startTime, duration: revealDuration, easing: .easeOutQuad, intensity: intensity))
            animations.append(makeAnimation(type: .slam, startTime: startTime, duration: 0.35, easing: .easeOutExpo, intensity: intensity))
            animations.append(makeAnimation(type: .flash, startTime: startTime, duration: 0.15, easing: .easeOutExpo, intensity: intensity))
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: 0.2, easing: .easeOut, intensity: intensity))

        case "glitchreveal":
            animations.append(makeAnimation(type: .glitchText, startTime: startTime, duration: 0.6, easing: .linear, intensity: intensity))
            animations.append(makeAnimation(type: .reveal, startTime: startTime, duration: 0.7, easing: .easeOutCubic, intensity: intensity))
            animations.append(makeAnimation(type: .flash, startTime: startTime + 0.05, duration: 0.2, easing: .easeOutExpo, intensity: intensity))
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: 0.3, easing: .easeOut, intensity: intensity))

        case "glitchcore", "glitchmaster", "glitchmain", "glitchwow":
            // Cinematic multi-burst glitch (translated from common AE glitch script patterns)
            let totalDuration = max(0.6, params.duration ?? 1.2)
            let burstDuration = totalDuration * 0.28
            let burstGap = totalDuration * 0.12
            
            let burst1 = startTime
            let burst2 = startTime + burstDuration + burstGap
            let burst3 = startTime + (burstDuration + burstGap) * 2
            
            // Ensure visibility before bursts
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: min(0.25, totalDuration * 0.2), easing: .easeOut, intensity: intensity))
            
            // Burst 1
            animations.append(makeAnimation(type: .glitchText, startTime: burst1, duration: burstDuration, easing: .linear, intensity: intensity * 1.2))
            animations.append(makeAnimation(type: .glitch, startTime: burst1, duration: burstDuration * 0.9, easing: .linear, intensity: intensity))
            animations.append(makeAnimation(type: .flicker, startTime: burst1, duration: burstDuration * 0.8, easing: .linear, intensity: intensity * 0.9))
            
            // Burst 2
            animations.append(makeAnimation(type: .glitchText, startTime: burst2, duration: burstDuration, easing: .linear, intensity: intensity))
            animations.append(makeAnimation(type: .glitch, startTime: burst2, duration: burstDuration * 0.9, easing: .linear, intensity: intensity * 0.9))
            animations.append(makeAnimation(type: .flicker, startTime: burst2, duration: burstDuration * 0.8, easing: .linear, intensity: intensity * 0.8))
            
            // Burst 3
            animations.append(makeAnimation(type: .glitchText, startTime: burst3, duration: burstDuration * 0.9, easing: .linear, intensity: intensity * 0.8))
            animations.append(makeAnimation(type: .glitch, startTime: burst3, duration: burstDuration * 0.8, easing: .linear, intensity: intensity * 0.7))
            animations.append(makeAnimation(type: .flicker, startTime: burst3, duration: burstDuration * 0.7, easing: .linear, intensity: intensity * 0.7))

        case "neonpulse":
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: 0.3, easing: .easeOut, intensity: intensity))
            animations.append(makeAnimation(type: .pulse, startTime: startTime + 0.3, duration: 1.4, easing: .easeInOut, intensity: intensity, repeatCount: -1))
            animations.append(makeAnimation(type: .flicker, startTime: startTime + 0.2, duration: 0.6, easing: .linear, intensity: intensity))

        case "floatparallax":
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: 0.4, easing: .easeOut, intensity: intensity))
            animations.append(makeAnimation(type: .float, startTime: startTime + 0.4, duration: 2.5, easing: .easeInOutQuad, intensity: intensity, repeatCount: -1))
            animations.append(makeAnimation(type: .drift, startTime: startTime + 0.4, duration: 3.0, easing: .easeInOutQuad, intensity: intensity, repeatCount: -1))

        case "slidestack":
            animations.append(makeAnimation(type: .slideIn, startTime: startTime, duration: 0.6, easing: .easeOutCubic, intensity: intensity))
            animations.append(makeAnimation(type: .scale, startTime: startTime + 0.1, duration: 0.5, easing: .easeOutBack, intensity: intensity))
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: 0.4, easing: .easeOut, intensity: intensity))

        case "driftfade":
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: 0.4, easing: .easeOut, intensity: intensity))
            animations.append(makeAnimation(type: .drift, startTime: startTime + 0.4, duration: 2.2, easing: .easeInOutQuad, intensity: intensity))
            animations.append(makeAnimation(type: .fadeOut, startTime: startTime + 2.2, duration: 0.5, easing: .easeInCubic, intensity: intensity))

        case "whipreveal":
            animations.append(makeAnimation(type: .whipIn, startTime: startTime, duration: 0.4, easing: .easeOutExpo, intensity: intensity))
            animations.append(makeAnimation(type: .reveal, startTime: startTime, duration: 0.5, easing: .easeOutCubic, intensity: intensity))
            animations.append(makeAnimation(type: .flash, startTime: startTime + 0.05, duration: 0.15, easing: .easeOutExpo, intensity: intensity))
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: 0.3, easing: .easeOut, intensity: intensity))

        case "bouncedrop":
            animations.append(makeAnimation(type: .dropIn, startTime: startTime, duration: 0.8, easing: .easeOutBack, intensity: intensity))
            animations.append(makeAnimation(type: .bounce, startTime: startTime + 0.2, duration: 1.0, easing: .bounce, intensity: intensity))
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: 0.3, easing: .easeOut, intensity: intensity))

        case "cleanminimal":
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: 0.6, easing: .easeOutCubic, intensity: intensity))
            animations.append(makeAnimation(type: .moveY, startTime: startTime, duration: 0.6, easing: .easeOutCubic, intensity: intensity))
            animations.append(makeAnimation(type: .fadeOut, startTime: startTime + 2.0, duration: 0.6, easing: .easeInCubic, intensity: intensity))

        case "herorise":
            animations.append(makeAnimation(type: .riseUp, startTime: startTime, duration: 0.8, easing: .easeOutBack, intensity: intensity))
            animations.append(makeAnimation(type: .scale, startTime: startTime, duration: 0.8, easing: .easeOutBack, intensity: intensity))
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: 0.4, easing: .easeOut, intensity: intensity))

        case "followtarget", "parentedposition":
            applyFollowTargetPreset(to: target, parameters: params)
            return

        case "aspectratiodrift", "respectaspectratio":
            animations.append(makeAspectRatioDriftAnimation(startTime: startTime, intensity: intensity, duration: params.duration ?? 1.8))

        case "lumamappulse", "layermapluma":
            animations.append(makeAnimation(type: .pulse, startTime: startTime, duration: 1.2, easing: .easeInOut, intensity: intensity, repeatCount: -1))
            animations.append(makeAnimation(type: .flicker, startTime: startTime + 0.1, duration: 0.6, easing: .linear, intensity: intensity))
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: 0.3, easing: .easeOut, intensity: intensity))
        
        case "screenflash", "flashoverlay", "impactflash":
            // Screen flash: quick flash then fade out completely
            // Best used on a white rectangle that covers the full canvas
            let flashDuration = (params.duration ?? 0.3) * intensity
            animations.append(AnimationDefinition(
                type: .flash,
                startTime: startTime,
                duration: flashDuration,
                easing: .easeOutExpo,
                keyframes: [
                    Keyframe(time: 0, value: .double(0)),
                    Keyframe(time: 0.15, value: .double(1)),    // Peak flash
                    Keyframe(time: 0.5, value: .double(0.3)),
                    Keyframe(time: 1, value: .double(0))        // Fully invisible
                ],
                repeatCount: 0
            ))
            
        case "linedraw", "linewriteon", "linewrite", "lineanim":
            animations.append(contentsOf: lineAnimationService.lineDrawAnimations(
                for: object,
                startTime: startTime,
                duration: params.duration,
                intensity: intensity
            ))
            
        case "linesweepglow", "linesweep", "lineglow":
            animations.append(contentsOf: lineAnimationService.lineSweepGlowAnimations(
                for: object,
                startTime: startTime,
                duration: params.duration,
                intensity: intensity
            ))
            
        case "lineunderline", "underline":
            animations.append(contentsOf: lineAnimationService.lineUnderlineAnimations(
                for: object,
                startTime: startTime,
                duration: params.duration,
                intensity: intensity
            ))
            
        case "linestackstagger", "linestack":
            animations.append(contentsOf: lineAnimationService.lineStackStaggerAnimations(
                for: object,
                startTime: startTime,
                duration: params.duration,
                intensity: intensity
            ))
            
        case "pathdrawon", "drawon", "writeon", "penwrite", "pathwrite", "strokereveal":
            // Path draw-on: reveals the stroke progressively using trimPathEnd
            // Sets trimEnd to 0 first (hidden), then animates to 1 (fully drawn)
            let drawDuration = max(0.3, params.duration ?? 1.5)
            
            // Force trimEnd to 0 so the path starts invisible
            if let targetName = target,
               let idx = sceneState.objects.firstIndex(where: { $0.name.lowercased() == targetName.lowercased() }) {
                sceneState.objects[idx].properties.trimEnd = 0
            }
            
            // Draw-on animation
            animations.append(AnimationDefinition(
                type: .trimPathEnd,
                startTime: startTime,
                duration: drawDuration,
                easing: .easeInOutCubic,
                keyframes: [
                    Keyframe(time: 0, value: .double(0)),
                    Keyframe(time: 1, value: .double(1))
                ]
            ))
            // Subtle stroke width grow for pen pressure feel
            if intensity > 0.8 {
                animations.append(AnimationDefinition(
                    type: .strokeWidthAnim,
                    startTime: startTime,
                    duration: drawDuration * 0.3,
                    easing: .easeOut,
                    keyframes: [
                        Keyframe(time: 0, value: .double(0.5)),
                        Keyframe(time: 1, value: .double(object.properties.strokeWidth > 0 ? object.properties.strokeWidth : 3))
                    ]
                ))
            }
            
        case "mathorbit", "orbit":
            animations.append(contentsOf: mathAnimationService.orbitAnimations(
                for: object,
                startTime: startTime,
                duration: params.duration,
                intensity: intensity
            ))
            
        case "mathsinedrift", "sinedrift":
            animations.append(contentsOf: mathAnimationService.sineDriftAnimations(
                for: object,
                startTime: startTime,
                duration: params.duration,
                intensity: intensity
            ))
            
        case "mathlissajous", "lissajous":
            animations.append(contentsOf: mathAnimationService.lissajousAnimations(
                for: object,
                startTime: startTime,
                duration: params.duration,
                intensity: intensity
            ))
            
        case "mathpendulum", "pendulum":
            animations.append(contentsOf: mathAnimationService.pendulumAnimations(
                for: object,
                startTime: startTime,
                duration: params.duration,
                intensity: intensity
            ))
            
        // MARK: Kinetic Typography Presets (from AE tutorial)
            
        case "wordpopin", "sequentialpop", "wordpop":
            // Word Pop-In: words appear one-by-one with scale overshoot + opacity
            // AE: Range Selector with Start/End offset on Opacity
            let revealDuration = max(0.9, params.duration ?? 1.4)
            animations.append(makeAnimation(type: .wordByWord, startTime: startTime, duration: revealDuration, easing: .easeOutBack, intensity: intensity))
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: min(0.35, revealDuration * 0.3), easing: .easeOut, intensity: intensity))
            // Pop scale overshoot per word
            animations.append(makeAnimation(type: .scale, startTime: startTime, duration: revealDuration * 0.7, easing: .easeOutBack, intensity: intensity))
            
        case "rotationhinge", "hingedim", "hingerotate":
            // Rotation Hinge + Color Focus: text rotates -90° around anchor, scales down, and dims
            // AE: Anchor Point Center + Rotation (-90°) + Fill Color dim
            let hingeDuration = params.duration ?? 0.8
            // Rotation from 0 → -90°
            animations.append(AnimationDefinition(
                type: .rotate,
                startTime: startTime,
                duration: hingeDuration,
                easing: .easeInOutCubic,
                keyframes: [
                    Keyframe(time: 0, value: .double(0)),
                    Keyframe(time: 1, value: .double(-90 * intensity))
                ]
            ))
            // Scale down as it rotates
            animations.append(AnimationDefinition(
                type: .scale,
                startTime: startTime,
                duration: hingeDuration,
                easing: .easeInOutCubic,
                keyframes: [
                    Keyframe(time: 0, value: .scale(x: 1, y: 1)),
                    Keyframe(time: 1, value: .scale(x: max(0.3, 0.6 * intensity), y: max(0.3, 0.6 * intensity)))
                ]
            ))
            // Fade / dim (color focus effect via opacity reduction)
            animations.append(AnimationDefinition(
                type: .fade,
                startTime: startTime,
                duration: hingeDuration,
                easing: .easeInOutCubic,
                keyframes: [
                    Keyframe(time: 0, value: .double(1)),
                    Keyframe(time: 1, value: .double(max(0.25, 0.4 / intensity)))
                ]
            ))
            
        case "cinematicstretch", "trackingreveal", "letterstretch", "kerningreveal":
            // Cinematic Stretch: letters start with wide tracking, compress to normal + fade in
            // AE: Animate Tracking Amount from high to 0
            let stretchDuration = params.duration ?? 1.2
            // Wide tracking → 0
            animations.append(AnimationDefinition(
                type: .tracking,
                startTime: startTime,
                duration: stretchDuration,
                easing: .spring,
                keyframes: [
                    Keyframe(time: 0, value: .double(30 * intensity)),
                    Keyframe(time: 1, value: .double(0))
                ]
            ))
            // Fade in alongside the tracking collapse
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: stretchDuration * 0.6, easing: .easeOut, intensity: intensity))
            
        // MARK: Anime.js-Inspired Presets
            
        case "staggerfadein", "staggerfade", "groupfade":
            // Stagger fade-in (individual object with its own stagger delay)
            animations.append(makeAnimation(type: .staggerFadeIn, startTime: startTime, duration: 0.5, easing: .easeOutCubic, intensity: intensity))
            
        case "staggerslideup", "staggerslide", "groupslide":
            // Stagger slide up entrance
            animations.append(makeAnimation(type: .staggerSlideUp, startTime: startTime, duration: 0.6, easing: .easeOutBack, intensity: intensity))
            
        case "staggerscalein", "staggerscale", "groupscale":
            // Stagger scale entrance
            animations.append(makeAnimation(type: .staggerScaleIn, startTime: startTime, duration: 0.5, easing: .easeOutBack, intensity: intensity))
            
        case "rippleenter", "ripplein", "rippleeffect":
            // Ripple entrance from center
            animations.append(makeAnimation(type: .ripple, startTime: startTime, duration: 0.6, easing: .easeOutBack, intensity: intensity))
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: 0.3, easing: .easeOut, intensity: intensity))
            
        case "cascadeenter", "waterfallenter", "cascadein":
            // Cascade / waterfall entrance
            animations.append(makeAnimation(type: .cascade, startTime: startTime, duration: 0.7, easing: .easeOutCubic, intensity: intensity))
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: 0.3, easing: .easeOut, intensity: intensity))
            
        case "dominoenter", "dominoeffect", "dominofall":
            // Domino topple entrance
            animations.append(makeAnimation(type: .domino, startTime: startTime, duration: 0.6, easing: .easeOutBack, intensity: intensity))
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: 0.3, easing: .easeOut, intensity: intensity))
            
        case "scalerotate", "scalerotatein", "spinscale":
            // Scale + rotate entrance combo
            animations.append(makeAnimation(type: .scaleRotateIn, startTime: startTime, duration: 0.7, easing: .easeOutBack, intensity: intensity))
            
        case "blurslide", "blurslidein", "blurenter":
            // Blur + slide entrance combo
            animations.append(makeAnimation(type: .blurSlideIn, startTime: startTime, duration: 0.6, easing: .easeOutCubic, intensity: intensity))
            
        case "flipreveal", "flipenter", "flipin":
            // 3D flip reveal entrance
            animations.append(makeAnimation(type: .flipReveal, startTime: startTime, duration: 0.8, easing: .easeOutCubic, intensity: intensity))
            
        case "elasticslide", "elasticslidein", "elasticenter":
            // Elastic slide entrance
            animations.append(makeAnimation(type: .elasticSlideIn, startTime: startTime, duration: 0.8, easing: .linear, intensity: intensity))
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: 0.2, easing: .easeOut, intensity: intensity))
            
        case "spiralin", "spiralenter", "spiralreveal":
            // Spiral inward entrance
            animations.append(makeAnimation(type: .spiralIn, startTime: startTime, duration: 1.0, easing: .easeInOutCubic, intensity: intensity))
            
        case "unfoldenter", "unfoldreveal", "unfoldeffect":
            // Unfold entrance
            animations.append(makeAnimation(type: .unfold, startTime: startTime, duration: 0.6, easing: .easeOutBack, intensity: intensity))
            
        case "scalerotateexit", "scalerotateout", "spinscaleexit":
            // Scale + rotate exit
            animations.append(makeAnimation(type: .scaleRotateOut, startTime: startTime, duration: 0.6, easing: .easeInCubic, intensity: intensity))
            
        case "blurslideexit", "blurslideout", "blurexit":
            // Blur + slide exit
            animations.append(makeAnimation(type: .blurSlideOut, startTime: startTime, duration: 0.5, easing: .easeInCubic, intensity: intensity))
            
        case "fliphide", "flipexit", "flipout":
            // 3D flip exit
            animations.append(makeAnimation(type: .flipHide, startTime: startTime, duration: 0.6, easing: .easeInCubic, intensity: intensity))
            
        case "spiralout", "spiralexit":
            // Spiral outward exit
            animations.append(makeAnimation(type: .spiralOut, startTime: startTime, duration: 0.8, easing: .easeInOutCubic, intensity: intensity))
            
        case "foldup", "foldexit", "foldupexit":
            // Fold up exit
            animations.append(makeAnimation(type: .foldUp, startTime: startTime, duration: 0.5, easing: .easeInCubic, intensity: intensity))
            
        case "pendulumswing", "pendulumeffect":
            // Smooth pendulum swing loop
            animations.append(makeAnimation(type: .pendulum, startTime: startTime, duration: params.duration ?? 2.0, easing: .easeInOutSine, intensity: intensity, repeatCount: -1))
            
        case "orbit2d", "circleorbit", "orbit2dloop":
            // 2D circular orbit loop
            animations.append(makeAnimation(type: .orbit2D, startTime: startTime, duration: params.duration ?? 3.0, easing: .linear, intensity: intensity, repeatCount: -1))
            
        case "figureeight2d", "figure82d", "lemniscateloop", "infinity2d":
            // Figure-8 infinity loop
            animations.append(makeAnimation(type: .lemniscate, startTime: startTime, duration: params.duration ?? 4.0, easing: .linear, intensity: intensity, repeatCount: -1))
            
        case "morphpulse", "squashpulse", "squashstretchloop":
            // Alternating squash-stretch loop
            animations.append(makeAnimation(type: .morphPulse, startTime: startTime, duration: params.duration ?? 1.5, easing: .easeInOutQuad, intensity: intensity, repeatCount: -1))
            
        case "neonflicker", "neoneffect", "neonsign":
            // Neon sign flicker loop
            animations.append(makeAnimation(type: .neonFlicker, startTime: startTime, duration: params.duration ?? 2.0, easing: .linear, intensity: intensity, repeatCount: -1))
            
        case "glowpulse", "gloweffect", "glowloop":
            // Glow/shadow pulse loop
            animations.append(makeAnimation(type: .glowPulse, startTime: startTime, duration: params.duration ?? 1.5, easing: .easeInOutSine, intensity: intensity, repeatCount: -1))
            
        case "oscillateloop", "oscillate", "sinewave":
            // Sine wave oscillation loop
            animations.append(makeAnimation(type: .oscillate, startTime: startTime, duration: params.duration ?? 2.0, easing: .easeInOutSine, intensity: intensity, repeatCount: -1))
            
        case "textwave", "wavetext", "textwavy":
            // Text wave effect
            animations.append(makeAnimation(type: .textWave, startTime: startTime, duration: params.duration ?? 1.5, easing: .easeInOutQuad, intensity: intensity, repeatCount: -1))
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: 0.3, easing: .easeOut, intensity: intensity))
            
        case "textrainbow", "rainbowtext", "textcolor":
            // Per-character rainbow hue rotation
            animations.append(makeAnimation(type: .textRainbow, startTime: startTime, duration: params.duration ?? 2.0, easing: .linear, intensity: intensity, repeatCount: -1))
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: 0.3, easing: .easeOut, intensity: intensity))
            
        case "textbouncein", "bouncytext", "textbounce":
            // Characters bounce in from above
            animations.append(makeAnimation(type: .textBounceIn, startTime: startTime, duration: 0.8, easing: .linear, intensity: intensity))
            
        case "textelasticin", "textelastic", "elastictext":
            // Characters elastic scale in
            animations.append(makeAnimation(type: .textElasticIn, startTime: startTime, duration: 0.7, easing: .linear, intensity: intensity))
            
        case "springentrance", "springenter", "springin":
            // Spring physics entrance using custom spring easing
            let springDuration = params.duration ?? 0.8
            animations.append(AnimationDefinition(
                type: .scale,
                startTime: startTime,
                duration: springDuration,
                easing: .springCustom(stiffness: 120, damping: 8, mass: 1),
                keyframes: [
                    Keyframe(time: 0, value: .scale(x: 0, y: 0)),
                    Keyframe(time: 1, value: .scale(x: 1, y: 1))
                ]
            ))
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: springDuration * 0.3, easing: .easeOut, intensity: intensity))
            
        case "popin", "popentrance":
            let popDuration = params.duration ?? 0.5
            animations.append(AnimationDefinition(
                type: .scale,
                startTime: startTime,
                duration: popDuration,
                easing: .springCustom(stiffness: 200, damping: 10, mass: 1),
                keyframes: [
                    Keyframe(time: 0, value: .scale(x: 0, y: 0)),
                    Keyframe(time: 0.6, value: .scale(x: 1.15, y: 1.15)),
                    Keyframe(time: 1, value: .scale(x: 1, y: 1))
                ]
            ))
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: popDuration * 0.2, easing: .easeOut, intensity: intensity))
            
        case "springslide", "springslidein":
            // Spring slide entrance
            let springDuration = params.duration ?? 0.8
            animations.append(AnimationDefinition(
                type: .moveX,
                startTime: startTime,
                duration: springDuration,
                easing: .springCustom(stiffness: 180, damping: 12, mass: 1),
                keyframes: [
                    Keyframe(time: 0, value: .double(-300 * intensity)),
                    Keyframe(time: 1, value: .double(0))
                ]
            ))
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: springDuration * 0.3, easing: .easeOut, intensity: intensity))
            
        case "springbounce", "springbouncein":
            // Bouncy spring entrance
            let springDuration = params.duration ?? 1.0
            animations.append(AnimationDefinition(
                type: .moveY,
                startTime: startTime,
                duration: springDuration,
                easing: .springCustom(stiffness: 100, damping: 6, mass: 1),
                keyframes: [
                    Keyframe(time: 0, value: .double(-250 * intensity)),
                    Keyframe(time: 1, value: .double(0))
                ]
            ))
            animations.append(AnimationDefinition(
                type: .scale,
                startTime: startTime,
                duration: springDuration,
                easing: .springCustom(stiffness: 100, damping: 6, mass: 1),
                keyframes: [
                    Keyframe(time: 0, value: .scale(x: 0.5, y: 0.5)),
                    Keyframe(time: 1, value: .scale(x: 1, y: 1))
                ]
            ))
            animations.append(makeAnimation(type: .fadeIn, startTime: startTime, duration: springDuration * 0.2, easing: .easeOut, intensity: intensity))
            
        case "timelinesequence", "sequenceenter", "timelineenter":
            // Timeline-sequenced entrance: fadeIn → slideUp → scale pop
            let tl = AnimeTimeline()
            tl.add(.fadeIn, duration: 0.3, easing: .easeOut,
                   keyframes: animationEngine.defaultKeyframes(for: .fadeIn),
                   at: .absolute(startTime))
            tl.add(.staggerSlideUp, duration: 0.5, easing: .easeOutBack,
                   keyframes: animationEngine.defaultKeyframes(for: .staggerSlideUp),
                   at: .withPrevious)
            tl.add(.pulse, duration: 0.4, easing: .easeInOut,
                   keyframes: animationEngine.defaultKeyframes(for: .pulse),
                   at: .offset(-0.1))
            animations.append(contentsOf: tl.build())
            
        case "steppedreveal", "steppedenter", "stepreveal":
            // Reveal using stepped easing (like stop-motion)
            let stepCount = Int(intensity * 8)
            let stepDuration = params.duration ?? 0.8
            animations.append(AnimationDefinition(
                type: .fadeIn,
                startTime: startTime,
                duration: stepDuration,
                easing: .steps(max(2, stepCount)),
                keyframes: [
                    Keyframe(time: 0, value: .double(0)),
                    Keyframe(time: 1, value: .double(1))
                ]
            ))
            animations.append(AnimationDefinition(
                type: .scale,
                startTime: startTime,
                duration: stepDuration,
                easing: .steps(max(2, stepCount)),
                keyframes: [
                    Keyframe(time: 0, value: .scale(x: 0, y: 0)),
                    Keyframe(time: 1, value: .scale(x: 1, y: 1))
                ]
            ))
            
        default:
            let normalizedFallback = presetNameRaw.replacingOccurrences(of: "-", with: "").lowercased()
            if let fallbackType = AnimationType.allCases.first(where: { $0.rawValue.lowercased() == normalizedFallback }) {
                logger.info("applyPreset: '\(presetNameRaw)' is not a preset — converting to addAnimation(\(fallbackType.rawValue))", category: .animation)
                let duration = parameters?.duration ?? 2.0
                var anim = AnimationDefinition(
                    type: fallbackType,
                    startTime: startTime,
                    duration: duration,
                    easing: .easeInOut
                )
                if fallbackType == .spin || fallbackType == .rotate {
                    anim.keyframes = [
                        Keyframe(time: 0, value: .double(0)),
                        Keyframe(time: 1, value: .double(360))
                    ]
                    anim.repeatCount = parameters?.repeatCount ?? -1
                }
                animations.append(anim)
            } else {
                logger.warning("applyPreset: Unknown preset '\(presetNameRaw)'", category: .animation)
                return
            }
        }
        
        sceneState.objects[idx].animations.append(contentsOf: animations)
        logger.success("Applied preset '\(presetNameRaw)' to '\(sceneState.objects[idx].name)'", category: .animation)
    }
    
    /// Smart object lookup: exact match → case-insensitive → partial match → fuzzy match.
    /// Returns nil (NOT last object) when target is specified but not found — prevents silent misdirected actions.
    private func resolveTargetIndex(for target: String?, parameters: ActionParameters?, allowFallback: Bool = false) -> Int? {
        let logger = DebugLogger.shared
        let effectiveTarget = target ?? parameters?.targetId ?? parameters?.id ?? parameters?.effectiveName
        
        guard let targetName = effectiveTarget, !targetName.isEmpty else {
            if allowFallback, let last = sceneState.objects.indices.last {
                logger.debug("resolveTarget: No target specified, using last object '\(sceneState.objects[last].name)'", category: .canvas)
                return last
            }
            logger.warning("resolveTarget: No target name provided and fallback disabled", category: .canvas)
            return nil
        }
        
        let lowerTarget = targetName.lowercased()
        
        // 1. Exact case-insensitive match
        if let idx = sceneState.objects.firstIndex(where: { $0.name.lowercased() == lowerTarget }) {
            return idx
        }
        
        // 2. Partial match (target is contained in object name or vice versa)
        if let idx = sceneState.objects.firstIndex(where: {
            $0.name.lowercased().contains(lowerTarget) || lowerTarget.contains($0.name.lowercased())
        }) {
            logger.debug("resolveTarget: Partial match '\(targetName)' → '\(sceneState.objects[idx].name)'", category: .canvas)
            return idx
        }
        
        // 3. Fuzzy match: strip underscores, hyphens, spaces and compare
        let normalizedTarget = lowerTarget.replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        if let idx = sceneState.objects.firstIndex(where: {
            let normalizedName = $0.name.lowercased()
                .replacingOccurrences(of: "_", with: "")
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: " ", with: "")
            return normalizedName == normalizedTarget || normalizedName.contains(normalizedTarget) || normalizedTarget.contains(normalizedName)
        }) {
            logger.debug("resolveTarget: Fuzzy match '\(targetName)' → '\(sceneState.objects[idx].name)'", category: .canvas)
            return idx
        }
        
        // 4. No match found — log warning, do NOT fall through to last object
        let availableNames = sceneState.objects.map { $0.name }.joined(separator: ", ")
        logger.warning("resolveTarget: Object '\(targetName)' not found. Available: [\(availableNames)]", category: .canvas)
        return nil
    }
    
    private func makeAnimation(
        type: AnimationType,
        startTime: Double,
        duration: Double,
        easing: EasingType,
        intensity: Double,
        repeatCount: Int = 0
    ) -> AnimationDefinition {
        let keyframes = animationEngine.defaultKeyframes(for: type).map { kf in
            var value = kf.value
            // Scale intensity for numeric values
            switch value {
            case .double(let d):
                value = .double(d * intensity)
            case .point(let x, let y):
                value = .point(x: x * intensity, y: y * intensity)
            case .scale(let x, let y):
                value = .scale(x: x * max(0.1, intensity), y: y * max(0.1, intensity))
            case .color:
                break
            }
            return Keyframe(time: kf.time, value: value)
        }
        
        return AnimationDefinition(
            type: type,
            startTime: startTime,
            duration: duration,
            easing: easing,
            keyframes: keyframes,
            repeatCount: repeatCount,
            autoReverse: false,
            delay: 0
        )
    }
    
    private func applyGridLayout(parameters: ActionParameters, target: String?) {
        let padding = parameters.gridPadding ?? 180
        let objects = filteredObjectsForGrid(target: target)
        
        guard !objects.isEmpty else { return }
        
        let count = objects.count
        let columns = parameters.gridColumns ?? Int(ceil(sqrt(Double(count))))
        let rows = Int(ceil(Double(count) / Double(columns)))
        
        let gridWidth = Double(max(columns - 1, 0)) * padding
        let gridHeight = Double(max(rows - 1, 0)) * padding
        
        let startX = parameters.gridStartX ?? (sceneState.canvasWidth - gridWidth) / 2
        let startY = parameters.gridStartY ?? (sceneState.canvasHeight - gridHeight) / 2
        
        for (i, idx) in objects.enumerated() {
            let col = i % columns
            let row = i / columns
            let x = startX + Double(col) * padding
            let y = startY + Double(row) * padding
            
            sceneState.objects[idx].properties.x = x
            sceneState.objects[idx].properties.y = y
            autoLayoutObjectNames.remove(sceneState.objects[idx].name)
        }
    }
    
    private func filteredObjectsForGrid(target: String?) -> [Int] {
        guard let target = target?.lowercased(), !target.isEmpty else {
            return Array(sceneState.objects.indices)
        }
        
        return sceneState.objects.indices.filter { idx in
            sceneState.objects[idx].name.lowercased().contains(target)
        }
    }
    
    private func applyLookAtPreset(to target: String?, parameters: ActionParameters) {
        guard let sourceIndex = resolveTargetIndex(for: target, parameters: parameters),
              let targetName = parameters.targetId ?? parameters.name ?? parameters.id,
              let targetIndex = sceneState.objects.firstIndex(where: { $0.name.lowercased() == targetName.lowercased() }) else {
            return
        }
        
        let source = sceneState.objects[sourceIndex]
        let targetObj = sceneState.objects[targetIndex]
        
        let dx = targetObj.properties.x - source.properties.x
        let dy = targetObj.properties.y - source.properties.y
        let angle = atan2(dy, dx) * 180 / .pi
        
        let anim = AnimationDefinition(
            type: .rotate,
            startTime: parameters.startTime ?? 0,
            duration: parameters.duration ?? 0.3,
            easing: .easeOut,
            keyframes: [
                Keyframe(time: 0, value: .double(source.properties.rotation)),
                Keyframe(time: 1, value: .double(angle))
            ]
        )
        
        sceneState.objects[sourceIndex].animations.append(anim)
    }

    private func applyFollowTargetPreset(to target: String?, parameters: ActionParameters) {
        guard let sourceIndex = resolveTargetIndex(for: target, parameters: parameters),
              let targetName = parameters.targetId ?? parameters.name ?? parameters.id,
              let targetIndex = sceneState.objects.firstIndex(where: { $0.name.lowercased() == targetName.lowercased() }) else {
            return
        }
        
        let source = sceneState.objects[sourceIndex]
        let targetObj = sceneState.objects[targetIndex]
        
        let anim = AnimationDefinition(
            type: .move,
            startTime: parameters.startTime ?? 0,
            duration: parameters.duration ?? 0.6,
            easing: .easeOutCubic,
            keyframes: [
                Keyframe(time: 0, value: .point(x: 0, y: 0)),
                Keyframe(time: 1, value: .point(x: targetObj.properties.x - source.properties.x,
                                               y: targetObj.properties.y - source.properties.y))
            ]
        )
        
        sceneState.objects[sourceIndex].animations.append(anim)
    }

    private func makeAspectRatioDriftAnimation(startTime: Double, intensity: Double, duration: Double) -> AnimationDefinition {
        let ratio = sceneState.canvasHeight / sceneState.canvasWidth
        let distance = 220.0 * intensity
        let dx = distance
        let dy = distance * ratio
        
        return AnimationDefinition(
            type: .move,
            startTime: startTime,
            duration: duration,
            easing: .easeInOutQuad,
            keyframes: [
                Keyframe(time: 0, value: .point(x: -dx, y: -dy)),
                Keyframe(time: 1, value: .point(x: dx, y: dy))
            ]
        )
    }
    
    private func convertAnimationValue(_ value: AnimationValue) -> KeyframeValue {
        if let d = value.doubleValue {
            return .double(d)
        }
        if let x = value.pointX, let y = value.pointY {
            return .point(x: x, y: y)
        }
        if let sx = value.scaleX, let sy = value.scaleY {
            return .scale(x: sx, y: sy)
        }
        if let color = value.color {
            return .color(color.toCodableColor())
        }
        return .double(0)
    }
    
    // MARK: - Procedural Effects
    
    private func applyProceduralEffect(_ action: SceneAction) {
        guard let params = action.parameters else {
            DebugLogger.shared.warning("applyEffect: No parameters provided", category: .canvas)
            return
        }
        
        // Find the target object's position and animations if referenced
        var originRect: (x: Double, y: Double, width: Double, height: Double)?
        var parentAnims: [AnimationDefinition] = []
        if let targetName = action.target,
           let obj = sceneState.objects.first(where: { $0.name.lowercased() == targetName.lowercased() }) {
            originRect = (x: obj.properties.x, y: obj.properties.y,
                          width: obj.properties.width, height: obj.properties.height)
            parentAnims = obj.animations
        }
        
        // Default to canvas center if no origin found
        if originRect == nil {
            originRect = (x: sceneState.canvasWidth / 2,
                          y: sceneState.canvasHeight / 2,
                          width: 50, height: 50)
        }
        
        let startTime = params.startTime ?? 0
        let effectType = params.effectType?.lowercased() ?? ""
        
        // Trail effects need parent animations to work properly
        if effectType == "trail" || effectType == "ghost" || effectType == "afterimage" {
            if parentAnims.isEmpty {
                DebugLogger.shared.warning(
                    "applyEffect 'trail': No parent animations found — trail needs a moving object to follow. Skipping.",
                    category: .canvas
                )
                return
            }
            let trailActions = ProceduralEffectService.processTrailWithAnimations(
                params: params,
                origin: originRect!,
                parentAnimations: parentAnims,
                startTime: startTime
            )
            DebugLogger.shared.info(
                "applyEffect 'trail': expanded to \(trailActions.count) actions",
                category: .canvas
            )
            for expanded in trailActions {
                processAction(expanded)
            }
            return
        }
        
        let expandedActions = ProceduralEffectService.processEffect(
            params: params, originObject: originRect, startTime: startTime
        )
        
        DebugLogger.shared.info(
            "applyEffect '\(params.effectType ?? "?")': expanded to \(expandedActions.count) actions",
            category: .canvas
        )
        
        for expanded in expandedActions {
            processAction(expanded)
        }
    }
    
    // MARK: - Scene Management
    
    private func clearScene() {
        sceneState.objects.removeAll()
        currentTime = 0
        isPlaying = false
    }
    
    private func setCanvasSize(_ parameters: ActionParameters?) {
        guard let params = parameters else { return }
        if let width = params.canvasWidth { sceneState.canvasWidth = width }
        if let height = params.canvasHeight { sceneState.canvasHeight = height }
    }
    
    /// Update canvas dimensions from UI (e.g., dimension picker)
    func setCanvasDimensions(width: Double, height: Double) {
        sceneState.canvasWidth = width
        sceneState.canvasHeight = height
        objectWillChange.send()
        onSceneStateChanged?(sceneState)
    }
    
    private func setBackgroundColor(_ parameters: ActionParameters?) {
        let logger = DebugLogger.shared
        guard let params = parameters,
              let bgColor = params.effectiveBackgroundColor else {
            logger.warning("setBackgroundColor: No color parameter found", category: .canvas)
            return
        }
        sceneState.backgroundColor = bgColor.toCodableColor()
        logger.success("Set background color", category: .canvas)
    }
    
    // MARK: - Helpers
    
    private func findObject(named name: String) -> SceneObject? {
        if let idx = resolveTargetIndex(for: name, parameters: nil) {
            return sceneState.objects[idx]
        }
        return nil
    }
    
    func loadScene(_ scene: SceneState) {
        self.sceneState = scene
        self.currentTime = 0
        self.isPlaying = false
        resolveTimingDependencies()
        
        // Ensure any custom Google Fonts used by text objects are loaded + registered
        // with CoreText. Without this, font changes from the AI agent won't appear
        // in the canvas preview (they'd show system fallback until next export/reload).
        ensureFontsLoaded(for: scene.objects)
    }
    
    /// Asynchronously load/register Google Fonts referenced by objects,
    /// then trigger a SwiftUI refresh so text views pick up the new fonts.
    private func ensureFontsLoaded(for objects: [SceneObject]) {
        var fontRequests: [(family: String, weight: String)] = []
        var seen: Set<String> = []
        
        for obj in objects where obj.type == .text {
            if let fontName = obj.properties.fontName,
               fontName.lowercased() != "sf pro" {
                let weight = obj.properties.fontWeight ?? "Regular"
                let key = "\(fontName)-\(weight)"
                if !seen.contains(key) {
                    seen.insert(key)
                    fontRequests.append((fontName, weight))
                }
            }
        }
        
        guard !fontRequests.isEmpty else { return }
        
        Task {
            for req in fontRequests {
                await GoogleFontsService.shared.ensureFontLoaded(family: req.family, weight: req.weight)
            }
            // Force SwiftUI to re-render text views with the now-available fonts
            await MainActor.run { [weak self] in
                self?.objectWillChange.send()
            }
        }
    }
    
    /// Recompute timing offsets from the current scene's object dependencies.
    /// Call this after any change that affects animation durations or dependencies.
    func resolveTimingDependencies() {
        resolvedTimingOffsets = TimingResolver.resolveOffsets(objects: sceneState.objects)
    }
    
    /// Load scene from a SceneFile + project canvas config
    func loadSceneFile(_ sceneFile: SceneFile, canvas: CanvasConfig) {
        let state = sceneFile.toSceneState(canvas: canvas)
        loadScene(state)
    }
    
    // MARK: - Project Scene Management
    
    /// Switch to a scene by index (delegates to ProjectManager)
    func switchScene(to index: Int) {
        guard let pm = projectManager else { return }
        
        // Save current scene state back to project manager first
        syncToProjectManager()
        
        // Switch scene in project manager
        pm.switchToScene(at: index)
        
        // Load the new scene
        loadSceneFile(pm.currentScene, canvas: pm.currentProject.canvas)
    }
    
    /// Switch to a scene by name (delegates to ProjectManager)
    func switchScene(named name: String) {
        guard let pm = projectManager else { return }
        
        syncToProjectManager()
        pm.switchToScene(named: name)
        loadSceneFile(pm.currentScene, canvas: pm.currentProject.canvas)
    }
    
    /// Switch to a scene by ID
    func switchScene(withId id: String) {
        guard let pm = projectManager else { return }
        
        syncToProjectManager()
        pm.switchToScene(withId: id)
        loadSceneFile(pm.currentScene, canvas: pm.currentProject.canvas)
    }
    
    /// Add a new scene to the project
    @discardableResult
    func addNewScene(name: String? = nil) -> SceneFile? {
        guard let pm = projectManager else { return nil }
        
        // Save current scene first
        syncToProjectManager()
        
        // Add scene
        guard let newScene = pm.addScene(name: name) else { return nil }
        
        // Switch to the new scene
        let newIndex = pm.currentProject.orderedScenes.count - 1
        pm.switchToScene(at: newIndex)
        loadSceneFile(pm.currentScene, canvas: pm.currentProject.canvas)
        
        return newScene
    }
    
    /// Delete a scene from the project
    func deleteScene(withId id: String) {
        guard let pm = projectManager else { return }
        pm.deleteScene(withId: id)
        
        // Load whatever scene is now current
        loadSceneFile(pm.currentScene, canvas: pm.currentProject.canvas)
    }
    
    /// Sync current sceneState back to the project manager
    func syncToProjectManager() {
        projectManager?.updateCurrentScene(from: sceneState)
        projectManager?.saveProject()
    }

    // MARK: - Layout Helpers
    
    private func estimateTextSize(text: String, fontSize: Double) -> (width: Double, height: Double) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let maxLineLength = lines.map { $0.count }.max() ?? 0
        
        let width = max(1, Double(maxLineLength)) * fontSize * 0.6
        let height = max(1, Double(lines.count)) * fontSize * 1.2
        
        return (width, height)
    }

    private func resolveImageDataURL(from params: ActionParameters) -> String? {
        if let attachmentId = params.attachmentId,
           let uuid = UUID(uuidString: attachmentId),
           let match = commandAttachments.first(where: { $0.id == uuid }) {
            return match.dataURL
        }
        
        if let index = params.attachmentIndex,
           index >= 0,
           index < commandAttachments.count {
            return commandAttachments[index].dataURL
        }
        
        if let imageData = params.imageData {
            return normalizeImageDataURL(imageData)
        }
        
        if let imageUrl = params.imageUrl {
            return normalizeImageDataURL(imageUrl)
        }
        
        return nil
    }
    
    private func normalizeImageDataURL(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("data:") {
            return trimmed
        }
        return "data:image/png;base64,\(trimmed)"
    }
    
    private func resolveImageSize(from dataURL: String) -> CGSize? {
        guard let data = dataFromDataURL(dataURL),
              let image = NSImage(data: data) else {
            return nil
        }
        return image.size
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
    
    private func clampPropertiesToCanvas(_ properties: inout ObjectProperties) {
        let padding: Double = 24
        let halfWidth = properties.width / 2
        let halfHeight = properties.height / 2
        
        let minX = halfWidth + padding
        let maxX = sceneState.canvasWidth - halfWidth - padding
        let minY = halfHeight + padding
        let maxY = sceneState.canvasHeight - halfHeight - padding
        
        if minX < maxX {
            properties.x = min(max(properties.x, minX), maxX)
        } else {
            properties.x = sceneState.canvasWidth / 2
        }
        
        if minY < maxY {
            properties.y = min(max(properties.y, minY), maxY)
        } else {
            properties.y = sceneState.canvasHeight / 2
        }
    }

    private func applyAutoLayout() {
        guard !autoLayoutObjectNames.isEmpty else { return }
        
        let indices = sceneState.objects.indices.filter { idx in
            autoLayoutObjectNames.contains(sceneState.objects[idx].name)
        }
        
        guard !indices.isEmpty else { return }
        
        let textIndices = indices.filter { sceneState.objects[$0].type == .text }
        let nonTextIndices = indices.filter { sceneState.objects[$0].type != .text }
        
        if !textIndices.isEmpty {
            applyTimelineTextLayout(textIndices)
        }
        
        if !nonTextIndices.isEmpty {
            applyGridLayoutForIndices(nonTextIndices)
        }
        
        autoLayoutObjectNames.removeAll()
    }
    
    private func applyTimelineTextLayout(_ indices: [Int]) {
        // Compute time ranges
        let items = indices.map { idx -> (idx: Int, start: Double, end: Double, fontSize: Double) in
            let obj = sceneState.objects[idx]
            let range = objectTimeRange(obj)
            let fontSize = obj.properties.fontSize ?? 48
            return (idx, range.start, range.end, fontSize)
        }
        .sorted { lhs, rhs in
            if lhs.start == rhs.start { return lhs.fontSize > rhs.fontSize }
            return lhs.start < rhs.start
        }
        
        // Assign rows to avoid time overlap
        var rows: [[(start: Double, end: Double)]] = []
        var rowAssignment: [Int: Int] = [:]
        let buffer: Double = 0.15
        
        for item in items {
            var assignedRow: Int? = nil
            
            for (rowIndex, ranges) in rows.enumerated() {
                let overlaps = ranges.contains { r in
                    !(item.end + buffer <= r.start || item.start - buffer >= r.end)
                }
                if !overlaps {
                    assignedRow = rowIndex
                    break
                }
            }
            
            if assignedRow == nil {
                rows.append([])
                assignedRow = rows.count - 1
            }
            
            rows[assignedRow!].append((item.start, item.end))
            rowAssignment[item.idx] = assignedRow!
        }
        
        // Compute y positions for rows (keep within central safe band)
        let rowCount = max(rows.count, 1)
        let topMargin = sceneState.canvasHeight * 0.2
        let bottomMargin = sceneState.canvasHeight * 0.2
        let available = sceneState.canvasHeight - topMargin - bottomMargin
        let spacing = rowCount > 1 ? available / Double(rowCount - 1) : 0
        
        for item in items {
            guard let row = rowAssignment[item.idx] else { continue }
            var obj = sceneState.objects[item.idx]
            obj.properties.x = sceneState.canvasWidth / 2
            obj.properties.y = rowCount > 1
                ? topMargin + Double(row) * spacing
                : sceneState.canvasHeight / 2
            clampPropertiesToCanvas(&obj.properties)
            sceneState.objects[item.idx] = obj
        }
    }
    
    private func applyGridLayoutForIndices(_ indices: [Int]) {
        let count = indices.count
        let aspect = sceneState.canvasWidth / sceneState.canvasHeight
        var columns = Int(ceil(sqrt(Double(count) * aspect)))
        columns = min(max(columns, 1), 4)
        let rows = Int(ceil(Double(count) / Double(columns)))
        
        let cellWidth = sceneState.canvasWidth / Double(columns)
        let cellHeight = sceneState.canvasHeight / Double(rows)
        
        for (i, idx) in indices.enumerated() {
            let col = i % columns
            let row = i / columns
            
            var obj = sceneState.objects[idx]
            obj.properties.x = cellWidth * (Double(col) + 0.5)
            obj.properties.y = cellHeight * (Double(row) + 0.5)
            clampPropertiesToCanvas(&obj.properties)
            
            sceneState.objects[idx] = obj
        }
    }

    /// Normalize z-indices so there are no gaps or duplicates.
    /// Preserves the AI's intended ordering — just compacts indices to 0, 1, 2, ...
    private func normalizeZIndices() {
        let sorted = sceneState.objects.enumerated()
            .sorted { $0.element.zIndex < $1.element.zIndex }
        
        for (newIndex, entry) in sorted.enumerated() {
            sceneState.objects[entry.offset].zIndex = newIndex
        }
    }
    
    private func isBackgroundObject(_ object: SceneObject) -> Bool {
        guard object.type == .rectangle || object.type == .ellipse || object.type == .circle || object.type == .polygon else {
            return false
        }
        
        let widthRatio = object.properties.width / sceneState.canvasWidth
        let heightRatio = object.properties.height / sceneState.canvasHeight
        return widthRatio >= 0.9 && heightRatio >= 0.9
    }

    // resolveTextOverlaps and removeImageBackplates removed — the AI controls
    // object positioning and layering directly via explicit x, y, and zIndex.
    
    private func objectTimeRange(_ object: SceneObject) -> (start: Double, end: Double) {
        guard !object.animations.isEmpty else {
            return (0, sceneState.duration)
        }
        
        var start = Double.greatestFiniteMagnitude
        var end = 0.0
        
        for animation in object.animations {
            // Ignore ambient/looping animations for layout
            if animation.repeatCount == -1 || isAmbientAnimationType(animation.type) {
                continue
            }
            
            let animStart = animation.startTime + animation.delay
            var animDuration = animation.duration
            
            if animation.repeatCount > 0 {
                animDuration *= Double(animation.repeatCount + 1)
            }
            if animation.autoReverse {
                animDuration *= 2
            }
            
            let animEnd = animStart + animDuration
            start = min(start, animStart)
            end = max(end, animEnd)
        }
        
        if start == Double.greatestFiniteMagnitude { start = 0 }
        if end <= 0 { end = start + 0.1 }
        return (start, end)
    }

    private func isAmbientAnimationType(_ type: AnimationType) -> Bool {
        switch type {
        case .pulse, .breathe, .float, .drift, .sway, .jitter, .wiggle,
             .shake, .glitch, .glitchText, .flicker:
            return true
        default:
            return false
        }
    }
    
    // MARK: - Selection & Object Mutation (Inspector / Layer Panel / Timeline)
    
    /// Select an object by ID (nil to deselect).
    /// Clears animation/keyframe selection when switching objects.
    func selectObject(_ id: UUID?) {
        if id != selectedObjectId {
            selectedAnimationId = nil
            selectedKeyframeId = nil
        }
        selectedObjectId = id
    }
    
    /// Select an animation track. Also selects the parent object.
    func selectAnimation(_ animationId: UUID?, objectId: UUID?) {
        if let oid = objectId { selectedObjectId = oid }
        selectedAnimationId = animationId
        selectedKeyframeId = nil
    }
    
    /// Select a keyframe. Also selects the parent animation and object,
    /// and moves the playhead to the keyframe's absolute time.
    func selectKeyframe(_ keyframeId: UUID?, animationId: UUID?, objectId: UUID?) {
        if let oid = objectId { selectedObjectId = oid }
        selectedAnimationId = animationId
        selectedKeyframeId = keyframeId
        
        // Move playhead to the keyframe's absolute time
        if let kid = keyframeId, let aid = animationId, let oid = objectId,
           let obj = sceneState.objects.first(where: { $0.id == oid }),
           let anim = obj.animations.first(where: { $0.id == aid }),
           let kf = anim.keyframes.first(where: { $0.id == kid }) {
            let absoluteTime = anim.startTime + anim.delay + kf.time * anim.duration
            currentTime = min(max(0, absoluteTime), sceneState.duration)
        }
    }
    
    /// The currently selected object (convenience)
    var selectedObject: SceneObject? {
        guard let id = selectedObjectId else { return nil }
        return sceneState.objects.first(where: { $0.id == id })
    }
    
    /// The currently selected animation definition (convenience)
    var selectedAnimation: AnimationDefinition? {
        guard let aid = selectedAnimationId, let obj = selectedObject else { return nil }
        return obj.animations.first(where: { $0.id == aid })
    }
    
    /// The currently selected keyframe (convenience)
    var selectedKeyframe: Keyframe? {
        guard let kid = selectedKeyframeId, let anim = selectedAnimation else { return nil }
        return anim.keyframes.first(where: { $0.id == kid })
    }
    
    /// Absolute timeline time for the selected keyframe, if selection is valid.
    var selectedKeyframeAbsoluteTime: Double? {
        guard let anim = selectedAnimation, let kf = selectedKeyframe else { return nil }
        return anim.startTime + anim.delay + kf.time * anim.duration
    }
    
    private func timelineFrameIndex(for time: Double) -> Int {
        let fps = max(Double(sceneState.fps), 1)
        return Int((time * fps).rounded())
    }
    
    /// True when the playhead is on the same frame as the selected keyframe.
    func isSelectedKeyframeAtCurrentTime() -> Bool {
        guard let keyframeTime = selectedKeyframeAbsoluteTime else { return false }
        return timelineFrameIndex(for: currentTime) == timelineFrameIndex(for: keyframeTime)
    }
    
    // MARK: - Animation Property Mapping (for Inspector scoping)
    
    /// Returns the set of property names that a given AnimationType controls.
    /// Used by the inspector to show only relevant fields when an animation track is selected.
    static func propertiesControlledBy(_ type: AnimationType) -> Set<String> {
        var result = Set<String>()
        for mapping in propertyAnimationMap {
            if mapping.types.contains(type) {
                result.insert(mapping.keyPath)
            }
        }
        // Fallback: if no mapping found, the animation might control multiple props
        // Return empty set → inspector will show all properties
        return result
    }
    
    /// Toggle visibility for an object
    func toggleObjectVisibility(_ objectId: UUID) {
        guard let idx = sceneState.objects.firstIndex(where: { $0.id == objectId }) else { return }
        sceneState.objects[idx].isVisible.toggle()
        notifySceneChanged()
    }
    
    /// Toggle lock for an object
    func toggleObjectLock(_ objectId: UUID) {
        guard let idx = sceneState.objects.firstIndex(where: { $0.id == objectId }) else { return }
        sceneState.objects[idx].isLocked.toggle()
        notifySceneChanged()
    }
    
    /// Delete an object by ID
    func deleteObjectById(_ objectId: UUID) {
        guard let idx = sceneState.objects.firstIndex(where: { $0.id == objectId }) else { return }
        let obj = sceneState.objects[idx]
        guard !obj.isLocked else { return }
        sceneState.objects.remove(at: idx)
        if selectedObjectId == objectId { selectedObjectId = nil }
        notifySceneChanged()
    }
    
    /// Rename an object
    func renameObject(_ objectId: UUID, to newName: String) {
        guard let idx = sceneState.objects.firstIndex(where: { $0.id == objectId }) else { return }
        sceneState.objects[idx].name = newName
        notifySceneChanged()
    }
    
    /// Update the full ObjectProperties for a given object (used by the Property Inspector "Apply" action)
    func applyObjectProperties(_ objectId: UUID, properties: ObjectProperties) {
        guard let idx = sceneState.objects.firstIndex(where: { $0.id == objectId }) else { return }
        guard !sceneState.objects[idx].isLocked else { return }
        sceneState.objects[idx].properties = properties
        notifySceneChanged()
    }
    
    // MARK: - Gizmo Property Updates
    
    /// Apply properties from a gizmo drag in real-time (no undo recording per frame).
    /// Use `recordGizmoUndo` at drag end for a single undo step.
    func applyGizmoProperties(_ objectId: UUID, properties: ObjectProperties) {
        guard let idx = sceneState.objects.firstIndex(where: { $0.id == objectId }) else { return }
        guard !sceneState.objects[idx].isLocked else { return }
        sceneState.objects[idx].properties = properties
        // Bump counter so the PropertyInspector can live-update
        gizmoPropertyChangeCounter &+= 1
    }
    
    /// Record an undo step for a completed gizmo drag.
    /// Called once at the end of a drag, not per-frame.
    func recordGizmoUndo(objectId: UUID, oldProperties: ObjectProperties) {
        // Build a snapshot with the old properties for undo
        var undoState = sceneState
        if let idx = undoState.objects.firstIndex(where: { $0.id == objectId }) {
            undoState.objects[idx].properties = oldProperties
        }
        let snapshot = TimelineHistorySnapshot(
            sceneState: undoState,
            currentTime: currentTime,
            selectedObjectId: selectedObjectId,
            selectedAnimationId: selectedAnimationId,
            selectedKeyframeId: selectedKeyframeId
        )
        pushUndoSnapshot(snapshot)
        timelineRedoStack.removeAll()
        updateTimelineHistoryAvailability()
        notifySceneChanged()
    }
    
    /// Move an object to a new zIndex, shifting others as needed
    func reorderObject(_ objectId: UUID, toZIndex newZ: Int) {
        guard let idx = sceneState.objects.firstIndex(where: { $0.id == objectId }) else { return }
        sceneState.objects[idx].zIndex = newZ
        notifySceneChanged()
    }
    
    // MARK: - Timeline Undo/Redo
    
    /// Begins a transaction for drag-based timeline edits.
    /// All intermediate changes are coalesced into one undo step.
    func beginTimelineHistoryTransaction() {
        guard activeTimelineTransactionStart == nil else { return }
        activeTimelineTransactionStart = makeTimelineHistorySnapshot()
    }
    
    /// Ends an active timeline transaction and records one undo step if changed.
    func endTimelineHistoryTransaction() {
        guard let start = activeTimelineTransactionStart else { return }
        activeTimelineTransactionStart = nil
        
        let current = makeTimelineHistorySnapshot()
        guard start != current else { return }
        
        pushUndoSnapshot(start)
        timelineRedoStack.removeAll()
        updateTimelineHistoryAvailability()
    }
    
    /// Undo the last timeline edit.
    func undoTimelineChange() {
        // If a drag is still "open", finalize it first.
        endTimelineHistoryTransaction()
        
        guard let previous = timelineUndoStack.popLast() else { return }
        let current = makeTimelineHistorySnapshot()
        timelineRedoStack.append(current)
        applyTimelineHistorySnapshot(previous)
        updateTimelineHistoryAvailability()
        notifySceneChanged()
    }
    
    /// Redo the last timeline edit.
    func redoTimelineChange() {
        guard let next = timelineRedoStack.popLast() else { return }
        let current = makeTimelineHistorySnapshot()
        pushUndoSnapshot(current)
        applyTimelineHistorySnapshot(next)
        updateTimelineHistoryAvailability()
        notifySceneChanged()
    }
    
    private func makeTimelineHistorySnapshot() -> TimelineHistorySnapshot {
        TimelineHistorySnapshot(
            sceneState: sceneState,
            currentTime: currentTime,
            selectedObjectId: selectedObjectId,
            selectedAnimationId: selectedAnimationId,
            selectedKeyframeId: selectedKeyframeId
        )
    }
    
    private func applyTimelineHistorySnapshot(_ snapshot: TimelineHistorySnapshot) {
        sceneState = snapshot.sceneState
        currentTime = snapshot.currentTime
        selectedObjectId = snapshot.selectedObjectId
        selectedAnimationId = snapshot.selectedAnimationId
        selectedKeyframeId = snapshot.selectedKeyframeId
    }
    
    private func captureTimelineMutationBeforeChange() -> TimelineHistorySnapshot? {
        guard activeTimelineTransactionStart == nil else { return nil }
        return makeTimelineHistorySnapshot()
    }
    
    private func recordTimelineMutationIfNeeded(_ previous: TimelineHistorySnapshot?) {
        guard let previous else { return }
        let current = makeTimelineHistorySnapshot()
        guard previous != current else { return }
        
        pushUndoSnapshot(previous)
        timelineRedoStack.removeAll()
        updateTimelineHistoryAvailability()
    }
    
    private func pushUndoSnapshot(_ snapshot: TimelineHistorySnapshot) {
        timelineUndoStack.append(snapshot)
        if timelineUndoStack.count > maxTimelineHistoryDepth {
            timelineUndoStack.removeFirst(timelineUndoStack.count - maxTimelineHistoryDepth)
        }
    }
    
    private func updateTimelineHistoryAvailability() {
        canUndoTimeline = !timelineUndoStack.isEmpty
        canRedoTimeline = !timelineRedoStack.isEmpty
    }
    
    /// Update an animation definition on an object (used by timeline edits)
    func updateAnimation(_ objectId: UUID, animationId: UUID, startTime: Double? = nil, duration: Double? = nil) {
        let timelineBefore = captureTimelineMutationBeforeChange()
        guard let objIdx = sceneState.objects.firstIndex(where: { $0.id == objectId }) else { return }
        guard let animIdx = sceneState.objects[objIdx].animations.firstIndex(where: { $0.id == animationId }) else { return }
        if let st = startTime { sceneState.objects[objIdx].animations[animIdx].startTime = max(0, st) }
        if let dur = duration { sceneState.objects[objIdx].animations[animIdx].duration = max(0.01, dur) }
        notifySceneChanged()
        recordTimelineMutationIfNeeded(timelineBefore)
    }
    
    /// Move a keyframe to a new absolute time on the timeline.
    ///
    /// When the keyframe is moved past the animation bar's edges, this method
    /// automatically extends/shrinks the animation's startTime and duration and
    /// renormalizes **all** keyframes so they remain correctly positioned.
    /// This makes diamond-drag behave like After Effects: moving an edge keyframe
    /// resizes the bar.
    func moveKeyframeToAbsoluteTime(_ objectId: UUID, animationId: UUID, keyframeId: UUID, newAbsoluteTime: Double) {
        let timelineBefore = captureTimelineMutationBeforeChange()
        guard let objIdx = sceneState.objects.firstIndex(where: { $0.id == objectId }) else { return }
        guard let animIdx = sceneState.objects[objIdx].animations.firstIndex(where: { $0.id == animationId }) else { return }
        guard let kfIdx = sceneState.objects[objIdx].animations[animIdx].keyframes.firstIndex(where: { $0.id == keyframeId }) else { return }
        
        let anim = sceneState.objects[objIdx].animations[animIdx]
        let clampedAbsTime = max(0, newAbsoluteTime)
        
        // Convert all existing keyframes to absolute time
        var absoluteTimes: [(index: Int, absTime: Double)] = anim.keyframes.enumerated().map { (idx, kf) in
            (idx, anim.startTime + kf.time * anim.duration)
        }
        
        // Update the dragged keyframe's absolute time
        if let entry = absoluteTimes.firstIndex(where: { $0.index == kfIdx }) {
            absoluteTimes[entry].absTime = clampedAbsTime
        }
        
        // Find new range
        let newMin = absoluteTimes.map(\.absTime).min() ?? 0
        let newMax = absoluteTimes.map(\.absTime).max() ?? 0.05
        let newStart = max(0, newMin)
        let newDuration = max(0.02, newMax - newMin) // minimum 20ms
        
        // Update animation timing
        sceneState.objects[objIdx].animations[animIdx].startTime = newStart
        sceneState.objects[objIdx].animations[animIdx].duration = newDuration
        
        // Renormalize all keyframes within the new range
        for (origIdx, absTime) in absoluteTimes {
            let normalized = newDuration > 0 ? (absTime - newStart) / newDuration : 0
            sceneState.objects[objIdx].animations[animIdx].keyframes[origIdx].time = min(1, max(0, normalized))
        }
        sceneState.objects[objIdx].animations[animIdx].keyframes.sort(by: { $0.time < $1.time })
        
        notifySceneChanged()
        recordTimelineMutationIfNeeded(timelineBefore)
    }
    
    /// Legacy method — simple normalized-time update (no bar resize).
    /// Kept for backward compatibility but prefer moveKeyframeToAbsoluteTime.
    func updateKeyframeTime(_ objectId: UUID, animationId: UUID, keyframeId: UUID, newTime: Double) {
        let timelineBefore = captureTimelineMutationBeforeChange()
        guard let objIdx = sceneState.objects.firstIndex(where: { $0.id == objectId }) else { return }
        guard let animIdx = sceneState.objects[objIdx].animations.firstIndex(where: { $0.id == animationId }) else { return }
        guard let kfIdx = sceneState.objects[objIdx].animations[animIdx].keyframes.firstIndex(where: { $0.id == keyframeId }) else { return }
        sceneState.objects[objIdx].animations[animIdx].keyframes[kfIdx].time = min(1, max(0, newTime))
        sceneState.objects[objIdx].animations[animIdx].keyframes.sort(by: { $0.time < $1.time })
        notifySceneChanged()
        recordTimelineMutationIfNeeded(timelineBefore)
    }
    
    /// Delete an animation from an object
    func deleteAnimation(_ objectId: UUID, animationId: UUID) {
        let timelineBefore = captureTimelineMutationBeforeChange()
        guard let objIdx = sceneState.objects.firstIndex(where: { $0.id == objectId }) else { return }
        sceneState.objects[objIdx].animations.removeAll(where: { $0.id == animationId })
        notifySceneChanged()
        recordTimelineMutationIfNeeded(timelineBefore)
    }
    
    /// Delete a keyframe from an animation
    func deleteKeyframe(_ objectId: UUID, animationId: UUID, keyframeId: UUID) {
        let timelineBefore = captureTimelineMutationBeforeChange()
        guard let objIdx = sceneState.objects.firstIndex(where: { $0.id == objectId }) else { return }
        guard let animIdx = sceneState.objects[objIdx].animations.firstIndex(where: { $0.id == animationId }) else { return }
        sceneState.objects[objIdx].animations[animIdx].keyframes.removeAll(where: { $0.id == keyframeId })
        
        // If no keyframes remain, remove the whole animation layer.
        if sceneState.objects[objIdx].animations[animIdx].keyframes.isEmpty {
            sceneState.objects[objIdx].animations.remove(at: animIdx)
            if selectedAnimationId == animationId {
                selectedAnimationId = nil
            }
        } else {
            shrinkAnimationBoundsToRemainingKeyframes(objectIndex: objIdx, animationIndex: animIdx)
        }
        
        if selectedKeyframeId == keyframeId {
            selectedKeyframeId = nil
        }
        notifySceneChanged()
        recordTimelineMutationIfNeeded(timelineBefore)
    }

    /// Refit animation start/duration to the min/max absolute time of remaining keyframes.
    /// This keeps the bar tightly aligned to existing diamonds after deletions.
    private func shrinkAnimationBoundsToRemainingKeyframes(objectIndex: Int, animationIndex: Int) {
        let anim = sceneState.objects[objectIndex].animations[animationIndex]
        guard !anim.keyframes.isEmpty else { return }
        
        let absoluteTimes = anim.keyframes.map { kf in
            anim.startTime + anim.delay + kf.time * anim.duration
        }
        guard let minAbs = absoluteTimes.min(), let maxAbs = absoluteTimes.max() else { return }
        
        let newStartAbsolute = minAbs
        let newDuration = max(0.02, maxAbs - minAbs)
        
        sceneState.objects[objectIndex].animations[animationIndex].startTime = newStartAbsolute - anim.delay
        sceneState.objects[objectIndex].animations[animationIndex].duration = newDuration
        
        for idx in sceneState.objects[objectIndex].animations[animationIndex].keyframes.indices {
            let absTime = absoluteTimes[idx]
            let normalized = (absTime - newStartAbsolute) / newDuration
            sceneState.objects[objectIndex].animations[animationIndex].keyframes[idx].time = min(1, max(0, normalized))
        }
        sceneState.objects[objectIndex].animations[animationIndex].keyframes.sort(by: { $0.time < $1.time })
    }
    
    /// Delete the currently selected keyframe, if any.
    func deleteSelectedKeyframe() {
        guard let keyframeId = selectedKeyframeId else { return }
        
        // Fast path: selection is fully scoped.
        if let objectId = selectedObjectId, let animationId = selectedAnimationId {
            deleteKeyframe(objectId, animationId: animationId, keyframeId: keyframeId)
            return
        }
        
        // Fallback: locate selected keyframe by ID.
        for object in sceneState.objects {
            for animation in object.animations where animation.keyframes.contains(where: { $0.id == keyframeId }) {
                deleteKeyframe(object.id, animationId: animation.id, keyframeId: keyframeId)
                return
            }
        }
    }
    
    /// Notify that the scene changed and persist
    private func notifySceneChanged() {
        onSceneStateChanged?(sceneState)
    }
    
    // MARK: - Animated Property Computation (for Inspector live preview)
    
    /// Computes the animated ObjectProperties for a given object at a given time.
    /// This mirrors the logic in ObjectRendererView.updateAnimatedProperties
    /// but writes back into an ObjectProperties struct for the inspector.
    func computeAnimatedProperties(for objectId: UUID, at time: Double) -> ObjectProperties? {
        guard let object = sceneState.objects.first(where: { $0.id == objectId }) else { return nil }
        
        var props = object.properties
        
        // At time 0 (editing idle) → just return base properties
        if time <= 0.001 { return props }
        
        // Start with opacity = 1 as the animation channel (will multiply by base later)
        var animOpacity: Double = 1.0
        
        for animation in object.animations {
            let startTime = animation.startTime + animation.delay
            let animTime = time - startTime
            guard animTime >= 0 else { continue }
            
            let progress = min(animTime / max(animation.duration, 0.001), 1.0)
            let easedProgress = EasingHelper.apply(animation.easing, to: progress)
            
            // Apply animation effects to props
            applyAnimationToProperties(
                type: animation.type,
                progress: easedProgress,
                keyframes: animation.keyframes,
                baseProps: object.properties,
                props: &props,
                animOpacity: &animOpacity
            )
        }
        
        // Final opacity = animation channel * base opacity
        props.opacity = max(0, min(1, animOpacity * object.properties.opacity))
        
        return props
    }
    
    /// Lightweight animation applier for the inspector.
    /// Only handles the most common animatable properties.
    private func applyAnimationToProperties(
        type: AnimationType,
        progress: Double,
        keyframes: [Keyframe],
        baseProps: ObjectProperties,
        props: inout ObjectProperties,
        animOpacity: inout Double
    ) {
        switch type {
        case .fadeIn:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let v) = value {
                animOpacity = v
            } else {
                animOpacity = progress
            }
        case .fadeOut:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let v) = value {
                animOpacity = v
            } else {
                animOpacity = 1 - progress
            }
        case .fade:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let v) = value {
                animOpacity = v
            }
        case .colorChange, .fillColorChange:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .color(let c) = value {
                props.fillColor = c
            }
        case .strokeColorChange:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .color(let c) = value {
                props.strokeColor = c
            }
        case .moveX:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let x) = value {
                props.x = baseProps.x + x
            }
        case .moveY:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let y) = value {
                props.y = baseProps.y + y
            }
        case .move:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .point(let x, let y) = value {
                props.x = baseProps.x + x
                props.y = baseProps.y + y
            }
        case .scale:
            if let value = interpolateKF(keyframes: keyframes, progress: progress) {
                if case .scale(let sx, let sy) = value {
                    props.scaleX = sx; props.scaleY = sy
                } else if case .double(let s) = value {
                    props.scaleX = s; props.scaleY = s
                }
            }
        case .scaleX:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let sx) = value { props.scaleX = sx }
        case .scaleY:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let sy) = value { props.scaleY = sy }
        case .rotate, .spin:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let r) = value { props.rotation = r }
        case .grow:
            props.scaleX = progress; props.scaleY = progress
        case .shrink:
            props.scaleX = 1 - progress; props.scaleY = 1 - progress
        case .slideIn:
            let startX = -baseProps.width
            props.x = startX + (baseProps.x - startX) * progress
        case .slideOut:
            let endX = sceneState.canvasWidth + baseProps.width
            props.x = baseProps.x + (endX - baseProps.x) * progress
        case .dropIn:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let offset) = value { props.y = baseProps.y + offset }
            animOpacity = min(1, progress * 2)
        case .riseUp:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let offset) = value { props.y = baseProps.y + offset }
            animOpacity = min(1, progress * 2)
        case .blur, .blurIn, .blurOut:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let blur) = value { props.blurRadius = max(0, blur) }
        case .strokeWidthAnim:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let w) = value { props.strokeWidth = max(0, w) }
        case .brightnessAnim:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let v) = value { props.brightness = v }
        case .contrastAnim:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let v) = value { props.contrast = v }
        case .saturationAnim:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let v) = value { props.saturation = v }
        case .hueRotate:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let v) = value { props.hueRotation = v }
        case .grayscaleAnim:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let v) = value { props.grayscale = v }
        case .shadowAnim:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let v) = value { props.shadowRadius = max(0, v) }
        case .trimPathStart:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let v) = value { props.trimStart = max(0, min(1, v)) }
        case .trimPathEnd:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let v) = value { props.trimEnd = max(0, min(1, v)) }
        case .trimPath:
            if let value = interpolateKF(keyframes: keyframes, progress: progress) {
                if case .point(let start, let end) = value {
                    props.trimStart = max(0, min(1, start))
                    props.trimEnd = max(0, min(1, end))
                } else if case .double(let v) = value {
                    props.trimEnd = max(0, min(1, v))
                }
            }
        case .trimPathOffset:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let v) = value { props.trimOffset = v.truncatingRemainder(dividingBy: 1.0) }
        case .dashOffset:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let v) = value { props.dashPhase = v }
            
        // MARK: 3D Model Animations
        case .materialFade:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let v) = value { animOpacity = v }
        case .scaleUp3D:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let s) = value {
                props.scaleX = baseProps.scaleX * s
                props.scaleY = baseProps.scaleY * s
                props.scaleZ = (baseProps.scaleZ ?? 1) * s
            }
        case .scaleDown3D:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let s) = value {
                props.scaleX = baseProps.scaleX * s
                props.scaleY = baseProps.scaleY * s
                props.scaleZ = (baseProps.scaleZ ?? 1) * s
            }
        case .popIn3D:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let s) = value {
                props.scaleX = baseProps.scaleX * s
                props.scaleY = baseProps.scaleY * s
                props.scaleZ = (baseProps.scaleZ ?? 1) * s
            }
        case .slamDown3D:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let offset) = value { props.y = baseProps.y + offset }
        case .springBounce3D:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let offset) = value { props.y = baseProps.y + offset }
        case .dropAndSettle:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let offset) = value { props.y = baseProps.y + offset }
        case .rotate3DX:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let angle) = value { props.rotationX = angle }
        case .rotate3DY:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let angle) = value { props.rotationY = angle }
        case .rotate3DZ:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let angle) = value { props.rotationZ = angle }
        case .turntable:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let angle) = value { props.rotationY = angle }
        case .cameraZoom:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let dist) = value { props.cameraDistance = dist }
        case .cameraPan:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let angle) = value {
                props.cameraAngleY = (baseProps.cameraAngleY ?? 0) + angle
            }
        case .cameraOrbit:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let angle) = value {
                props.cameraAngleY = (baseProps.cameraAngleY ?? 0) + angle
            }
        case .cameraShake:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let intensity) = value {
                let shakeX = sin(progress * .pi * 20) * intensity * 0.5
                let shakeY = cos(progress * .pi * 15) * intensity * 0.3
                props.cameraAngleX = (baseProps.cameraAngleX ?? 0) + shakeX
                props.cameraAngleY = (baseProps.cameraAngleY ?? 0) + shakeY
            }
        case .cameraRise, .cameraDive:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let angle) = value {
                props.cameraAngleX = (baseProps.cameraAngleX ?? 0) + angle
            }
        case .float3D, .levitate:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let offset) = value { props.y = baseProps.y + offset }
        case .breathe3D:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let s) = value {
                props.scaleX = baseProps.scaleX * s
                props.scaleY = baseProps.scaleY * s
                props.scaleZ = (baseProps.scaleZ ?? 1) * s
            }
        case .wobble3D:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let angle) = value { props.rotationZ = angle }
        case .flip3D:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let angle) = value { props.rotationX = angle }
        // 3D Position keyframe tracks
        case .move3DX:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let v) = value { props.position3DX = v }
        case .move3DY:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let v) = value { props.position3DY = v }
        case .move3DZ:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let v) = value { props.position3DZ = v }
        case .scale3DZ:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let v) = value { props.scaleZ = v }
        case .textSizeChange:
            if let value = interpolateKF(keyframes: keyframes, progress: progress),
               case .double(let v) = value { props.fontSize = v }
        default:
            break // Remaining types handled by ObjectRendererView/Model3DRendererView only
        }
    }
    
    /// Simple keyframe interpolation (mirrors ObjectRendererView)
    private func interpolateKF(keyframes: [Keyframe], progress: Double) -> KeyframeValue? {
        guard !keyframes.isEmpty else { return nil }
        if keyframes.count == 1 { return keyframes[0].value }
        
        let sorted = keyframes.sorted(by: { $0.time < $1.time })
        var prev = sorted[0]
        var next = sorted[sorted.count - 1]
        
        for i in 0..<sorted.count - 1 {
            if progress >= sorted[i].time && progress <= sorted[i + 1].time {
                prev = sorted[i]; next = sorted[i + 1]; break
            }
        }
        
        let span = next.time - prev.time
        let localProgress = span > 0 ? (progress - prev.time) / span : 1.0
        return interpolateKFValues(from: prev.value, to: next.value, progress: localProgress)
    }
    
    private func interpolateKFValues(from: KeyframeValue, to: KeyframeValue, progress: Double) -> KeyframeValue {
        switch (from, to) {
        case (.double(let a), .double(let b)):
            let result: Double = a + (b - a) * progress
            return .double(result)
        case (.point(let ax, let ay), .point(let bx, let by)):
            let rx: Double = ax + (bx - ax) * progress
            let ry: Double = ay + (by - ay) * progress
            return .point(x: rx, y: ry)
        case (.scale(let ax, let ay), .scale(let bx, let by)):
            let rx: Double = ax + (bx - ax) * progress
            let ry: Double = ay + (by - ay) * progress
            return .scale(x: rx, y: ry)
        case (.color(let a), .color(let b)):
            let r: Double = a.red + (b.red - a.red) * progress
            let g: Double = a.green + (b.green - a.green) * progress
            let bl: Double = a.blue + (b.blue - a.blue) * progress
            let al: Double = a.alpha + (b.alpha - a.alpha) * progress
            return .color(CodableColor(red: r, green: g, blue: bl, alpha: al))
        default:
            return progress < 0.5 ? from : to
        }
    }
    
    // MARK: - Property → Animation Type Mapping
    
    /// Which animation types control which properties
    static let propertyAnimationMap: [(keyPath: String, types: [AnimationType])] = [
        ("opacity", [.fadeIn, .fadeOut, .fade, .flicker, .flash, .neonFlicker, .materialFade]),
        ("fillColor", [.fillColorChange, .colorChange]),
        ("strokeColor", [.strokeColorChange]),
        ("x", [.moveX, .move, .slideIn, .slideOut, .drift]),
        ("y", [.moveY, .move, .dropIn, .riseUp, .drift, .float, .slamDown3D, .springBounce3D, .dropAndSettle, .float3D, .levitate]),
        ("scaleX", [.scale, .scaleX, .grow, .shrink, .pulse, .breathe, .elasticIn, .elasticOut, .scaleUp3D, .scaleDown3D, .popIn3D, .breathe3D]),
        ("scaleY", [.scale, .scaleY, .grow, .shrink, .pulse, .breathe, .elasticIn, .elasticOut, .scaleUp3D, .scaleDown3D, .popIn3D, .breathe3D]),
        ("rotation", [.rotate, .spin, .sway]),
        ("blurRadius", [.blur, .blurIn, .blurOut]),
        ("strokeWidth", [.strokeWidthAnim]),
        ("trimStart", [.trimPathStart, .trimPath]),
        ("trimEnd", [.trimPathEnd, .trimPath]),
        ("trimOffset", [.trimPathOffset]),
        ("dashPhase", [.dashOffset]),
        ("brightness", [.brightnessAnim]),
        ("contrast", [.contrastAnim]),
        ("saturation", [.saturationAnim]),
        ("hueRotation", [.hueRotate]),
        ("grayscale", [.grayscaleAnim]),
        ("shadowRadius", [.shadowAnim]),
        ("rotationX", [.rotate3DX, .flip3D]),
        ("rotationY", [.rotate3DY, .turntable]),
        ("rotationZ", [.rotate3DZ, .wobble3D]),
        ("position3DX", [.move3DX, .orbit3D]),
        ("position3DY", [.move3DY, .float3D, .levitate, .springBounce3D, .slamDown3D]),
        ("position3DZ", [.move3DZ, .orbit3D, .magnetPull, .magnetPush]),
        ("scaleZ", [.scale3DZ, .scaleUp3D, .scaleDown3D, .breathe3D, .popIn3D]),
        ("fontSize", [.textSizeChange]),
        ("cameraDistance", [.cameraZoom]),
        ("cameraAngleX", [.cameraShake, .cameraRise, .cameraDive]),
        ("cameraAngleY", [.cameraPan, .cameraOrbit, .cameraShake]),
    ]
    
    func canKeyframeProperty(_ property: String, for object: SceneObject) -> Bool {
        if property == "opacity" && object.type == .model3D { return true }
        return Self.propertyAnimationMap.contains(where: { $0.keyPath == property })
    }
    
    /// Find which animation (if any) controls the given property at the given time.
    /// First checks for an animation whose range covers the time exactly.
    /// If none found, returns the nearest animation that controls this property
    /// (preferring one that ended most recently before the current time).
    /// This allows keyframe creation past the bar's end — the bar will be extended.
    func findAnimationForProperty(_ property: String, object: SceneObject, at time: Double) -> AnimationDefinition? {
        guard let mapping = Self.propertyAnimationMap.first(where: { $0.keyPath == property }) else { return nil }
        
        let candidates = object.animations.filter { mapping.types.contains($0.type) }
        guard !candidates.isEmpty else { return nil }
        
        // 1. Exact match — cursor is within the animation range
        if let exact = candidates.first(where: { anim in
            let start = anim.startTime + anim.delay
            let end = start + anim.duration
            return time >= start && time <= end
        }) {
            return exact
        }
        
        // 2. Nearest match — find the animation whose end is closest to (but before) the cursor.
        //    This handles creating keyframes just past the bar's end.
        let nearest = candidates
            .map { anim -> (anim: AnimationDefinition, distance: Double) in
                let end = anim.startTime + anim.delay + anim.duration
                let start = anim.startTime + anim.delay
                if time > end {
                    return (anim, time - end)  // past the end
                } else {
                    return (anim, start - time) // before the start
                }
            }
            .sorted(by: { $0.distance < $1.distance })
            .first
        
        return nearest?.anim
    }
    
    private func preferredAnimationType(for property: String, object: SceneObject) -> AnimationType? {
        if property == "opacity", object.type == .model3D {
            return .materialFade
        }
        return AnimationType.animationType(forProperty: property)
    }
    
    /// Creates a new animation track for a property that doesn't have one yet.
    /// Seeds two keyframes (baseline at t=0 and edited value at current time).
    private func createAnimationTrackForProperty(
        objectIndex: Int,
        property: String,
        at time: Double,
        baselineValue: Double,
        editedValue: Double,
        makeValue: (Double) -> KeyframeValue
    ) -> (animationId: UUID, keyframeId: UUID)? {
        let object = sceneState.objects[objectIndex]
        guard let animType = preferredAnimationType(for: property, object: object) else { return nil }
        
        let safeTime = max(0, time)
        let fps = max(Double(sceneState.fps), 1)
        let oneFrame = 1.0 / fps
        
        let startTime = 0.0
        let duration = max(oneFrame, safeTime - startTime)
        let normalizedAtTime = min(1, max(0, (safeTime - startTime) / duration))
        
        let startKF = Keyframe(time: 0, value: makeValue(baselineValue))
        let editKF = Keyframe(time: normalizedAtTime, value: makeValue(editedValue))
        
        let newAnimation = AnimationDefinition(
            type: animType,
            startTime: startTime,
            duration: duration,
            easing: .easeInOut,
            keyframes: [startKF, editKF].sorted(by: { $0.time < $1.time }),
            repeatCount: 0,
            autoReverse: false,
            delay: 0
        )
        
        sceneState.objects[objectIndex].animations.append(newAnimation)
        return (newAnimation.id, editKF.id)
    }
    
    // MARK: - Smart Apply (Base props vs Keyframe creation)
    
    /// Snapping threshold: keyframes within this many seconds of each other are considered "same frame"
    static let keyframeSnapThresholdSeconds: Double = 0.03 // ~1 frame at 30fps
    
    /// Apply property changes intelligently:
    /// - At time 0: update base properties
    /// - At time > 0 with selectedAnimationId: target that specific animation
    /// - At time > 0 without selectedAnimationId: find the nearest animation for each property
    func smartApplyProperties(_ objectId: UUID, draft: ObjectProperties, at time: Double) {
        let timelineBefore = time > 0.001 ? captureTimelineMutationBeforeChange() : nil
        guard let objIdx = sceneState.objects.firstIndex(where: { $0.id == objectId }) else { return }
        let object = sceneState.objects[objIdx]
        
        let opacityAnimationTypes: Set<AnimationType> = [.fadeIn, .fadeOut, .fade, .flicker, .flash, .neonFlicker, .materialFade]
        
        // At time 0, just update base properties
        if time <= 0.001 {
            sceneState.objects[objIdx].properties = draft
            notifySceneChanged()
            return
        }
        
        // At time > 0: check each animatable property for changes
        let base = object.properties
        var updatedBase = draft // Start with all draft changes on base
        
        // Compute animated values once for all property checks
        let animatedProps = computeAnimatedProperties(for: objectId, at: time)
        
        let propertyChecks: [(String, Double, Double, (Double) -> KeyframeValue)] = [
            ("opacity", base.opacity, draft.opacity, { .double($0) }),
            ("x", base.x, draft.x, { .double($0 - base.x) }),
            ("y", base.y, draft.y, { .double($0 - base.y) }),
            ("scaleX", base.scaleX, draft.scaleX, { .double($0) }),
            ("scaleY", base.scaleY, draft.scaleY, { .double($0) }),
            ("rotation", base.rotation, draft.rotation, { .double($0) }),
            ("blurRadius", base.blurRadius, draft.blurRadius, { .double($0) }),
            ("strokeWidth", base.strokeWidth, draft.strokeWidth, { .double($0) }),
            ("trimStart", base.trimStart ?? 0, draft.trimStart ?? 0, { .double($0) }),
            ("trimEnd", base.trimEnd ?? 1, draft.trimEnd ?? 1, { .double($0) }),
            ("trimOffset", base.trimOffset ?? 0, draft.trimOffset ?? 0, { .double($0) }),
            ("dashPhase", base.dashPhase ?? 0, draft.dashPhase ?? 0, { .double($0) }),
            ("brightness", base.brightness, draft.brightness, { .double($0) }),
            ("contrast", base.contrast, draft.contrast, { .double($0) }),
            ("saturation", base.saturation, draft.saturation, { .double($0) }),
            ("hueRotation", base.hueRotation, draft.hueRotation, { .double($0) }),
            ("grayscale", base.grayscale, draft.grayscale, { .double($0) }),
            ("shadowRadius", base.shadowRadius, draft.shadowRadius, { .double($0) }),
            // 3D model properties
            ("rotationX", base.rotationX ?? 0, draft.rotationX ?? 0, { .double($0) }),
            ("rotationY", base.rotationY ?? 0, draft.rotationY ?? 0, { .double($0) }),
            ("rotationZ", base.rotationZ ?? 0, draft.rotationZ ?? 0, { .double($0) }),
            ("cameraDistance", base.cameraDistance ?? 4.2, draft.cameraDistance ?? 4.2, { .double($0) }),
            ("cameraAngleX", base.cameraAngleX ?? 0, draft.cameraAngleX ?? 0, { .double($0) }),
            ("cameraAngleY", base.cameraAngleY ?? 0, draft.cameraAngleY ?? 0, { .double($0) }),
            // 3D position, scale, text size
            ("position3DX", base.position3DX ?? 0, draft.position3DX ?? 0, { .double($0) }),
            ("position3DY", base.position3DY ?? 0, draft.position3DY ?? 0, { .double($0) }),
            ("position3DZ", base.position3DZ ?? 0, draft.position3DZ ?? 0, { .double($0) }),
            ("scaleZ", base.scaleZ ?? 1, draft.scaleZ ?? 1, { .double($0) }),
            ("fontSize", base.fontSize ?? 48, draft.fontSize ?? 48, { .double($0) }),
        ]
        
        for (propName, _, draftValue, makeValue) in propertyChecks {
            let currentAnimatedValue: Double
            switch propName {
            case "opacity": currentAnimatedValue = animatedProps?.opacity ?? base.opacity
            case "x": currentAnimatedValue = animatedProps?.x ?? base.x
            case "y": currentAnimatedValue = animatedProps?.y ?? base.y
            case "scaleX": currentAnimatedValue = animatedProps?.scaleX ?? base.scaleX
            case "scaleY": currentAnimatedValue = animatedProps?.scaleY ?? base.scaleY
            case "rotation": currentAnimatedValue = animatedProps?.rotation ?? base.rotation
            case "blurRadius": currentAnimatedValue = animatedProps?.blurRadius ?? base.blurRadius
            case "strokeWidth": currentAnimatedValue = animatedProps?.strokeWidth ?? base.strokeWidth
            case "trimStart": currentAnimatedValue = animatedProps?.trimStart ?? base.trimStart ?? 0
            case "trimEnd": currentAnimatedValue = animatedProps?.trimEnd ?? base.trimEnd ?? 1
            case "trimOffset": currentAnimatedValue = animatedProps?.trimOffset ?? base.trimOffset ?? 0
            case "dashPhase": currentAnimatedValue = animatedProps?.dashPhase ?? base.dashPhase ?? 0
            case "brightness": currentAnimatedValue = animatedProps?.brightness ?? base.brightness
            case "contrast": currentAnimatedValue = animatedProps?.contrast ?? base.contrast
            case "saturation": currentAnimatedValue = animatedProps?.saturation ?? base.saturation
            case "hueRotation": currentAnimatedValue = animatedProps?.hueRotation ?? base.hueRotation
            case "grayscale": currentAnimatedValue = animatedProps?.grayscale ?? base.grayscale
            case "shadowRadius": currentAnimatedValue = animatedProps?.shadowRadius ?? base.shadowRadius
            case "rotationX": currentAnimatedValue = animatedProps?.rotationX ?? base.rotationX ?? 0
            case "rotationY": currentAnimatedValue = animatedProps?.rotationY ?? base.rotationY ?? 0
            case "rotationZ": currentAnimatedValue = animatedProps?.rotationZ ?? base.rotationZ ?? 0
            case "cameraDistance": currentAnimatedValue = animatedProps?.cameraDistance ?? base.cameraDistance ?? 4.2
            case "cameraAngleX": currentAnimatedValue = animatedProps?.cameraAngleX ?? base.cameraAngleX ?? 0
            case "cameraAngleY": currentAnimatedValue = animatedProps?.cameraAngleY ?? base.cameraAngleY ?? 0
            case "position3DX": currentAnimatedValue = animatedProps?.position3DX ?? base.position3DX ?? 0
            case "position3DY": currentAnimatedValue = animatedProps?.position3DY ?? base.position3DY ?? 0
            case "position3DZ": currentAnimatedValue = animatedProps?.position3DZ ?? base.position3DZ ?? 0
            case "scaleZ": currentAnimatedValue = animatedProps?.scaleZ ?? base.scaleZ ?? 1
            case "fontSize": currentAnimatedValue = animatedProps?.fontSize ?? base.fontSize ?? 48
            default: continue
            }
            
            // Only process if user actually changed this property
            guard abs(draftValue - currentAnimatedValue) > 0.001 else { continue }
            
            // Determine target animation:
            // 1. If user selected a specific animation track, use it (if it controls this property)
            // 2. Otherwise, find the nearest animation for this property
            let targetAnim: AnimationDefinition?
            if let selAnimId = selectedAnimationId,
               let selAnim = object.animations.first(where: { $0.id == selAnimId }) {
                // Check if the selected animation controls this property
                let controlled = Self.propertiesControlledBy(selAnim.type)
                if controlled.isEmpty || controlled.contains(propName) {
                    targetAnim = selAnim
                } else {
                    targetAnim = findAnimationForProperty(propName, object: object, at: time)
                }
            } else {
                targetAnim = findAnimationForProperty(propName, object: object, at: time)
            }
            
            guard let anim = targetAnim else { continue }
            guard let animIdx = sceneState.objects[objIdx].animations.firstIndex(where: { $0.id == anim.id }) else { continue }
            
            let animStart = anim.startTime + anim.delay
            let animEnd = animStart + anim.duration
            
            // Extend the bar if needed (past end or before start)
            if time > animEnd {
                let newDuration = time - animStart  // Fixed: use animStart (includes delay)
                let oldDuration = anim.duration
                
                // Renormalize existing keyframes proportionally
                let ratio = oldDuration / max(newDuration, 0.001)
                for kfIdx in sceneState.objects[objIdx].animations[animIdx].keyframes.indices {
                    sceneState.objects[objIdx].animations[animIdx].keyframes[kfIdx].time *= ratio
                }
                sceneState.objects[objIdx].animations[animIdx].duration = newDuration
            }
            
            if time < animStart {
                let newDuration = animEnd - time
                let oldDuration = anim.duration
                let startShift = animStart - time
                
                let ratio = oldDuration / max(newDuration, 0.001)
                let offset = startShift / max(newDuration, 0.001)
                for kfIdx in sceneState.objects[objIdx].animations[animIdx].keyframes.indices {
                    sceneState.objects[objIdx].animations[animIdx].keyframes[kfIdx].time =
                        sceneState.objects[objIdx].animations[animIdx].keyframes[kfIdx].time * ratio + offset
                }
                sceneState.objects[objIdx].animations[animIdx].startTime = time - anim.delay
                sceneState.objects[objIdx].animations[animIdx].duration = newDuration
            }
            
            // Compute normalized time within the (possibly extended) animation
            let updatedAnim = sceneState.objects[objIdx].animations[animIdx]
            let updatedStart = updatedAnim.startTime + updatedAnim.delay
            let normalizedTime = (time - updatedStart) / max(updatedAnim.duration, 0.001)
            let clampedNorm = min(1, max(0, normalizedTime))
            
            // If user explicitly selected a keyframe on this animation, always update
            // that keyframe in-place (ID-precise), never a neighboring keyframe.
            if let selectedKfId = selectedKeyframeId,
               let selectedIdx = sceneState.objects[objIdx].animations[animIdx].keyframes.firstIndex(where: { $0.id == selectedKfId }) {
                sceneState.objects[objIdx].animations[animIdx].keyframes[selectedIdx].value = makeValue(draftValue)
                selectedAnimationId = anim.id
                selectedKeyframeId = selectedKfId
                
                switch propName {
                case "opacity":
                    // materialFade should not be capped by an old base opacity=0.
                    if opacityAnimationTypes.contains(anim.type), anim.type == .materialFade {
                        updatedBase.opacity = 1.0
                    } else {
                        updatedBase.opacity = base.opacity
                    }
                case "x": updatedBase.x = base.x
                case "y": updatedBase.y = base.y
                case "scaleX": updatedBase.scaleX = base.scaleX
                case "scaleY": updatedBase.scaleY = base.scaleY
                case "rotation": updatedBase.rotation = base.rotation
                case "blurRadius": updatedBase.blurRadius = base.blurRadius
                case "strokeWidth": updatedBase.strokeWidth = base.strokeWidth
                case "trimStart": updatedBase.trimStart = base.trimStart
                case "trimEnd": updatedBase.trimEnd = base.trimEnd
                case "trimOffset": updatedBase.trimOffset = base.trimOffset
                case "dashPhase": updatedBase.dashPhase = base.dashPhase
                case "brightness": updatedBase.brightness = base.brightness
                case "contrast": updatedBase.contrast = base.contrast
                case "saturation": updatedBase.saturation = base.saturation
                case "hueRotation": updatedBase.hueRotation = base.hueRotation
                case "grayscale": updatedBase.grayscale = base.grayscale
                case "shadowRadius": updatedBase.shadowRadius = base.shadowRadius
                case "rotationX": updatedBase.rotationX = base.rotationX
                case "rotationY": updatedBase.rotationY = base.rotationY
                case "rotationZ": updatedBase.rotationZ = base.rotationZ
                case "cameraDistance": updatedBase.cameraDistance = base.cameraDistance
                case "cameraAngleX": updatedBase.cameraAngleX = base.cameraAngleX
                case "cameraAngleY": updatedBase.cameraAngleY = base.cameraAngleY
                case "position3DX": updatedBase.position3DX = base.position3DX
                case "position3DY": updatedBase.position3DY = base.position3DY
                case "position3DZ": updatedBase.position3DZ = base.position3DZ
                case "scaleZ": updatedBase.scaleZ = base.scaleZ
                case "fontSize": updatedBase.fontSize = base.fontSize
                default: break
                }
                continue
            }
            
            // SNAPPING: Check if there's already a keyframe at this time (absolute-time-based snap)
            let snapThreshold = Self.keyframeSnapThresholdSeconds / max(updatedAnim.duration, 0.001)
            if let existingIdx = sceneState.objects[objIdx].animations[animIdx].keyframes.firstIndex(where: {
                abs($0.time - clampedNorm) < snapThreshold
            }) {
                // Snap: update the existing keyframe's value instead of creating a new one
                sceneState.objects[objIdx].animations[animIdx].keyframes[existingIdx].value = makeValue(draftValue)
                // Select this keyframe
                selectedKeyframeId = sceneState.objects[objIdx].animations[animIdx].keyframes[existingIdx].id
                selectedAnimationId = anim.id
            } else {
                // Create new keyframe
                let newKF = Keyframe(time: clampedNorm, value: makeValue(draftValue))
                sceneState.objects[objIdx].animations[animIdx].keyframes.append(newKF)
                sceneState.objects[objIdx].animations[animIdx].keyframes.sort(by: { $0.time < $1.time })
                // Select the new keyframe
                selectedKeyframeId = newKF.id
                selectedAnimationId = anim.id
            }
            
            // Don't change the base property for animated values
            switch propName {
            case "opacity":
                if opacityAnimationTypes.contains(anim.type), anim.type == .materialFade {
                    updatedBase.opacity = 1.0
                } else {
                    updatedBase.opacity = base.opacity
                }
            case "x": updatedBase.x = base.x
            case "y": updatedBase.y = base.y
            case "scaleX": updatedBase.scaleX = base.scaleX
            case "scaleY": updatedBase.scaleY = base.scaleY
            case "rotation": updatedBase.rotation = base.rotation
            case "blurRadius": updatedBase.blurRadius = base.blurRadius
            case "strokeWidth": updatedBase.strokeWidth = base.strokeWidth
            case "trimStart": updatedBase.trimStart = base.trimStart
            case "trimEnd": updatedBase.trimEnd = base.trimEnd
            case "trimOffset": updatedBase.trimOffset = base.trimOffset
            case "dashPhase": updatedBase.dashPhase = base.dashPhase
            case "brightness": updatedBase.brightness = base.brightness
            case "contrast": updatedBase.contrast = base.contrast
            case "saturation": updatedBase.saturation = base.saturation
            case "hueRotation": updatedBase.hueRotation = base.hueRotation
            case "grayscale": updatedBase.grayscale = base.grayscale
            case "shadowRadius": updatedBase.shadowRadius = base.shadowRadius
            case "rotationX": updatedBase.rotationX = base.rotationX
            case "rotationY": updatedBase.rotationY = base.rotationY
            case "rotationZ": updatedBase.rotationZ = base.rotationZ
            case "cameraDistance": updatedBase.cameraDistance = base.cameraDistance
            case "cameraAngleX": updatedBase.cameraAngleX = base.cameraAngleX
            case "cameraAngleY": updatedBase.cameraAngleY = base.cameraAngleY
            case "position3DX": updatedBase.position3DX = base.position3DX
            case "position3DY": updatedBase.position3DY = base.position3DY
            case "position3DZ": updatedBase.position3DZ = base.position3DZ
            case "scaleZ": updatedBase.scaleZ = base.scaleZ
            case "fontSize": updatedBase.fontSize = base.fontSize
            default: break
            }
        }
        
        // Color keyframe updates (used by fill/stroke color tracks)
        let currentAnimatedFill = animatedProps?.fillColor ?? base.fillColor
        let currentAnimatedStroke = animatedProps?.strokeColor ?? base.strokeColor
        
        func upsertColorKeyframe(property: String, draftColor: CodableColor, currentAnimatedColor: CodableColor) {
            guard draftColor != currentAnimatedColor else { return }
            
            let currentObject = sceneState.objects[objIdx]
            let targetAnim: AnimationDefinition?
            if let selAnimId = selectedAnimationId,
               let selAnim = currentObject.animations.first(where: { $0.id == selAnimId }) {
                let controlled = Self.propertiesControlledBy(selAnim.type)
                if controlled.isEmpty || controlled.contains(property) {
                    targetAnim = selAnim
                } else {
                    targetAnim = findAnimationForProperty(property, object: currentObject, at: time)
                }
            } else {
                targetAnim = findAnimationForProperty(property, object: currentObject, at: time)
            }
            
            guard let anim = targetAnim,
                  let animIdx = sceneState.objects[objIdx].animations.firstIndex(where: { $0.id == anim.id }) else { return }
            
            let animStart = anim.startTime + anim.delay
            let animEnd = animStart + anim.duration
            
            if time > animEnd {
                let newDuration = time - animStart
                let oldDuration = anim.duration
                let ratio = oldDuration / max(newDuration, 0.001)
                for kfIdx in sceneState.objects[objIdx].animations[animIdx].keyframes.indices {
                    sceneState.objects[objIdx].animations[animIdx].keyframes[kfIdx].time *= ratio
                }
                sceneState.objects[objIdx].animations[animIdx].duration = newDuration
            } else if time < animStart {
                let newDuration = animEnd - time
                let oldDuration = anim.duration
                let startShift = animStart - time
                let ratio = oldDuration / max(newDuration, 0.001)
                let offset = startShift / max(newDuration, 0.001)
                for kfIdx in sceneState.objects[objIdx].animations[animIdx].keyframes.indices {
                    sceneState.objects[objIdx].animations[animIdx].keyframes[kfIdx].time =
                        sceneState.objects[objIdx].animations[animIdx].keyframes[kfIdx].time * ratio + offset
                }
                sceneState.objects[objIdx].animations[animIdx].startTime = time - anim.delay
                sceneState.objects[objIdx].animations[animIdx].duration = newDuration
            }
            
            let updatedAnim = sceneState.objects[objIdx].animations[animIdx]
            let updatedStart = updatedAnim.startTime + updatedAnim.delay
            let normalizedTime = (time - updatedStart) / max(updatedAnim.duration, 0.001)
            let clampedNorm = min(1, max(0, normalizedTime))
            
            if let selectedKfId = selectedKeyframeId,
               let selectedIdx = sceneState.objects[objIdx].animations[animIdx].keyframes.firstIndex(where: { $0.id == selectedKfId }) {
                sceneState.objects[objIdx].animations[animIdx].keyframes[selectedIdx].value = .color(draftColor)
                selectedAnimationId = anim.id
                selectedKeyframeId = selectedKfId
                return
            }
            
            let snapThreshold = Self.keyframeSnapThresholdSeconds / max(updatedAnim.duration, 0.001)
            if let existingIdx = sceneState.objects[objIdx].animations[animIdx].keyframes.firstIndex(where: {
                abs($0.time - clampedNorm) < snapThreshold
            }) {
                sceneState.objects[objIdx].animations[animIdx].keyframes[existingIdx].value = .color(draftColor)
                selectedKeyframeId = sceneState.objects[objIdx].animations[animIdx].keyframes[existingIdx].id
                selectedAnimationId = anim.id
            } else {
                let newKF = Keyframe(time: clampedNorm, value: .color(draftColor))
                sceneState.objects[objIdx].animations[animIdx].keyframes.append(newKF)
                sceneState.objects[objIdx].animations[animIdx].keyframes.sort(by: { $0.time < $1.time })
                selectedKeyframeId = newKF.id
                selectedAnimationId = anim.id
            }
        }
        
        upsertColorKeyframe(property: "fillColor", draftColor: draft.fillColor, currentAnimatedColor: currentAnimatedFill)
        upsertColorKeyframe(property: "strokeColor", draftColor: draft.strokeColor, currentAnimatedColor: currentAnimatedStroke)
        
        // Apply the base property updates (for non-animated properties)
        sceneState.objects[objIdx].properties = updatedBase
        notifySceneChanged()
        recordTimelineMutationIfNeeded(timelineBefore)
    }
    
    /// Adds (or updates) a keyframe for one specific property at the playhead time.
    /// Used by object-mode per-property keyframe buttons.
    func addKeyframeForProperty(_ objectId: UUID, property: String, value: Double, at time: Double) {
        let timelineBefore = captureTimelineMutationBeforeChange()
        guard let objIdx = sceneState.objects.firstIndex(where: { $0.id == objectId }) else { return }
        guard time > 0.001 else { return }
        
        let object = sceneState.objects[objIdx]
        let base = object.properties
        
        let baseValue: Double
        let makeValue: (Double) -> KeyframeValue
        switch property {
        case "opacity":
            baseValue = base.opacity
            makeValue = { .double($0) }
        case "x":
            baseValue = base.x
            makeValue = { .double($0 - base.x) }
        case "y":
            baseValue = base.y
            makeValue = { .double($0 - base.y) }
        case "scaleX":
            baseValue = base.scaleX
            makeValue = { .double($0) }
        case "scaleY":
            baseValue = base.scaleY
            makeValue = { .double($0) }
        case "rotation":
            baseValue = base.rotation
            makeValue = { .double($0) }
        case "blurRadius":
            baseValue = base.blurRadius
            makeValue = { .double($0) }
        case "strokeWidth":
            baseValue = base.strokeWidth
            makeValue = { .double($0) }
        case "trimStart":
            baseValue = base.trimStart ?? 0
            makeValue = { .double($0) }
        case "trimEnd":
            baseValue = base.trimEnd ?? 1
            makeValue = { .double($0) }
        case "trimOffset":
            baseValue = base.trimOffset ?? 0
            makeValue = { .double($0) }
        case "dashPhase":
            baseValue = base.dashPhase ?? 0
            makeValue = { .double($0) }
        case "brightness":
            baseValue = base.brightness
            makeValue = { .double($0) }
        case "contrast":
            baseValue = base.contrast
            makeValue = { .double($0) }
        case "saturation":
            baseValue = base.saturation
            makeValue = { .double($0) }
        case "hueRotation":
            baseValue = base.hueRotation
            makeValue = { .double($0) }
        case "grayscale":
            baseValue = base.grayscale
            makeValue = { .double($0) }
        case "shadowRadius":
            baseValue = base.shadowRadius
            makeValue = { .double($0) }
        case "rotationX":
            baseValue = base.rotationX ?? 0
            makeValue = { .double($0) }
        case "rotationY":
            baseValue = base.rotationY ?? 0
            makeValue = { .double($0) }
        case "rotationZ":
            baseValue = base.rotationZ ?? 0
            makeValue = { .double($0) }
        case "cameraDistance":
            baseValue = base.cameraDistance ?? 4.2
            makeValue = { .double($0) }
        case "cameraAngleX":
            baseValue = base.cameraAngleX ?? 0
            makeValue = { .double($0) }
        case "cameraAngleY":
            baseValue = base.cameraAngleY ?? 0
            makeValue = { .double($0) }
        case "position3DX":
            baseValue = base.position3DX ?? 0
            makeValue = { .double($0) }
        case "position3DY":
            baseValue = base.position3DY ?? 0
            makeValue = { .double($0) }
        case "position3DZ":
            baseValue = base.position3DZ ?? 0
            makeValue = { .double($0) }
        case "scaleZ":
            baseValue = base.scaleZ ?? 1.0
            makeValue = { .double($0) }
        case "fontSize":
            baseValue = base.fontSize ?? 48
            makeValue = { .double($0) }
        default:
            return
        }
        
        let targetAnim: AnimationDefinition?
        if let selAnimId = selectedAnimationId,
           let selAnim = object.animations.first(where: { $0.id == selAnimId }) {
            let controlled = Self.propertiesControlledBy(selAnim.type)
            if controlled.isEmpty || controlled.contains(property) {
                targetAnim = selAnim
            } else {
                targetAnim = findAnimationForProperty(property, object: object, at: time)
            }
        } else {
            targetAnim = findAnimationForProperty(property, object: object, at: time)
        }
        
        let animId: UUID
        let animIdx: Int
        if let anim = targetAnim, let idx = sceneState.objects[objIdx].animations.firstIndex(where: { $0.id == anim.id }) {
            animId = anim.id
            animIdx = idx
        } else {
            guard let created = createAnimationTrackForProperty(
                objectIndex: objIdx,
                property: property,
                at: time,
                baselineValue: baseValue,
                editedValue: value,
                makeValue: makeValue
            ),
            let idx = sceneState.objects[objIdx].animations.firstIndex(where: { $0.id == created.animationId }) else { return }
            
            selectedAnimationId = created.animationId
            selectedKeyframeId = created.keyframeId
            
            if property == "opacity", sceneState.objects[objIdx].type == .model3D {
                sceneState.objects[objIdx].properties.opacity = 1.0
            }
            
            notifySceneChanged()
            recordTimelineMutationIfNeeded(timelineBefore)
            return
        }
        
        let anim = sceneState.objects[objIdx].animations[animIdx]
        let animStart = anim.startTime + anim.delay
        let animEnd = animStart + anim.duration
        
        if time > animEnd {
            let newDuration = time - animStart
            let oldDuration = anim.duration
            let ratio = oldDuration / max(newDuration, 0.001)
            for kfIdx in sceneState.objects[objIdx].animations[animIdx].keyframes.indices {
                sceneState.objects[objIdx].animations[animIdx].keyframes[kfIdx].time *= ratio
            }
            sceneState.objects[objIdx].animations[animIdx].duration = newDuration
        } else if time < animStart {
            let newDuration = animEnd - time
            let oldDuration = anim.duration
            let startShift = animStart - time
            let ratio = oldDuration / max(newDuration, 0.001)
            let offset = startShift / max(newDuration, 0.001)
            for kfIdx in sceneState.objects[objIdx].animations[animIdx].keyframes.indices {
                sceneState.objects[objIdx].animations[animIdx].keyframes[kfIdx].time =
                    sceneState.objects[objIdx].animations[animIdx].keyframes[kfIdx].time * ratio + offset
            }
            sceneState.objects[objIdx].animations[animIdx].startTime = time - anim.delay
            sceneState.objects[objIdx].animations[animIdx].duration = newDuration
        }
        
        let updatedAnim = sceneState.objects[objIdx].animations[animIdx]
        let updatedStart = updatedAnim.startTime + updatedAnim.delay
        let normalizedTime = (time - updatedStart) / max(updatedAnim.duration, 0.001)
        let clampedNorm = min(1, max(0, normalizedTime))
        
        let snapThreshold = Self.keyframeSnapThresholdSeconds / max(updatedAnim.duration, 0.001)
        if let existingIdx = sceneState.objects[objIdx].animations[animIdx].keyframes.firstIndex(where: {
            abs($0.time - clampedNorm) < snapThreshold
        }) {
            sceneState.objects[objIdx].animations[animIdx].keyframes[existingIdx].value = makeValue(value)
            selectedKeyframeId = sceneState.objects[objIdx].animations[animIdx].keyframes[existingIdx].id
        } else {
            let newKF = Keyframe(time: clampedNorm, value: makeValue(value))
            sceneState.objects[objIdx].animations[animIdx].keyframes.append(newKF)
            sceneState.objects[objIdx].animations[animIdx].keyframes.sort(by: { $0.time < $1.time })
            selectedKeyframeId = newKF.id
        }
        
        selectedAnimationId = animId
        if property == "opacity", sceneState.objects[objIdx].type == .model3D {
            sceneState.objects[objIdx].properties.opacity = 1.0
        }
        
        notifySceneChanged()
        recordTimelineMutationIfNeeded(timelineBefore)
    }
    
    /// Adds (or updates) a keyframe for one specific color property at the playhead time.
    /// Supported properties: "fillColor", "strokeColor".
    func addKeyframeForColorProperty(_ objectId: UUID, property: String, value: CodableColor, at time: Double) {
        let timelineBefore = captureTimelineMutationBeforeChange()
        guard let objIdx = sceneState.objects.firstIndex(where: { $0.id == objectId }) else { return }
        guard time > 0.001 else { return }
        
        let object = sceneState.objects[objIdx]
        let base = object.properties
        
        let baseValue: CodableColor
        switch property {
        case "fillColor":
            baseValue = base.fillColor
        case "strokeColor":
            baseValue = base.strokeColor
        default:
            return
        }
        
        let targetAnim: AnimationDefinition?
        if let selAnimId = selectedAnimationId,
           let selAnim = object.animations.first(where: { $0.id == selAnimId }) {
            let controlled = Self.propertiesControlledBy(selAnim.type)
            if controlled.isEmpty || controlled.contains(property) {
                targetAnim = selAnim
            } else {
                targetAnim = findAnimationForProperty(property, object: object, at: time)
            }
        } else {
            targetAnim = findAnimationForProperty(property, object: object, at: time)
        }
        
        let animId: UUID
        let animIdx: Int
        if let anim = targetAnim, let idx = sceneState.objects[objIdx].animations.firstIndex(where: { $0.id == anim.id }) {
            animId = anim.id
            animIdx = idx
        } else {
            guard let animType = preferredAnimationType(for: property, object: object) else { return }
            let safeTime = max(0, time)
            let fps = max(Double(sceneState.fps), 1)
            let oneFrame = 1.0 / fps
            let startTime = 0.0
            let duration = max(oneFrame, safeTime - startTime)
            let normalizedAtTime = min(1, max(0, (safeTime - startTime) / duration))
            
            let startKF = Keyframe(time: 0, value: .color(baseValue))
            let editKF = Keyframe(time: normalizedAtTime, value: .color(value))
            let newAnimation = AnimationDefinition(
                type: animType,
                startTime: startTime,
                duration: duration,
                easing: .easeInOut,
                keyframes: [startKF, editKF].sorted(by: { $0.time < $1.time }),
                repeatCount: 0,
                autoReverse: false,
                delay: 0
            )
            sceneState.objects[objIdx].animations.append(newAnimation)
            
            selectedAnimationId = newAnimation.id
            selectedKeyframeId = editKF.id
            notifySceneChanged()
            recordTimelineMutationIfNeeded(timelineBefore)
            return
        }
        
        let anim = sceneState.objects[objIdx].animations[animIdx]
        let animStart = anim.startTime + anim.delay
        let animEnd = animStart + anim.duration
        
        if time > animEnd {
            let newDuration = time - animStart
            let oldDuration = anim.duration
            let ratio = oldDuration / max(newDuration, 0.001)
            for kfIdx in sceneState.objects[objIdx].animations[animIdx].keyframes.indices {
                sceneState.objects[objIdx].animations[animIdx].keyframes[kfIdx].time *= ratio
            }
            sceneState.objects[objIdx].animations[animIdx].duration = newDuration
        } else if time < animStart {
            let newDuration = animEnd - time
            let oldDuration = anim.duration
            let startShift = animStart - time
            let ratio = oldDuration / max(newDuration, 0.001)
            let offset = startShift / max(newDuration, 0.001)
            for kfIdx in sceneState.objects[objIdx].animations[animIdx].keyframes.indices {
                sceneState.objects[objIdx].animations[animIdx].keyframes[kfIdx].time =
                    sceneState.objects[objIdx].animations[animIdx].keyframes[kfIdx].time * ratio + offset
            }
            sceneState.objects[objIdx].animations[animIdx].startTime = time - anim.delay
            sceneState.objects[objIdx].animations[animIdx].duration = newDuration
        }
        
        let updatedAnim = sceneState.objects[objIdx].animations[animIdx]
        let updatedStart = updatedAnim.startTime + updatedAnim.delay
        let normalizedTime = (time - updatedStart) / max(updatedAnim.duration, 0.001)
        let clampedNorm = min(1, max(0, normalizedTime))
        
        let snapThreshold = Self.keyframeSnapThresholdSeconds / max(updatedAnim.duration, 0.001)
        if let existingIdx = sceneState.objects[objIdx].animations[animIdx].keyframes.firstIndex(where: {
            abs($0.time - clampedNorm) < snapThreshold
        }) {
            sceneState.objects[objIdx].animations[animIdx].keyframes[existingIdx].value = .color(value)
            selectedKeyframeId = sceneState.objects[objIdx].animations[animIdx].keyframes[existingIdx].id
        } else {
            let newKF = Keyframe(time: clampedNorm, value: .color(value))
            sceneState.objects[objIdx].animations[animIdx].keyframes.append(newKF)
            sceneState.objects[objIdx].animations[animIdx].keyframes.sort(by: { $0.time < $1.time })
            selectedKeyframeId = newKF.id
        }
        
        selectedAnimationId = animId
        notifySceneChanged()
        recordTimelineMutationIfNeeded(timelineBefore)
    }
}
