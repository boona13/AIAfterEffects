//
//  ToolActivityView.swift
//  AIAfterEffects
//
//  Shows the AI's tool usage activity in the chat — which files it's reading,
//  writing, or searching. Collapsible with a summary header.
//

import SwiftUI

struct ToolActivityView: View {
    let activities: [ToolActivity]
    
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — tap to toggle
            Button(action: { withAnimation(AppTheme.Animation.quick) { isExpanded.toggle() } }) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    // Animated spinner
                    if activities.contains(where: { $0.status == .running }) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "22C55E"))
                    }
                    
                    Text(headerText)
                        .font(AppTheme.Typography.captionMedium)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(AppTheme.Colors.textTertiary)
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)
            }
            .buttonStyle(.plain)
            
            // Expanded detail
            if isExpanded {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                    ForEach(activities) { activity in
                        ToolActivityRow(activity: activity)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.bottom, AppTheme.Spacing.sm)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .fill(AppTheme.Colors.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .strokeBorder(AppTheme.Colors.border, lineWidth: 1)
        )
    }
    
    private var headerText: String {
        let count = activities.count
        let completed = activities.filter { $0.status == .success }.count
        let running = activities.filter { $0.status == .running }.count
        
        if running > 0 {
            return "Working... (\(completed)/\(count) tools done)"
        } else {
            return "Used \(count) tool\(count == 1 ? "" : "s")"
        }
    }
}

// MARK: - Single Activity Row

private struct ToolActivityRow: View {
    let activity: ToolActivity
    
    @State private var showOutput = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: AppTheme.Spacing.xs) {
                // Status icon
                statusIcon
                    .frame(width: 14)
                
                // Tool icon
                Image(systemName: activity.iconName)
                    .font(.system(size: 10))
                    .foregroundColor(toolColor)
                    .frame(width: 14)
                
                // Summary
                Text(activity.summary)
                    .font(AppTheme.Typography.mono)
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .lineLimit(1)
                
                Spacer()
                
                // Toggle output
                if let result = activity.result, !result.output.isEmpty {
                    Button(action: { withAnimation(AppTheme.Animation.quick) { showOutput.toggle() } }) {
                        Image(systemName: showOutput ? "eye.slash" : "eye")
                            .font(.system(size: 9))
                            .foregroundColor(AppTheme.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Collapsible output
            if showOutput, let result = activity.result, !result.output.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(truncateOutput(result.output))
                        .font(AppTheme.Typography.mono)
                        .foregroundColor(AppTheme.Colors.textTertiary)
                        .lineLimit(8)
                }
                .padding(.leading, 32)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, AppTheme.Spacing.xxxs)
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch activity.status {
        case .running:
            ProgressView()
                .scaleEffect(0.5)
        case .success:
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Color(hex: "22C55E"))
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Color(hex: "EF4444"))
        }
    }
    
    private var toolColor: Color {
        switch activity.tool {
        case .readFile:      return Color(hex: "3B82F6")
        case .writeFile:     return Color(hex: "F59E0B")
        case .listFiles:     return Color(hex: "E8AB6A")
        case .grep:          return Color(hex: "8B5CF6")
        case .searchReplace: return Color(hex: "EC4899")
        case .projectInfo:   return Color(hex: "06B6D4")
        case .updateObject:  return Color(hex: "10B981")
        case .queryObjects:  return Color(hex: "6366F1")
        case .shiftTimeline:   return Color(hex: "F97316")
        case .getReferenceDocs: return Color(hex: "A78BFA")
        }
    }
    
    private func truncateOutput(_ output: String) -> String {
        if output.count > 500 {
            return String(output.prefix(500)) + "..."
        }
        return output
    }
}
