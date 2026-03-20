//
//  LayerPanelView.swift
//  AIAfterEffects
//
//  Layer panel listing all objects in the scene with visibility, lock, delete, and reorder controls.
//  Modeled after the After Effects layer panel.
//

import SwiftUI

// MARK: - Layer Panel View

struct LayerPanelView: View {
    @ObservedObject var viewModel: CanvasViewModel
    
    /// Objects sorted by zIndex descending (highest = top of list, like AE)
    private var sortedObjects: [SceneObject] {
        viewModel.sceneState.objects.sorted(by: { $0.zIndex > $1.zIndex })
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            layerPanelHeader
            
            ThemedDivider()
            
            // Layer list
            if sortedObjects.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sortedObjects) { object in
                            LayerRowView(
                                object: object,
                                isSelected: viewModel.selectedObjectId == object.id,
                                onSelect: {
                                    viewModel.selectObject(object.id)
                                },
                                onToggleVisibility: {
                                    viewModel.toggleObjectVisibility(object.id)
                                },
                                onToggleLock: {
                                    viewModel.toggleObjectLock(object.id)
                                },
                                onDelete: {
                                    viewModel.deleteObjectById(object.id)
                                },
                                onRename: { newName in
                                    viewModel.renameObject(object.id, to: newName)
                                }
                            )
                            
                            ThemedDivider(opacity: 0.5)
                        }
                    }
                }
            }
        }
        .background(AppTheme.Colors.surface)
    }
    
    // MARK: - Header
    
    private var layerPanelHeader: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.Colors.textTertiary)
            
            Text("Layers")
                .font(AppTheme.Typography.captionMedium)
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            Spacer()
            
            Text("\(sortedObjects.count)")
                .font(AppTheme.Typography.mono)
                .foregroundColor(AppTheme.Colors.textTertiary)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(AppTheme.Colors.surface)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Spacer()
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 24))
                .foregroundColor(AppTheme.Colors.textTertiary)
            Text("No objects")
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.Colors.textTertiary)
            Text("Use the chat to create objects")
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.Colors.textTertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

// MARK: - Layer Row View

struct LayerRowView: View {
    let object: SceneObject
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleVisibility: () -> Void
    let onToggleLock: () -> Void
    let onDelete: () -> Void
    let onRename: (String) -> Void
    
    @State private var isHovering = false
    @State private var isEditing = false
    @State private var editName = ""
    
    var body: some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            // Visibility toggle
            Button(action: onToggleVisibility) {
                Image(systemName: object.isVisible ? "eye.fill" : "eye.slash")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(object.isVisible ? AppTheme.Colors.textSecondary : AppTheme.Colors.textTertiary.opacity(0.5))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(object.isVisible ? "Hide" : "Show")
            
            // Lock toggle
            Button(action: onToggleLock) {
                Image(systemName: object.isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(object.isLocked ? AppTheme.Colors.warning : AppTheme.Colors.textTertiary.opacity(0.5))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(object.isLocked ? "Unlock" : "Lock")
            
            // Type icon
            Image(systemName: iconForType(object.type))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(colorForType(object.type))
                .frame(width: 16)
            
            // Name
            if isEditing {
                TextField("Name", text: $editName, onCommit: {
                    let trimmed = editName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        onRename(trimmed)
                    }
                    isEditing = false
                })
                .textFieldStyle(.plain)
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.Colors.textPrimary)
                .onExitCommand { isEditing = false }
            } else {
                Text(object.name)
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(isSelected ? AppTheme.Colors.textPrimary : AppTheme.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            
            Spacer()
            
            // Delete button (visible on hover)
            if isHovering && !object.isLocked {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(AppTheme.Colors.textTertiary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Delete")
            }
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xs)
                .fill(isSelected ? AppTheme.Colors.primary.opacity(0.08) :
                      (isHovering ? AppTheme.Colors.surfaceHover : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xs)
                .strokeBorder(isSelected ? AppTheme.Colors.primary.opacity(0.2) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onTapGesture(count: 2) {
            editName = object.name
            isEditing = true
        }
        .onHover { hovering in
            withAnimation(AppTheme.Animation.quick) { isHovering = hovering }
        }
        .contextMenu {
            Button("Rename") {
                editName = object.name
                isEditing = true
            }
            Divider()
            Button(object.isVisible ? "Hide" : "Show") { onToggleVisibility() }
            Button(object.isLocked ? "Unlock" : "Lock") { onToggleLock() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
                .disabled(object.isLocked)
        }
        .opacity(object.isVisible ? 1.0 : 0.5)
    }
    
    // MARK: - Helpers
    
    private func iconForType(_ type: SceneObjectType) -> String {
        switch type {
        case .rectangle: return "rectangle.fill"
        case .circle: return "circle.fill"
        case .ellipse: return "oval.fill"
        case .polygon: return "pentagon.fill"
        case .line: return "line.diagonal"
        case .text: return "textformat"
        case .icon: return "star.fill"
        case .image: return "photo"
        case .path: return "scribble.variable"
        case .model3D: return "cube.fill"
        case .shader: return "sparkles"
        case .particleSystem: return "sparkles"
        }
    }
    
    private func colorForType(_ type: SceneObjectType) -> Color {
        switch type {
        case .rectangle, .circle, .ellipse, .polygon: return Color.blue.opacity(0.7)
        case .line, .path: return Color.green.opacity(0.7)
        case .text: return Color.orange.opacity(0.7)
        case .icon: return Color.yellow.opacity(0.7)
        case .image: return Color.pink.opacity(0.7)
        case .model3D: return Color.purple.opacity(0.7)
        case .shader: return Color.cyan.opacity(0.7)
        case .particleSystem: return Color.pink.opacity(0.7)
        }
    }
}
