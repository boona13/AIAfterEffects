//
//  SketchfabBrowserViewModel.swift
//  AIAfterEffects
//
//  ViewModel for browsing and searching Sketchfab 3D models
//

import Foundation

@MainActor
class SketchfabBrowserViewModel: ObservableObject {
    
    // MARK: - Published State
    
    @Published var searchQuery: String = ""
    @Published var models: [SketchfabModel] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var error: String?
    @Published var selectedCategory: String?
    @Published var sortOption: SketchfabSortOption = .relevance
    @Published var animatedOnly: Bool = false
    @Published var selectedModel: SketchfabModel?
    @Published var categories: [SketchfabCategory] = []
    
    // MARK: - Pagination
    
    private var nextCursor: String?
    private var hasMore = true
    
    // MARK: - Dependencies
    
    private let sketchfabService: SketchfabServiceProtocol
    private let assetManager: AssetManagerService
    
    // MARK: - Init
    
    init(
        sketchfabService: SketchfabServiceProtocol = SketchfabService.shared,
        assetManager: AssetManagerService = AssetManagerService.shared
    ) {
        self.sketchfabService = sketchfabService
        self.assetManager = assetManager
    }
    
    // MARK: - Search
    
    func search() async {
        isLoading = true
        error = nil
        models = []
        nextCursor = nil
        hasMore = true
        
        do {
            let response = try await sketchfabService.searchModels(
                query: searchQuery,
                category: selectedCategory,
                sortBy: sortOption,
                animated: animatedOnly ? true : nil,
                cursor: nil,
                count: 24
            )
            
            models = response.results
            nextCursor = response.cursors?.next ?? response.next?.components(separatedBy: "cursor=").last
            hasMore = nextCursor != nil
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    // MARK: - Load More
    
    func loadMore() async {
        guard hasMore, !isLoadingMore, let cursor = nextCursor else { return }
        
        isLoadingMore = true
        
        do {
            let response = try await sketchfabService.searchModels(
                query: searchQuery,
                category: selectedCategory,
                sortBy: sortOption,
                animated: animatedOnly ? true : nil,
                cursor: cursor,
                count: 24
            )
            
            models.append(contentsOf: response.results)
            nextCursor = response.cursors?.next ?? response.next?.components(separatedBy: "cursor=").last
            hasMore = nextCursor != nil
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoadingMore = false
    }
    
    // MARK: - Categories
    
    func loadCategories() async {
        do {
            categories = try await sketchfabService.getCategories()
        } catch {
            // Non-critical, categories are optional
            DebugLogger.shared.warning("Failed to load categories: \(error)", category: .network)
        }
    }
    
    // MARK: - Download
    
    func downloadModel(_ model: SketchfabModel) async throws -> Local3DAsset {
        let downloadResponse = try await sketchfabService.getDownloadLinks(uid: model.uid)
        return try await assetManager.downloadModel(model, downloadResponse: downloadResponse)
    }
    
    // MARK: - Helpers
    
    func isModelDownloaded(_ model: SketchfabModel) -> Bool {
        assetManager.isDownloaded(uid: model.uid)
    }
    
    /// Load initial content (popular downloadable models)
    func loadInitialContent() async {
        await loadCategories()
        searchQuery = ""
        await search()
    }
}
