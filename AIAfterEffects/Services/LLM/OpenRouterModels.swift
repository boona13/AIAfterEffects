//
//  OpenRouterModels.swift
//  AIAfterEffects
//
//  Service for fetching available models from OpenRouter API
//

import Foundation

// MARK: - Model Info

struct OpenRouterModel: Identifiable, Codable {
    let id: String
    let name: String
    let description: String?
    let contextLength: Int?
    let pricing: ModelPricing?
    let architecture: ModelArchitecture?
    let supportedParameters: [String]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case contextLength = "context_length"
        case pricing
        case architecture
        case supportedParameters = "supported_parameters"
    }
    
    var displayName: String {
        name.isEmpty ? id : name
    }
    
    var pricePerMillionTokens: String? {
        guard let pricing = pricing else { return nil }
        let promptPrice = (Double(pricing.prompt) ?? 0) * 1_000_000
        if promptPrice == 0 { return "Free" }
        return String(format: "$%.2f/M tokens", promptPrice)
    }
    
    var supportsVision: Bool {
        if let modalities = architecture?.inputModalities,
           modalities.contains(where: { $0.lowercased().contains("image") }) {
            return true
        }
        
        if let modality = architecture?.modality?.lowercased(),
           modality.contains("image") {
            return true
        }
        
        return false
    }
    
    var supportsReasoning: Bool {
        let params = supportedParameters ?? []
        return params.contains("reasoning") || params.contains("reasoning_effort") || params.contains("include_reasoning")
    }
}

struct ModelPricing: Codable {
    let prompt: String
    let completion: String
}

struct ModelArchitecture: Codable {
    let inputModalities: [String]?
    let outputModalities: [String]?
    let modality: String?
    let tokenizer: String?
    
    enum CodingKeys: String, CodingKey {
        case inputModalities = "input_modalities"
        case outputModalities = "output_modalities"
        case modality
        case tokenizer
    }
}

// MARK: - API Response

struct ModelsResponse: Codable {
    let data: [OpenRouterModel]
}

// MARK: - Models Service

@MainActor
class OpenRouterModelsService: ObservableObject {
    static let shared = OpenRouterModelsService()
    
    @Published var models: [OpenRouterModel] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let modelsURL = "https://openrouter.ai/api/v1/models"
    
    private init() {}
    
    /// Fetch all available models from OpenRouter
    func fetchModels() async {
        guard !OpenRouterConfig.apiKey.isEmpty else {
            error = "API key not configured"
            return
        }
        
        isLoading = true
        error = nil
        
        defer { isLoading = false }
        
        do {
            var request = URLRequest(url: URL(string: modelsURL)!)
            request.httpMethod = "GET"
            request.addValue("Bearer \(OpenRouterConfig.apiKey)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                error = "Failed to fetch models"
                return
            }
            
            let decoder = JSONDecoder()
            let modelsResponse = try decoder.decode(ModelsResponse.self, from: data)
            
            // Sort models by name and filter to show popular/useful ones first
            models = modelsResponse.data.sorted { model1, model2 in
                // Prioritize certain providers
                let priority1 = modelPriority(model1.id)
                let priority2 = modelPriority(model2.id)
                
                if priority1 != priority2 {
                    return priority1 < priority2
                }
                
                return model1.displayName.localizedCaseInsensitiveCompare(model2.displayName) == .orderedAscending
            }
            
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    /// Get priority for sorting (lower = higher priority)
    private func modelPriority(_ modelId: String) -> Int {
        if modelId.contains("claude") { return 0 }
        if modelId.contains("gpt-4") { return 1 }
        if modelId.contains("gpt-3.5") { return 2 }
        if modelId.contains("gemini") { return 3 }
        if modelId.contains("llama") { return 4 }
        if modelId.contains("mistral") { return 5 }
        return 10
    }
    
    /// Get the currently selected model info
    func selectedModel(id: String) -> OpenRouterModel? {
        models.first { $0.id == id }
    }
}
