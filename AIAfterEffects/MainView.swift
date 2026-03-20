//
//  MainView.swift
//  AIAfterEffects
//
//  Canvas-focused layout with floating chat overlay (inspired by modern 3D tools)
//

import SwiftUI
import AppKit

struct MainView: View {
    // MARK: - Environment & State Objects
    
    @EnvironmentObject var projectManager: ProjectManager
    @StateObject private var chatViewModel = ChatViewModel()
    @StateObject private var canvasViewModel = CanvasViewModel()
    @StateObject private var sessionManager = SessionManager()
    
    // MARK: - State
    
    @State private var showSettings = false
    @State private var show3DBrowser = false
    @State private var isChatExpanded = false
    @State private var showSessionList = false
    @State private var showNewProjectSheet = false
    
    // Panel visibility toggles
    @State private var showInspectorPanel = true
    @State private var showTimelinePanel = true
    
    // MARK: - Body
    
    var body: some View {
        VSplitView {
            // ── Top: HSplitView with Canvas | Inspector ──
            HSplitView {
                // Left: Canvas with floating chat
                ZStack(alignment: .bottom) {
                    CanvasView(viewModel: canvasViewModel)
                    
                    // Floating chat overlay
                    floatingChatOverlay
                        .padding(.horizontal, AppTheme.Spacing.xxl)
                        .padding(.bottom, showTimelinePanel ? AppTheme.Spacing.sm : AppTheme.Spacing.xl)
                }
                .frame(minWidth: 400)
                
                // Right: Property Inspector
                if showInspectorPanel {
                    PropertyInspectorView(viewModel: canvasViewModel)
                        .frame(minWidth: 220, idealWidth: 280, maxWidth: 400)
                }
            }
            .frame(minHeight: 300)
            
            // ── Bottom: Timeline Panel (resizable via VSplitView divider) ──
            if showTimelinePanel {
                TimelineView(viewModel: canvasViewModel)
                    .frame(minHeight: 120, idealHeight: 200, maxHeight: 500)
            }
        }
        .frame(minWidth: 1000, minHeight: 700)
        .background(AppTheme.Colors.surface)
        .toolbarBackground(AppTheme.Colors.surface, for: .windowToolbar)
        .toolbarColorScheme(.light, for: .windowToolbar)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarButtons
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $show3DBrowser) {
            SketchfabBrowserView(onAssetSelected: { asset in
                chatViewModel.attachAsset(asset)
                show3DBrowser = false
            })
        }
        .sheet(isPresented: $projectManager.showProjectBrowser) {
            ProjectBrowserView(mode: .sheet)
        }
        .sheet(isPresented: $showNewProjectSheet) {
            NewProjectSheet(onProjectCreated: {
                chatViewModel.clearMessages()
                canvasViewModel.loadSceneFile(
                    projectManager.currentScene,
                    canvas: projectManager.currentProject.canvas
                )
            })
        }
        .onAppear {
            setupBindings()
            loadProject()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newProjectRequested)) { _ in
            handleNewProject()
        }
        .onReceive(NotificationCenter.default.publisher(for: .undoTimelineRequested)) { _ in
            handleUndoTimelineCommand()
        }
        .onReceive(NotificationCenter.default.publisher(for: .redoTimelineRequested)) { _ in
            handleRedoTimelineCommand()
        }
        .onReceive(NotificationCenter.default.publisher(for: .deleteSelectedKeyframeRequested)) { _ in
            handleDeleteKeyframeCommand()
        }
        .onChange(of: projectManager.currentProject.id) { _, _ in
            // A different project was loaded (from welcome, open, or browser)
            // → reload the scene into the canvas and reset chat
            loadProject()
            canvasViewModel.selectObject(nil)
        }
        .onChange(of: projectManager.currentSceneIndex) { _, _ in
            guard canvasViewModel.playbackMode != .allScenes else { return }
            canvasViewModel.loadSceneFile(projectManager.currentScene, canvas: projectManager.currentProject.canvas)
        }
        .onDeleteCommand {
            handleDeleteKeyframeCommand()
        }
        .alert("Error", isPresented: $chatViewModel.showError) {
            Button("OK") { chatViewModel.dismissError() }
        } message: {
            Text(chatViewModel.errorMessage ?? "An unknown error occurred")
        }
    }
    
    // MARK: - Floating Chat Overlay
    
    private var floatingChatOverlay: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            // Session list (above the composer)
            if showSessionList {
                SessionListPanel(
                    onSessionSelected: { id in
                        handleSessionSwitch(id)
                        withAnimation(AppTheme.Animation.quick) { showSessionList = false }
                    },
                    onNewSession: {
                        projectManager.newChatSession()
                        chatViewModel.clearMessages()
                        withAnimation(AppTheme.Animation.quick) { showSessionList = false }
                    },
                    onDeleteSession: { id in
                        projectManager.deleteChatSession(id: id)
                    }
                )
                .frame(maxWidth: 700)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            
            // ── Unified Chat Composer (expands with animation) ──
            FloatingChatComposer(
                viewModel: chatViewModel,
                isChatExpanded: $isChatExpanded,
                showSessionList: $showSessionList
            )
            .frame(maxWidth: 700)
        }
    }
    
    // MARK: - Toolbar Buttons
    
    @ViewBuilder
    private var toolbarButtons: some View {
        // Panel toggle: Timeline
        Button(action: {
            withAnimation(AppTheme.Animation.quick) { showTimelinePanel.toggle() }
        }) {
            Image(systemName: "timeline.selection")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(showTimelinePanel ? AppTheme.Colors.primary : AppTheme.Colors.textTertiary)
                .frame(width: 34, height: 28)
        }
        .buttonStyle(.plain)
        .help(showTimelinePanel ? "Hide Timeline" : "Show Timeline")
        
        // Panel toggle: Inspector
        Button(action: {
            withAnimation(AppTheme.Animation.quick) { showInspectorPanel.toggle() }
        }) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(showInspectorPanel ? AppTheme.Colors.primary : AppTheme.Colors.textTertiary)
                .frame(width: 34, height: 28)
        }
        .buttonStyle(.plain)
        .help(showInspectorPanel ? "Hide Inspector" : "Show Inspector")
        
        Rectangle()
            .fill(AppTheme.Colors.border)
            .frame(width: 1, height: 18)
        
        Button(action: { projectManager.showProjectBrowser = true }) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(AppTheme.Colors.textTertiary)
                .frame(width: 34, height: 28)
        }
        .buttonStyle(.plain)
        .help("Browse Projects")
        
        Button(action: { show3DBrowser = true }) {
            Image(systemName: "cube")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(AppTheme.Colors.textTertiary)
                .frame(width: 34, height: 28)
        }
        .buttonStyle(.plain)
        .help("3D Models")
        
        Button(action: { showSettings = true }) {
            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(AppTheme.Colors.textTertiary)
                .frame(width: 34, height: 28)
        }
        .buttonStyle(.plain)
        .help("Settings")
    }
    
    // MARK: - Setup & Actions
    
    private func setupBindings() {
        canvasViewModel.projectManager = projectManager
        chatViewModel.setProjectManager(projectManager)
        chatViewModel.setSessionManager(sessionManager)
        
        chatViewModel.onSceneUpdate = { [weak canvasViewModel, weak projectManager] commands, attachments in
            canvasViewModel?.processCommands(commands, attachments: attachments)
            if let newState = canvasViewModel?.sceneState {
                projectManager?.updateCurrentScene(from: newState)
                projectManager?.saveProject()
            }
            if canvasViewModel?.sceneState != nil {
                projectManager?.autoSave()
            }
        }
        
        canvasViewModel.onSceneStateChanged = { [weak projectManager] newState in
            projectManager?.updateCurrentScene(from: newState)
            projectManager?.saveProject()
        }
        
        chatViewModel.onCheckpointReverted = { [weak canvasViewModel, weak projectManager] in
            guard let pm = projectManager else { return }
            canvasViewModel?.loadSceneFile(pm.currentScene, canvas: pm.currentProject.canvas)
        }
    }
    
    private func loadProject() {
        canvasViewModel.loadSceneFile(
            projectManager.currentScene,
            canvas: projectManager.currentProject.canvas
        )
        if let chatSession = projectManager.currentChatSession, !chatSession.messages.isEmpty {
            chatViewModel.loadMessages(from: chatSession)
        } else {
            chatViewModel.loadMessages(from: projectManager.currentSession)
        }
    }
    
    private func handleNewProject() {
        canvasViewModel.stop()
        canvasViewModel.syncToProjectManager()
        showNewProjectSheet = true
    }
    
    private func handleSessionSwitch(_ sessionId: UUID) {
        projectManager.saveChatSession()
        projectManager.switchChatSession(to: sessionId)
        if let session = projectManager.currentChatSession {
            chatViewModel.loadMessages(from: session)
        }
    }
    
    private func handleDeleteKeyframeCommand() {
        // Do not intercept delete while editing text fields.
        if NSApp.keyWindow?.firstResponder is NSTextView { return }
        canvasViewModel.deleteSelectedKeyframe()
    }
    
    private func handleUndoTimelineCommand() {
        // Keep native text editing undo behavior.
        if NSApp.keyWindow?.firstResponder is NSTextView { return }
        canvasViewModel.undoTimelineChange()
    }
    
    private func handleRedoTimelineCommand() {
        if NSApp.keyWindow?.firstResponder is NSTextView { return }
        canvasViewModel.redoTimelineChange()
    }
}

// MARK: - Floating Chat Composer (unified — expands with animation)

struct FloatingChatComposer: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var isChatExpanded: Bool
    @Binding var showSessionList: Bool
    @FocusState private var isInputFocused: Bool
    @State private var isFileImporterPresented = false
    
    private var canSend: Bool {
        let trimmed = viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !viewModel.isLoading && (!trimmed.isEmpty || !viewModel.pendingAttachments.isEmpty || !viewModel.pendingAssets.isEmpty)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // ── Messages area (expands upward with animation) ──
            if isChatExpanded {
                messagesArea
                    .frame(maxHeight: 340)
                
                ThemedDivider()
            }
            
            // ── Attachment pills ──
            if !viewModel.pendingAssets.isEmpty || !viewModel.pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        ForEach(viewModel.pendingAssets, id: \.id) { asset in
                            pillView(icon: "cube", name: asset.name) {
                                viewModel.removeAssetAttachment(assetId: asset.id)
                            }
                        }
                        ForEach(viewModel.pendingAttachments) { att in
                            pillView(icon: "photo", name: att.filename) {
                                viewModel.removePendingAttachment(id: att.id)
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.xs)
                }
            }
            
            // ── Input row (always visible) ──
            HStack(spacing: AppTheme.Spacing.sm) {
                // Attach
                Button(action: { isFileImporterPresented = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.Colors.textTertiary)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
                
                // Text input (multiline, native placeholder)
                MultilineTextField(
                    text: $viewModel.inputText,
                    placeholder: "Describe what you want to create...",
                    maxHeight: 80,
                    onCommandReturn: {
                        Task { await viewModel.sendMessage() }
                    }
                )
                .frame(minHeight: 20, maxHeight: 80)
                .focused($isInputFocused)
                .disabled(viewModel.isLoading)
                
                // Session picker
                SessionPickerButton(isExpanded: $showSessionList)
                
                // Expand/collapse chat
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isChatExpanded.toggle()
                    }
                }) {
                    Image(systemName: isChatExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(isChatExpanded ? AppTheme.Colors.textPrimary : AppTheme.Colors.textTertiary)
                        .frame(width: 26, height: 26)
                        .background(
                            Circle()
                                .fill(isChatExpanded ? AppTheme.Colors.backgroundSecondary : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help("Toggle chat history")
                
                // Send
                Button(action: {
                    Task { await viewModel.sendMessage() }
                }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                            .fill(canSend ? AppTheme.Colors.primary : AppTheme.Colors.backgroundSecondary)
                            .frame(width: 30, height: 30)
                        
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.45)
                                .tint(AppTheme.Colors.textTertiary)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(canSend ? .white : AppTheme.Colors.textTertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl)
                .fill(AppTheme.Colors.surface)
                .shadow(color: Color.black.opacity(0.1), radius: 20, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl)
                .strokeBorder(AppTheme.Colors.border.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xl))
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): viewModel.addAttachments(from: urls)
            case .failure(let error): viewModel.handleAttachmentImportError(error)
            }
        }
    }
    
    // MARK: - Messages Area
    
    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: AppTheme.Spacing.md) {
                    ForEach(viewModel.messages) { message in
                        VStack(spacing: 0) {
                            if let cpId = message.checkpointId, message.role == .user {
                                CheckpointDividerView(
                                    checkpointId: cpId,
                                    message: "",
                                    onRevert: {
                                        Task { await viewModel.revertToCheckpoint(cpId) }
                                    }
                                )
                                .padding(.bottom, AppTheme.Spacing.xxs)
                            }
                            
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }
                    }
                    
                    if !viewModel.toolActivities.isEmpty && viewModel.isLoading {
                        ToolActivityView(activities: viewModel.toolActivities)
                            .transition(.opacity)
                    }
                    
                    if viewModel.messages.isEmpty {
                        EmptyStateView(onSuggestionTap: { suggestion in
                            viewModel.inputText = suggestion
                            Task { await viewModel.sendMessage() }
                        })
                        .frame(maxWidth: 400)
                    }
                }
                .padding(AppTheme.Spacing.md)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let lastMessage = viewModel.messages.last {
                    withAnimation(AppTheme.Animation.smooth) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - Pill Helper
    
    private func pillView(icon: String, name: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(AppTheme.Colors.textSecondary)
            Text(name)
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.Colors.textPrimary)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(AppTheme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.xxs)
        .background(AppTheme.Colors.background)
        .cornerRadius(AppTheme.Radius.full)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.full)
                .strokeBorder(AppTheme.Colors.border, lineWidth: 1)
        )
    }
}

// MARK: - MultilineTextField (NSViewRepresentable)

/// Native NSTextView wrapper with proper placeholder alignment.
struct MultilineTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var maxHeight: CGFloat
    var onCommandReturn: (() -> Void)?
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        
        let textView = PlaceholderTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        
        // Font & colors
        textView.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        textView.textColor = NSColor(AppTheme.Colors.textPrimary)
        textView.insertionPointColor = NSColor(AppTheme.Colors.textPrimary)
        
        // Placeholder
        textView.placeholderString = placeholder
        textView.placeholderColor = NSColor(AppTheme.Colors.textTertiary)
        
        // Command+Return handler
        textView.onCommandReturn = onCommandReturn
        
        scrollView.documentView = textView
        context.coordinator.textView = textView
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PlaceholderTextView else { return }
        
        if textView.string != text {
            textView.string = text
            textView.needsDisplay = true
        }
        textView.onCommandReturn = onCommandReturn
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MultilineTextField
        weak var textView: NSTextView?
        
        init(_ parent: MultilineTextField) { self.parent = parent }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

/// NSTextView subclass that draws a placeholder when empty.
class PlaceholderTextView: NSTextView {
    var placeholderString: String = ""
    var placeholderColor: NSColor = .placeholderTextColor
    var onCommandReturn: (() -> Void)?
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        if string.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font ?? NSFont.systemFont(ofSize: 14),
                .foregroundColor: placeholderColor
            ]
            let inset = textContainerInset
            let padding = textContainer?.lineFragmentPadding ?? 0
            let rect = NSRect(
                x: inset.width + padding,
                y: inset.height,
                width: bounds.width - (inset.width + padding) * 2,
                height: bounds.height - inset.height * 2
            )
            placeholderString.draw(in: rect, withAttributes: attrs)
        }
    }
    
    override func keyDown(with event: NSEvent) {
        // Command+Return to send
        if event.keyCode == 36 && event.modifierFlags.contains(.command) {
            onCommandReturn?()
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - Preview

#Preview {
    MainView()
        .environmentObject(ProjectManager())
}
