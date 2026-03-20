//
//  ContextCompactionService.swift
//  AIAfterEffects
//
//  Intelligent context compaction system.
//  Instead of truncating (losing information), compaction uses the LLM to
//  summarize older messages into a dense context block that preserves:
//    - What objects/scenes were created and modified
//    - Key user preferences and decisions
//    - Important creative direction and constraints
//    - Checkpoint references
//
//  The compact summary replaces many messages with one, keeping total
//  context small while retaining all essential information.
//

import Foundation

// MARK: - Compaction Models

/// A compact summary that replaces a block of older messages
struct CompactedContext: Codable {
    /// The compacted summary text
    let summary: String
    
    /// Number of original messages that were compacted
    let originalMessageCount: Int
    
    /// When the compaction was performed
    let compactedAt: Date
    
    /// IDs of messages that were compacted (for reference)
    let compactedMessageIds: [UUID]
}

// MARK: - Protocol

protocol ContextCompactionServiceProtocol {
    /// Check whether compaction is needed for the given history
    func needsCompaction(_ history: [ChatMessage]) -> Bool
    
    /// Compact the conversation history, returning a mixed array of:
    ///   - A single compacted summary message (for old messages)
    ///   - Recent messages in full (preserved verbatim)
    func compact(
        history: [ChatMessage],
        sceneState: SceneState
    ) async -> CompactionResult
    
    /// Prepare history for LLM submission (compact if needed, otherwise pass through)
    func prepareForSubmission(
        history: [ChatMessage],
        sceneState: SceneState
    ) async -> [ChatMessage]
}

/// The result of a compaction operation
struct CompactionResult {
    let messages: [ChatMessage]
    let wasCompacted: Bool
    let compactedContext: CompactedContext?
}

// MARK: - Implementation

class ContextCompactionService: ContextCompactionServiceProtocol {
    
    static let shared = ContextCompactionService()
    
    // MARK: - Configuration
    
    /// Messages below this count are never compacted
    private let minMessagesForCompaction = 16
    
    /// Number of recent messages to always keep in full
    private let recentMessagesToKeep = 10
    
    /// Approximate char limit before compaction triggers
    /// (~4 chars per token, 30K chars ≈ 7.5K tokens of history)
    private let charThreshold = 25_000
    
    /// Maximum chars for the compacted summary
    private let maxSummaryChars = 3_000
    
    /// Cache to avoid re-compacting the same history
    private var lastCompactionHash: Int = 0
    private var cachedResult: CompactionResult?
    
    private init() {}
    
    // MARK: - Public Methods
    
    func needsCompaction(_ history: [ChatMessage]) -> Bool {
        let filtered = history.filter { !$0.isLoading }
        
        // Not enough messages to bother
        if filtered.count < minMessagesForCompaction {
            return false
        }
        
        // Check total character count
        let totalChars = filtered.reduce(0) { $0 + $1.content.count }
        return totalChars > charThreshold
    }
    
    func compact(
        history: [ChatMessage],
        sceneState: SceneState
    ) async -> CompactionResult {
        let filtered = history.filter { !$0.isLoading }
        
        // Check cache — if the history hasn't changed, return cached result
        let historyHash = filtered.map { $0.id }.hashValue
        if historyHash == lastCompactionHash, let cached = cachedResult {
            return cached
        }
        
        // If not enough messages, no compaction needed
        guard needsCompaction(filtered) else {
            let result = CompactionResult(messages: filtered, wasCompacted: false, compactedContext: nil)
            return result
        }
        
        let logger = DebugLogger.shared
        logger.info("[Compaction] Starting compaction of \(filtered.count) messages", category: .llm)
        
        // Split: old messages to compact + recent messages to keep
        let splitIndex = max(0, filtered.count - recentMessagesToKeep)
        let oldMessages = Array(filtered.prefix(splitIndex))
        let recentMessages = Array(filtered.suffix(recentMessagesToKeep))
        
        // If there aren't enough old messages to justify compaction
        if oldMessages.count < 4 {
            let result = CompactionResult(messages: filtered, wasCompacted: false, compactedContext: nil)
            return result
        }
        
        // Generate the compacted summary via LLM
        let summary = await generateSummary(
            oldMessages: oldMessages,
            sceneState: sceneState
        )
        
        if let summary {
            let compactedContext = CompactedContext(
                summary: summary,
                originalMessageCount: oldMessages.count,
                compactedAt: Date(),
                compactedMessageIds: oldMessages.map { $0.id }
            )
            
            // Create a synthetic message containing the compacted context
            let compactedMessage = ChatMessage(
                role: .system,
                content: buildCompactedMessageContent(summary, oldMessageCount: oldMessages.count)
            )
            
            let result = CompactionResult(
                messages: [compactedMessage] + recentMessages,
                wasCompacted: true,
                compactedContext: compactedContext
            )
            
            // Cache
            lastCompactionHash = historyHash
            cachedResult = result
            
            logger.success("[Compaction] Compacted \(oldMessages.count) messages → \(summary.count) char summary + \(recentMessages.count) recent messages", category: .llm)
            
            return result
        } else {
            // Fallback: if LLM summarization fails, use a basic extractive summary
            logger.warning("[Compaction] LLM summarization failed, using extractive fallback", category: .llm)
            
            let fallbackSummary = buildExtractiveSummary(from: oldMessages)
            let compactedMessage = ChatMessage(
                role: .system,
                content: buildCompactedMessageContent(fallbackSummary, oldMessageCount: oldMessages.count)
            )
            
            let result = CompactionResult(
                messages: [compactedMessage] + recentMessages,
                wasCompacted: true,
                compactedContext: CompactedContext(
                    summary: fallbackSummary,
                    originalMessageCount: oldMessages.count,
                    compactedAt: Date(),
                    compactedMessageIds: oldMessages.map { $0.id }
                )
            )
            
            lastCompactionHash = historyHash
            cachedResult = result
            return result
        }
    }
    
    func prepareForSubmission(
        history: [ChatMessage],
        sceneState: SceneState
    ) async -> [ChatMessage] {
        let result = await compact(history: history, sceneState: sceneState)
        return result.messages
    }
    
    /// Invalidate the cache (call when messages are added/removed)
    func invalidateCache() {
        lastCompactionHash = 0
        cachedResult = nil
    }
    
    // MARK: - LLM Summarization
    
    /// Calls the LLM with a specialized summarization prompt to condense old messages
    private func generateSummary(
        oldMessages: [ChatMessage],
        sceneState: SceneState
    ) async -> String? {
        
        guard OpenRouterConfig.isDebugProxy || !OpenRouterConfig.apiKey.isEmpty else { return nil }
        
        // Build the content to summarize
        let conversationText = oldMessages.map { msg in
            let role = msg.role == .user ? "User" : "Assistant"
            let content = msg.content.count > 1000
                ? String(msg.content.prefix(1000)) + "..."
                : msg.content
            
            var line = "[\(role)]: \(content)"
            if let cpId = msg.checkpointId {
                line += " [checkpoint: \(cpId)]"
            }
            return line
        }.joined(separator: "\n\n")
        
        // Limit the input to avoid exceeding context on the summarization call itself
        let truncatedText = conversationText.count > 15_000
            ? String(conversationText.prefix(15_000)) + "\n\n[...earlier messages truncated for summarization...]"
            : conversationText
        
        let systemPrompt = """
        You are a conversation summarizer for a motion design AI tool called AI After Effects.
        
        Your job is to condense a conversation into a COMPACT SUMMARY that preserves ALL important context.
        The summary will replace the original messages in the conversation history.
        
        ## What to preserve (CRITICAL):
        - **Objects created**: Names, types, positions, colors, and key properties
        - **Animations applied**: What was animated, timing, easing, and keyframe details
        - **User preferences**: Style choices, color preferences, layout decisions
        - **Creative direction**: Theme, mood, story arc, design system choices
        - **Scene structure**: Which scenes exist, what's in each, transitions
        - **Modifications made**: What was changed and why (especially recent edits)
        - **Checkpoint references**: Note any checkpoint IDs mentioned
        - **Errors/retries**: If something was attempted and failed, note it
        - **3D models**: If 3D assets were used, note model names and placements
        
        ## What to discard:
        - Pleasantries, greetings, acknowledgments
        - Verbose explanations of how animations work
        - Repetitive JSON snippets (just note what was created/changed)
        - Tool call details (just note the outcome)
        
        ## Output format:
        Write a structured summary using this format:
        
        ```
        CONVERSATION SUMMARY (messages 1-N):
        
        OBJECTS ON CANVAS:
        - [list each object with key properties]
        
        ANIMATIONS:
        - [list active animations with timing]
        
        KEY DECISIONS:
        - [user preferences and creative choices]
        
        MODIFICATIONS LOG:
        - [chronological list of changes made]
        
        CURRENT STATE:
        - [brief description of what the scene looks like now]
        ```
        
        Be CONCISE but COMPLETE. Every detail that could affect future edits must be included.
        Maximum 800 words.
        """
        
        let userPrompt = """
        Summarize this conversation from an AI motion design tool session.
        The current canvas is \(Int(sceneState.canvasWidth))x\(Int(sceneState.canvasHeight)) with \(sceneState.objects.count) objects.
        
        CONVERSATION TO SUMMARIZE:
        \(truncatedText)
        """
        
        do {
            let encoder = JSONEncoder()
            
            let messages: [AnyOpenRouterMessage] = [
                OpenRouterMessage(role: "system", content: .text(systemPrompt)).asAny,
                OpenRouterMessage(role: "user", content: .text(userPrompt)).asAny
            ]
            
            let body = OpenRouterRequestBody(
                model: OpenRouterConfig.selectedModel,
                messages: messages,
                temperature: 0.3,  // Low temperature for factual summarization
                maxTokens: 2048
            )
            
            var request = URLRequest(url: URL(string: OpenRouterConfig.baseURL)!)
            request.httpMethod = "POST"
            request.addValue("Bearer \(OpenRouterConfig.apiKey)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("AIAfterEffects/1.0", forHTTPHeaderField: "HTTP-Referer")
            request.addValue("AI After Effects macOS App", forHTTPHeaderField: "X-Title")
            request.httpBody = try encoder.encode(body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }
            
            let decoder = JSONDecoder()
            let apiResponse = try decoder.decode(OpenRouterAPIResponse.self, from: data)
            
            guard let content = apiResponse.choices.first?.message?.content?.textValue,
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            
            let summary = content.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Enforce max length
            if summary.count > maxSummaryChars {
                return String(summary.prefix(maxSummaryChars))
            }
            
            return summary
        } catch {
            DebugLogger.shared.warning("[Compaction] LLM call failed: \(error.localizedDescription)", category: .llm)
            return nil
        }
    }
    
    // MARK: - Extractive Fallback
    
    /// When LLM summarization fails, build a basic summary by extracting key info from messages
    private func buildExtractiveSummary(from messages: [ChatMessage]) -> String {
        var parts: [String] = []
        
        parts.append("CONVERSATION SUMMARY (\(messages.count) earlier messages):")
        parts.append("")
        
        // Extract user requests
        let userMessages = messages.filter { $0.role == .user }
        if !userMessages.isEmpty {
            parts.append("USER REQUESTS:")
            for (i, msg) in userMessages.enumerated() {
                let preview = msg.content.count > 120
                    ? String(msg.content.prefix(120)) + "..."
                    : msg.content
                let cpNote = msg.checkpointId != nil ? " [checkpoint: \(msg.checkpointId!)]" : ""
                parts.append("  \(i + 1). \(preview)\(cpNote)")
            }
            parts.append("")
        }
        
        // Extract key AI responses (first sentence or short ones)
        let assistantMessages = messages.filter { $0.role == .assistant && !$0.content.isEmpty }
        if !assistantMessages.isEmpty {
            parts.append("AI ACTIONS TAKEN:")
            for msg in assistantMessages {
                // Extract just the first sentence
                let firstSentence: String
                if let dotRange = msg.content.range(of: ". ") {
                    firstSentence = String(msg.content[..<dotRange.lowerBound]) + "."
                } else if msg.content.count > 150 {
                    firstSentence = String(msg.content.prefix(150)) + "..."
                } else {
                    firstSentence = msg.content
                }
                parts.append("  - \(firstSentence)")
            }
            parts.append("")
        }
        
        // Extract any 3D asset references
        let assetMessages = messages.filter { $0.hasAssetAttachment }
        if !assetMessages.isEmpty {
            parts.append("3D ASSETS USED:")
            for msg in assetMessages {
                for asset in msg.allAssetInfos {
                    parts.append("  - \(asset.name) by \(asset.author ?? "unknown")")
                }
            }
            parts.append("")
        }
        
        parts.append("(The current scene state in the system prompt reflects all these changes.)")
        
        return parts.joined(separator: "\n")
    }
    
    // MARK: - Message Formatting
    
    /// Build the content string for the compacted context message
    private func buildCompactedMessageContent(_ summary: String, oldMessageCount: Int) -> String {
        """
        [COMPACTED CONTEXT — \(oldMessageCount) earlier messages summarized below]
        
        \(summary)
        
        [END OF COMPACTED CONTEXT — the messages below are the most recent and should be treated as the current conversation]
        """
    }
}
