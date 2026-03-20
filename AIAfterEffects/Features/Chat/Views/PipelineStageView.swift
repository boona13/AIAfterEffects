//
//  PipelineStageView.swift
//  AIAfterEffects
//
//  Compact indicator showing which agent in the creative pipeline is currently active.
//

import SwiftUI

struct PipelineStageView: View {
    let stage: PipelineStage
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            ProgressView()
                .scaleEffect(0.55)
                .frame(width: 14, height: 14)
            
            Image(systemName: stage.iconName)
                .font(.system(size: 11))
                .foregroundColor(stageColor)
            
            Text(stage.activityLabel)
                .font(AppTheme.Typography.captionMedium)
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            Spacer()
            
            Text(stage.rawValue)
                .font(AppTheme.Typography.captionMedium)
                .foregroundColor(AppTheme.Colors.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(stageColor.opacity(0.12))
                )
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(AppTheme.Colors.backgroundSecondary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
        .padding(.horizontal, AppTheme.Spacing.md)
        .animation(.easeInOut(duration: 0.3), value: stage.rawValue)
    }
    
    private var stageColor: Color {
        switch stage {
        case .director: return Color(hex: "A855F7")
        case .designer: return Color(hex: "EC4899")
        case .choreographer: return Color(hex: "F59E0B")
        case .executor: return Color(hex: "3B82F6")
        case .validator: return Color(hex: "06B6D4")
        case .critic: return Color(hex: "22C55E")
        }
    }
}
