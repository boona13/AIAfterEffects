//
//  AssetLibraryView.swift
//  AIAfterEffects
//
//  View for managing locally downloaded 3D model assets
//

import SwiftUI

struct AssetLibraryView: View {
    @StateObject private var viewModel = AssetLibraryViewModel()
    
    /// Called when user selects an asset to use in scene
    var onAssetSelected: ((Local3DAsset) -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            if viewModel.assets.isEmpty {
                emptyState
            } else {
                libraryContent
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 36))
                .foregroundColor(AppTheme.Colors.textTertiary)
            
            Text("No downloaded models")
                .font(AppTheme.Typography.body)
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            Text("Browse Sketchfab to find and download free 3D models")
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.Colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Library Content
    
    private var libraryContent: some View {
        VStack(spacing: 0) {
            // Search and info bar
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.Colors.textTertiary)
                
                TextField("Search downloads...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .font(AppTheme.Typography.body)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                
                Spacer()
                
                Text("\(viewModel.assetCount) models")
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.textTertiary)
                
                Text(viewModel.totalCacheSize)
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.textTertiary)
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, AppTheme.Spacing.xxs)
                    .background(AppTheme.Colors.backgroundTertiary)
                    .cornerRadius(AppTheme.Radius.xs)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.sm)
            
            ThemedDivider()
            
            // Grid
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 160, maximum: 200), spacing: AppTheme.Spacing.md)
                ], spacing: AppTheme.Spacing.md) {
                    ForEach(viewModel.assets) { asset in
                        AssetCardView(
                            asset: asset,
                            thumbnailURL: viewModel.thumbnailFileURL(for: asset),
                            isSelected: viewModel.selectedAsset?.id == asset.id,
                            onTap: { viewModel.selectedAsset = asset },
                            onUse: {
                                onAssetSelected?(asset)
                            },
                            onDelete: {
                                viewModel.deleteAsset(asset)
                            }
                        )
                    }
                }
                .padding(AppTheme.Spacing.lg)
            }
        }
    }
}

// MARK: - Asset Card View

struct AssetCardView: View {
    let asset: Local3DAsset
    let thumbnailURL: URL?
    let isSelected: Bool
    let onTap: () -> Void
    let onUse: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    @State private var showDeleteConfirm = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail
            ZStack {
                Rectangle()
                    .fill(AppTheme.Colors.backgroundTertiary)
                
                if let url = thumbnailURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        default:
                            Image(systemName: "cube.fill")
                                .font(.system(size: 24))
                                .foregroundColor(AppTheme.Colors.textTertiary)
                        }
                    }
                } else {
                    Image(systemName: "cube.fill")
                        .font(.system(size: 24))
                        .foregroundColor(AppTheme.Colors.textTertiary)
                }
                
                // Hover overlay
                if isHovering {
                    VStack {
                        Spacer()
                        HStack(spacing: AppTheme.Spacing.sm) {
                            Button(action: onUse) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 10))
                                    Text("Use")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppTheme.Colors.primary)
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            
                            Spacer()
                            
                            Button(action: { showDeleteConfirm = true }) {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white)
                                    .frame(width: 22, height: 22)
                                    .background(AppTheme.Colors.error.opacity(0.8))
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(AppTheme.Spacing.xs)
                        .background(Color.black.opacity(0.6))
                    }
                }
            }
            .frame(height: 120)
            .clipped()
            
            // Info
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(asset.name)
                    .font(AppTheme.Typography.captionMedium)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                
                Text(asset.authorName)
                    .font(AppTheme.Typography.micro)
                    .foregroundColor(AppTheme.Colors.textTertiary)
                    .lineLimit(1)
                
                HStack(spacing: AppTheme.Spacing.sm) {
                    Text(asset.formattedFileSize)
                        .font(AppTheme.Typography.micro)
                        .foregroundColor(AppTheme.Colors.textTertiary)
                    
                    Text(asset.format.rawValue.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(AppTheme.Colors.accent)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(AppTheme.Colors.accent.opacity(0.15))
                        .cornerRadius(2)
                }
            }
            .padding(AppTheme.Spacing.sm)
        }
        .background(AppTheme.Colors.surface)
        .cornerRadius(AppTheme.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .strokeBorder(
                    isSelected ? AppTheme.Colors.primary.opacity(0.5)
                    : (isHovering ? AppTheme.Colors.primary.opacity(0.3) : AppTheme.Colors.border),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .onTapGesture { onTap() }
        .onHover { hovering in
            withAnimation(AppTheme.Animation.quick) {
                isHovering = hovering
            }
        }
        .alert("Delete Model", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete \"\(asset.name)\"? This will remove the downloaded file.")
        }
    }
}
