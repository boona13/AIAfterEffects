//
//  AIAfterEffectsApp.swift
//  AIAfterEffects
//
//  Created by Ibrahim Boona on 16/08/1447 AH.
//

import SwiftUI

@main
struct AIAfterEffectsApp: App {
    
    @StateObject private var projectManager = ProjectManager()
    
    init() {
        // Initialize the debug logger (this clears the log file)
        _ = DebugLogger.shared
        DebugLogger.shared.info("App initialized", category: .app)
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(projectManager)
                .preferredColorScheme(.light)
                .onAppear {
                    DebugLogger.shared.info("RootView appeared", category: .ui)
                }
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo Timeline Change") {
                    NotificationCenter.default.post(name: .undoTimelineRequested, object: nil)
                }
                .keyboardShortcut("z", modifiers: .command)
                
                Button("Redo Timeline Change") {
                    NotificationCenter.default.post(name: .redoTimelineRequested, object: nil)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            
            CommandGroup(before: .pasteboard) {
                Button("Delete Selected Keyframe") {
                    NotificationCenter.default.post(name: .deleteSelectedKeyframeRequested, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: [])
            }
            
            // File menu — project management
            CommandGroup(replacing: .newItem) {
                Button("New Project") {
                    DebugLogger.shared.info("New Project requested via menu", category: .session)
                    NotificationCenter.default.post(name: .newProjectRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                
                Button("Open Project...") {
                    projectManager.showProjectBrowser = true
                }
                .keyboardShortcut("o", modifiers: .command)
                
                Divider()
                
                Button("Save Project") {
                    projectManager.autoSave()
                    DebugLogger.shared.info("Project saved via menu", category: .session)
                }
                .keyboardShortcut("s", modifiers: .command)
                
                Divider()
                
                Button("Show Welcome Screen") {
                    projectManager.showWelcome = true
                }
            }
            
            #if DEBUG
            // Debug menu
            CommandMenu("Debug") {
                Button("Open Debug Log in Finder") {
                    DebugLogger.shared.openLogInFinder()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                
                Button("Copy Log Path") {
                    DebugLogger.shared.copyLogPathToClipboard()
                    DebugLogger.shared.info("Log path copied to clipboard", category: .app)
                }
                
                Divider()
                
                Button("Log Current State") {
                    logCurrentState()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
            #endif
        }
        
        Settings {
            SettingsView()
                .preferredColorScheme(.light)
        }
    }
    
    private func logCurrentState() {
        let logger = DebugLogger.shared
        logger.info("=== CURRENT STATE DUMP ===", category: .app)
        logger.info("API Key configured: \(!OpenRouterConfig.apiKey.isEmpty)", category: .app)
        logger.info("Selected model: \(OpenRouterConfig.selectedModel)", category: .app)
        logger.info("Current project: \(projectManager.currentProject.name)", category: .app)
        logger.info("Scenes: \(projectManager.currentProject.sceneCount)", category: .app)
    }
}

// MARK: - Root View (Welcome vs Editor switch)

struct RootView: View {
    @EnvironmentObject var projectManager: ProjectManager
    
    var body: some View {
        ZStack {
            if projectManager.showWelcome {
                WelcomeView()
            } else {
                MainView()
            }
        }
        .animation(AppTheme.Animation.smooth, value: projectManager.showWelcome)
        .onAppear {
            // Load last project and show welcome — called exactly once at app launch
            projectManager.loadOnStartup()
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let newSessionRequested = Notification.Name("newSessionRequested")
    static let newProjectRequested = Notification.Name("newProjectRequested")
    static let undoTimelineRequested = Notification.Name("undoTimelineRequested")
    static let redoTimelineRequested = Notification.Name("redoTimelineRequested")
    static let deleteSelectedKeyframeRequested = Notification.Name("deleteSelectedKeyframeRequested")
}
