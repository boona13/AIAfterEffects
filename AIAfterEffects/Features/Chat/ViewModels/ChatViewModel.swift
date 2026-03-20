//
//  ChatViewModel.swift
//  AIAfterEffects
//
//  ViewModel for chat functionality with memory management
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
class ChatViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showError: Bool = false
    @Published var pendingAttachments: [ChatAttachment] = []
    @Published var pendingAssets: [Local3DAsset] = []
    @Published var pendingObjectContexts: [ObjectContextAttachment] = []
    @Published var toolActivities: [ToolActivity] = []  // Agent tool activity for UI
    @Published var currentPipelineStage: PipelineStage? = nil
    
    // MARK: - Dependencies
    
    private let llmService: OpenRouterService
    private let agentLoop: AgentLoopService
    private weak var sessionManager: SessionManager?
    private weak var projectManager: ProjectManager?
    private var activeAttachments: [ChatAttachment] = []
    
    // MARK: - Callbacks
    
    var onSceneUpdate: ((SceneCommands, [ChatAttachment]) -> Void)?
    var onCheckpointReverted: (() -> Void)?
    
    // MARK: - Init
    
    init(llmService: OpenRouterService = .shared, agentLoop: AgentLoopService = .shared) {
        self.llmService = llmService
        self.agentLoop = agentLoop
    }
    
    func setSessionManager(_ manager: SessionManager) {
        self.sessionManager = manager
    }
    
    func setProjectManager(_ manager: ProjectManager) {
        self.projectManager = manager
    }
    
    // MARK: - Public Methods
    
    /// Send a message to the AI
    func sendMessage() async {
        let displayText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let messageAttachments = pendingAttachments
        let contextAttachments = messageAttachments.isEmpty ? activeAttachments : messageAttachments
        let attachedAssets = pendingAssets
        guard !displayText.isEmpty || !contextAttachments.isEmpty || !attachedAssets.isEmpty else { return }
        
        // Build the LLM input: prepend asset context for all attached models
        var llmInput = displayText
        var llmAttachments = contextAttachments
        if !attachedAssets.isEmpty {
            var allAssetContexts: [String] = []
            for (index, asset) in attachedAssets.enumerated() {
                var assetContext = "[Attached 3D Model \(index + 1): \"\(asset.name)\" (asset ID: \(asset.id), by \(asset.authorName))"
                if let verts = asset.vertexCount { assetContext += ", \(verts) vertices" }
                if let desc = asset.shapeDescription { assetContext += ", \(desc)" }
                assetContext += ". Coordinate system: Y=up, X=width, Z=depth. cameraAngleX 0°=eye level, +15°=above, -15°=below. cameraAngleY 0°=front, ±90°=side.]"
                
                // Auto-attach the model's thumbnail so the AI can see it (visual reference only)
                if let thumbnailURL = asset.thumbnailURL(baseDirectory: AssetManagerService.shared.baseDirectory),
                   let thumbData = try? Data(contentsOf: thumbnailURL) {
                    let thumbAttachment = ChatAttachment(
                        filename: "3D_MODEL_REFERENCE_DO_NOT_USE_AS_IMAGE_\(asset.name).jpg",
                        mimeType: "image/jpeg",
                        data: thumbData
                    )
                    llmAttachments.append(thumbAttachment)
                    assetContext += " [WARNING: The attached image is ONLY a reference photo of the 3D model. Do NOT create an image object from it. Do NOT use it with attachmentIndex. The 3D model is rendered live in the scene via objectType:\"model3D\" with modelAssetId:\"\(asset.id)\". Use this reference photo ONLY to understand what the model looks like — its shape, colors, and proportions — so you can choose the best camera angles, lighting, and animations.]"
                }
                allAssetContexts.append(assetContext)
            }
            
            let combinedContext = allAssetContexts.joined(separator: "\n")
            if llmInput.isEmpty {
                let modelWord = attachedAssets.count == 1 ? "this 3D model" : "these \(attachedAssets.count) 3D models"
                llmInput = "\(combinedContext) Add \(modelWord) to the scene"
            } else {
                llmInput = "\(combinedContext)\n\(llmInput)"
            }
        }
        
        // Prepend focused object context when the user has attached scene objects
        let objectContexts = pendingObjectContexts
        if !objectContexts.isEmpty, let pm = projectManager {
            let focusedDescriptions = objectContexts.compactMap { ctx -> String? in
                return Self.describeObject(objectId: ctx.objectId, in: pm.currentProject)
            }
            if !focusedDescriptions.isEmpty {
                let header = "[User attached \(focusedDescriptions.count) object(s) for context — these are the objects the user is referring to:]"
                let joined = focusedDescriptions.joined(separator: "\n")
                llmInput = "\(header)\n\(joined)\n\n\(llmInput)"
            }
        }
        
        // Clear input immediately
        inputText = ""
        pendingAttachments = []
        pendingAssets = []
        pendingObjectContexts = []
        
        // Invalidate compaction cache since we're adding new messages
        ContextCompactionService.shared.invalidateCache()
        
        // Build asset attachment info for the message
        let assetInfos = attachedAssets.map { AssetAttachmentInfo(id: $0.id, name: $0.name, author: $0.authorName) }
        
        // Add user message (display text is clean, asset info stored separately)
        let defaultContent: String
        if displayText.isEmpty && !attachedAssets.isEmpty {
            defaultContent = attachedAssets.count == 1 ? "Add this 3D model to the scene" : "Add these \(attachedAssets.count) 3D models to the scene"
        } else {
            defaultContent = displayText
        }
        var userMessage = ChatMessage(
            role: .user,
            content: defaultContent,
            attachments: messageAttachments,
            assetAttachments: assetInfos,
            objectContexts: objectContexts
        )
        
        // --- Checkpoint BEFORE AI processing ---
        // Snapshot the current project state so the user can revert to "before this AI response"
        if let checkpoint = await projectManager?.createCheckpoint(
            message: defaultContent.count > 80 ? String(defaultContent.prefix(80)) + "..." : defaultContent,
            messageId: userMessage.id
        ) {
            userMessage.checkpointId = checkpoint.id
            DebugLogger.shared.success("Pre-AI checkpoint created: \(checkpoint.id)", category: .chat)
        }
        
        messages.append(userMessage)
        sessionManager?.currentSession.addMessage(userMessage)
        projectManager?.addMessageToChatSession(userMessage)
        
        // Add loading indicator
        let loadingMessage = ChatMessage.loadingMessage()
        messages.append(loadingMessage)
        isLoading = true
        
        do {
            // Get current scene state from the project (has correct canvas dimensions)
            let sceneState: SceneState
            if let pm = projectManager {
                sceneState = pm.currentScene.toSceneState(canvas: pm.currentProject.canvas)
            } else {
                sceneState = sessionManager?.currentSession.sceneState ?? SceneState()
            }
            
            // Get conversation history (excluding the current message and loading)
            let history = messages.filter { !$0.isLoading && $0.id != userMessage.id }
            
            if !messageAttachments.isEmpty {
                activeAttachments = messageAttachments
            }
            
            // Clear previous tool activities
            toolActivities = []
            
            let response: LLMResponse
            
            // Use the agentic loop when we have a project with a URL
            if let project = projectManager?.currentProject,
               let projectURL = projectManager?.projectURL {
                
                response = try await agentLoop.run(
                    userMessage: llmInput,
                    attachments: llmAttachments,
                    conversationHistory: history,
                    sceneState: sceneState,
                    project: project,
                    projectURL: projectURL,
                    currentSceneIndex: projectManager?.currentSceneIndex ?? 0,
                    onToolActivity: { [weak self] activities in
                        self?.toolActivities = activities
                    },
                    onPipelineStageChange: { [weak self] stage in
                        Task { @MainActor in
                            self?.currentPipelineStage = stage
                        }
                    }
                )
                
            } else {
                // Fallback: standard non-agentic LLM call with streaming
                response = try await llmService.sendMessageStreaming(
                    userMessage: llmInput,
                    attachments: llmAttachments,
                    conversationHistory: history,
                    sceneState: sceneState,
                    project: projectManager?.currentProject,
                    currentSceneIndex: projectManager?.currentSceneIndex ?? 0,
                    onPartial: { [weak self] partial in
                        Task { @MainActor in
                            self?.updateLoadingMessage(partial)
                        }
                    }
                )
            }
            
            // Remove loading message
            messages.removeAll { $0.isLoading }
            
            // Add assistant response
            let assistantMessage = ChatMessage(role: .assistant, content: response.textResponse)
            messages.append(assistantMessage)
            sessionManager?.currentSession.addMessage(assistantMessage)
            projectManager?.addMessageToChatSession(assistantMessage)
            
            // Determine if the agent modified project files directly (update_object, write_file, search_replace)
            let agentModifiedFiles = toolActivities.contains(where: {
                [AgentTool.writeFile, .searchReplace, .updateObject].contains($0.tool) && $0.status == .success
            })
            
            if agentModifiedFiles {
                // Agent wrote to project.json directly → refresh from disk FIRST.
                // IMPORTANT: Do NOT call onSceneUpdate here — it would sync the STALE
                // canvas sceneState back to ProjectManager, overwriting the agent's file changes
                // for the current scene. Instead, refresh from disk and reload the canvas.
                projectManager?.refreshAfterAgentEdits()
                onCheckpointReverted?()  // Tells canvas to reload from the refreshed project
                
                // Preload Google Fonts for ALL scenes so newly-set fonts are registered
                // with CoreText before the canvas tries to render them.
                if let project = projectManager?.currentProject {
                    Task {
                        await Self.preloadFontsForAllScenes(project: project)
                    }
                }
                
                // Still process scene-level commands (createScene, switchScene) if present,
                // but only when there are actual actions beyond what file tools handled.
                if let commands = response.commands,
                   let actions = commands.actions, !actions.isEmpty {
                    DebugLogger.shared.success("Received commands with \(actions.count) actions (post-refresh)", category: .chat)
                    onSceneUpdate?(commands, contextAttachments)
                }
            } else if let commands = response.commands {
                // Standard path: no file tools used, apply scene commands normally
                DebugLogger.shared.success("Received commands with \(commands.actions?.count ?? 0) actions", category: .chat)
                onSceneUpdate?(commands, contextAttachments)
            } else if toolActivities.isEmpty {
                DebugLogger.shared.warning("No commands in response (parsing may have failed)", category: .chat)
            }
            
            // Generate conversation title if this is the first exchange
            if messages.count == 2 {
                sessionManager?.currentSession.conversation.generateTitle()
            }
            
            // Save chat session
            projectManager?.saveChatSession()
            
        } catch {
            // Remove loading message
            messages.removeAll { $0.isLoading }
            
            // Show error
            errorMessage = error.localizedDescription
            showError = true
            
            // Add error message to chat
            let errorChatMessage = ChatMessage(
                role: .assistant,
                content: "Sorry, I encountered an error: \(error.localizedDescription)"
            )
            messages.append(errorChatMessage)
        }
        
        isLoading = false
        currentPipelineStage = nil
    }
    
    /// Updates the loading message with partial streaming content.
    /// Tries to extract the "message" field from partial JSON for cleaner display.
    private func updateLoadingMessage(_ partial: String) {
        guard let idx = messages.lastIndex(where: { $0.isLoading }) else { return }
        
        var display = partial
        if let msgStart = partial.range(of: "\"message\""),
           let colonRange = partial.range(of: ":", range: msgStart.upperBound..<partial.endIndex),
           let quoteStart = partial.range(of: "\"", range: colonRange.upperBound..<partial.endIndex) {
            let textStart = quoteStart.upperBound
            if let quoteEnd = partial.range(of: "\"", range: textStart..<partial.endIndex) {
                display = String(partial[textStart..<quoteEnd.lowerBound])
            } else {
                display = String(partial[textStart...])
            }
            display = display.replacingOccurrences(of: "\\n", with: "\n")
        }
        
        messages[idx] = ChatMessage(
            id: messages[idx].id,
            role: .assistant,
            content: display,
            isLoading: true
        )
    }

    func addAttachments(from urls: [URL]) {
        var newAttachments: [ChatAttachment] = []
        
        for url in urls {
            let didStart = url.startAccessingSecurityScopedResource()
            defer {
                if didStart { url.stopAccessingSecurityScopedResource() }
            }
            
            do {
                let data = try Data(contentsOf: url)
                let maxSizeBytes = 6 * 1024 * 1024
                if data.count > maxSizeBytes {
                    showAttachmentError("Image '\(url.lastPathComponent)' is too large. Max 6 MB.")
                    continue
                }
                
                let mimeType = resolveMimeType(for: url, data: data)
                let attachment = ChatAttachment(
                    filename: url.lastPathComponent,
                    mimeType: mimeType,
                    data: data
                )
                newAttachments.append(attachment)
            } catch {
                showAttachmentError("Failed to read image '\(url.lastPathComponent)'.")
            }
        }
        
        if !newAttachments.isEmpty {
            pendingAttachments.append(contentsOf: newAttachments)
        }
    }
    
    func removePendingAttachment(id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
    }
    
    func handleAttachmentImportError(_ error: Error) {
        showAttachmentError("Unable to import image. \(error.localizedDescription)")
    }
    
    private func showAttachmentError(_ message: String) {
        errorMessage = message
        showError = true
    }
    
    private func resolveMimeType(for url: URL, data: Data) -> String {
        if let type = UTType(filenameExtension: url.pathExtension),
           let mime = type.preferredMIMEType {
            return mime
        }
        
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "image/png"
        }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "image/jpeg"
        }
        if data.starts(with: [0x47, 0x49, 0x46, 0x38]) {
            return "image/gif"
        }
        if data.count >= 12,
           let header = String(data: data.prefix(12), encoding: .ascii),
           header.contains("WEBP") {
            return "image/webp"
        }
        
        return "image/png"
    }
    
    /// Clear all messages (new session)
    func clearMessages() {
        messages.removeAll()
        errorMessage = nil
        showError = false
        pendingAttachments = []
        pendingAssets = []
        pendingObjectContexts = []
        activeAttachments = []
    }
    
    /// Load messages from a legacy Session
    func loadMessages(from session: Session) {
        messages = session.conversation.messages
        activeAttachments = messages.last(where: { !$0.attachments.isEmpty })?.attachments ?? []
    }
    
    /// Load messages from a file-based ChatSessionFile
    func loadMessages(from chatSession: ChatSessionFile) {
        messages = chatSession.messages
        activeAttachments = messages.last(where: { !$0.attachments.isEmpty })?.attachments ?? []
    }
    
    /// Revert to a checkpoint (restores project files and trims chat history)
    func revertToCheckpoint(_ checkpointId: String) async {
        guard let pm = projectManager else { return }
        
        // Find the user message that owns this checkpoint
        guard let msgIndex = messages.firstIndex(where: {
            $0.checkpointId == checkpointId && $0.role == .user
        }) else {
            errorMessage = "Could not find the message for checkpoint \(checkpointId)"
            showError = true
            return
        }
        
        // Grab the user's original text before removing it
        let originalText = messages[msgIndex].content
        
        isLoading = true
        let result = await pm.revertToCheckpoint(checkpointId)
        isLoading = false
        
        if result.success {
            // Remove the checkpoint message and everything after it
            messages.removeSubrange(msgIndex...)
            
            // Update the chat session to match the trimmed history
            pm.currentChatSession?.messages = messages
            pm.saveChatSession()
            
            // Put the original message text in the composer so the user can resend or edit
            inputText = originalText
            
            // Notify the canvas to reload from reverted files
            onCheckpointReverted?()
        } else {
            errorMessage = result.error ?? "Failed to revert to checkpoint"
            showError = true
        }
    }
    
    /// Dismiss error
    func dismissError() {
        showError = false
        errorMessage = nil
    }
    
    /// Attach a 3D asset to the chat composer (adds to the list, does NOT auto-send)
    func attachAsset(_ asset: Local3DAsset) {
        // Don't add the same asset twice
        guard !pendingAssets.contains(where: { $0.id == asset.id }) else { return }
        pendingAssets.append(asset)
    }
    
    /// Remove a specific 3D asset from the composer by asset ID
    func removeAssetAttachment(assetId: String) {
        pendingAssets.removeAll { $0.id == assetId }
    }
    
    /// Remove all 3D assets from the composer
    func removeAllAssetAttachments() {
        pendingAssets.removeAll()
    }
    
    // MARK: - Object Context
    
    func addObjectContext(_ attachment: ObjectContextAttachment) {
        guard !pendingObjectContexts.contains(where: { $0.objectId == attachment.objectId }) else { return }
        pendingObjectContexts.append(attachment)
    }
    
    func removeObjectContext(id: UUID) {
        pendingObjectContexts.removeAll { $0.id == id }
    }
    
    /// Build a concise textual snapshot of a scene object including its properties and animations.
    private static func describeObject(objectId: UUID, in project: Project) -> String? {
        for scene in project.orderedScenes {
            guard let obj = scene.objects.first(where: { $0.id == objectId }) else { continue }
            
            var lines: [String] = []
            lines.append("Object: \"\(obj.name)\" (id: \(obj.id), type: \(obj.type.rawValue), scene: \(scene.name))")
            
            let p = obj.properties
            var props: [String] = []
            props.append("position: (\(p.x), \(p.y))")
            props.append("size: \(p.width)×\(p.height)")
            if p.rotation != 0 { props.append("rotation: \(p.rotation)°") }
            if p.opacity != 1.0 { props.append("opacity: \(p.opacity)") }
            props.append("fill: \(p.fillColor)")
            if p.strokeWidth > 0 { props.append("stroke: \(p.strokeColor), width: \(p.strokeWidth)") }
            if p.cornerRadius > 0 { props.append("cornerRadius: \(p.cornerRadius)") }
            if let text = p.text { props.append("text: \"\(text)\"") }
            if let font = p.fontName { props.append("font: \(font)") }
            if let fontSize = p.fontSize { props.append("fontSize: \(fontSize)") }
            if p.imageData != nil { props.append("hasImage: true") }
            if let model = p.modelAssetId { props.append("modelAssetId: \(model)") }
            lines.append("  Properties: { \(props.joined(separator: ", ")) }")
            
            if !obj.animations.isEmpty {
                let animDescs = obj.animations.map { anim -> String in
                    var desc = anim.type.rawValue
                    desc += " (delay: \(anim.delay)s, duration: \(anim.duration)s"
                    desc += ", easing: \(anim.easing.rawValue)"
                    if !anim.keyframes.isEmpty {
                        desc += ", \(anim.keyframes.count) keyframes"
                    }
                    desc += ")"
                    return desc
                }
                lines.append("  Animations: [\(animDescs.joined(separator: ", "))]")
            } else {
                lines.append("  Animations: none")
            }
            
            return lines.joined(separator: "\n")
        }
        return nil
    }
    
    // MARK: - Font Preloading
    
    /// Preload Google Fonts for all text objects across all scenes.
    /// Called after agent edits so the canvas preview shows updated fonts immediately.
    private static func preloadFontsForAllScenes(project: Project) async {
        var fontRequests: [(family: String, weight: String)] = []
        var seen: Set<String> = []
        
        for scene in project.orderedScenes {
            for obj in scene.objects where obj.type == .text {
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
        }
        
        guard !fontRequests.isEmpty else { return }
        
        DebugLogger.shared.info("Preloading \(fontRequests.count) font variants after agent edits...", category: .fonts)
        
        for req in fontRequests {
            await GoogleFontsService.shared.ensureFontLoaded(family: req.family, weight: req.weight)
        }
        
        DebugLogger.shared.success("Font preloading after agent edits complete", category: .fonts)
    }
}
