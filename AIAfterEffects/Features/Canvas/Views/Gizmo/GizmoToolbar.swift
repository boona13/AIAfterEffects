//
//  GizmoToolbar.swift
//  AIAfterEffects
//
//  Compact toolbar for switching between gizmo modes (Move/Rotate/Scale).
//  Displayed in the canvas top bar.
//

import SwiftUI

struct GizmoToolbar: View {
    @ObservedObject var gizmoVM: GizmoViewModel
    @ObservedObject var canvasVM: CanvasViewModel
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(GizmoMode.allCases, id: \.self) { mode in
                GizmoModeButton(
                    mode: mode,
                    isActive: gizmoVM.activeMode == mode,
                    action: { gizmoVM.setMode(mode) }
                )
            }
            
            // 3D edit mode button (only for 3D objects)
            if gizmoVM.isSelected3DModel {
                Rectangle()
                    .fill(AppTheme.Colors.border)
                    .frame(width: 1, height: 18)
                    .padding(.horizontal, 2)
                
                GizmoToolbarButton(
                    icon: "cube",
                    tooltip: gizmoVM.is3DEditMode ? "Exit 3D Mode" : "Enter 3D Mode",
                    isActive: gizmoVM.is3DEditMode,
                    action: {
                        if gizmoVM.is3DEditMode {
                            gizmoVM.exit3DEditMode()
                        } else {
                            gizmoVM.enter3DEditMode()
                        }
                    }
                )
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                .fill(AppTheme.Colors.backgroundSecondary)
        )
    }
}

// MARK: - Gizmo Mode Button

private struct GizmoModeButton: View {
    let mode: GizmoMode
    let isActive: Bool
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: mode.icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(
                    isActive ? AppTheme.Colors.textPrimary :
                    (isHovering ? AppTheme.Colors.textSecondary : AppTheme.Colors.textTertiary)
                )
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.xs)
                        .fill(isActive ? AppTheme.Colors.surface : Color.clear)
                )
                .shadow(color: isActive ? Color.black.opacity(0.06) : .clear, radius: 1, y: 1)
        }
        .buttonStyle(.plain)
        .help(mode.label)
        .onHover { hovering in
            withAnimation(AppTheme.Animation.quick) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Generic Gizmo Toolbar Button

private struct GizmoToolbarButton: View {
    let icon: String
    let tooltip: String
    let isActive: Bool
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(
                    isActive ? Color(hex: "007AFF") :
                    (isHovering ? AppTheme.Colors.textSecondary : AppTheme.Colors.textTertiary)
                )
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.xs)
                        .fill(isActive ? Color(hex: "007AFF").opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { hovering in
            withAnimation(AppTheme.Animation.quick) {
                isHovering = hovering
            }
        }
    }
}
