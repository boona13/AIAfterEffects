//
//  SessionListView.swift
//  AIAfterEffects
//
//  Dropdown session picker for switching between chat sessions within a project.
//  Shows a list of past conversations with titles and timestamps.
//

import SwiftUI

// MARK: - Session Picker Button (in chat header)

struct SessionPickerButton: View {
    @EnvironmentObject var projectManager: ProjectManager
    @Binding var isExpanded: Bool
    
    var body: some View {
        Button(action: {
            withAnimation(AppTheme.Animation.quick) {
                isExpanded.toggle()
            }
        }) {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 11))
                
                if let session = projectManager.currentChatSession {
                    Text(session.title ?? "New Chat")
                        .font(AppTheme.Typography.captionMedium)
                        .lineLimit(1)
                } else {
                    Text("Sessions")
                        .font(AppTheme.Typography.captionMedium)
                }
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .foregroundColor(AppTheme.Colors.textSecondary)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .fill(AppTheme.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .strokeBorder(AppTheme.Colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Session List Panel

struct SessionListPanel: View {
    @EnvironmentObject var projectManager: ProjectManager
    var onSessionSelected: (UUID) -> Void
    var onNewSession: () -> Void
    var onDeleteSession: (UUID) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Chat Sessions")
                    .font(AppTheme.Typography.captionMedium)
                    .foregroundColor(AppTheme.Colors.textTertiary)
                
                Spacer()
                
                Button(action: onNewSession) {
                    HStack(spacing: AppTheme.Spacing.xxs) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("New")
                            .font(AppTheme.Typography.micro)
                    }
                    .foregroundColor(AppTheme.Colors.primary)
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, AppTheme.Spacing.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                            .fill(AppTheme.Colors.primary.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            
            Divider()
                .background(AppTheme.Colors.border)
            
            // Session list
            if projectManager.chatSessionList.isEmpty {
                Text("No sessions yet")
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.textTertiary)
                    .padding(AppTheme.Spacing.lg)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: AppTheme.Spacing.xxs) {
                        ForEach(projectManager.chatSessionList) { summary in
                            SessionRow(
                                summary: summary,
                                isActive: summary.id == projectManager.currentChatSession?.id,
                                onSelect: { onSessionSelected(summary.id) },
                                onDelete: { onDeleteSession(summary.id) }
                            )
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.sm)
                    .padding(.vertical, AppTheme.Spacing.xs)
                }
                .frame(maxHeight: 250)
            }
        }
        .background(AppTheme.Colors.surface)
        .cornerRadius(AppTheme.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                .strokeBorder(AppTheme.Colors.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, y: 4)
    }
}

// MARK: - Session Row

struct SessionRow: View {
    let summary: ChatSessionSummary
    let isActive: Bool
    var onSelect: () -> Void
    var onDelete: () -> Void
    @State private var isHovering = false
    @State private var showDeleteConfirm = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: AppTheme.Spacing.sm) {
                // Active indicator
                Circle()
                    .fill(isActive ? AppTheme.Colors.primary : Color.clear)
                    .frame(width: 6, height: 6)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.title ?? "New Chat")
                        .font(isActive ? AppTheme.Typography.captionMedium : AppTheme.Typography.caption)
                        .foregroundColor(isActive ? AppTheme.Colors.textPrimary : AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                    
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Text("\(summary.messageCount) messages")
                            .font(AppTheme.Typography.micro)
                            .foregroundColor(AppTheme.Colors.textTertiary)
                        
                        Text("·")
                            .foregroundColor(AppTheme.Colors.textTertiary)
                        
                        Text(formatRelativeDate(summary.updatedAt))
                            .font(AppTheme.Typography.micro)
                            .foregroundColor(AppTheme.Colors.textTertiary)
                    }
                }
                
                Spacer()
                
                // Delete button (on hover)
                if isHovering {
                    Button(action: { showDeleteConfirm = true }) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.Colors.error.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .fill(isActive ? AppTheme.Colors.primary.opacity(0.06) : (isHovering ? AppTheme.Colors.background : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(AppTheme.Animation.quick) {
                isHovering = hovering
            }
        }
        .alert("Delete Session?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete this chat session.")
        }
    }
    
    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
