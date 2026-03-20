//
//  OpenRouterService.swift
//  AIAfterEffects
//
//  Service for communicating with OpenRouter LLM API
//

import Foundation

// MARK: - OpenRouter Configuration

struct OpenRouterConfig {
    static let productionBaseURL = "https://openrouter.ai/api/v1/chat/completions"
    static let debugBaseURL = "http://localhost:8765/api/v1/chat/completions"
    static let defaultModel = "anthropic/claude-3.5-sonnet"
    
    /// Returns true when using the local debug proxy instead of OpenRouter
    static var isDebugProxy: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "use_debug_proxy")
        #else
        return false
        #endif
    }
    
    /// Toggle debug proxy on/off (DEBUG builds only)
    static func setDebugProxy(_ enabled: Bool) {
        #if DEBUG
        UserDefaults.standard.set(enabled, forKey: "use_debug_proxy")
        #endif
    }
    
    static var baseURL: String {
        #if DEBUG
        if isDebugProxy {
            return debugBaseURL
        }
        #endif
        return productionBaseURL
    }
    
    static var apiKey: String {
        get {
            if let key = KeychainSecretStore.string(for: .openRouterAPIKey), !key.isEmpty {
                return key
            }
            return KeychainSecretStore.migrateLegacyUserDefaultsValue(for: .openRouterAPIKey) ?? ""
        }
        set {
            KeychainSecretStore.set(newValue, for: .openRouterAPIKey)
            UserDefaults.standard.removeObject(forKey: SecretStoreKey.openRouterAPIKey.rawValue)
        }
    }
    
    /// Currently selected model (fetched dynamically from OpenRouter)
    static var selectedModel: String {
        get { UserDefaults.standard.string(forKey: "selected_model") ?? defaultModel }
        set { UserDefaults.standard.set(newValue, forKey: "selected_model") }
    }
}

// MARK: - OpenRouter Service

@MainActor
class OpenRouterService: ObservableObject {
    static let shared = OpenRouterService()
    
    @Published var isLoading = false
    @Published var error: OpenRouterError?
    
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private init() {
        // Types use explicit CodingKeys (e.g. "max_tokens", "tool_calls", "finish_reason")
        // so no automatic key strategy is needed.
    }
    
    // MARK: - Send Message with Context
    
    /// Sends a message to OpenRouter with full conversation history for context
    func sendMessage(
        userMessage: String,
        attachments: [ChatAttachment],
        conversationHistory: [ChatMessage],
        sceneState: SceneState,
        project: Project? = nil,
        currentSceneIndex: Int = 0,
        model: String = OpenRouterConfig.selectedModel
    ) async throws -> LLMResponse {
        
        let logger = DebugLogger.shared
        
        guard OpenRouterConfig.isDebugProxy || !OpenRouterConfig.apiKey.isEmpty else {
            logger.error("API key is missing", category: .llm)
            throw OpenRouterError.missingAPIKey
        }
        
        isLoading = true
        error = nil
        
        defer { isLoading = false }
        
        if OpenRouterConfig.isDebugProxy {
            logger.info("🔧 Using DEBUG PROXY at \(OpenRouterConfig.baseURL)", category: .llm)
        }
        
        // Log the request
        logger.logLLMRequest(
            userMessage: userMessage,
            model: model,
            historyCount: conversationHistory.count
        )
        logger.debug("Scene has \(sceneState.objects.count) objects, canvas: \(Int(sceneState.canvasWidth))x\(Int(sceneState.canvasHeight))", category: .llm)
        
        // Extract image dimensions from attachments for prompt context
        let attachmentInfos = PromptBuilder.extractAttachmentInfos(from: attachments)
        if !attachmentInfos.isEmpty {
            for info in attachmentInfos {
                logger.debug("Attachment[\(info.index)] '\(info.filename)': \(info.width)x\(info.height)px", category: .llm)
            }
        }
        
        // Compact conversation history (summarizes old messages if needed)
        // Done FIRST so both planning pass and main request benefit
        let compactedHistory = await compactConversationHistory(
            conversationHistory,
            sceneState: sceneState
        )
        
        // Planning pass (concept + layout + timeline)
        let plan = try await generatePlan(
            userMessage: userMessage,
            attachments: attachments,
            conversationHistory: compactedHistory,
            sceneState: sceneState,
            project: project,
            currentSceneIndex: currentSceneIndex,
            model: model,
            attachmentInfos: attachmentInfos
        )
        
        if let plan = plan {
            logger.info("Planning pass succeeded (plan length: \(plan.count) chars)", category: .llm)
        } else {
            logger.warning("Planning pass failed or returned empty plan; continuing without it", category: .llm)
        }
        
        // Build the request
        let request = try buildRequest(
            userMessage: userMessage,
            attachments: attachments,
            conversationHistory: compactedHistory,
            sceneState: sceneState,
            project: project,
            currentSceneIndex: currentSceneIndex,
            model: model,
            plan: plan,
            attachmentInfos: attachmentInfos
        )
        
        // Make the API call
        logger.info("Sending request to OpenRouter...", category: .network)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check response status
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("Invalid HTTP response", category: .network)
            throw OpenRouterError.invalidResponse
        }
        
        logger.info("Response status: \(httpResponse.statusCode)", category: .network)
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let rawBody = String(data: data, encoding: .utf8) ?? ""
            let errorMessage = OpenRouterService.parseAPIErrorMessage(statusCode: httpResponse.statusCode, body: rawBody)
            logger.error("API error \(httpResponse.statusCode): \(errorMessage)", category: .network)
            throw OpenRouterError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        // Parse the response
        let apiResponse = try decoder.decode(OpenRouterAPIResponse.self, from: data)
        
        guard let content = extractResponseText(from: apiResponse, rawData: data) else {
            logger.error("Empty response from API", category: .llm)
            throw OpenRouterError.emptyResponse
        }
        
        logger.debug("Raw response length: \(content.count) chars", category: .llm)
        
        // Parse the LLM response to extract scene commands
        let result = try parseLLMResponse(content)
        
        // Log the parsed result
        logger.logLLMResponse(
            response: content,
            parsed: result.commands != nil,
            actionsCount: result.commands?.actions?.count ?? 0
        )
        
        return result
    }
    
    // MARK: - Streaming Send (SSE)
    
    /// Sends a message with SSE streaming, invoking `onPartial` as content tokens arrive.
    /// Returns the full parsed `LLMResponse` once the stream completes.
    func sendMessageStreaming(
        userMessage: String,
        attachments: [ChatAttachment],
        conversationHistory: [ChatMessage],
        sceneState: SceneState,
        project: Project? = nil,
        currentSceneIndex: Int = 0,
        model: String = OpenRouterConfig.selectedModel,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> LLMResponse {
        let logger = DebugLogger.shared
        
        guard OpenRouterConfig.isDebugProxy || !OpenRouterConfig.apiKey.isEmpty else {
            throw OpenRouterError.missingAPIKey
        }
        
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        let attachmentInfos = PromptBuilder.extractAttachmentInfos(from: attachments)
        let compactedHistory = await compactConversationHistory(conversationHistory, sceneState: sceneState)
        
        let plan = try await generatePlan(
            userMessage: userMessage,
            attachments: attachments,
            conversationHistory: compactedHistory,
            sceneState: sceneState,
            project: project,
            currentSceneIndex: currentSceneIndex,
            model: model,
            attachmentInfos: attachmentInfos
        )
        
        var request = try buildRequest(
            userMessage: userMessage,
            attachments: attachments,
            conversationHistory: compactedHistory,
            sceneState: sceneState,
            project: project,
            currentSceneIndex: currentSceneIndex,
            model: model,
            plan: plan,
            attachmentInfos: attachmentInfos
        )
        
        // Override body to include stream: true
        let systemPrompt = PromptBuilder.buildSystemPrompt(
            sceneState: sceneState, project: project, currentSceneIndex: currentSceneIndex,
            plan: plan, attachmentInfos: attachmentInfos, available3DAssets: AssetManagerService.shared.assets
        )
        var messages: [AnyOpenRouterMessage] = [makeMessage(role: "system", text: systemPrompt).asAny]
        for message in compactedHistory {
            if message.isLoading { continue }
            let role = message.role == .user ? "user" : "assistant"
            var historyText = message.content
            if message.role == .user, !message.attachments.isEmpty {
                let names = message.attachments.map { $0.filename }.joined(separator: ", ")
                historyText += "\n[Attached images: \(names)]"
            }
            messages.append(makeMessage(role: role, text: historyText).asAny)
        }
        messages.append(makeMessage(role: "user", text: userMessage, attachments: attachments).asAny)
        
        let body = OpenRouterRequestBody(
            model: model, messages: messages, temperature: 0.7, maxTokens: 8192, stream: true
        )
        request.httpBody = try encoder.encode(body)
        
        logger.info("Sending STREAMING request to OpenRouter...", category: .network)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw OpenRouterError.apiError(statusCode: statusCode, message: "Streaming request failed")
        }
        
        var accumulated = ""
        
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }
            
            guard let chunkData = payload.data(using: .utf8),
                  let chunk = try? JSONSerialization.jsonObject(with: chunkData) as? [String: Any],
                  let choices = chunk["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String else { continue }
            
            accumulated += content
            onPartial(accumulated)
        }
        
        logger.info("Stream complete, accumulated \(accumulated.count) chars", category: .network)
        
        if accumulated.isEmpty {
            throw OpenRouterError.emptyResponse
        }
        
        let result = try parseLLMResponse(accumulated)
        logger.logLLMResponse(
            response: accumulated,
            parsed: result.commands != nil,
            actionsCount: result.commands?.actions?.count ?? 0
        )
        return result
    }
    
    // MARK: - Build Request
    
    private func buildRequest(
        userMessage: String,
        attachments: [ChatAttachment],
        conversationHistory: [ChatMessage],
        sceneState: SceneState,
        project: Project? = nil,
        currentSceneIndex: Int = 0,
        model: String,
        plan: String?,
        attachmentInfos: [AttachmentInfo] = []
    ) throws -> URLRequest {
        
        var request = URLRequest(url: URL(string: OpenRouterConfig.baseURL)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(OpenRouterConfig.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("AIAfterEffects/1.0", forHTTPHeaderField: "HTTP-Referer")
        request.addValue("AI After Effects macOS App", forHTTPHeaderField: "X-Title")
        
        // Build messages array with system prompt and conversation history
        var messages: [AnyOpenRouterMessage] = []
        
        // System prompt with scene context
        let systemPrompt = PromptBuilder.buildSystemPrompt(sceneState: sceneState, project: project, currentSceneIndex: currentSceneIndex, plan: plan, attachmentInfos: attachmentInfos, available3DAssets: AssetManagerService.shared.assets)
        messages.append(makeMessage(role: "system", text: systemPrompt).asAny)
        
        // Add conversation history — strip base64 images from old messages to save tokens.
        // Only the current user message gets full image attachments.
        for message in conversationHistory {
            if message.isLoading { continue }
            let role = message.role == .user ? "user" : "assistant"
            var historyText = message.content
            if message.role == .user, !message.attachments.isEmpty {
                let names = message.attachments.map { $0.filename }.joined(separator: ", ")
                historyText += "\n[Attached images: \(names)]"
            }
            messages.append(makeMessage(role: role, text: historyText).asAny)
        }
        
        // Add current user message
        messages.append(makeMessage(role: "user", text: userMessage, attachments: attachments).asAny)
        
        let body = OpenRouterRequestBody(
            model: model,
            messages: messages,
            temperature: 0.7,
            maxTokens: 8192
        )
        
        request.httpBody = try encoder.encode(body)
        
        return request
    }

    private func makeMessage(role: String, text: String, attachments: [ChatAttachment] = []) -> OpenRouterMessage {
        if role == "user", !attachments.isEmpty {
            var parts: [OpenRouterMessagePart] = []
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                parts.append(.text(trimmed))
            }
            for attachment in attachments {
                parts.append(.image(url: attachment.dataURL))
            }
            return OpenRouterMessage(role: role, content: .parts(parts))
        }
        
        return OpenRouterMessage(role: role, content: .text(text))
    }

    // MARK: - Conversation History Management
    
    /// Prepares conversation history for LLM submission using intelligent compaction.
    /// If the history is short/small, it passes through unchanged.
    /// If large, older messages are compacted into a dense summary via the LLM,
    /// preserving all essential context (objects, animations, user preferences, etc.)
    /// while keeping recent messages in full.
    private func compactConversationHistory(
        _ history: [ChatMessage],
        sceneState: SceneState
    ) async -> [ChatMessage] {
        let compactor = ContextCompactionService.shared
        
        // Use intelligent compaction (summarizes old messages via LLM)
        let prepared = await compactor.prepareForSubmission(
            history: history,
            sceneState: sceneState
        )
        
        // Final safety: truncate very long individual messages
        return truncateLongMessages(prepared)
    }
    
    /// Truncates individual messages that are excessively long (e.g. raw JSON dumps),
    /// applied AFTER compaction as a safety net.
    private func truncateLongMessages(_ messages: [ChatMessage]) -> [ChatMessage] {
        let perMessageLimit = 3_000
        let maxTotalChars = 40_000  // Generous since compaction already handles overall size
        
        var result: [ChatMessage] = []
        var totalChars = 0
        
        for msg in messages {
            if msg.content.count > perMessageLimit && msg.role == .assistant {
                let preview = String(msg.content.prefix(perMessageLimit)) + "... [truncated]"
                result.append(ChatMessage(role: msg.role, content: preview, attachments: msg.attachments))
                totalChars += perMessageLimit
            } else {
                result.append(msg)
                totalChars += msg.content.count
            }
            
            if totalChars > maxTotalChars { break }
        }
        
        return result
    }
    
    // MARK: - Planning Pass
    
    private func generatePlan(
        userMessage: String,
        attachments: [ChatAttachment],
        conversationHistory: [ChatMessage],
        sceneState: SceneState,
        project: Project? = nil,
        currentSceneIndex: Int = 0,
        model: String,
        attachmentInfos: [AttachmentInfo] = []
    ) async throws -> String? {
        let logger = DebugLogger.shared
        
        // Build planning request
        var request = URLRequest(url: URL(string: OpenRouterConfig.baseURL)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(OpenRouterConfig.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("AIAfterEffects/1.0", forHTTPHeaderField: "HTTP-Referer")
        request.addValue("AI After Effects macOS App", forHTTPHeaderField: "X-Title")
        
        var messages: [AnyOpenRouterMessage] = []
        let planningPrompt = PromptBuilder.buildPlanningPrompt(sceneState: sceneState, attachmentInfos: attachmentInfos, project: project, currentSceneIndex: currentSceneIndex)
        messages.append(makeMessage(role: "system", text: planningPrompt).asAny)
        
        // History — strip base64 images from old messages (same as buildRequest)
        for message in conversationHistory {
            if message.isLoading { continue }
            let role = message.role == .user ? "user" : "assistant"
            var historyText = message.content
            if message.role == .user, !message.attachments.isEmpty {
                let names = message.attachments.map { $0.filename }.joined(separator: ", ")
                historyText += "\n[Attached images: \(names)]"
            }
            messages.append(makeMessage(role: role, text: historyText).asAny)
        }
        
        messages.append(makeMessage(role: "user", text: userMessage, attachments: attachments).asAny)
        
        let body = OpenRouterRequestBody(
            model: model,
            messages: messages,
            temperature: 0.6,
            maxTokens: 2048
        )
        
        request.httpBody = try encoder.encode(body)
        
        logger.info("Sending planning request to OpenRouter...", category: .network)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            logger.warning("Planning response failed", category: .network)
            return nil
        }
        
        let apiResponse = try decoder.decode(OpenRouterAPIResponse.self, from: data)
        guard let content = extractResponseText(from: apiResponse, rawData: data) else {
            logger.warning("Planning response empty", category: .llm)
            return nil
        }
        
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedContent.isEmpty {
            logger.warning("Planning response empty after trimming", category: .llm)
            return nil
        }
        
        // Extract plan JSON string
        if let planJSON = extractJSONBlob(from: trimmedContent) {
            let planString = extractPlanFromJSON(planJSON)
                ?? extractPlanObjectString(from: planJSON)
                ?? planJSON
            return planString
        }
        
        logger.warning("Planning response did not contain JSON; using raw content", category: .llm)
        return trimmedContent
    }
    
    // MARK: - Parse LLM Response
    
    private func parseLLMResponse(_ content: String) throws -> LLMResponse {
        let logger = DebugLogger.shared
        logger.debug("Parsing LLM response (\(content.count) chars)", category: .parsing)
        
        // First, try to extract just the message (always do this for clean UI)
        let extractedMessage = extractMessageFromJSON(content)
        if let msg = extractedMessage {
            logger.debug("Extracted message: \(msg.prefix(100))...", category: .parsing)
        }
        
        // Try multiple JSON extraction patterns for full parsing
        let jsonPatterns = [
            ("```json", "```"),
            ("```JSON", "```"),
            ("```", "```"),
            ("{", nil) // Raw JSON without code blocks
        ]
        
        for (startMarker, endMarker) in jsonPatterns {
            if let result = tryExtractJSON(from: content, startMarker: startMarker, endMarker: endMarker, fallbackMessage: extractedMessage) {
                logger.success("Successfully parsed JSON with pattern '\(startMarker)'", category: .parsing)
                return result
            }
        }
        
        logger.warning("Could not parse full JSON, using fallback", category: .parsing)
        
        // No valid JSON found, but if we extracted a message, use it
        if let message = extractedMessage {
            return LLMResponse(textResponse: message, commands: nil)
        }
        
        // Fallback: return the content but clean it up
        return LLMResponse(
            textResponse: cleanupResponse(content),
            commands: nil
        )
    }

    private func extractResponseText(from apiResponse: OpenRouterAPIResponse, rawData: Data) -> String? {
        if let choice = apiResponse.choices.first {
            if let text = extractResponseText(from: choice), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        
        return extractResponseTextFromRawJSON(rawData)
    }
    
    private func extractResponseText(from choice: OpenRouterChoice) -> String? {
        if let messageText = choice.message?.content?.textValue {
            return messageText
        }
        
        if let text = choice.text {
            return text
        }
        
        return nil
    }
    
    private func extractResponseTextFromRawJSON(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let found = findFirstText(in: json) else {
            return nil
        }
        return found
    }
    
    private func findFirstText(in value: Any) -> String? {
        if let string = value as? String, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return string
        }
        
        if let dict = value as? [String: Any] {
            for key in ["content", "text", "output_text", "outputText", "message"] {
                if let candidate = dict[key], let found = findFirstText(in: candidate) {
                    return found
                }
            }
            for (_, candidate) in dict {
                if let found = findFirstText(in: candidate) {
                    return found
                }
            }
        }
        
        if let array = value as? [Any] {
            for item in array {
                if let found = findFirstText(in: item) {
                    return found
                }
            }
        }
        
        return nil
    }
    
    /// Extract just the "message" field from JSON without full parsing
    private func extractMessageFromJSON(_ content: String) -> String? {
        // Look for "message": "..." pattern
        let patterns = [
            #""message"\s*:\s*"([^"]+)"#,
            #"\"message\"\s*:\s*\"([^\"]+)\""#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)),
               let range = Range(match.range(at: 1), in: content) {
                return String(content[range])
            }
        }
        
        return nil
    }
    
    /// Extract the "plan" field from JSON as a string
    private func extractPlanFromJSON(_ content: String) -> String? {
        let patterns = [
            #""plan"\s*:\s*"([^"]+)"#,
            #"\"plan\"\s*:\s*\"([^\"]+)\""#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)),
               let range = Range(match.range(at: 1), in: content) {
                return String(content[range])
            }
        }
        
        return nil
    }
    
    /// Extract the "plan" field (string or object) from JSON
    private func extractPlanObjectString(from content: String) -> String? {
        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = json as? [String: Any],
              let planValue = dict["plan"] else {
            return nil
        }
        
        if let planString = planValue as? String {
            return planString
        }
        
        guard JSONSerialization.isValidJSONObject(planValue),
              let planData = try? JSONSerialization.data(withJSONObject: planValue, options: [.prettyPrinted]),
              let planText = String(data: planData, encoding: .utf8) else {
            return nil
        }
        
        return planText
    }
    
    /// Extract the first JSON blob from content (best-effort)
    private func extractJSONBlob(from content: String) -> String? {
        guard let startIndex = findJSONStart(in: content) else {
            return nil
        }
        
        let endIndex = findMatchingBrace(in: content, from: startIndex)
            ?? findMatchingBraceLenient(in: content, from: startIndex)
            ?? content.lastIndex(of: "}")
        
        guard let resolvedEnd = endIndex else {
            return nil
        }
        
        let jsonString = String(content[startIndex...resolvedEnd])
        return jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Clean up response text by removing JSON
    private func cleanupResponse(_ content: String) -> String {
        // If content starts with {, try to extract message
        if content.trimmingCharacters(in: .whitespaces).hasPrefix("{") {
            if let message = extractMessageFromJSON(content) {
                return message
            }
        }
        
        // Remove any JSON blocks
        var cleaned = content
        if let jsonStart = cleaned.range(of: "{"),
           let jsonEnd = findMatchingBrace(in: cleaned, from: jsonStart.lowerBound) {
            let beforeJSON = String(cleaned[..<jsonStart.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let afterJSON = String(cleaned[cleaned.index(after: jsonEnd)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned = beforeJSON.isEmpty ? afterJSON : beforeJSON
        }
        
        return cleaned.isEmpty ? "Done!" : cleaned
    }
    
    private func tryExtractJSON(from content: String, startMarker: String, endMarker: String?, fallbackMessage: String?) -> LLMResponse? {
        let logger = DebugLogger.shared
        
        guard let startRange = content.range(of: startMarker) else {
            logger.debug("Pattern '\(startMarker)' not found in content", category: .parsing)
            return nil
        }
        
        let jsonStartIndex: String.Index
        var jsonEndIndex: String.Index
        var textBeforeJSON: String = ""
        
        if startMarker == "{" {
            // Raw JSON - find a more reliable start (avoid stray '{' in text)
            jsonStartIndex = findJSONStart(in: content) ?? startRange.lowerBound
            textBeforeJSON = String(content[..<jsonStartIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let endIndex = findMatchingBrace(in: content, from: jsonStartIndex) {
                jsonEndIndex = content.index(after: endIndex)
            } else if let endIndex = findMatchingBraceLenient(in: content, from: jsonStartIndex) {
                logger.warning("Strict brace matching failed, using lenient match", category: .parsing)
                jsonEndIndex = content.index(after: endIndex)
            } else if let lastBrace = content.lastIndex(of: "}") {
                logger.warning("Brace matching failed, using last '}' as end", category: .parsing)
                jsonEndIndex = content.index(after: lastBrace)
            } else {
                logger.warning("Could not find matching brace for raw JSON", category: .parsing)
                return nil
            }
        } else {
            // Code block format
            jsonStartIndex = startRange.upperBound
            textBeforeJSON = String(content[..<startRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let endMarker = endMarker,
               let endRange = content.range(of: endMarker, range: jsonStartIndex..<content.endIndex) {
                jsonEndIndex = endRange.lowerBound
            } else {
                jsonEndIndex = content.endIndex
            }
        }
        
        var jsonString = String(content[jsonStartIndex..<jsonEndIndex])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If using code block, the JSON might not start with {
        if !jsonString.hasPrefix("{") {
            if let braceIndex = jsonString.firstIndex(of: "{") {
                jsonString = String(jsonString[braceIndex...])
            } else {
                logger.warning("JSON string doesn't contain '{'", category: .parsing)
                return nil
            }
        }
        
        let sanitizedJSON = sanitizeJSONString(jsonString)
        let balancedJSON = balanceJSONBrackets(sanitizedJSON)
        
        if balancedJSON != jsonString {
            logger.warning("JSON was sanitized/rebalanced before decoding", category: .parsing)
        }
        
        logger.debug("Attempting to decode JSON (\(balancedJSON.count) chars)", category: .parsing)
        logger.debug("JSON preview: \(String(balancedJSON.prefix(200)))...", category: .parsing)
        
        guard let jsonData = balancedJSON.data(using: .utf8) else {
            logger.error("Could not convert JSON string to data", category: .parsing)
            return nil
        }
        
        do {
            let sceneCommands = try decoder.decode(SceneCommands.self, from: jsonData)
            
            // Log what was parsed
            let logger = DebugLogger.shared
            let actionsCount = sceneCommands.actions?.count ?? 0
            logger.info("Decoded SceneCommands: \(actionsCount) actions", category: .parsing)
            
            if let actions = sceneCommands.actions {
                for (i, action) in actions.enumerated() {
                    logger.debug("  Action[\(i)]: \(action.type.rawValue) -> \(action.target ?? "no target")", category: .parsing)
                }
            } else {
                logger.warning("SceneCommands.actions is nil!", category: .parsing)
            }
            
            // ALWAYS prefer the message from the JSON for clean UI
            let displayMessage: String
            if let jsonMessage = sceneCommands.message, !jsonMessage.isEmpty {
                displayMessage = jsonMessage
            } else if let fallback = fallbackMessage {
                displayMessage = fallback
            } else if !textBeforeJSON.isEmpty {
                displayMessage = textBeforeJSON
            } else {
                displayMessage = "Done!"
            }
            
            return LLMResponse(
                textResponse: displayMessage,
                commands: sceneCommands
            )
        } catch {
            DebugLogger.shared.logParsingError(
                "\(error)",
                json: String(balancedJSON.prefix(500))
            )
            
            // Try to salvage actions even if the full JSON is invalid
            if let salvaged = trySalvageSceneCommands(from: balancedJSON, fallbackMessage: fallbackMessage) {
                DebugLogger.shared.info("Salvaged \(salvaged.actions?.count ?? 0) actions from invalid JSON", category: .parsing)
                return LLMResponse(textResponse: salvaged.message ?? (fallbackMessage ?? "Done!"), commands: salvaged)
            }
            
            return nil
        }
    }
    
    private func findMatchingBrace(in string: String, from startIndex: String.Index) -> String.Index? {
        var depth = 0
        var index = startIndex
        var inString = false
        var escapeNext = false
        
        while index < string.endIndex {
            let char = string[index]
            
            if escapeNext {
                escapeNext = false
            } else if char == "\\" {
                escapeNext = true
            } else if char == "\"" {
                inString.toggle()
            } else if !inString {
                if char == "{" {
                    depth += 1
                } else if char == "}" {
                    depth -= 1
                    if depth == 0 {
                        return index
                    }
                }
            }
            
            index = string.index(after: index)
        }
        
        return nil
    }
    
    private func sanitizeJSONString(_ input: String) -> String {
        var output = ""
        var inString = false
        var escapeNext = false
        
        for char in input {
            if escapeNext {
                output.append(char)
                escapeNext = false
                continue
            }
            
            if char == "\\" {
                output.append(char)
                escapeNext = true
                continue
            }
            
            if char == "\"" {
                inString.toggle()
                output.append(char)
                continue
            }
            
            if inString {
                switch char {
                case "\n":
                    output.append("\\n")
                case "\r":
                    output.append("\\r")
                case "\t":
                    output.append("\\t")
                default:
                    if char.unicodeScalars.first?.value ?? 0 < 0x20 {
                        // Drop other control characters
                        continue
                    } else {
                        output.append(char)
                    }
                }
            } else {
                output.append(char)
            }
        }
        
        return output
    }
    
    private func balanceJSONBrackets(_ input: String) -> String {
        var inString = false
        var escapeNext = false
        var braceCount = 0
        var bracketCount = 0
        
        for char in input {
            if escapeNext {
                escapeNext = false
                continue
            }
            if char == "\\" {
                escapeNext = true
                continue
            }
            if char == "\"" {
                inString.toggle()
                continue
            }
            if inString { continue }
            
            if char == "{" { braceCount += 1 }
            if char == "}" { braceCount = max(0, braceCount - 1) }
            if char == "[" { bracketCount += 1 }
            if char == "]" { bracketCount = max(0, bracketCount - 1) }
        }
        
        var output = input
        if bracketCount > 0 {
            output.append(String(repeating: "]", count: bracketCount))
        }
        if braceCount > 0 {
            output.append(String(repeating: "}", count: braceCount))
        }
        return output
    }
    
    private func trySalvageSceneCommands(from json: String, fallbackMessage: String?) -> SceneCommands? {
        let logger = DebugLogger.shared
        let message = extractMessageFromJSON(json) ?? fallbackMessage
        
        guard let actionsStart = findActionsArrayStart(in: json) else {
            logger.warning("Could not locate actions array for salvage", category: .parsing)
            return nil
        }
        
        let actionsSubstring = String(json[actionsStart...])
        let actionObjects = extractJSONArrayObjects(from: actionsSubstring)
        
        if actionObjects.isEmpty {
            logger.warning("No complete action objects found during salvage", category: .parsing)
            return nil
        }
        
        var decodedActions: [SceneAction] = []
        for actionJSON in actionObjects {
            let sanitized = sanitizeJSONString(actionJSON)
            guard let data = sanitized.data(using: .utf8) else { continue }
            if let action = try? decoder.decode(SceneAction.self, from: data) {
                decodedActions.append(action)
            } else {
                logger.warning("Failed to decode salvaged action: \(String(actionJSON.prefix(120)))", category: .parsing)
            }
        }
        
        if decodedActions.isEmpty {
            return nil
        }
        
        return SceneCommands(message: message, actions: decodedActions)
    }
    
    private func findActionsArrayStart(in content: String) -> String.Index? {
        let pattern = #""actions"\s*:\s*\["#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)),
           let range = Range(match.range, in: content) {
            if let bracket = content[range].firstIndex(of: "[") {
                return bracket
            }
        }
        return nil
    }
    
    private func extractJSONArrayObjects(from arrayString: String) -> [String] {
        var results: [String] = []
        var inString = false
        var escapeNext = false
        var depth = 0
        var objectStart: String.Index?
        
        for index in arrayString.indices {
            let char = arrayString[index]
            
            if escapeNext {
                escapeNext = false
                continue
            }
            if char == "\\" {
                escapeNext = true
                continue
            }
            if char == "\"" {
                inString.toggle()
                continue
            }
            if inString { continue }
            
            if char == "{" {
                if depth == 0 {
                    objectStart = index
                }
                depth += 1
            } else if char == "}" {
                depth = max(0, depth - 1)
                if depth == 0, let start = objectStart {
                    results.append(String(arrayString[start...index]))
                    objectStart = nil
                }
            }
        }
        
        return results
    }
    
    /// Lenient brace matcher (ignores quoted strings) for malformed JSON
    private func findMatchingBraceLenient(in string: String, from startIndex: String.Index) -> String.Index? {
        var depth = 0
        var index = startIndex
        
        while index < string.endIndex {
            let char = string[index]
            if char == "{" {
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
            index = string.index(after: index)
        }
        
        return nil
    }
    
    /// Find the most likely JSON object start in the content
    private func findJSONStart(in content: String) -> String.Index? {
        let patterns = [
            #"\{\s*"message""#,
            #"\{\s*"actions""#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)),
               let range = Range(match.range(at: 0), in: content) {
                return range.lowerBound
            }
        }
        
        return content.firstIndex(of: "{")
    }
    
    // MARK: - Error Parsing
    
    /// Converts raw API error bodies (including HTML from Cloudflare) into clean, user-friendly messages.
    static func parseAPIErrorMessage(statusCode: Int, body: String) -> String {
        // Detect HTML error pages (Cloudflare 502/500/503 etc.)
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<!DOCTYPE") || trimmed.hasPrefix("<html") || trimmed.contains("<head>") {
            switch statusCode {
            case 500:
                return "OpenRouter is experiencing an internal server error. Please try again in a moment."
            case 502:
                return "OpenRouter's server returned a bad gateway error. This is usually temporary — please retry."
            case 503:
                return "OpenRouter is temporarily unavailable (maintenance or overload). Please try again shortly."
            case 504:
                return "The request to OpenRouter timed out. Please try again."
            case 429:
                return "Rate limit exceeded. Please wait a moment before trying again."
            default:
                return "OpenRouter returned an error (\(statusCode)). Please try again in a few moments."
            }
        }
        
        // Try to parse JSON error body (e.g. {"error": {"message": "..."}})
        if let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let errorObj = json["error"] as? [String: Any],
               let message = errorObj["message"] as? String {
                return message
            }
            if let message = json["message"] as? String {
                return message
            }
        }
        
        // Fallback: use raw body but truncate if too long
        if body.count > 200 {
            return String(body.prefix(200)) + "..."
        }
        return body.isEmpty ? "Unknown error" : body
    }
}

// MARK: - OpenRouter API Types

struct OpenRouterRequestBody: Encodable {
    let model: String
    let messages: [AnyOpenRouterMessage]
    let temperature: Double
    let maxTokens: Int
    let tools: [OpenRouterTool]?
    let toolChoice: String?       // "auto", "none", or omitted
    let stream: Bool
    
    init(model: String, messages: [AnyOpenRouterMessage], temperature: Double, maxTokens: Int, tools: [OpenRouterTool]? = nil, toolChoice: String? = nil, stream: Bool = false) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.tools = tools
        self.toolChoice = toolChoice
        self.stream = stream
    }
    
    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case tools
        case toolChoice = "tool_choice"
        case stream
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(temperature, forKey: .temperature)
        try container.encode(maxTokens, forKey: .maxTokens)
        if let tools, !tools.isEmpty {
            try container.encode(tools, forKey: .tools)
        }
        if let toolChoice {
            try container.encode(toolChoice, forKey: .toolChoice)
        }
        if stream {
            try container.encode(stream, forKey: .stream)
        }
    }
}

// MARK: - Tool Definitions (Request)

struct OpenRouterTool: Encodable {
    let type: String // "function"
    let function: OpenRouterFunctionDef
    
    init(name: String, description: String, parameters: [String: Any]) {
        self.type = "function"
        self.function = OpenRouterFunctionDef(name: name, description: description, parameters: parameters)
    }
}

struct OpenRouterFunctionDef: Encodable {
    let name: String
    let description: String
    let parameters: [String: Any]
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        // Encode parameters as raw JSON
        let jsonData = try JSONSerialization.data(withJSONObject: parameters)
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData)
        try container.encode(AnyEncodable(jsonObject), forKey: .parameters)
    }
    
    enum CodingKeys: String, CodingKey {
        case name, description, parameters
    }
}

/// Type-erasing wrapper so we can encode arbitrary JSON (dicts, arrays, scalars).
struct AnyEncodable: Encodable {
    let value: Any
    init(_ value: Any) { self.value = value }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as String:   try container.encode(v)
        case let v as Int:      try container.encode(v)
        case let v as Double:   try container.encode(v)
        case let v as Bool:     try container.encode(v)
        case let v as [Any]:    try container.encode(v.map { AnyEncodable($0) })
        case let v as [String: Any]:
            try container.encode(v.mapValues { AnyEncodable($0) })
        case is NSNull:         try container.encodeNil()
        default:
            try container.encodeNil()
        }
    }
}

// MARK: - Messages (polymorphic: text, assistant+tool_calls, tool result)

/// A type-erased message that can be system/user/assistant text, assistant with tool_calls, or tool result.
enum AnyOpenRouterMessage: Encodable {
    case text(OpenRouterMessage)
    case assistantToolCalls(OpenRouterAssistantToolCallMessage)
    case toolResult(OpenRouterToolResultMessage)
    
    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let m):             try m.encode(to: encoder)
        case .assistantToolCalls(let m): try m.encode(to: encoder)
        case .toolResult(let m):       try m.encode(to: encoder)
        }
    }
}

struct OpenRouterMessage: Encodable {
    let role: String
    let content: OpenRouterMessageContent
    
    /// Wrap as an AnyOpenRouterMessage for the polymorphic messages array.
    var asAny: AnyOpenRouterMessage { .text(self) }
}

/// An assistant message that contains tool_calls (content is null).
struct OpenRouterAssistantToolCallMessage: Encodable {
    let role: String // "assistant"
    let toolCalls: [OpenRouterToolCallRequest]
    
    enum CodingKeys: String, CodingKey {
        case role
        case toolCalls = "tool_calls"
    }
}

/// A single tool call the assistant wants to make.
struct OpenRouterToolCallRequest: Codable {
    let id: String
    let type: String // "function"
    let function: OpenRouterFunctionCallRequest
}

struct OpenRouterFunctionCallRequest: Codable {
    let name: String
    let arguments: String // JSON string
}

/// A tool result message (role: "tool").
struct OpenRouterToolResultMessage: Encodable {
    let role: String // "tool"
    let toolCallId: String
    let content: String
    
    enum CodingKeys: String, CodingKey {
        case role
        case toolCallId = "tool_call_id"
        case content
    }
}

enum OpenRouterMessageContent: Encodable {
    case text(String)
    case parts([OpenRouterMessagePart])
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(text)
        case .parts(let parts):
            try container.encode(parts)
        }
    }
}

struct OpenRouterMessagePart: Codable {
    let type: String
    let text: String?
    let imageUrl: OpenRouterImageURL?
    
    static func text(_ value: String) -> OpenRouterMessagePart {
        OpenRouterMessagePart(type: "text", text: value, imageUrl: nil)
    }
    
    static func image(url: String) -> OpenRouterMessagePart {
        OpenRouterMessagePart(type: "image_url", text: nil, imageUrl: OpenRouterImageURL(url: url))
    }
}

struct OpenRouterImageURL: Codable {
    let url: String
}

// MARK: - API Response Types

struct OpenRouterAPIResponse: Decodable {
    let id: String
    let choices: [OpenRouterChoice]
}

struct OpenRouterChoice: Decodable {
    let message: OpenRouterResponseMessage?
    let text: String?
    let finishReason: String?
    
    enum CodingKeys: String, CodingKey {
        case message, text
        case finishReason = "finish_reason"
    }
}

struct OpenRouterResponseMessage: Decodable {
    let role: String?
    let content: OpenRouterResponseContent?
    let reasoning: String?
    let toolCalls: [OpenRouterToolCallResponse]?
    
    enum CodingKeys: String, CodingKey {
        case role, content, reasoning
        case toolCalls = "tool_calls"
    }
}

/// A tool call returned by the model in the response.
struct OpenRouterToolCallResponse: Decodable {
    let id: String
    let type: String       // "function"
    let function: OpenRouterFunctionCallResponse
}

struct OpenRouterFunctionCallResponse: Decodable {
    let name: String
    let arguments: String  // JSON string — must be parsed
}

enum OpenRouterResponseContent: Decodable {
    case text(String)
    case parts([OpenRouterMessagePart])
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
            return
        }
        if let parts = try? container.decode([OpenRouterMessagePart].self) {
            self = .parts(parts)
            return
        }
        self = .text("")
    }
    
    var textValue: String? {
        switch self {
        case .text(let text):
            return text
        case .parts(let parts):
            let textParts = parts.compactMap { $0.text }
            return textParts.joined(separator: " ")
        }
    }
}

// MARK: - OpenRouter Errors

enum OpenRouterError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case emptyResponse
    case apiError(statusCode: Int, message: String)
    case parsingError(String)
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenRouter API key is not configured. Please add your API key in settings."
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .emptyResponse:
            return "Received an empty response from the AI."
        case .apiError(let statusCode, let message):
            return "API Error (\(statusCode)): \(message)"
        case .parsingError(let message):
            return "Failed to parse response: \(message)"
        }
    }
}
