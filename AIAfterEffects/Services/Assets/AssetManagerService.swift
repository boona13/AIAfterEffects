//
//  AssetManagerService.swift
//  AIAfterEffects
//
//  Manages local storage and download of 3D model assets
//

import Foundation
import AppKit
import SceneKit

// MARK: - Asset Manager Service

@MainActor
class AssetManagerService: ObservableObject, AssetManagerProtocol {
    static let shared = AssetManagerService()
    
    // MARK: - Published State
    
    @Published var assets: [Local3DAsset] = []
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var downloadingModelId: String?
    
    // MARK: - Paths
    
    private let assetsDirectoryName = "Assets3D"
    private let catalogFileName = "catalog.json"
    private let thumbnailsDirectoryName = "thumbnails"
    
    var baseDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("AIAfterEffects").appendingPathComponent(assetsDirectoryName)
    }
    
    private var catalogURL: URL {
        baseDirectory.appendingPathComponent(catalogFileName)
    }
    
    private var thumbnailsDirectory: URL {
        baseDirectory.appendingPathComponent(thumbnailsDirectoryName)
    }
    
    // MARK: - Init
    
    private init() {
        ensureDirectoriesExist()
        reloadCatalog()
        backfillBoundingBoxes()
    }
    
    // MARK: - Directory Setup
    
    private func ensureDirectoriesExist() {
        let fm = FileManager.default
        try? fm.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Catalog Management
    
    func reloadCatalog() {
        guard FileManager.default.fileExists(atPath: catalogURL.path) else {
            assets = []
            return
        }
        
        do {
            let data = try Data(contentsOf: catalogURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            assets = try decoder.decode([Local3DAsset].self, from: data)
        } catch {
            DebugLogger.shared.error("Failed to load asset catalog: \(error)", category: .app)
            assets = []
        }
    }
    
    private func saveCatalog() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(assets)
            try data.write(to: catalogURL)
        } catch {
            DebugLogger.shared.error("Failed to save asset catalog: \(error)", category: .app)
        }
    }
    
    // MARK: - Download Model
    
    func downloadModel(_ model: SketchfabModel, downloadResponse: SketchfabDownloadResponse) async throws -> Local3DAsset {
        let logger = DebugLogger.shared
        
        // Check if already downloaded
        if let existing = getAsset(id: model.uid) {
            logger.info("Model '\(model.name)' already downloaded", category: .app)
            return existing
        }
        
        isDownloading = true
        downloadProgress = 0
        downloadingModelId = model.uid
        defer {
            isDownloading = false
            downloadProgress = 1.0
            downloadingModelId = nil
        }
        
        // Prefer USDZ (native Apple format), fall back to glTF
        let (downloadURL, format): (URL, Local3DAsset.AssetFormat)
        
        if let usdz = downloadResponse.usdz {
            guard let url = URL(string: usdz.url) else {
                throw SketchfabError.downloadFailed("Invalid USDZ URL")
            }
            downloadURL = url
            format = .usdz
            logger.info("Downloading USDZ for '\(model.name)' (\(usdz.size ?? 0) bytes)", category: .network)
        } else if let gltf = downloadResponse.gltf {
            guard let url = URL(string: gltf.url) else {
                throw SketchfabError.downloadFailed("Invalid glTF URL")
            }
            downloadURL = url
            format = .gltf
            logger.info("Downloading glTF for '\(model.name)' (\(gltf.size ?? 0) bytes)", category: .network)
        } else {
            throw SketchfabError.modelNotDownloadable
        }
        
        // Download the model file
        let modelDir = baseDirectory.appendingPathComponent(model.uid)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        
        let (tempURL, _) = try await downloadFile(from: downloadURL)
        
        downloadProgress = 0.7
        
        // Process downloaded file
        let localPath: String
        let fileSize: Int64
        
        switch format {
        case .usdz:
            let destPath = modelDir.appendingPathComponent("model.usdz")
            try FileManager.default.moveItem(at: tempURL, to: destPath)
            localPath = "\(model.uid)/model.usdz"
            fileSize = Self.fileSize(at: destPath)
            
        case .gltf, .glb:
            // glTF comes as a ZIP - unzip it
            let destPath = modelDir.appendingPathComponent("model.zip")
            try FileManager.default.moveItem(at: tempURL, to: destPath)
            try unzipFile(at: destPath, to: modelDir)
            try? FileManager.default.removeItem(at: destPath) // Remove zip
            
            // Find the .gltf or .glb file
            let contents = try FileManager.default.contentsOfDirectory(at: modelDir, includingPropertiesForKeys: nil)
            if let gltfFile = contents.first(where: { $0.pathExtension == "gltf" || $0.pathExtension == "glb" }) {
                localPath = "\(model.uid)/\(gltfFile.lastPathComponent)"
            } else if let sceneFile = contents.first(where: { $0.lastPathComponent == "scene.gltf" || $0.lastPathComponent == "scene.glb" }) {
                localPath = "\(model.uid)/\(sceneFile.lastPathComponent)"
            } else {
                localPath = "\(model.uid)"
            }
            fileSize = Self.directorySize(at: modelDir)
        }
        
        downloadProgress = 0.85
        
        // Download thumbnail
        var thumbnailPath: String?
        if let thumbURL = model.thumbnailURL {
            do {
                let (thumbData, _) = try await URLSession.shared.data(from: thumbURL)
                let thumbFile = thumbnailsDirectory.appendingPathComponent("\(model.uid).jpg")
                try thumbData.write(to: thumbFile)
                thumbnailPath = "\(thumbnailsDirectoryName)/\(model.uid).jpg"
            } catch {
                logger.warning("Failed to download thumbnail: \(error)", category: .network)
            }
        }
        
        downloadProgress = 0.95
        
        // Create asset entry
        let asset = Local3DAsset(
            id: model.uid,
            name: model.name,
            authorName: model.authorName,
            licenseText: model.licenseText,
            localPath: localPath,
            thumbnailPath: thumbnailPath,
            fileSize: fileSize,
            format: format,
            downloadDate: Date(),
            vertexCount: model.vertexCount,
            animationCount: model.animationCount,
            sketchfabURL: "https://sketchfab.com/3d-models/\(model.uid)"
        )
        
        // Pre-calculate bounding box from the model file
        var finalAsset = asset
        let modelFileURL = asset.fileURL(baseDirectory: baseDirectory)
        if let bbox = Self.calculateBoundingBox(fileURL: modelFileURL) {
            finalAsset = Local3DAsset(
                id: asset.id, name: asset.name, authorName: asset.authorName,
                licenseText: asset.licenseText, localPath: asset.localPath,
                thumbnailPath: asset.thumbnailPath, fileSize: asset.fileSize,
                format: asset.format, downloadDate: asset.downloadDate,
                vertexCount: asset.vertexCount, animationCount: asset.animationCount,
                sketchfabURL: asset.sketchfabURL,
                boundingBoxX: bbox.x, boundingBoxY: bbox.y, boundingBoxZ: bbox.z
            )
            logger.info("Model bbox: \(String(format: "%.1f", bbox.x)) × \(String(format: "%.1f", bbox.y)) × \(String(format: "%.1f", bbox.z))", category: .app)
        }
        
        assets.append(finalAsset)
        saveCatalog()
        
        logger.success("Downloaded '\(model.name)' (\(finalAsset.formattedFileSize))", category: .app)
        
        return finalAsset
    }
    
    // MARK: - Delete Asset
    
    func deleteAsset(_ asset: Local3DAsset) throws {
        let modelDir = baseDirectory.appendingPathComponent(asset.id)
        try? FileManager.default.removeItem(at: modelDir)
        
        // Remove thumbnail
        if let thumbPath = asset.thumbnailPath {
            let thumbURL = baseDirectory.appendingPathComponent(thumbPath)
            try? FileManager.default.removeItem(at: thumbURL)
        }
        
        assets.removeAll { $0.id == asset.id }
        saveCatalog()
    }
    
    // MARK: - Query
    
    func isDownloaded(uid: String) -> Bool {
        assets.contains { $0.id == uid }
    }
    
    func getAsset(id: String) -> Local3DAsset? {
        assets.first { $0.id == id }
    }
    
    /// Get the full file URL for a model asset
    func modelFileURL(for assetId: String) -> URL? {
        guard let asset = getAsset(id: assetId) else { return nil }
        return asset.fileURL(baseDirectory: baseDirectory)
    }
    
    /// Get the full thumbnail URL for a model asset
    func thumbnailFileURL(for assetId: String) -> URL? {
        guard let asset = getAsset(id: assetId) else { return nil }
        return asset.thumbnailURL(baseDirectory: baseDirectory)
    }
    
    // MARK: - Bounding Box Calculation
    
    /// Loads a 3D model file via SceneKit and measures its bounding box
    static func calculateBoundingBox(fileURL: URL) -> (x: Float, y: Float, z: Float)? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        
        do {
            let scene = try SCNScene(url: fileURL, options: [
                .checkConsistency: false,
                .flattenScene: false
            ])
            
            let container = SCNNode()
            for child in scene.rootNode.childNodes {
                container.addChildNode(child.clone())
            }
            
            let (minBound, maxBound) = container.boundingBox
            let sizeX = maxBound.x - minBound.x
            let sizeY = maxBound.y - minBound.y
            let sizeZ = maxBound.z - minBound.z
            
            guard sizeX > 0 || sizeY > 0 || sizeZ > 0 else { return nil }
            return (x: Float(sizeX), y: Float(sizeY), z: Float(sizeZ))
        } catch {
            DebugLogger.shared.warning("BBox calculation failed: \(error.localizedDescription)", category: .app)
            return nil
        }
    }
    
    /// Backfill bounding boxes for already-downloaded assets that don't have them
    func backfillBoundingBoxes() {
        var updated = false
        for i in 0..<assets.count {
            guard !assets[i].hasBoundingBox else { continue }
            let fileURL = assets[i].fileURL(baseDirectory: baseDirectory)
            if let bbox = Self.calculateBoundingBox(fileURL: fileURL) {
                assets[i] = Local3DAsset(
                    id: assets[i].id, name: assets[i].name, authorName: assets[i].authorName,
                    licenseText: assets[i].licenseText, localPath: assets[i].localPath,
                    thumbnailPath: assets[i].thumbnailPath, fileSize: assets[i].fileSize,
                    format: assets[i].format, downloadDate: assets[i].downloadDate,
                    vertexCount: assets[i].vertexCount, animationCount: assets[i].animationCount,
                    sketchfabURL: assets[i].sketchfabURL,
                    boundingBoxX: bbox.x, boundingBoxY: bbox.y, boundingBoxZ: bbox.z
                )
                updated = true
            }
        }
        if updated { saveCatalog() }
    }
    
    // MARK: - Cache Management
    
    var totalCacheSize: Int64 {
        assets.reduce(0) { $0 + $1.fileSize }
    }
    
    var formattedCacheSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalCacheSize)
    }
    
    func clearCache() throws {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: baseDirectory, includingPropertiesForKeys: nil)
        for item in contents where item.lastPathComponent != catalogFileName {
            try fm.removeItem(at: item)
        }
        assets = []
        saveCatalog()
        ensureDirectoriesExist()
    }
    
    // MARK: - File Helpers
    
    private func downloadFile(from url: URL) async throws -> (URL, URLResponse) {
        let (localURL, response) = try await URLSession.shared.download(from: url)
        return (localURL, response)
    }
    
    private func unzipFile(at source: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", source.path, "-d", destination.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw SketchfabError.downloadFailed("Failed to unzip model archive")
        }
    }
    
    private static func fileSize(at url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? Int64) ?? 0
    }
    
    private static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(attrs?.fileSize ?? 0)
        }
        return total
    }
}
