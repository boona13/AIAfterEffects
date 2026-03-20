//
//  ProjectManager.swift
//  AIAfterEffects
//
//  Manages the current project lifecycle: loading, saving, scene switching.
//  All scene data lives in-memory within the Project model and is saved to a single project.json.
//

import Foundation
import Combine

@MainActor
class ProjectManager: ObservableObject {
    // MARK: - Published Properties
    
    @Published var currentProject: Project
    @Published var currentSceneIndex: Int = 0
    @Published var projectURL: URL?
    @Published var projectList: [ProjectSummary] = []
    @Published var isLoaded: Bool = false
    @Published var showWelcome: Bool = false
    @Published var showProjectBrowser: Bool = false
    
    // Chat session management (file-based, multiple sessions per project)
    @Published var currentChatSession: ChatSessionFile?
    @Published var chatSessionList: [ChatSessionSummary] = []
    
    // Checkpoint management
    @Published var checkpoints: [Checkpoint] = []
    @Published private(set) var isGitReady: Bool = false
    
    // Legacy session support (kept for conversation persistence during migration)
    @Published var currentSession: Session
    
    // MARK: - Computed Properties
    
    /// The current scene — derived from the project's scenes array and current index.
    var currentScene: SceneFile {
        get {
            let ordered = currentProject.orderedScenes
            guard currentSceneIndex >= 0, currentSceneIndex < ordered.count else {
                return SceneFile.empty()
            }
            return ordered[currentSceneIndex]
        }
        set {
            let ordered = currentProject.orderedScenes
            guard currentSceneIndex >= 0, currentSceneIndex < ordered.count else { return }
            let sceneId = ordered[currentSceneIndex].id
            if let idx = currentProject.scenes.firstIndex(where: { $0.id == sceneId }) {
                currentProject.scenes[idx] = newValue
            }
            objectWillChange.send()
        }
    }
    
    // MARK: - Private Properties
    
    private let fileService: ProjectFileServiceProtocol
    private let chatSessionService: ChatSessionServiceProtocol
    private let checkpointService: CheckpointServiceProtocol
    private let currentProjectURLKey = "ai_aftereffects_current_project_url"
    private let recentProjectURLsKey = "ai_aftereffects_recent_project_urls"
    private var gitInitTask: Task<Void, Never>?
    
    // MARK: - Init
    
    init(
        fileService: ProjectFileServiceProtocol = ProjectFileService.shared,
        chatSessionService: ChatSessionServiceProtocol = ChatSessionService.shared,
        checkpointService: CheckpointServiceProtocol = CheckpointService.shared
    ) {
        self.fileService = fileService
        self.chatSessionService = chatSessionService
        self.checkpointService = checkpointService
        self.currentProject = Project.newProject()
        self.currentSession = Session.newSession()
    }
    
    // MARK: - Startup
    
    /// Load the last-used project or create a new one.
    /// Always shows the welcome screen first — the user picks a project from there.
    func loadOnStartup() {
        // Run migration from legacy sessions if needed
        migrateLegacySessions()
        
        // Pre-load last project data in the background so it's ready when picked
        if let savedURLString = UserDefaults.standard.string(forKey: currentProjectURLKey),
           let savedURL = URL(string: savedURLString) {
            do {
                let project = try fileService.loadProject(at: savedURL)
                self.currentProject = project
                self.projectURL = savedURL
                self.currentSceneIndex = 0
                
                // Load chat sessions (file-based)
                loadChatSessions(projectURL: savedURL)
                
                // Legacy: load conversation
                loadSessionForProject()
                
                // Auto-init checkpoint system (idempotent, loads checkpoints)
                ensureGitInitialized()
            } catch {
                print("Failed to restore project: \(error)")
            }
        }
        
        refreshProjectList()
        
        // Always show welcome screen on launch
        showWelcome = true
        isLoaded = true
    }
    
    // MARK: - Migration
    
    private static let migrationKey = "ai_aftereffects_migration_v2_done"
    
    /// Migrate legacy UserDefaults sessions into project folders
    private func migrateLegacySessions() {
        guard !UserDefaults.standard.bool(forKey: Self.migrationKey) else { return }
        
        print("[Migration] Checking for legacy sessions to migrate...")
        
        // Try to load the current legacy session
        if let currentSession = SessionManager.loadCurrentSession(),
           !currentSession.conversation.messages.isEmpty || !currentSession.sceneState.objects.isEmpty {
            
            let sessionName = currentSession.conversation.title ?? "Migrated Project"
            
            do {
                let canvas = CanvasConfig(
                    width: currentSession.sceneState.canvasWidth,
                    height: currentSession.sceneState.canvasHeight,
                    fps: currentSession.sceneState.fps
                )
                let (_, url) = try fileService.createProject(name: sessionName, canvas: canvas)
                
                // Load the project we just created
                var project = try fileService.loadProject(at: url)
                
                // Update the first scene with migrated data
                if !project.scenes.isEmpty {
                    project.scenes[0] = SceneFile(
                        from: currentSession.sceneState,
                        id: project.scenes[0].id,
                        name: "Scene 1",
                        order: 0
                    )
                    try fileService.saveProject(project, at: url)
                }
                
                // Save the conversation for this project
                let sessionKey = "project_session_\(project.id.uuidString)"
                if let data = try? JSONEncoder().encode(currentSession) {
                    UserDefaults.standard.set(data, forKey: sessionKey)
                }
                
                // Point to this project as the current one
                UserDefaults.standard.set(url.absoluteString, forKey: currentProjectURLKey)
                
                print("[Migration] Successfully migrated session '\(sessionName)' to project")
            } catch {
                print("[Migration] Failed to migrate session: \(error)")
            }
        }
        
        // Also migrate session history
        let historyKey = "ai_aftereffects_sessions"
        if let historyData = UserDefaults.standard.data(forKey: historyKey),
           let summaries = try? JSONDecoder().decode([SessionSummary].self, from: historyData) {
            
            for summary in summaries.prefix(10) {
                let sessionKey = "session_\(summary.id.uuidString)"
                guard let sessionData = UserDefaults.standard.data(forKey: sessionKey),
                      let session = try? JSONDecoder().decode(Session.self, from: sessionData),
                      !session.sceneState.objects.isEmpty else { continue }
                
                let name = summary.title ?? "Migrated \(summary.id.uuidString.prefix(8))"
                
                do {
                    let canvas = CanvasConfig(
                        width: session.sceneState.canvasWidth,
                        height: session.sceneState.canvasHeight,
                        fps: session.sceneState.fps
                    )
                    let (_, url) = try fileService.createProject(name: name, canvas: canvas)
                    var project = try fileService.loadProject(at: url)
                    
                    if !project.scenes.isEmpty {
                        project.scenes[0] = SceneFile(
                            from: session.sceneState,
                            id: project.scenes[0].id,
                            name: "Scene 1",
                            order: 0
                        )
                        try fileService.saveProject(project, at: url)
                    }
                    
                    let projSessionKey = "project_session_\(project.id.uuidString)"
                    if let data = try? JSONEncoder().encode(session) {
                        UserDefaults.standard.set(data, forKey: projSessionKey)
                    }
                    
                    print("[Migration] Migrated historical session '\(name)'")
                } catch {
                    print("[Migration] Failed to migrate session '\(name)': \(error)")
                }
            }
        }
        
        // Mark migration as complete
        UserDefaults.standard.set(true, forKey: Self.migrationKey)
        print("[Migration] Migration complete")
    }
    
    // MARK: - Project Management
    
    /// Create a new project in the default location
    @discardableResult
    func createNewProject(name: String, canvas: CanvasConfig = CanvasConfig()) -> Bool {
        do {
            let (project, url) = try fileService.createProject(name: name, canvas: canvas)
            return finishProjectCreation(project, url: url)
        } catch {
            print("Failed to create project: \(error)")
            return false
        }
    }
    
    /// Create a new project at a user-chosen location
    @discardableResult
    func createNewProject(name: String, canvas: CanvasConfig = CanvasConfig(), at parentURL: URL) -> Bool {
        do {
            let (project, url) = try fileService.createProject(name: name, canvas: canvas, at: parentURL)
            return finishProjectCreation(project, url: url)
        } catch {
            print("Failed to create project at \(parentURL.path): \(error)")
            return false
        }
    }
    
    private func finishProjectCreation(_ project: Project, url: URL) -> Bool {
        do {
            self.currentProject = project
            self.projectURL = url
            self.currentSceneIndex = 0
            
            // Create the first chat session (file-based)
            let chatSession = try chatSessionService.createSession(projectURL: url)
            self.currentChatSession = chatSession
            refreshChatSessions()
            
            // Legacy: reset conversation
            self.currentSession = Session.newSession()
            saveSessionForProject()
            
            // Auto-init checkpoint system (idempotent, loads checkpoints)
            ensureGitInitialized()
            
            // Remember this project
            saveCurrentProjectURL()
            refreshProjectList()
            
            return true
        } catch {
            print("Failed to finish project creation: \(error)")
            return false
        }
    }
    
    /// Open an existing project
    func openProject(at url: URL) {
        do {
            let project = try fileService.loadProject(at: url)
            
            // Save current project first
            saveProject()
            saveChatSession()
            
            self.currentProject = project
            self.projectURL = url
            self.currentSceneIndex = 0
            
            // Load chat sessions (file-based)
            loadChatSessions(projectURL: url)
            
            // Legacy: Load conversation
            loadSessionForProject()
            
            // Auto-init checkpoint system (idempotent, loads checkpoints)
            ensureGitInitialized()
            
            saveCurrentProjectURL()
            refreshProjectList()
        } catch {
            print("Failed to open project: \(error)")
        }
    }
    
    /// Delete a project
    func deleteProject(at url: URL) {
        do {
            try fileService.deleteProject(at: url)
            
            // If deleting current project, create a new one
            if url == projectURL {
                createNewProject(name: "Untitled Project")
            }
            
            refreshProjectList()
        } catch {
            print("Failed to delete project: \(error)")
        }
    }
    
    /// Refresh the project list.
    /// Merges the hardcoded folder scan with recently-opened project URLs
    /// so that projects opened via "Open…" from any location also appear.
    func refreshProjectList() {
        do {
            // 1. Scan the default ~/Documents/AIAfterEffects/ folder
            var summaries = try fileService.listProjects()
            let knownIDs = Set(summaries.map { $0.id })
            
            // 2. Also load recently-opened projects that live outside the base folder
            let recentURLs = loadRecentProjectURLs()
            let baseURL = fileService.projectsBaseURL()
            
            for url in recentURLs {
                // Skip if already found in the base-folder scan
                if url.path.hasPrefix(baseURL.path) { continue }
                // Skip if the folder no longer exists
                guard FileManager.default.fileExists(atPath: url.appendingPathComponent("project.json").path) else { continue }
                
                do {
                    let project = try fileService.loadProject(at: url)
                    // Avoid duplicates by project ID
                    if !knownIDs.contains(project.id) {
                        summaries.append(ProjectSummary(from: project, url: url))
                    }
                } catch {
                    // Skip corrupted external projects
                    continue
                }
            }
            
            // Sort by updatedAt descending (most recent first)
            projectList = summaries.sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            print("Failed to list projects: \(error)")
        }
    }
    
    // MARK: - Scene Management
    
    /// Switch to a scene by index. No disk read needed — scenes are in memory.
    func switchToScene(at index: Int) {
        let orderedScenes = currentProject.orderedScenes
        guard index >= 0, index < orderedScenes.count else { return }
        self.currentSceneIndex = index
        objectWillChange.send()
    }
    
    /// Switch to a scene by ID
    func switchToScene(withId id: String) {
        let orderedScenes = currentProject.orderedScenes
        guard let index = orderedScenes.firstIndex(where: { $0.id == id }) else { return }
        switchToScene(at: index)
    }
    
    /// Switch to a scene by name (fuzzy match)
    func switchToScene(named name: String) {
        let lowercaseName = name.lowercased()
        let orderedScenes = currentProject.orderedScenes
        
        // Exact match first
        if let index = orderedScenes.firstIndex(where: { $0.name.lowercased() == lowercaseName }) {
            switchToScene(at: index)
            return
        }
        
        // Partial match
        if let index = orderedScenes.firstIndex(where: {
            $0.name.lowercased().contains(lowercaseName) || lowercaseName.contains($0.name.lowercased())
        }) {
            switchToScene(at: index)
            return
        }
        
        // Try matching by scene number (e.g., "scene 3" → index 2)
        let digits = name.filter(\.isNumber)
        if let number = Int(digits), number > 0, number <= orderedScenes.count {
            switchToScene(at: number - 1)
        }
    }
    
    /// Add a new scene to the project (in-memory, saved to project.json)
    @discardableResult
    func addScene(name: String? = nil) -> SceneFile? {
        let sceneName = name ?? "Scene \(currentProject.sceneCount + 1)"
        let nextOrder = (currentProject.scenes.map(\.order).max() ?? -1) + 1
        
        let newScene = SceneFile(
            name: sceneName,
            order: nextOrder
        )
        
        currentProject.scenes.append(newScene)
        currentProject.touch()
        saveProject()
        
        return newScene
    }
    
    /// Delete a scene by ID
    func deleteScene(withId id: String) {
        guard currentProject.sceneCount > 1 else { return }
        
        // If deleting the current scene, switch to another first
        let orderedScenes = currentProject.orderedScenes
        if orderedScenes[safe: currentSceneIndex]?.id == id {
            let newIndex = currentSceneIndex > 0 ? currentSceneIndex - 1 : 1
            if newIndex < orderedScenes.count, orderedScenes[newIndex].id != id {
                switchToScene(at: newIndex)
            }
        }
        
        // Remove from project
        currentProject.scenes.removeAll { $0.id == id }
        
        // Remove related transitions
        currentProject.transitions.removeAll { $0.fromSceneId == id || $0.toSceneId == id }
        
        // Re-order remaining scenes
        let sorted = currentProject.scenes.sorted { $0.order < $1.order }
        for (i, scene) in sorted.enumerated() {
            if let idx = currentProject.scenes.firstIndex(where: { $0.id == scene.id }) {
                currentProject.scenes[idx].order = i
            }
        }
        
        // Adjust current scene index if needed
        let newOrderedScenes = currentProject.orderedScenes
        if currentSceneIndex >= newOrderedScenes.count {
            currentSceneIndex = max(0, newOrderedScenes.count - 1)
        }
        
        currentProject.touch()
        saveProject()
    }
    
    /// Duplicate a scene
    @discardableResult
    func duplicateScene(withId id: String) -> SceneFile? {
        guard let source = currentProject.scenes.first(where: { $0.id == id }) else { return nil }
        
        let nextOrder = (currentProject.scenes.map(\.order).max() ?? -1) + 1
        let newScene = SceneFile(
            name: "\(source.name) Copy",
            order: nextOrder,
            duration: source.duration,
            backgroundColor: source.backgroundColor,
            objects: source.objects
        )
        
        currentProject.scenes.append(newScene)
        currentProject.touch()
        saveProject()
        
        return newScene
    }
    
    /// Rename a scene
    func renameScene(withId id: String, to newName: String) {
        if let index = currentProject.scenes.firstIndex(where: { $0.id == id }) {
            currentProject.scenes[index].name = newName
            currentProject.touch()
            saveProject()
        }
    }
    
    /// Reorder scenes
    func reorderScenes(_ newOrder: [String]) {
        for (index, sceneId) in newOrder.enumerated() {
            if let sceneIdx = currentProject.scenes.firstIndex(where: { $0.id == sceneId }) {
                currentProject.scenes[sceneIdx].order = index
            }
        }
        
        currentProject.touch()
        saveProject()
    }
    
    /// Set transition between two scenes
    func setTransition(from fromId: String, to toId: String, type: TransitionType, duration: Double = 0.8) {
        // Remove existing transition between these scenes
        currentProject.transitions.removeAll { $0.fromSceneId == fromId && $0.toSceneId == toId }
        
        // Add new transition
        if type != .none {
            let transition = SceneTransition(
                fromSceneId: fromId,
                toSceneId: toId,
                type: type,
                duration: duration
            )
            currentProject.transitions.append(transition)
        }
        
        currentProject.touch()
        saveProject()
    }
    
    // MARK: - Scene State Bridge
    
    /// Get the current SceneState (backward compatibility with existing rendering)
    var sceneState: SceneState {
        currentScene.toSceneState(canvas: currentProject.canvas)
    }
    
    /// Update the current scene from a SceneState (backward compat with CanvasViewModel)
    func updateCurrentScene(from sceneState: SceneState) {
        let ordered = currentProject.orderedScenes
        guard currentSceneIndex >= 0, currentSceneIndex < ordered.count else { return }
        let sceneId = ordered[currentSceneIndex].id
        
        guard let idx = currentProject.scenes.firstIndex(where: { $0.id == sceneId }) else { return }
        
        currentProject.scenes[idx].duration = sceneState.duration
        currentProject.scenes[idx].backgroundColor = sceneState.backgroundColor
        currentProject.scenes[idx].objects = sceneState.objects
        
        // Also sync canvas config if it changed
        currentProject.canvas.width = sceneState.canvasWidth
        currentProject.canvas.height = sceneState.canvasHeight
        currentProject.canvas.fps = sceneState.fps
    }
    
    // MARK: - Saving
    
    /// Save the project (single file — includes all scenes)
    func saveProject() {
        guard let url = projectURL else { return }
        currentProject.touch()
        
        do {
            try fileService.saveProject(currentProject, at: url)
        } catch {
            print("Failed to save project: \(error)")
        }
    }
    
    /// Auto-save: saves project and chat session
    func autoSave() {
        saveProject()
        saveChatSession()
        saveSessionForProject()
    }
    
    // MARK: - Agent Refresh
    
    /// Called after the AI agent has directly written project.json via file tools.
    /// Reloads the current project from disk to pick up changes.
    func refreshAfterAgentEdits() {
        guard let url = projectURL else {
            DebugLogger.shared.warning("[Agent] refreshAfterAgentEdits: no projectURL", category: .llm)
            return
        }
        
        do {
            let refreshedProject = try fileService.loadProject(at: url)
            let oldObjCount = currentProject.orderedScenes.flatMap(\.objects).count
            let newObjCount = refreshedProject.orderedScenes.flatMap(\.objects).count
            
            self.currentProject = refreshedProject
            
            // Ensure scene index is valid
            let orderedScenes = refreshedProject.orderedScenes
            if currentSceneIndex >= orderedScenes.count {
                currentSceneIndex = max(0, orderedScenes.count - 1)
            }
            
            refreshProjectList()
            DebugLogger.shared.success("[Agent] Refreshed project after agent edits (\(oldObjCount) → \(newObjCount) objects)", category: .llm)
        } catch {
            DebugLogger.shared.error("[Agent] FAILED to refresh after agent edits: \(error.localizedDescription)", category: .llm)
        }
    }
    
    // MARK: - Chat Session Management
    
    /// Refresh the list of chat sessions for the current project
    func refreshChatSessions() {
        guard let url = projectURL else { return }
        do {
            chatSessionList = try chatSessionService.listSessions(projectURL: url)
        } catch {
            print("Failed to list chat sessions: \(error)")
        }
    }
    
    /// Load chat sessions for a project (picks the most recent or creates one)
    private func loadChatSessions(projectURL url: URL) {
        do {
            chatSessionList = try chatSessionService.listSessions(projectURL: url)
            
            if let firstSummary = chatSessionList.first {
                let session = try chatSessionService.loadSession(id: firstSummary.id, projectURL: url)
                self.currentChatSession = session
            } else {
                // Migrate legacy session or create new one
                let legacyKey = "project_session_\(currentProject.id.uuidString)"
                if let data = UserDefaults.standard.data(forKey: legacyKey),
                   let legacySession = try? JSONDecoder().decode(Session.self, from: data),
                   !legacySession.conversation.messages.isEmpty {
                    let migrated = try chatSessionService.migrateFromLegacy(session: legacySession, projectURL: url)
                    self.currentChatSession = migrated
                    refreshChatSessions()
                } else {
                    let session = try chatSessionService.createSession(projectURL: url)
                    self.currentChatSession = session
                    refreshChatSessions()
                }
            }
        } catch {
            print("Failed to load chat sessions: \(error)")
            self.currentChatSession = ChatSessionFile()
        }
    }
    
    /// Create a new chat session for the current project
    func newChatSession() {
        guard let url = projectURL else { return }
        saveChatSession()
        
        do {
            let session = try chatSessionService.createSession(projectURL: url)
            self.currentChatSession = session
            refreshChatSessions()
        } catch {
            print("Failed to create new chat session: \(error)")
        }
    }
    
    /// Switch to a different chat session
    func switchChatSession(to id: UUID) {
        guard let url = projectURL else { return }
        saveChatSession()
        
        do {
            let session = try chatSessionService.loadSession(id: id, projectURL: url)
            self.currentChatSession = session
        } catch {
            print("Failed to switch chat session: \(error)")
        }
    }
    
    /// Delete a chat session
    func deleteChatSession(id: UUID) {
        guard let url = projectURL else { return }
        
        do {
            try chatSessionService.deleteSession(id: id, projectURL: url)
            
            if currentChatSession?.id == id {
                refreshChatSessions()
                if let first = chatSessionList.first {
                    switchChatSession(to: first.id)
                } else {
                    let session = try chatSessionService.createSession(projectURL: url)
                    self.currentChatSession = session
                    refreshChatSessions()
                }
            } else {
                refreshChatSessions()
            }
        } catch {
            print("Failed to delete chat session: \(error)")
        }
    }
    
    /// Save the current chat session to disk
    func saveChatSession() {
        guard let url = projectURL, var session = currentChatSession else { return }
        session.generateTitle()
        do {
            try chatSessionService.saveSession(session, projectURL: url)
            self.currentChatSession = session
        } catch {
            print("Failed to save chat session: \(error)")
        }
    }
    
    /// Add a message to the current chat session
    func addMessageToChatSession(_ message: ChatMessage) {
        currentChatSession?.addMessage(message)
    }
    
    /// Update a specific message's checkpoint ID in the current session
    func setCheckpointOnMessage(messageId: UUID, checkpointId: String) {
        guard var session = currentChatSession else { return }
        if let idx = session.messages.firstIndex(where: { $0.id == messageId }) {
            session.messages[idx].checkpointId = checkpointId
            self.currentChatSession = session
        }
    }
    
    // MARK: - Git Initialization
    
    func ensureGitInitialized() {
        guard let url = projectURL else { return }
        
        gitInitTask?.cancel()
        isGitReady = false
        
        gitInitTask = Task {
            let success = await checkpointService.initializeRepo(at: url)
            let loaded = await checkpointService.listCheckpoints(at: url, limit: 50)
            
            guard !Task.isCancelled else { return }
            self.isGitReady = success
            self.checkpoints = loaded
            
            if success {
                print("[ProjectManager] Checkpoint system ready at \(url.lastPathComponent)")
            } else {
                print("[ProjectManager] Failed to initialize checkpoints at \(url.lastPathComponent)")
            }
        }
    }
    
    private func waitForGitReady() async {
        if isGitReady { return }
        await gitInitTask?.value
    }
    
    // MARK: - Checkpoint Management
    
    func createCheckpoint(message: String, messageId: UUID) async -> Checkpoint? {
        guard let url = projectURL else { return nil }
        
        await waitForGitReady()
        
        // Save current state to disk first
        saveProject()
        
        let checkpoint = await checkpointService.createCheckpoint(
            at: url,
            message: message,
            messageId: messageId
        )
        
        if let checkpoint {
            self.checkpoints.insert(checkpoint, at: 0)
        }
        
        return checkpoint
    }
    
    func revertToCheckpoint(_ checkpointId: String) async -> RevertResult {
        guard let url = projectURL else {
            return .failed("No project URL")
        }
        
        await waitForGitReady()
        saveProject()
        
        let result = await checkpointService.revertToCheckpoint(at: url, checkpointId: checkpointId)
        
        if result.success {
            refreshAfterAgentEdits()
            
            let loaded = await checkpointService.listCheckpoints(at: url, limit: 50)
            self.checkpoints = loaded
        }
        
        return result
    }
    
    func diffForCheckpoint(_ checkpointId: String) async -> CheckpointDiff? {
        guard let url = projectURL else { return nil }
        return await checkpointService.diffForCheckpoint(at: url, checkpointId: checkpointId)
    }
    
    // MARK: - Canvas Config
    
    func setCanvasDimensions(width: Double, height: Double) {
        currentProject.canvas.width = width
        currentProject.canvas.height = height
        currentProject.touch()
        saveProject()
    }
    
    // MARK: - Legacy Session Bridge
    
    /// Keep a lightweight compatibility snapshot in UserDefaults.
    /// Full scene data lives in `project.json`, and full chat history lives in chat files.
    private func makeLegacySessionSnapshot() -> Session {
        let sourceMessages = currentChatSession?.messages ?? currentSession.conversation.messages
        let createdAt = currentChatSession?.createdAt ?? currentSession.createdAt
        let updatedAt = currentChatSession?.updatedAt ?? currentSession.updatedAt
        let title = currentChatSession?.title ?? currentSession.conversation.title
        
        var conversation = Conversation(
            id: currentSession.conversation.id,
            messages: makeLegacyMessageSnapshot(sourceMessages),
            createdAt: createdAt,
            updatedAt: updatedAt,
            title: title
        )
        conversation.generateTitle()
        
        let sceneSnapshot = SceneState(
            objects: [],
            canvasWidth: currentProject.canvas.width,
            canvasHeight: currentProject.canvas.height,
            backgroundColor: currentScene.backgroundColor,
            duration: currentScene.duration,
            fps: currentProject.canvas.fps
        )
        
        return Session(
            id: currentChatSession?.id ?? currentSession.id,
            conversation: conversation,
            sceneState: sceneSnapshot,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
    
    private func makeLegacyMessageSnapshot(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages
            .filter { !$0.isLoading }
            .map { message in
                var snapshot = message
                snapshot.attachments = []
                return snapshot
            }
    }
    
    private func saveSessionForProject() {
        let key = "project_session_\(currentProject.id.uuidString)"
        let snapshot = makeLegacySessionSnapshot()
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    private func loadSessionForProject() {
        let key = "project_session_\(currentProject.id.uuidString)"
        if let data = UserDefaults.standard.data(forKey: key),
           let session = try? JSONDecoder().decode(Session.self, from: data) {
            self.currentSession = session
        } else {
            self.currentSession = Session.newSession()
        }
    }
    
    private func saveCurrentProjectURL() {
        if let url = projectURL {
            UserDefaults.standard.set(url.absoluteString, forKey: currentProjectURLKey)
            addToRecentProjectURLs(url)
        }
    }
    
    // MARK: - Recent Project URLs (external projects opened via "Open…")
    
    private func addToRecentProjectURLs(_ url: URL) {
        var urls = loadRecentProjectURLs()
        // Remove duplicate if present, then prepend
        urls.removeAll { $0.path == url.path }
        urls.insert(url, at: 0)
        // Keep at most 20 recent entries
        if urls.count > 20 { urls = Array(urls.prefix(20)) }
        let strings = urls.map { $0.absoluteString }
        UserDefaults.standard.set(strings, forKey: recentProjectURLsKey)
    }
    
    private func loadRecentProjectURLs() -> [URL] {
        guard let strings = UserDefaults.standard.stringArray(forKey: recentProjectURLsKey) else { return [] }
        return strings.compactMap { URL(string: $0) }
    }
}

// MARK: - Array Safe Subscript

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
