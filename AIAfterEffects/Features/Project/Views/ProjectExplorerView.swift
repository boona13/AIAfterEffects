//
//  ProjectExplorerView.swift
//  AIAfterEffects
//
//  Tree-style file explorer sidebar showing project structure:
//  scenes, assets, and the project manifest.
//

import SwiftUI

struct ProjectExplorerView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @ObservedObject var canvasViewModel: CanvasViewModel
    
    @State private var scenesExpanded = true
    @State private var assetsExpanded = true
    @State private var renamingSceneId: String?
    @State private var renameText = ""
    @State private var confirmingDeleteId: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            explorerHeader
            
            ThemedDivider()
            
            // File tree
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // project.json
                    fileRow(
                        icon: "doc.text.fill",
                        name: "project.json",
                        iconColor: AppTheme.Colors.textSecondary,
                        indent: 0
                    )
                    
                    // Scenes folder
                    folderSection(
                        title: "scenes",
                        expanded: $scenesExpanded,
                        indent: 0
                    ) {
                        ForEach(Array(projectManager.currentProject.orderedScenes.enumerated()), id: \.element.id) { index, sceneRef in
                            sceneRow(sceneRef: sceneRef, index: index)
                        }
                        
                        // Add scene button
                        addSceneRow
                    }
                    
                    // Assets folder
                    folderSection(
                        title: "assets",
                        expanded: $assetsExpanded,
                        indent: 0
                    ) {
                        folderLabel(name: "images", indent: 2)
                        folderLabel(name: "models", indent: 2)
                    }
                }
                .padding(.vertical, AppTheme.Spacing.xs)
            }
        }
        .background(AppTheme.Colors.surface)
        .alert("Delete Scene?", isPresented: .init(
            get: { confirmingDeleteId != nil },
            set: { if !$0 { confirmingDeleteId = nil } }
        )) {
            Button("Cancel", role: .cancel) { confirmingDeleteId = nil }
            Button("Delete", role: .destructive) {
                if let id = confirmingDeleteId {
                    projectManager.deleteScene(withId: id)
                }
                confirmingDeleteId = nil
            }
        } message: {
            Text("This scene will be permanently deleted.")
        }
    }
    
    // MARK: - Header
    
    private var explorerHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
            Text(projectManager.currentProject.name)
                .font(AppTheme.Typography.headline)
                .foregroundColor(AppTheme.Colors.textPrimary)
                .lineLimit(1)
            
            Text("Project")
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.md)
    }
    
    // MARK: - Scene Row
    
    private func sceneRow(sceneRef: SceneFile, index: Int) -> some View {
        let isActive = index == projectManager.currentSceneIndex
        
        return Group {
            if renamingSceneId == sceneRef.id {
                // Inline rename
                HStack(spacing: AppTheme.Spacing.xs) {
                    Spacer().frame(width: CGFloat(2) * AppTheme.Spacing.lg)
                    
                    Image(systemName: "doc.fill")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.Colors.primary)
                        .frame(width: 16)
                    
                    TextField("Scene name", text: $renameText, onCommit: {
                        commitRename(sceneRef.id)
                    })
                    .textFieldStyle(.plain)
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                    
                    Button(action: { renamingSceneId = nil }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                            .foregroundColor(AppTheme.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.xxs)
            } else {
                Button(action: {
                    projectManager.switchToScene(at: index)
                }) {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Spacer().frame(width: CGFloat(2) * AppTheme.Spacing.lg)
                        
                        Image(systemName: isActive ? "doc.fill" : "doc")
                            .font(.system(size: 11))
                            .foregroundColor(isActive ? AppTheme.Colors.primary : AppTheme.Colors.textTertiary)
                            .frame(width: 16)
                        
                        Text(sceneRef.name)
                            .font(AppTheme.Typography.mono)
                            .foregroundColor(isActive ? AppTheme.Colors.textPrimary : AppTheme.Colors.textSecondary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        if isActive {
                            Circle()
                                .fill(AppTheme.Colors.primary)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.xxs)
                    .background(isActive ? AppTheme.Colors.primary.opacity(0.06) : Color.clear)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Rename") {
                        renameText = sceneRef.name
                        renamingSceneId = sceneRef.id
                    }
                    Button("Duplicate") {
                        projectManager.duplicateScene(withId: sceneRef.id)
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        if projectManager.currentProject.sceneCount > 1 {
                            confirmingDeleteId = sceneRef.id
                        }
                    }
                    .disabled(projectManager.currentProject.sceneCount <= 1)
                }
            }
        }
    }
    
    // MARK: - Add Scene Row
    
    private var addSceneRow: some View {
        Button(action: {
            projectManager.addScene()
        }) {
            HStack(spacing: AppTheme.Spacing.xs) {
                Spacer().frame(width: CGFloat(2) * AppTheme.Spacing.lg)
                
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppTheme.Colors.textTertiary)
                    .frame(width: 16)
                
                Text("Add Scene")
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.textTertiary)
                
                Spacer()
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.xxs)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Folder Section
    
    private func folderSection<Content: View>(
        title: String,
        expanded: Binding<Bool>,
        indent: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(AppTheme.Animation.quick) { expanded.wrappedValue.toggle() } }) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    if indent > 0 {
                        Spacer().frame(width: CGFloat(indent) * AppTheme.Spacing.lg)
                    }
                    
                    Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(AppTheme.Colors.textTertiary)
                        .frame(width: 14)
                    
                    Image(systemName: expanded.wrappedValue ? "folder.fill" : "folder")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "D4956B"))
                        .frame(width: 18)
                    
                    Text(title)
                        .font(AppTheme.Typography.captionMedium)
                        .foregroundColor(AppTheme.Colors.textSecondary)
                    
                    Spacer()
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if expanded.wrappedValue {
                content()
            }
        }
    }
    
    // MARK: - Simple Rows
    
    private func fileRow(icon: String, name: String, iconColor: Color, indent: Int) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            if indent > 0 {
                Spacer().frame(width: CGFloat(indent) * AppTheme.Spacing.lg)
            }
            
            // Spacer for chevron alignment
            Spacer().frame(width: 14)
            
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(iconColor)
                .frame(width: 18)
            
            Text(name)
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.Colors.textSecondary)
                .lineLimit(1)
            
            Spacer()
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.xs)
    }
    
    private func folderLabel(name: String, indent: Int) -> some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Spacer().frame(width: CGFloat(indent) * AppTheme.Spacing.lg)
            
            Spacer().frame(width: 12)
            
            Image(systemName: "folder")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "E8AB6A").opacity(0.6))
                .frame(width: 16)
            
            Text(name)
                .font(AppTheme.Typography.mono)
                .foregroundColor(AppTheme.Colors.textTertiary)
                .lineLimit(1)
            
            Spacer()
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.xxs)
    }
    
    // MARK: - Actions
    
    private func commitRename(_ id: String) {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            projectManager.renameScene(withId: id, to: trimmed)
        }
        renamingSceneId = nil
    }
}
