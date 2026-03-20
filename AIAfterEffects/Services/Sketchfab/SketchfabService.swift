//
//  SketchfabService.swift
//  AIAfterEffects
//
//  Sketchfab API service for searching and downloading 3D models
//

import Foundation
import AuthenticationServices

// MARK: - Sketchfab Service

@MainActor
class SketchfabService: NSObject, ObservableObject, SketchfabServiceProtocol {
    static let shared = SketchfabService()
    
    // MARK: - Constants
    
    private let baseURL = "https://api.sketchfab.com/v3"
    
    /// Register your app at https://sketchfab.com/settings/applications to get a client ID.
    /// Leave empty to disable OAuth2 (users will use API token instead).
    private let oauthClientID = "" // Set this after registering at Sketchfab
    private let oauthRedirectScheme = "aiaftereffects"
    
    /// Whether OAuth2 login is available (requires a registered client ID)
    var isOAuthConfigured: Bool {
        !oauthClientID.isEmpty
    }
    
    // MARK: - Published State
    
    @Published var isLoading = false
    @Published var categories: [SketchfabCategory] = []
    
    // MARK: - Private
    
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
    
    private override init() {
        super.init()
    }
    
    // MARK: - Authentication
    
    var isAuthenticated: Bool {
        SketchfabAuthConfig.isAuthenticated
    }
    
    func authenticateWithOAuth() async throws -> String {
        guard isOAuthConfigured else {
            throw SketchfabError.apiError(statusCode: 0, message: "OAuth2 is not configured. Please use an API token instead, or register an app at sketchfab.com/settings/applications to enable OAuth2.")
        }
        
        // OAuth2 implicit grant flow via ASWebAuthenticationSession
        let authURL = URL(string: "https://sketchfab.com/oauth2/authorize/?response_type=token&client_id=\(oauthClientID)&state=\(UUID().uuidString)")!
        
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: oauthRedirectScheme
            ) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: SketchfabError.networkError(error))
                    return
                }
                
                guard let callbackURL = callbackURL else {
                    continuation.resume(throwing: SketchfabError.invalidResponse)
                    return
                }
                
                // Parse the fragment (Sketchfab uses # instead of ?)
                let urlString = callbackURL.absoluteString.replacingOccurrences(of: "#", with: "?")
                guard let components = URLComponents(string: urlString),
                      let token = components.queryItems?.first(where: { $0.name == "access_token" })?.value else {
                    continuation.resume(throwing: SketchfabError.invalidResponse)
                    return
                }
                
                // Parse expiry
                let expiresIn = components.queryItems?.first(where: { $0.name == "expires_in" })?.value
                    .flatMap { Double($0) } ?? 2592000 // Default 30 days
                
                SketchfabAuthConfig.oauthToken = token
                SketchfabAuthConfig.oauthTokenExpiry = Date().addingTimeInterval(expiresIn)
                
                continuation.resume(returning: token)
            }
            
            // For macOS, we need a presentation context
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }
    
    // MARK: - Search Models
    
    func searchModels(
        query: String,
        category: String? = nil,
        sortBy: SketchfabSortOption = .relevance,
        animated: Bool? = nil,
        cursor: String? = nil,
        count: Int = 24
    ) async throws -> SketchfabSearchResponse {
        var components = URLComponents(string: "\(baseURL)/search")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "type", value: "models"),
            URLQueryItem(name: "downloadable", value: "true"),
            URLQueryItem(name: "count", value: "\(count)"),
            URLQueryItem(name: "sort_by", value: sortBy.rawValue)
        ]
        
        if !query.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }
        
        if let category = category {
            queryItems.append(URLQueryItem(name: "categories", value: category))
        }
        
        if let animated = animated {
            queryItems.append(URLQueryItem(name: "animated", value: animated ? "true" : "false"))
        }
        
        if let cursor = cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else {
            throw SketchfabError.invalidResponse
        }
        
        let request = buildRequest(url: url, requiresAuth: false)
        return try await performRequest(request)
    }
    
    // MARK: - Model Details
    
    func getModelDetails(uid: String) async throws -> SketchfabModel {
        let url = URL(string: "\(baseURL)/models/\(uid)")!
        let request = buildRequest(url: url, requiresAuth: false)
        return try await performRequest(request)
    }
    
    // MARK: - Download Links
    
    func getDownloadLinks(uid: String) async throws -> SketchfabDownloadResponse {
        guard isAuthenticated else {
            throw SketchfabError.notAuthenticated
        }
        
        let url = URL(string: "\(baseURL)/models/\(uid)/download")!
        let request = buildRequest(url: url, requiresAuth: true)
        return try await performRequest(request)
    }
    
    // MARK: - Categories
    
    func getCategories() async throws -> [SketchfabCategory] {
        let url = URL(string: "\(baseURL)/categories")!
        let request = buildRequest(url: url, requiresAuth: false)
        let response: SketchfabCategoriesResponse = try await performRequest(request)
        self.categories = response.results
        return response.results
    }
    
    // MARK: - Private Helpers
    
    private func buildRequest(url: URL, requiresAuth: Bool) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        if requiresAuth, let authHeader = SketchfabAuthConfig.authHeaderValue {
            request.addValue(authHeader, forHTTPHeaderField: "Authorization")
        } else if let authHeader = SketchfabAuthConfig.authHeaderValue {
            // Add auth even for non-required endpoints (may unlock more results)
            request.addValue(authHeader, forHTTPHeaderField: "Authorization")
        }
        
        return request
    }
    
    private func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        let logger = DebugLogger.shared
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SketchfabError.invalidResponse
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                logger.error("Sketchfab API error \(httpResponse.statusCode): \(errorMessage)", category: .network)
                throw SketchfabError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
            }
            
            return try decoder.decode(T.self, from: data)
        } catch let error as SketchfabError {
            throw error
        } catch let error as DecodingError {
            logger.error("Sketchfab decoding error: \(error)", category: .parsing)
            throw SketchfabError.invalidResponse
        } catch {
            throw SketchfabError.networkError(error)
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension SketchfabService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? ASPresentationAnchor()
    }
}
