//
//  SketchfabModels.swift
//  AIAfterEffects
//
//  Data models for Sketchfab API responses
//

import Foundation

// MARK: - Search Response

struct SketchfabSearchResponse: Codable {
    let results: [SketchfabModel]
    let cursors: Cursors?
    let next: String?
    let previous: String?
    
    struct Cursors: Codable {
        let next: String?
        let previous: String?
    }
}

// MARK: - Model

struct SketchfabModel: Codable, Identifiable, Equatable {
    let uid: String
    let name: String
    let description: String?
    let thumbnails: SketchfabThumbnails?
    let user: SketchfabUser?
    let license: SketchfabLicense?
    let viewCount: Int?
    let likeCount: Int?
    let isDownloadable: Bool?
    let animationCount: Int?
    let faceCount: Int?
    let vertexCount: Int?
    let publishedAt: String?
    let tags: [SketchfabTag]?
    let categories: [SketchfabCategory]?
    
    var id: String { uid }
    
    static func == (lhs: SketchfabModel, rhs: SketchfabModel) -> Bool {
        lhs.uid == rhs.uid
    }
    
    /// Best available thumbnail URL
    var thumbnailURL: URL? {
        if let urlStr = thumbnails?.images?.first(where: { $0.width == 256 })?.url
            ?? thumbnails?.images?.first?.url {
            return URL(string: urlStr)
        }
        return nil
    }
    
    /// Large preview thumbnail URL
    var previewURL: URL? {
        if let urlStr = thumbnails?.images?.last?.url {
            return URL(string: urlStr)
        }
        return nil
    }
    
    /// Author display name
    var authorName: String {
        user?.displayName ?? user?.username ?? "Unknown"
    }
    
    /// Formatted vertex count
    var formattedVertexCount: String? {
        guard let count = vertexCount else { return nil }
        if count >= 1_000_000 {
            return String(format: "%.1fM verts", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK verts", Double(count) / 1_000)
        }
        return "\(count) verts"
    }
    
    /// License display text
    var licenseText: String {
        license?.label ?? "Unknown License"
    }
}

// MARK: - Thumbnails

struct SketchfabThumbnails: Codable {
    let images: [SketchfabThumbnailImage]?
}

struct SketchfabThumbnailImage: Codable {
    let url: String
    let width: Int?
    let height: Int?
    let size: Int?
}

// MARK: - User

struct SketchfabUser: Codable {
    let uid: String?
    let username: String?
    let displayName: String?
    let profileUrl: String?
    let avatar: SketchfabAvatar?
}

struct SketchfabAvatar: Codable {
    let uri: String?
    let images: [SketchfabThumbnailImage]?
}

// MARK: - License

struct SketchfabLicense: Codable {
    let uid: String?
    let label: String?
    let requirements: String?
    let url: String?
    let fullName: String?
    let slug: String?
}

// MARK: - Tag

struct SketchfabTag: Codable {
    let name: String?
    let slug: String?
}

// MARK: - Category

struct SketchfabCategory: Codable {
    let uid: String?
    let name: String?
    let slug: String?
    let uri: String?
}

// MARK: - Download Response

struct SketchfabDownloadResponse: Codable {
    let gltf: SketchfabDownloadLink?
    let usdz: SketchfabDownloadLink?
}

struct SketchfabDownloadLink: Codable {
    let url: String
    let size: Int?
    let expires: Int?
}

// MARK: - Categories List Response

struct SketchfabCategoriesResponse: Codable {
    let results: [SketchfabCategory]
    let next: String?
}

// MARK: - Sort Options

enum SketchfabSortOption: String, CaseIterable {
    case relevance = "-relevance"
    case likes = "-likeCount"
    case views = "-viewCount"
    case recent = "-publishedAt"
    
    var displayName: String {
        switch self {
        case .relevance: return "Relevance"
        case .likes: return "Most Liked"
        case .views: return "Most Viewed"
        case .recent: return "Recent"
        }
    }
}

// MARK: - Auth Token

struct SketchfabAuthConfig {
    /// API Token from user settings
    static var apiToken: String {
        get {
            if let token = KeychainSecretStore.string(for: .sketchfabAPIToken), !token.isEmpty {
                return token
            }
            return KeychainSecretStore.migrateLegacyUserDefaultsValue(for: .sketchfabAPIToken) ?? ""
        }
        set {
            KeychainSecretStore.set(newValue, for: .sketchfabAPIToken)
            UserDefaults.standard.removeObject(forKey: SecretStoreKey.sketchfabAPIToken.rawValue)
        }
    }
    
    /// OAuth2 access token (from browser login)
    static var oauthToken: String {
        get {
            if let token = KeychainSecretStore.string(for: .sketchfabOAuthToken), !token.isEmpty {
                return token
            }
            return KeychainSecretStore.migrateLegacyUserDefaultsValue(for: .sketchfabOAuthToken) ?? ""
        }
        set {
            KeychainSecretStore.set(newValue, for: .sketchfabOAuthToken)
            UserDefaults.standard.removeObject(forKey: SecretStoreKey.sketchfabOAuthToken.rawValue)
        }
    }
    
    /// OAuth2 token expiry date
    static var oauthTokenExpiry: Date? {
        get {
            let interval = UserDefaults.standard.double(forKey: "sketchfab_oauth_expiry")
            return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "sketchfab_oauth_expiry")
        }
    }
    
    /// Whether we have any valid auth
    static var isAuthenticated: Bool {
        if !oauthToken.isEmpty, let expiry = oauthTokenExpiry, expiry > Date() {
            return true
        }
        return !apiToken.isEmpty
    }
    
    /// Best available auth header value
    static var authHeaderValue: String? {
        // Prefer OAuth2 if valid
        if !oauthToken.isEmpty, let expiry = oauthTokenExpiry, expiry > Date() {
            return "Bearer \(oauthToken)"
        }
        // Fall back to API token
        if !apiToken.isEmpty {
            return "Token \(apiToken)"
        }
        return nil
    }
    
    /// Clear all auth
    static func clearAuth() {
        apiToken = ""
        oauthToken = ""
        oauthTokenExpiry = nil
    }
}
