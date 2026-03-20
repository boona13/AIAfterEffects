//
//  ChatSessionService.swift
//  AIAfterEffects
//
//  File-based chat session storage. Each project stores its chat sessions
//  as JSON files inside a `chats/` directory, enabling multiple conversations
//  per project with full persistence.
//

import Foundation

// MARK: - Chat Session (on-disk model)

/// A chat session stored as a JSON file in the project's chats/ directory.
struct ChatSessionFile: Identifiable, Codable {
    let id: UUID
    var title: String?
    var messages: [ChatMessage]
    let createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        title: String? = nil,
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    /// Add a message
    mutating func addMessage(_ message: ChatMessage) {
        messages.append(message)
        updatedAt = Date()
    }
    
    /// Generate a title from the first user message
    mutating func generateTitle() {
        guard title == nil else { return }
        if let firstUserMsg = messages.first(where: { $0.role == .user }) {
            let content = firstUserMsg.content
            title = content.count > 50 ? String(content.prefix(50)) + "..." : content
        }
    }
    
    /// The file name for this session on disk
    var fileName: String {
        "chat_\(id.uuidString).json"
    }
}

/// Summary for displaying in the session list (lightweight)
struct ChatSessionSummary: Identifiable, Codable {
    let id: UUID
    let title: String?
    let messageCount: Int
    let createdAt: Date
    let updatedAt: Date
    
    init(from session: ChatSessionFile) {
        self.id = session.id
        self.title = session.title
        self.messageCount = session.messages.count
        self.createdAt = session.createdAt
        self.updatedAt = session.updatedAt
    }
}

// MARK: - Protocol

protocol ChatSessionServiceProtocol {
    /// Get the chats directory URL for a project
    func chatsDirectory(for projectURL: URL) -> URL
    
    /// List all chat sessions for a project (sorted by updatedAt descending)
    func listSessions(projectURL: URL) throws -> [ChatSessionSummary]
    
    /// Load a full chat session
    func loadSession(id: UUID, projectURL: URL) throws -> ChatSessionFile
    
    /// Save a chat session to disk
    func saveSession(_ session: ChatSessionFile, projectURL: URL) throws
    
    /// Create a new empty chat session
    func createSession(projectURL: URL) throws -> ChatSessionFile
    
    /// Delete a chat session
    func deleteSession(id: UUID, projectURL: URL) throws
    
    /// Migrate a legacy Session from UserDefaults into a ChatSessionFile
    func migrateFromLegacy(session: Session, projectURL: URL) throws -> ChatSessionFile
}

// MARK: - Implementation

class ChatSessionService: ChatSessionServiceProtocol {
    
    static let shared = ChatSessionService()
    
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager = FileManager.default
    
    private init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - Directory
    
    func chatsDirectory(for projectURL: URL) -> URL {
        projectURL.appendingPathComponent("chats")
    }
    
    private func ensureChatsDirectory(projectURL: URL) throws {
        let dir = chatsDirectory(for: projectURL)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - CRUD
    
    func listSessions(projectURL: URL) throws -> [ChatSessionSummary] {
        let dir = chatsDirectory(for: projectURL)
        
        guard fileManager.fileExists(atPath: dir.path) else {
            return []
        }
        
        let files = try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("chat_") }
        
        var summaries: [ChatSessionSummary] = []
        
        for fileURL in files {
            do {
                let data = try Data(contentsOf: fileURL)
                let session = try decoder.decode(ChatSessionFile.self, from: data)
                summaries.append(ChatSessionSummary(from: session))
            } catch {
                // Skip corrupt files
                continue
            }
        }
        
        // Sort by most recently updated first
        summaries.sort { $0.updatedAt > $1.updatedAt }
        
        return summaries
    }
    
    func loadSession(id: UUID, projectURL: URL) throws -> ChatSessionFile {
        let dir = chatsDirectory(for: projectURL)
        let fileName = "chat_\(id.uuidString).json"
        let fileURL = dir.appendingPathComponent(fileName)
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw ChatSessionError.sessionNotFound(id)
        }
        
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(ChatSessionFile.self, from: data)
    }
    
    func saveSession(_ session: ChatSessionFile, projectURL: URL) throws {
        try ensureChatsDirectory(projectURL: projectURL)
        
        let dir = chatsDirectory(for: projectURL)
        let fileURL = dir.appendingPathComponent(session.fileName)
        
        let data = try encoder.encode(session)
        try data.write(to: fileURL, options: .atomic)
    }
    
    func createSession(projectURL: URL) throws -> ChatSessionFile {
        let session = ChatSessionFile()
        try saveSession(session, projectURL: projectURL)
        return session
    }
    
    func deleteSession(id: UUID, projectURL: URL) throws {
        let dir = chatsDirectory(for: projectURL)
        let fileName = "chat_\(id.uuidString).json"
        let fileURL = dir.appendingPathComponent(fileName)
        
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }
    
    // MARK: - Migration
    
    func migrateFromLegacy(session: Session, projectURL: URL) throws -> ChatSessionFile {
        var chatSession = ChatSessionFile(
            id: session.id,
            title: session.conversation.title,
            messages: session.conversation.messages,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt
        )
        chatSession.generateTitle()
        try saveSession(chatSession, projectURL: projectURL)
        return chatSession
    }
}

// MARK: - Errors

enum ChatSessionError: LocalizedError {
    case sessionNotFound(UUID)
    
    var errorDescription: String? {
        switch self {
        case .sessionNotFound(let id):
            return "Chat session not found: \(id.uuidString)"
        }
    }
}
