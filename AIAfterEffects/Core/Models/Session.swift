//
//  Session.swift
//  AIAfterEffects
//
//  Session model that holds conversation and scene state
//

import Foundation

// MARK: - Session

struct Session: Identifiable, Codable {
    let id: UUID
    var conversation: Conversation
    var sceneState: SceneState
    let createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        conversation: Conversation = Conversation(),
        sceneState: SceneState = SceneState(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.conversation = conversation
        self.sceneState = sceneState
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    /// Creates a fresh new session
    static func newSession() -> Session {
        Session()
    }
    
    /// Update the scene state
    mutating func updateScene(_ newState: SceneState) {
        sceneState = newState
        updatedAt = Date()
    }
    
    /// Add a chat message
    mutating func addMessage(_ message: ChatMessage) {
        conversation.addMessage(message)
        updatedAt = Date()
    }
}

// MARK: - Session Summary (for persistence)

struct SessionSummary: Identifiable, Codable {
    let id: UUID
    let title: String?
    let createdAt: Date
    let updatedAt: Date
    let messageCount: Int
    let objectCount: Int
    
    init(from session: Session) {
        self.id = session.id
        self.title = session.conversation.title
        self.createdAt = session.createdAt
        self.updatedAt = session.updatedAt
        self.messageCount = session.conversation.messages.count
        self.objectCount = session.sceneState.objects.count
    }
}
