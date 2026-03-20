//
//  AssetManagerProtocol.swift
//  AIAfterEffects
//
//  Protocol defining local 3D asset management
//

import Foundation

// MARK: - Local 3D Asset

struct Local3DAsset: Codable, Identifiable, Equatable {
    let id: String          // Same as Sketchfab UID
    let name: String
    let authorName: String
    let licenseText: String
    let localPath: String   // Relative path within assets directory
    let thumbnailPath: String?
    let fileSize: Int64
    let format: AssetFormat
    let downloadDate: Date
    let vertexCount: Int?
    let animationCount: Int?
    let sketchfabURL: String?
    
    /// Bounding box size in model-space units (pre-normalization).
    /// X = width, Y = height (up), Z = depth. SceneKit uses Y-up.
    var boundingBoxX: Float?
    var boundingBoxY: Float?
    var boundingBoxZ: Float?
    
    enum AssetFormat: String, Codable {
        case usdz
        case gltf
        case glb
    }
    
    /// Full file URL for the model
    func fileURL(baseDirectory: URL) -> URL {
        baseDirectory.appendingPathComponent(localPath)
    }
    
    /// Full file URL for the thumbnail
    func thumbnailURL(baseDirectory: URL) -> URL? {
        guard let path = thumbnailPath else { return nil }
        return baseDirectory.appendingPathComponent(path)
    }
    
    /// Formatted file size string
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
    
    var hasBoundingBox: Bool {
        boundingBoxX != nil && boundingBoxY != nil && boundingBoxZ != nil
    }
    
    /// Human-readable shape description for the LLM, based on bounding box proportions
    var shapeDescription: String? {
        guard let bx = boundingBoxX, let by = boundingBoxY, let bz = boundingBoxZ else { return nil }
        let maxDim = max(bx, max(by, bz))
        guard maxDim > 0 else { return nil }
        
        let rx = bx / maxDim
        let ry = by / maxDim
        let rz = bz / maxDim
        
        var desc = "BBox proportions: width=\(String(format: "%.2f", rx)), height(up)=\(String(format: "%.2f", ry)), depth=\(String(format: "%.2f", rz))"
        
        if ry > rx && ry > rz {
            desc += " → TALL object (height is dominant, like a standing figure, bottle, or headphones)"
        } else if rx > ry && rx > rz {
            desc += " → WIDE object (width is dominant, like a car side-view, monitor, or shelf)"
        } else if rz > rx && rz > ry {
            desc += " → DEEP object (depth is dominant, like a shoe from the side, or a long vehicle)"
        } else {
            desc += " → roughly cubic/spherical"
        }
        
        return desc
    }
}

// MARK: - Asset Manager Protocol

protocol AssetManagerProtocol {
    /// All locally downloaded assets
    var assets: [Local3DAsset] { get }
    
    /// Download a model from Sketchfab and store locally
    func downloadModel(_ model: SketchfabModel, downloadResponse: SketchfabDownloadResponse) async throws -> Local3DAsset
    
    /// Delete a locally stored asset
    func deleteAsset(_ asset: Local3DAsset) throws
    
    /// Check if a model is already downloaded
    func isDownloaded(uid: String) -> Bool
    
    /// Get a local asset by ID
    func getAsset(id: String) -> Local3DAsset?
    
    /// Total size of all cached assets
    var totalCacheSize: Int64 { get }
    
    /// Clear all cached assets
    func clearCache() throws
    
    /// Reload the asset catalog from disk
    func reloadCatalog()
}
