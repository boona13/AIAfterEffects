//
//  ChatMessage.swift
//  AIAfterEffects
//
//  Chat message model for conversation history
//

import Foundation

// MARK: - Message Role

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

// MARK: - Asset Attachment Info (for persisting 3D model references in chat messages)

struct AssetAttachmentInfo: Codable, Identifiable {
    var id: String  // asset ID from Sketchfab
    let name: String
    let author: String?
    
    init(id: String, name: String, author: String?) {
        self.id = id
        self.name = name
        self.author = author
    }
}

// MARK: - Chat Message

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date
    var isLoading: Bool
    var attachments: [ChatAttachment]
    
    /// Multiple 3D asset attachments per message
    var assetAttachments: [AssetAttachmentInfo]
    
    /// Scene objects the user attached for focused context
    var objectContexts: [ObjectContextAttachment]
    
    /// Checkpoint ID (git commit short hash) associated with this message.
    /// Set on user messages when the AI response triggered file changes.
    var checkpointId: String?
    
    // Legacy single-asset fields (kept for backward compatibility with saved sessions)
    var assetName: String?
    var assetAuthor: String?
    
    /// Whether this message has any attached 3D assets
    var hasAssetAttachment: Bool {
        !assetAttachments.isEmpty || assetName != nil
    }
    
    /// All asset infos (merges legacy single field with new array for backward compat)
    var allAssetInfos: [AssetAttachmentInfo] {
        if !assetAttachments.isEmpty {
            return assetAttachments
        }
        // Backward compat: if legacy single field is set, wrap it
        if let name = assetName {
            return [AssetAttachmentInfo(id: "", name: name, author: assetAuthor)]
        }
        return []
    }
    
    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        isLoading: Bool = false,
        attachments: [ChatAttachment] = [],
        assetAttachments: [AssetAttachmentInfo] = [],
        objectContexts: [ObjectContextAttachment] = [],
        checkpointId: String? = nil,
        assetName: String? = nil,
        assetAuthor: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isLoading = isLoading
        self.attachments = attachments
        self.assetAttachments = assetAttachments
        self.objectContexts = objectContexts
        self.checkpointId = checkpointId
        self.assetName = assetName
        self.assetAuthor = assetAuthor
    }
    
    /// Creates a loading placeholder message
    static func loadingMessage() -> ChatMessage {
        ChatMessage(
            role: .assistant,
            content: "",
            isLoading: true,
            attachments: []
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case timestamp
        case isLoading
        case attachments
        case assetAttachments
        case objectContexts
        case checkpointId
        case assetName
        case assetAuthor
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(MessageRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        isLoading = try container.decodeIfPresent(Bool.self, forKey: .isLoading) ?? false
        attachments = try container.decodeIfPresent([ChatAttachment].self, forKey: .attachments) ?? []
        assetAttachments = try container.decodeIfPresent([AssetAttachmentInfo].self, forKey: .assetAttachments) ?? []
        objectContexts = try container.decodeIfPresent([ObjectContextAttachment].self, forKey: .objectContexts) ?? []
        checkpointId = try container.decodeIfPresent(String.self, forKey: .checkpointId)
        assetName = try container.decodeIfPresent(String.self, forKey: .assetName)
        assetAuthor = try container.decodeIfPresent(String.self, forKey: .assetAuthor)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(isLoading, forKey: .isLoading)
        try container.encode(attachments, forKey: .attachments)
        try container.encode(assetAttachments, forKey: .assetAttachments)
        if !objectContexts.isEmpty {
            try container.encode(objectContexts, forKey: .objectContexts)
        }
        try container.encodeIfPresent(checkpointId, forKey: .checkpointId)
        try container.encodeIfPresent(assetName, forKey: .assetName)
        try container.encodeIfPresent(assetAuthor, forKey: .assetAuthor)
    }
}

// MARK: - Conversation

struct Conversation: Identifiable, Codable {
    let id: UUID
    var messages: [ChatMessage]
    let createdAt: Date
    var updatedAt: Date
    var title: String?
    
    init(
        id: UUID = UUID(),
        messages: [ChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        title: String? = nil
    ) {
        self.id = id
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
    }
    
    /// Get messages formatted for API context (excluding loading messages)
    func getContextMessages() -> [ChatMessage] {
        messages.filter { !$0.isLoading }
    }
    
    /// Add a message to the conversation
    mutating func addMessage(_ message: ChatMessage) {
        messages.append(message)
        updatedAt = Date()
    }
    
    /// Remove loading messages
    mutating func removeLoadingMessages() {
        messages.removeAll { $0.isLoading }
    }
    
    /// Generate a title from the first user message
    mutating func generateTitle() {
        if title == nil, let firstUserMessage = messages.first(where: { $0.role == .user }) {
            let content = firstUserMessage.content
            if content.count > 40 {
                title = String(content.prefix(40)) + "..."
            } else {
                title = content
            }
        }
    }
}
