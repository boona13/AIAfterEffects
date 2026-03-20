//
//  SessionManager.swift
//  AIAfterEffects
//
//  Manages sessions with full conversation context and scene state
//

import Foundation
import Combine

@MainActor
class SessionManager: ObservableObject {
    // MARK: - Published Properties
    
    @Published var currentSession: Session
    @Published var sessionHistory: [SessionSummary] = []
    
    // MARK: - Private Properties
    
    private let storageKey = "ai_aftereffects_sessions"
    private let currentSessionKey = "ai_aftereffects_current_session"
    
    // MARK: - Init
    
    init() {
        // Try to restore last session or create new one
        if let savedSession = SessionManager.loadCurrentSession() {
            self.currentSession = savedSession
        } else {
            self.currentSession = Session.newSession()
        }
        
        // Load session history
        loadSessionHistory()
    }
    
    // MARK: - Session Management
    
    /// Creates a new empty session (resets everything)
    func newSession() {
        // Save current session to history if it has content
        if !currentSession.conversation.messages.isEmpty {
            saveSessionToHistory(currentSession)
        }
        
        // Create fresh session
        currentSession = Session.newSession()
        
        // Save
        saveCurrentSession()
    }
    
    /// Save the current session state
    func saveCurrentSession() {
        do {
            let data = try JSONEncoder().encode(currentSession)
            UserDefaults.standard.set(data, forKey: currentSessionKey)
        } catch {
            print("Failed to save current session: \(error)")
        }
    }
    
    /// Load the saved current session
    static func loadCurrentSession() -> Session? {
        guard let data = UserDefaults.standard.data(forKey: "ai_aftereffects_current_session"),
              let session = try? JSONDecoder().decode(Session.self, from: data) else {
            return nil
        }
        return session
    }
    
    // MARK: - Session History
    
    private func loadSessionHistory() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let history = try? JSONDecoder().decode([SessionSummary].self, from: data) else {
            sessionHistory = []
            return
        }
        sessionHistory = history
    }
    
    private func saveSessionToHistory(_ session: Session) {
        let summary = SessionSummary(from: session)
        
        // Add to history (remove if already exists)
        sessionHistory.removeAll { $0.id == summary.id }
        sessionHistory.insert(summary, at: 0)
        
        // Keep only last 50 sessions
        if sessionHistory.count > 50 {
            sessionHistory = Array(sessionHistory.prefix(50))
        }
        
        // Save to UserDefaults
        if let data = try? JSONEncoder().encode(sessionHistory) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        
        // Also save full session data
        saveFullSession(session)
    }
    
    private func saveFullSession(_ session: Session) {
        let key = "session_\(session.id.uuidString)"
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    /// Load a session from history
    func loadSession(id: UUID) -> Session? {
        let key = "session_\(id.uuidString)"
        guard let data = UserDefaults.standard.data(forKey: key),
              let session = try? JSONDecoder().decode(Session.self, from: data) else {
            return nil
        }
        return session
    }
    
    /// Switch to a session from history
    func switchToSession(id: UUID) {
        // Save current session first
        if !currentSession.conversation.messages.isEmpty {
            saveSessionToHistory(currentSession)
        }
        
        // Load and switch
        if let session = loadSession(id: id) {
            currentSession = session
            saveCurrentSession()
        }
    }
    
    /// Delete a session from history
    func deleteSession(id: UUID) {
        sessionHistory.removeAll { $0.id == id }
        
        // Update storage
        if let data = try? JSONEncoder().encode(sessionHistory) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        
        // Remove full session data
        UserDefaults.standard.removeObject(forKey: "session_\(id.uuidString)")
    }
    
    // MARK: - Auto-save
    
    /// Call this periodically or when app goes to background
    func autoSave() {
        saveCurrentSession()
    }
}
