//
//  PipelineLLMHelper.swift
//  AIAfterEffects
//
//  Shared LLM calling utility for pipeline agents. Keeps the URLSession
//  boilerplate in one place so each agent file stays focused on its prompt.
//

import Foundation

/// Lightweight LLM call used by all pipeline agents.
/// Returns the raw text content from the model, or nil if the call failed.
/// Pass `imageDataURLs` to include images in the user message (multimodal).
func callLLM(
    systemPrompt: String,
    userMessage: String,
    imageDataURLs: [String] = [],
    temperature: Double = 0.7,
    maxTokens: Int = 1024
) async throws -> String? {
    let logger = DebugLogger.shared
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    
    var messages: [AnyOpenRouterMessage] = []
    messages.append(OpenRouterMessage(role: "system", content: .text(systemPrompt)).asAny)
    
    if imageDataURLs.isEmpty {
        messages.append(OpenRouterMessage(role: "user", content: .text(userMessage)).asAny)
    } else {
        var parts: [OpenRouterMessagePart] = [.text(userMessage)]
        for url in imageDataURLs {
            parts.append(.image(url: url))
        }
        messages.append(OpenRouterMessage(role: "user", content: .parts(parts)).asAny)
    }
    
    let body = OpenRouterRequestBody(
        model: OpenRouterConfig.selectedModel,
        messages: messages,
        temperature: temperature,
        maxTokens: maxTokens
    )
    
    var request = URLRequest(url: URL(string: OpenRouterConfig.baseURL)!)
    request.httpMethod = "POST"
    request.addValue("Bearer \(OpenRouterConfig.apiKey)", forHTTPHeaderField: "Authorization")
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
    request.addValue("AIAfterEffects/1.0", forHTTPHeaderField: "HTTP-Referer")
    request.addValue("AI After Effects macOS App", forHTTPHeaderField: "X-Title")
    request.httpBody = try encoder.encode(body)

    let maxAttempts = 3
    for attempt in 1...maxAttempts {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                logger.warning("[PipelineLLM] HTTP \(statusCode) on attempt \(attempt)/\(maxAttempts)", category: .network)
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 400_000_000)
                    continue
                }
                return nil
            }
            
            let apiResponse = try decoder.decode(OpenRouterAPIResponse.self, from: data)
            if let content = extractResponseText(from: apiResponse, rawData: data)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !content.isEmpty {
                if attempt > 1 {
                    logger.info("[PipelineLLM] Recovered non-empty response on retry \(attempt)/\(maxAttempts)", category: .llm)
                }
                return content
            }
            
            logger.warning("[PipelineLLM] Empty or unsupported response format on attempt \(attempt)/\(maxAttempts)", category: .llm)
            if attempt < maxAttempts {
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 400_000_000)
            }
        } catch {
            logger.warning("[PipelineLLM] Request failed on attempt \(attempt)/\(maxAttempts): \(error.localizedDescription)", category: .llm)
            if attempt == maxAttempts {
                throw error
            }
            try? await Task.sleep(nanoseconds: UInt64(attempt) * 400_000_000)
        }
    }
    
    return nil
}

private func extractResponseText(from apiResponse: OpenRouterAPIResponse, rawData: Data) -> String? {
    if let choice = apiResponse.choices.first {
        if let messageText = choice.message?.content?.textValue,
           !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return messageText
        }
        
        if let text = choice.text,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
    }
    
    return extractResponseTextFromRawJSON(rawData)
}

private func extractResponseTextFromRawJSON(_ data: Data) -> String? {
    guard let json = try? JSONSerialization.jsonObject(with: data, options: []),
          let found = findFirstText(in: json) else {
        return nil
    }
    return found
}

private func findFirstText(in value: Any) -> String? {
    if let string = value as? String,
       !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
