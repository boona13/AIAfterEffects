//
//  ModelDetailView.swift
//  AIAfterEffects
//
//  Detail view for a Sketchfab 3D model with download and use options
//

import SwiftUI
import WebKit

struct ModelDetailView: View {
    let model: SketchfabModel
    let isDownloaded: Bool
    let onDownload: () -> Void
    let onUseInScene: (Local3DAsset) -> Void
    
    @StateObject private var assetManager = AssetManagerService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isDownloading = false
    @State private var downloadError: String?
    @State private var viewerLoaded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Model Details")
                    .font(AppTheme.Typography.headline)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                
                Spacer()
                
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
            
            ThemedDivider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    // Interactive 3D Viewer (Sketchfab embed)
                    ZStack {
                        SketchfabEmbedView(modelUID: model.uid, onLoaded: { viewerLoaded = true })
                            .frame(height: 300)
                            .cornerRadius(AppTheme.Radius.md)
                        
                        if !viewerLoaded {
                            ZStack {
                                Rectangle()
                                    .fill(AppTheme.Colors.backgroundTertiary)
                                VStack(spacing: AppTheme.Spacing.sm) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .tint(AppTheme.Colors.primary)
                                    Text("Loading 3D viewer...")
                                        .font(AppTheme.Typography.caption)
                                        .foregroundColor(AppTheme.Colors.textSecondary)
                                }
                            }
                            .frame(height: 300)
                            .cornerRadius(AppTheme.Radius.md)
                        }
                    }
                    
                    // Model name
                    Text(model.name)
                        .font(AppTheme.Typography.title1)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                    
                    // Author
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.Colors.textTertiary)
                        Text("by \(model.authorName)")
                            .font(AppTheme.Typography.body)
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                    
                    // Stats row
                    HStack(spacing: AppTheme.Spacing.lg) {
                        statBadge(icon: "heart.fill", value: "\(model.likeCount ?? 0)", label: "Likes")
                        statBadge(icon: "eye.fill", value: "\(model.viewCount ?? 0)", label: "Views")
                        if let verts = model.formattedVertexCount {
                            statBadge(icon: "triangle.fill", value: verts, label: "Geometry")
                        }
                        if (model.animationCount ?? 0) > 0 {
                            statBadge(icon: "play.circle.fill", value: "\(model.animationCount!)", label: "Animations")
                        }
                    }
                    
                    // License
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.Colors.textTertiary)
                        Text("License: \(model.licenseText)")
                            .font(AppTheme.Typography.caption)
                            .foregroundColor(AppTheme.Colors.textSecondary)
                    }
                    .padding(AppTheme.Spacing.md)
                    .background(AppTheme.Colors.backgroundTertiary)
                    .cornerRadius(AppTheme.Radius.sm)
                    
                    // Description
                    if let description = model.description, !description.isEmpty {
                        Text("Description")
                            .font(AppTheme.Typography.captionMedium)
                            .foregroundColor(AppTheme.Colors.textSecondary)
                        
                        Text(description.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
                            .font(AppTheme.Typography.body)
                            .foregroundColor(AppTheme.Colors.textSecondary)
                            .lineLimit(5)
                    }
                    
                    // Tags
                    if let tags = model.tags, !tags.isEmpty {
                        FlowLayout(spacing: AppTheme.Spacing.xxs) {
                            ForEach(tags.prefix(10), id: \.slug) { tag in
                                Text("#\(tag.name ?? "")")
                                    .font(AppTheme.Typography.micro)
                                    .foregroundColor(AppTheme.Colors.accent)
                                    .padding(.horizontal, AppTheme.Spacing.sm)
                                    .padding(.vertical, AppTheme.Spacing.xxs)
                                    .background(AppTheme.Colors.accent.opacity(0.1))
                                    .cornerRadius(AppTheme.Radius.xs)
                            }
                        }
                    }
                    
                    // Error
                    if let error = downloadError {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(AppTheme.Colors.error)
                            Text(error)
                                .font(AppTheme.Typography.caption)
                                .foregroundColor(AppTheme.Colors.error)
                        }
                        .padding(AppTheme.Spacing.md)
                        .background(AppTheme.Colors.error.opacity(0.1))
                        .cornerRadius(AppTheme.Radius.sm)
                    }
                }
                .padding(AppTheme.Spacing.lg)
            }
            
            ThemedDivider()
            
            // Action buttons
            HStack(spacing: AppTheme.Spacing.md) {
                // Sketchfab link
                Link(destination: URL(string: "https://sketchfab.com/3d-models/\(model.uid)")!) {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Image(systemName: "globe")
                            .font(.system(size: 12))
                        Text("View on Sketchfab")
                            .font(AppTheme.Typography.captionMedium)
                    }
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.sm)
                    .background(AppTheme.Colors.surface)
                    .cornerRadius(AppTheme.Radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                            .strokeBorder(AppTheme.Colors.border, lineWidth: 1)
                    )
                }
                
                Spacer()
                
                if isDownloaded || assetManager.isDownloaded(uid: model.uid) {
                    // Use in Scene button
                    Button(action: {
                        if let asset = assetManager.getAsset(id: model.uid) {
                            onUseInScene(asset)
                        }
                    }) {
                        HStack(spacing: AppTheme.Spacing.xs) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 14))
                            Text("Use in Scene")
                                .font(AppTheme.Typography.bodyMedium)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .padding(.vertical, AppTheme.Spacing.sm)
                        .background(AppTheme.Colors.primaryGradient)
                        .cornerRadius(AppTheme.Radius.md)
                    }
                    .buttonStyle(.plain)
                } else {
                    // Download button
                    Button(action: {
                        isDownloading = true
                        downloadError = nil
                        onDownload()
                    }) {
                        HStack(spacing: AppTheme.Spacing.xs) {
                            if assetManager.isDownloading && assetManager.downloadingModelId == model.uid {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .tint(.white)
                                Text("Downloading...")
                                    .font(AppTheme.Typography.bodyMedium)
                            } else {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 14))
                                Text("Download")
                                    .font(AppTheme.Typography.bodyMedium)
                            }
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .padding(.vertical, AppTheme.Spacing.sm)
                        .background(
                            SketchfabAuthConfig.isAuthenticated
                                ? AppTheme.Colors.primaryGradient
                                : LinearGradient(colors: [.gray], startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(AppTheme.Radius.md)
                    }
                    .buttonStyle(.plain)
                    .disabled(!SketchfabAuthConfig.isAuthenticated || (assetManager.isDownloading && assetManager.downloadingModelId == model.uid))
                }
            }
            .padding(AppTheme.Spacing.lg)
        }
        .frame(width: 560, height: 640)
        .background(AppTheme.Colors.background)
    }
    
    // MARK: - Helpers
    
    private var placeholderImage: some View {
        ZStack {
            Rectangle()
                .fill(AppTheme.Colors.backgroundTertiary)
            Image(systemName: "cube.fill")
                .font(.system(size: 32))
                .foregroundColor(AppTheme.Colors.textTertiary)
        }
        .frame(height: 200)
        .cornerRadius(AppTheme.Radius.md)
    }
    
    private func statBadge(icon: String, value: String, label: String) -> some View {
        VStack(spacing: AppTheme.Spacing.xxs) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(value)
                    .font(AppTheme.Typography.captionMedium)
            }
            .foregroundColor(AppTheme.Colors.textPrimary)
            
            Text(label)
                .font(AppTheme.Typography.micro)
                .foregroundColor(AppTheme.Colors.textTertiary)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(AppTheme.Colors.backgroundTertiary)
        .cornerRadius(AppTheme.Radius.sm)
    }
}

// MARK: - Sketchfab Embed Viewer (Interactive 3D)

struct SketchfabEmbedView: NSViewRepresentable {
    let modelUID: String
    var onLoaded: (() -> Void)?
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        
        // Load Sketchfab embed with dark UI, no branding clutter
        let embedURL = "https://sketchfab.com/models/\(modelUID)/embed?autostart=1&ui_theme=dark&ui_stop=0&transparent=1&ui_infos=0&ui_watermark_link=0&ui_watermark=0"
        if let url = URL(string: embedURL) {
            webView.load(URLRequest(url: url))
        }
        
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        // No updates needed - the model UID doesn't change
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onLoaded: onLoaded)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let onLoaded: (() -> Void)?
        
        init(onLoaded: (() -> Void)?) {
            self.onLoaded = onLoaded
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async { [weak self] in
                self?.onLoaded?()
            }
        }
    }
}

// MARK: - Flow Layout (for tags)

struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }
    
    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
        
        return (CGSize(width: maxWidth, height: currentY + lineHeight), positions)
    }
}
