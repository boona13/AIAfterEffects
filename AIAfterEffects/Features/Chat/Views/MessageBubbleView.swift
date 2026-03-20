//
//  MessageBubbleView.swift
//  AIAfterEffects
//
//  Individual message bubble component with clean, minimal light styling
//

import SwiftUI
import AppKit

struct MessageBubbleView: View {
    let message: ChatMessage
    @State private var isVisible = false
    
    private var isUser: Bool {
        message.role == .user
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.xs) {
            if isUser {
                Spacer(minLength: 80)
            }
            
            if !isUser {
                // AI Avatar
                AvatarView(isUser: false)
            }
            
            // Message content
            VStack(alignment: isUser ? .trailing : .leading, spacing: AppTheme.Spacing.xxs) {
                if message.isLoading {
                    LoadingBubble()
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .padding(.vertical, AppTheme.Spacing.md)
                        .background(AppTheme.Colors.background)
                        .cornerRadius(AppTheme.Radius.xl)
                        .cornerRadius(AppTheme.Radius.sm, corners: [.topLeft])
                } else {
                    // 3D Asset pills (supports multiple)
                    if message.hasAssetAttachment {
                        ForEach(message.allAssetInfos) { assetInfo in
                            MessageAssetPill(
                                name: assetInfo.name,
                                author: assetInfo.author,
                                isUser: isUser
                            )
                        }
                    }
                    
                    // Object context references
                    if !message.objectContexts.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(message.objectContexts) { ctx in
                                HStack(spacing: 4) {
                                    Image(systemName: ctx.displayIcon)
                                        .font(.system(size: 9))
                                    Text(ctx.objectName)
                                        .font(AppTheme.Typography.micro)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(AppTheme.Colors.primary.opacity(0.08))
                                .foregroundColor(AppTheme.Colors.primary)
                                .cornerRadius(AppTheme.Radius.sm)
                            }
                        }
                    }
                    
                    if !message.attachments.isEmpty {
                        AttachmentBubbleView(attachments: message.attachments, isUser: isUser)
                    }
                    
                    if !message.content.isEmpty {
                        Group {
                            if isUser {
                                // User messages: plain text
                                Text(message.content)
                                    .font(AppTheme.Typography.body)
                                    .textSelection(.enabled)
                                    .foregroundColor(AppTheme.Colors.textPrimary)
                            } else {
                                // AI messages: render markdown formatting
                                MarkdownTextView(
                                    message.content,
                                    foregroundColor: AppTheme.Colors.textPrimary,
                                    font: AppTheme.Typography.body
                                )
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .padding(.vertical, AppTheme.Spacing.md)
                        .background(bubbleBackground)
                        .cornerRadius(AppTheme.Radius.xl)
                        .cornerRadius(AppTheme.Radius.sm, corners: isUser ? [.bottomRight] : [.topLeft])
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.xl)
                                .strokeBorder(AppTheme.Colors.border, lineWidth: 1)
                        )
                    }
                }
                
                // Timestamp
                if !message.isLoading {
                    Text(formatTimestamp(message.timestamp))
                        .font(AppTheme.Typography.micro)
                        .foregroundColor(AppTheme.Colors.textTertiary)
                        .padding(.horizontal, AppTheme.Spacing.xs)
                }
            }
            
            if isUser {
                // User Avatar
                AvatarView(isUser: true)
            }
            
            if !isUser {
                Spacer(minLength: 80)
            }
        }
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 10)
        .onAppear {
            withAnimation(AppTheme.Animation.smooth) {
                isVisible = true
            }
        }
    }
    
    @ViewBuilder
    private var bubbleBackground: some View {
        if isUser {
            // Light warm tint for user messages
            AppTheme.Colors.backgroundSecondary
        } else {
            AppTheme.Colors.surface
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Attachment Bubble

struct AttachmentBubbleView: View {
    let attachments: [ChatAttachment]
    let isUser: Bool
    
    @ViewBuilder
    private var bubbleBackground: some View {
        if isUser {
            AppTheme.Colors.backgroundSecondary
        } else {
            AppTheme.Colors.surface
        }
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.sm) {
                ForEach(attachments) { attachment in
                    AttachmentThumbnail(attachment: attachment)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
        }
        .background(bubbleBackground)
        .cornerRadius(AppTheme.Radius.xl)
        .cornerRadius(AppTheme.Radius.sm, corners: isUser ? [.bottomRight] : [.topLeft])
    }
}

// MARK: - Message Asset Pill (3D model in sent message)

struct MessageAssetPill: View {
    let name: String
    let author: String?
    let isUser: Bool
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .fill(AppTheme.Colors.background)
                    .frame(width: 32, height: 32)
                
                Image(systemName: "cube")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppTheme.Colors.textSecondary)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(AppTheme.Typography.captionMedium)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                
                if let author = author {
                    Text("3D Model · \(author)")
                        .font(AppTheme.Typography.micro)
                        .foregroundColor(AppTheme.Colors.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(AppTheme.Colors.background)
        .cornerRadius(AppTheme.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                .strokeBorder(AppTheme.Colors.border, lineWidth: 1)
        )
    }
}

// MARK: - Attachment Thumbnail

struct AttachmentThumbnail: View {
    let attachment: ChatAttachment
    
    private var previewImage: NSImage? {
        guard let data = attachment.data else { return nil }
        return NSImage(data: data)
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .fill(AppTheme.Colors.background)
                .frame(width: 96, height: 96)
            
            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 96, height: 96)
                    .clipped()
                    .cornerRadius(AppTheme.Radius.md)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundColor(AppTheme.Colors.textTertiary)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .strokeBorder(AppTheme.Colors.border, lineWidth: 1)
        )
    }
}

// MARK: - Corner Radius Extension

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = NSBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - NSBezierPath Extension for macOS

extension NSBezierPath {
    convenience init(roundedRect rect: CGRect, byRoundingCorners corners: UIRectCorner, cornerRadii: CGSize) {
        self.init()
        
        let topLeft = corners.contains(.topLeft) ? cornerRadii.width : 0
        let topRight = corners.contains(.topRight) ? cornerRadii.width : 0
        let bottomLeft = corners.contains(.bottomLeft) ? cornerRadii.width : 0
        let bottomRight = corners.contains(.bottomRight) ? cornerRadii.width : 0
        
        move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
        
        // Top edge
        line(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
        if topRight > 0 {
            curve(to: CGPoint(x: rect.maxX, y: rect.minY + topRight),
                  controlPoint1: CGPoint(x: rect.maxX, y: rect.minY),
                  controlPoint2: CGPoint(x: rect.maxX, y: rect.minY))
        }
        
        // Right edge
        line(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
        if bottomRight > 0 {
            curve(to: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY),
                  controlPoint1: CGPoint(x: rect.maxX, y: rect.maxY),
                  controlPoint2: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        
        // Bottom edge
        line(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
        if bottomLeft > 0 {
            curve(to: CGPoint(x: rect.minX, y: rect.maxY - bottomLeft),
                  controlPoint1: CGPoint(x: rect.minX, y: rect.maxY),
                  controlPoint2: CGPoint(x: rect.minX, y: rect.maxY))
        }
        
        // Left edge
        line(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
        if topLeft > 0 {
            curve(to: CGPoint(x: rect.minX + topLeft, y: rect.minY),
                  controlPoint1: CGPoint(x: rect.minX, y: rect.minY),
                  controlPoint2: CGPoint(x: rect.minX, y: rect.minY))
        }
        
        close()
    }
    
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        
        for i in 0 ..< elementCount {
            let type = element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            @unknown default:
                break
            }
        }
        
        return path
    }
}

// MARK: - UIRectCorner for macOS

struct UIRectCorner: OptionSet {
    let rawValue: Int
    
    static let topLeft = UIRectCorner(rawValue: 1 << 0)
    static let topRight = UIRectCorner(rawValue: 1 << 1)
    static let bottomLeft = UIRectCorner(rawValue: 1 << 2)
    static let bottomRight = UIRectCorner(rawValue: 1 << 3)
    static let allCorners: UIRectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

// MARK: - Avatar View

struct AvatarView: View {
    let isUser: Bool
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // Avatar circle
            Circle()
                .fill(AppTheme.Colors.background)
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .strokeBorder(AppTheme.Colors.border, lineWidth: 1)
                )
            
            // Icon
            Image(systemName: isUser ? "person" : "sparkles")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.Colors.textSecondary)
        }
    }
}

// MARK: - Loading Bubble

struct LoadingBubble: View {
    @State private var animating = false
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(AppTheme.Colors.textTertiary)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .opacity(animating ? 1.0 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.5)
                        .repeatForever()
                        .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .onAppear {
            animating = true
        }
    }
}

// MARK: - Preview

#Preview("User Message") {
    MessageBubbleView(
        message: ChatMessage(
            role: .user,
            content: "Create a bouncing blue circle"
        )
    )
    .padding()
    .background(AppTheme.Colors.surface)
}

#Preview("Assistant Message") {
    MessageBubbleView(
        message: ChatMessage(
            role: .assistant,
            content: "I've created a blue circle with a bounce animation. The circle will bounce up and down continuously."
        )
    )
    .padding()
    .background(AppTheme.Colors.surface)
}

#Preview("Loading") {
    MessageBubbleView(
        message: ChatMessage.loadingMessage()
    )
    .padding()
    .background(AppTheme.Colors.surface)
}
