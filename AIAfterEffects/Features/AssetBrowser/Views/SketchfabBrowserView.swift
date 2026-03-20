//
//  SketchfabBrowserView.swift
//  AIAfterEffects
//
//  Browse and search Sketchfab 3D models for download
//

import SwiftUI

struct SketchfabBrowserView: View {
    @StateObject private var viewModel = SketchfabBrowserViewModel()
    @StateObject private var assetManager = AssetManagerService.shared
    @Environment(\.dismiss) private var dismiss
    
    /// Called when user selects a model to use in scene
    var onAssetSelected: ((Local3DAsset) -> Void)?
    
    // MARK: - Tab State
    
    @State private var selectedTab: BrowserTab = .browse
    
    enum BrowserTab: String, CaseIterable {
        case browse = "Browse"
        case library = "My Assets"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            ThemedDivider()
            tabBar
            ThemedDivider()
            
            switch selectedTab {
            case .browse:
                browseContent
            case .library:
                AssetLibraryView(onAssetSelected: onAssetSelected)
            }
        }
        .frame(width: 720, height: 600)
        .background(AppTheme.Colors.background)
        .onAppear {
            if viewModel.models.isEmpty {
                Task { await viewModel.loadInitialContent() }
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            HStack(spacing: AppTheme.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                        .fill(AppTheme.Colors.primary)
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: "cube")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                }
                
                Text("3D Models")
                    .font(AppTheme.Typography.headline)
                    .foregroundColor(AppTheme.Colors.textPrimary)
            }
            
            Spacer()
            
            if !SketchfabAuthConfig.isAuthenticated {
                HStack(spacing: AppTheme.Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.Colors.warning)
                    Text("Login required to download")
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.warning)
                }
            }
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.Colors.surface)
                    .cornerRadius(AppTheme.Radius.sm)
            }
            .buttonStyle(.plain)
        }
        .padding(AppTheme.Spacing.lg)
    }
    
    // MARK: - Tab Bar
    
    private var tabBar: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            ForEach(BrowserTab.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Image(systemName: tab == .browse ? "globe" : "folder.fill")
                            .font(.system(size: 11))
                        Text(tab.rawValue)
                            .font(AppTheme.Typography.captionMedium)
                        if tab == .library {
                            Text("(\(assetManager.assets.count))")
                                .font(AppTheme.Typography.caption)
                                .foregroundColor(AppTheme.Colors.textTertiary)
                        }
                    }
                    .foregroundColor(selectedTab == tab ? AppTheme.Colors.textPrimary : AppTheme.Colors.textSecondary)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.full)
                            .fill(selectedTab == tab ? AppTheme.Colors.primary.opacity(0.08) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.sm)
    }
    
    // MARK: - Browse Content
    
    private var browseContent: some View {
        VStack(spacing: 0) {
            searchAndFilters
            ThemedDivider()
            modelGrid
        }
    }
    
    // MARK: - Search & Filters
    
    private var searchAndFilters: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            // Search bar
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.Colors.textTertiary)
                
                TextField("Search 3D models...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .font(AppTheme.Typography.body)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                    .onSubmit {
                        Task { await viewModel.search() }
                    }
                
                if !viewModel.searchQuery.isEmpty {
                    Button(action: {
                        viewModel.searchQuery = ""
                        Task { await viewModel.search() }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                
                Button(action: { Task { await viewModel.search() } }) {
                    Text("Search")
                        .font(AppTheme.Typography.captionMedium)
                        .foregroundColor(.white)
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.vertical, AppTheme.Spacing.xs)
                        .background(AppTheme.Colors.primary)
                        .cornerRadius(AppTheme.Radius.sm)
                }
                .buttonStyle(.plain)
            }
            .padding(AppTheme.Spacing.sm)
            .background(AppTheme.Colors.backgroundTertiary)
            .cornerRadius(AppTheme.Radius.md)
            
            // Filters row
            HStack(spacing: AppTheme.Spacing.sm) {
                // Sort picker
                Menu {
                    ForEach(SketchfabSortOption.allCases, id: \.self) { option in
                        Button(option.displayName) {
                            viewModel.sortOption = option
                            Task { await viewModel.search() }
                        }
                    }
                } label: {
                    HStack(spacing: AppTheme.Spacing.xxs) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 10))
                        Text(viewModel.sortOption.displayName)
                            .font(AppTheme.Typography.caption)
                    }
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, AppTheme.Spacing.xs)
                    .background(AppTheme.Colors.surface)
                    .cornerRadius(AppTheme.Radius.sm)
                }
                
                // Animated toggle
                Button(action: {
                    viewModel.animatedOnly.toggle()
                    Task { await viewModel.search() }
                }) {
                    HStack(spacing: AppTheme.Spacing.xxs) {
                        Image(systemName: viewModel.animatedOnly ? "checkmark.square.fill" : "square")
                            .font(.system(size: 10))
                        Text("Animated")
                            .font(AppTheme.Typography.caption)
                    }
                    .foregroundColor(viewModel.animatedOnly ? AppTheme.Colors.primary : AppTheme.Colors.textSecondary)
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, AppTheme.Spacing.xs)
                    .background(AppTheme.Colors.surface)
                    .cornerRadius(AppTheme.Radius.sm)
                }
                .buttonStyle(.plain)
                
                // Category pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.xxs) {
                        categoryPill(name: "All", slug: nil)
                        ForEach(viewModel.categories.prefix(8), id: \.uid) { category in
                            categoryPill(name: category.name ?? "?", slug: category.slug)
                        }
                    }
                }
                
                Spacer()
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.sm)
    }
    
    private func categoryPill(name: String, slug: String?) -> some View {
        Button(action: {
            viewModel.selectedCategory = slug
            Task { await viewModel.search() }
        }) {
            Text(name)
                .font(AppTheme.Typography.micro)
                .foregroundColor(viewModel.selectedCategory == slug ? .white : AppTheme.Colors.textSecondary)
                .padding(.horizontal, AppTheme.Spacing.sm)
                .padding(.vertical, AppTheme.Spacing.xxs)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.xs)
                        .fill(viewModel.selectedCategory == slug ? AppTheme.Colors.primary : AppTheme.Colors.surface)
                )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Model Grid
    
    private var modelGrid: some View {
        Group {
            if viewModel.isLoading {
                VStack(spacing: AppTheme.Spacing.md) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(AppTheme.Colors.primary)
                    Text("Searching models...")
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.error {
                VStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(AppTheme.Colors.error)
                    Text(error)
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.Colors.error)
                        .multilineTextAlignment(.center)
                    Button("Retry") { Task { await viewModel.search() } }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if viewModel.models.isEmpty {
                VStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 32))
                        .foregroundColor(AppTheme.Colors.textTertiary)
                    Text("No models found")
                        .font(AppTheme.Typography.body)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 150, maximum: 180), spacing: AppTheme.Spacing.lg)
                    ], spacing: AppTheme.Spacing.lg) {
                        ForEach(viewModel.models) { model in
                            ModelCardView(
                                model: model,
                                isDownloaded: viewModel.isModelDownloaded(model),
                                onTap: { viewModel.selectedModel = model }
                            )
                            .onAppear {
                                // Trigger pagination when the user scrolls near the end
                                if model.id == viewModel.models.last?.id {
                                    Task {
                                        await viewModel.loadMore()
                                    }
                                }
                            }
                        }
                    }
                    .padding(AppTheme.Spacing.xl)
                    
                    if viewModel.isLoadingMore {
                        ProgressView()
                            .scaleEffect(0.6)
                            .padding()
                    }
                }
            }
        }
        .sheet(item: $viewModel.selectedModel) { model in
            ModelDetailView(
                model: model,
                isDownloaded: viewModel.isModelDownloaded(model),
                onDownload: {
                    Task {
                        do {
                            _ = try await viewModel.downloadModel(model)
                            // Download only -- don't auto-attach.
                            // User can click "Use in Scene" when ready.
                        } catch {
                            viewModel.error = error.localizedDescription
                        }
                    }
                },
                onUseInScene: { asset in
                    onAssetSelected?(asset)
                    dismiss()
                }
            )
        }
    }
}

// MARK: - Model Card View

struct ModelCardView: View {
    let model: SketchfabModel
    let isDownloaded: Bool
    let onTap: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Thumbnail
                ZStack(alignment: .topTrailing) {
                    Rectangle()
                        .fill(AppTheme.Colors.backgroundTertiary)
                        .frame(height: 120)
                        .overlay(
                            Group {
                                if let thumbURL = model.thumbnailURL {
                                    AsyncImage(url: thumbURL) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(height: 120)
                                                .clipped()
                                        case .failure:
                                            Image(systemName: "cube.fill")
                                                .font(.system(size: 24))
                                                .foregroundColor(AppTheme.Colors.textTertiary)
                                        case .empty:
                                            ProgressView()
                                                .scaleEffect(0.5)
                                        @unknown default:
                                            EmptyView()
                                        }
                                    }
                                } else {
                                    Image(systemName: "cube.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(AppTheme.Colors.textTertiary)
                                }
                            }
                        )
                        .clipped()
                    
                    // Badges
                    HStack(spacing: 4) {
                        if isDownloaded {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.Colors.success)
                        }
                        if (model.animationCount ?? 0) > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 10))
                                Text("Animated")
                                    .font(.system(size: 8, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(AppTheme.Colors.primary.opacity(0.8))
                            .cornerRadius(4)
                        }
                    }
                    .padding(AppTheme.Spacing.xs)
                }
                
                // Info
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                    Text(model.name)
                        .font(AppTheme.Typography.captionMedium)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                    
                    Text(model.authorName)
                        .font(AppTheme.Typography.micro)
                        .foregroundColor(AppTheme.Colors.textTertiary)
                        .lineLimit(1)
                    
                    HStack(spacing: AppTheme.Spacing.sm) {
                        if let likes = model.likeCount, likes > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 8))
                                Text("\(likes)")
                                    .font(AppTheme.Typography.micro)
                            }
                            .foregroundColor(AppTheme.Colors.textTertiary)
                        }
                        
                        if let verts = model.formattedVertexCount {
                            Text(verts)
                                .font(AppTheme.Typography.micro)
                                .foregroundColor(AppTheme.Colors.textTertiary)
                        }
                    }
                }
                .padding(AppTheme.Spacing.sm)
            }
            .background(AppTheme.Colors.surface)
            .cornerRadius(AppTheme.Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .strokeBorder(
                        isHovering ? AppTheme.Colors.primary.opacity(0.4) : AppTheme.Colors.border,
                        lineWidth: 1
                    )
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(AppTheme.Animation.quick) {
                isHovering = hovering
            }
        }
    }
}
