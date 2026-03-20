//
//  CheckpointBadgeView.swift
//  AIAfterEffects
//
//  Checkpoint indicator displayed on chat messages where the AI modified project files.
//  Similar to Cursor's checkpoint system — users can click to revert to that point.
//

import SwiftUI

// MARK: - Checkpoint Badge

struct CheckpointBadgeView: View {
    let checkpointId: String
    var onRevert: () -> Void
    
    @State private var isHovering = false
    @State private var showConfirm = false
    @State private var showDetails = false
    
    var body: some View {
        Button(action: {
            if isHovering {
                showConfirm = true
            } else {
                withAnimation(AppTheme.Animation.quick) {
                    showDetails.toggle()
                }
            }
        }) {
            HStack(spacing: AppTheme.Spacing.xs) {
                // Checkpoint icon
                Image(systemName: "arrow.counterclockwise.circle")
                    .font(.system(size: 10, weight: .semibold))
                
                Text(checkpointId)
                    .font(AppTheme.Typography.mono)
                
                if isHovering {
                    Text("Revert")
                        .font(AppTheme.Typography.micro)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .foregroundColor(isHovering ? AppTheme.Colors.warning : AppTheme.Colors.success)
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.xxxs)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .fill(
                        isHovering
                            ? AppTheme.Colors.warning.opacity(0.12)
                            : AppTheme.Colors.success.opacity(0.08)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .strokeBorder(
                        isHovering
                            ? AppTheme.Colors.warning.opacity(0.3)
                            : AppTheme.Colors.success.opacity(0.2),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(AppTheme.Animation.quick) {
                isHovering = hovering
            }
        }
        .alert("Revert to Checkpoint?", isPresented: $showConfirm) {
            Button("Revert", role: .destructive) { onRevert() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will restore all project files to the state at checkpoint \(checkpointId). Your current changes will be saved as a separate checkpoint before reverting.")
        }
    }
}

// MARK: - Checkpoint Divider (shown between messages at checkpoint boundary)

struct CheckpointDividerView: View {
    let checkpointId: String
    let message: String
    var onRevert: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            // Left line
            Rectangle()
                .fill(AppTheme.Colors.success.opacity(0.2))
                .frame(height: 1)
            
            // Checkpoint pill
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.Colors.success)
                
                Text("Checkpoint")
                    .font(AppTheme.Typography.micro)
                    .foregroundColor(AppTheme.Colors.success)
                
                Text(checkpointId)
                    .font(AppTheme.Typography.mono)
                    .foregroundColor(AppTheme.Colors.success.opacity(0.7))
                
                if isHovering {
                    Button(action: onRevert) {
                        Text("Revert")
                            .font(AppTheme.Typography.micro)
                            .foregroundColor(AppTheme.Colors.warning)
                            .padding(.horizontal, AppTheme.Spacing.xs)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.xs)
                                    .fill(AppTheme.Colors.warning.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .fixedSize()
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.xxxs)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.full)
                    .fill(AppTheme.Colors.success.opacity(0.06))
            )
            .onHover { hovering in
                withAnimation(AppTheme.Animation.quick) {
                    isHovering = hovering
                }
            }
            
            // Right line
            Rectangle()
                .fill(AppTheme.Colors.success.opacity(0.2))
                .frame(height: 1)
        }
        .padding(.vertical, AppTheme.Spacing.xs)
    }
}

// MARK: - Preview

#Preview("Checkpoint Badge") {
    VStack(spacing: 20) {
        CheckpointBadgeView(checkpointId: "a3f8c21", onRevert: {})
        CheckpointDividerView(checkpointId: "a3f8c21", message: "Updated title text", onRevert: {})
    }
    .padding()
    .background(AppTheme.Colors.surface)
}
