//
//  AssetLibraryViewModel.swift
//  AIAfterEffects
//
//  ViewModel for managing locally downloaded 3D model assets
//

import Foundation

@MainActor
class AssetLibraryViewModel: ObservableObject {
    
    // MARK: - Published State
    
    @Published var searchQuery: String = ""
    @Published var selectedAsset: Local3DAsset?
    @Published var error: String?
    
    // MARK: - Dependencies
    
    private let assetManager: AssetManagerService
    
    // MARK: - Init
    
    init(assetManager: AssetManagerService = AssetManagerService.shared) {
        self.assetManager = assetManager
    }
    
    // MARK: - Computed
    
    var assets: [Local3DAsset] {
        if searchQuery.isEmpty {
            return assetManager.assets
        }
        return assetManager.assets.filter {
            $0.name.localizedCaseInsensitiveContains(searchQuery) ||
            $0.authorName.localizedCaseInsensitiveContains(searchQuery)
        }
    }
    
    var totalCacheSize: String {
        assetManager.formattedCacheSize
    }
    
    var assetCount: Int {
        assetManager.assets.count
    }
    
    // MARK: - Actions
    
    func deleteAsset(_ asset: Local3DAsset) {
        do {
            try assetManager.deleteAsset(asset)
            if selectedAsset?.id == asset.id {
                selectedAsset = nil
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func clearCache() {
        do {
            try assetManager.clearCache()
            selectedAsset = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func modelFileURL(for asset: Local3DAsset) -> URL? {
        assetManager.modelFileURL(for: asset.id)
    }
    
    func thumbnailFileURL(for asset: Local3DAsset) -> URL? {
        assetManager.thumbnailFileURL(for: asset.id)
    }
}
