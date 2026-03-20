//
//  SketchfabServiceProtocol.swift
//  AIAfterEffects
//
//  Protocol defining the Sketchfab API service interface
//

import Foundation

// MARK: - Sketchfab Service Protocol

protocol SketchfabServiceProtocol {
    /// Search for downloadable 3D models
    func searchModels(
        query: String,
        category: String?,
        sortBy: SketchfabSortOption,
        animated: Bool?,
        cursor: String?,
        count: Int
    ) async throws -> SketchfabSearchResponse
    
    /// Get model details by UID
    func getModelDetails(uid: String) async throws -> SketchfabModel
    
    /// Request download URLs for a model (requires auth)
    func getDownloadLinks(uid: String) async throws -> SketchfabDownloadResponse
    
    /// Fetch available categories
    func getCategories() async throws -> [SketchfabCategory]
    
    /// Authenticate with OAuth2 (returns access token)
    func authenticateWithOAuth() async throws -> String
    
    /// Check if the user is authenticated
    var isAuthenticated: Bool { get }
}

// MARK: - Sketchfab Errors

enum SketchfabError: LocalizedError {
    case notAuthenticated
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case downloadFailed(String)
    case modelNotDownloadable
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Sketchfab authentication required. Please add your API token or log in via Settings."
        case .invalidResponse:
            return "Received an invalid response from Sketchfab."
        case .apiError(let statusCode, let message):
            return "Sketchfab API error (\(statusCode)): \(message)"
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .modelNotDownloadable:
            return "This model is not available for download."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
