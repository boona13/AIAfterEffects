//
//  ProjectBrowserView.swift
//  AIAfterEffects
//
//  Reusable grid of project cards. Used both embedded in WelcomeView
//  and as a standalone sheet opened from the toolbar / menu.
//

import SwiftUI

// MARK: - Display Mode

enum ProjectBrowserMode {
    case embedded   // Inside WelcomeView — no chrome
    case sheet      // Standalone sheet — has title bar & close
}

// MARK: - Project Browser View

struct ProjectBrowserView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @Environment(\.dismiss) private var dismiss
    
    let mode: ProjectBrowserMode
    
    @State private var confirmingDelete: ProjectSummary?
    @State private var searchText = ""
    
    private var filteredProjects: [ProjectSummary] {
        let projects = projectManager.projectList
        if searchText.isEmpty { return projects }
        return projects.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Sheet header (only when standalone)
            if mode == .sheet {
                sheetHeader
                ThemedDivider()
            }
            
            // Content
            if filteredProjects.isEmpty {
                emptyState
            } else {
                projectList
            }
        }
        .frame(
            minWidth: mode == .sheet ? 500 : nil,
            minHeight: mode == .sheet ? 360 : nil
        )
        .background(AppTheme.Colors.background)
        .onAppear {
            projectManager.refreshProjectList()
        }
        .alert("Delete Project?", isPresented: .init(
            get: { confirmingDelete != nil },
            set: { if !$0 { confirmingDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
            Button("Delete", role: .destructive) {
                if let project = confirmingDelete {
                    projectManager.deleteProject(at: project.projectURL)
                }
                confirmingDelete = nil
            }
        } message: {
            if let project = confirmingDelete {
                Text("Are you sure you want to delete \"\(project.name)\"? This cannot be undone.")
            }
        }
    }
    
    // MARK: - Sheet Header
    
    private var sheetHeader: some View {
        HStack {
            Text("Projects")
                .font(AppTheme.Typography.title2)
                .foregroundColor(AppTheme.Colors.textPrimary)
            
            Spacer()
            
            // Search field
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppTheme.Colors.textTertiary)
                    .font(.system(size: 12))
                
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(AppTheme.Typography.body)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                    .frame(width: 140)
            }
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.xs)
            .background(AppTheme.Colors.surface)
            .cornerRadius(AppTheme.Radius.sm)
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(AppTheme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppTheme.Spacing.xxl)
        .padding(.vertical, AppTheme.Spacing.lg)
    }
    
    // MARK: - Project List (compact rows)
    
    private var projectList: some View {
        ScrollView {
            LazyVStack(spacing: AppTheme.Spacing.xxs) {
                ForEach(filteredProjects) { project in
                    ProjectRowView(
                        project: project,
                        isCurrentProject: project.id == projectManager.currentProject.id,
                        onOpen: {
                            projectManager.openProject(at: project.projectURL)
                            projectManager.showWelcome = false
                            if mode == .sheet { dismiss() }
                        },
                        onDelete: {
                            confirmingDelete = project
                        }
                    )
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.md)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 40))
                .foregroundColor(AppTheme.Colors.textTertiary)
            
            Text(searchText.isEmpty ? "No projects yet" : "No matching projects")
                .font(AppTheme.Typography.title3)
                .foregroundColor(AppTheme.Colors.textSecondary)
            
            if searchText.isEmpty {
                Text("Create a new project to get started.")
                    .font(AppTheme.Typography.body)
                    .foregroundColor(AppTheme.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppTheme.Spacing.huge)
    }
}

// MARK: - Project Row (compact)

struct ProjectRowView: View {
    let project: ProjectSummary
    let isCurrentProject: Bool
    let onOpen: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: AppTheme.Spacing.md) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                        .fill(isCurrentProject
                              ? AppTheme.Colors.primary.opacity(0.08)
                              : AppTheme.Colors.background)
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "film.stack")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isCurrentProject
                                         ? AppTheme.Colors.primary
                                         : AppTheme.Colors.textTertiary)
                }
                
                // Name + metadata
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(AppTheme.Typography.headline)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                    
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Text(project.canvasSize)
                            .font(AppTheme.Typography.micro)
                            .foregroundColor(AppTheme.Colors.textSecondary)
                        
                        Text("\(project.sceneCount) scene\(project.sceneCount == 1 ? "" : "s")")
                            .font(AppTheme.Typography.micro)
                            .foregroundColor(AppTheme.Colors.textTertiary)
                    }
                }
                
                Spacer()
                
                // Date
                Text(relativeDate(project.updatedAt))
                    .font(AppTheme.Typography.micro)
                    .foregroundColor(AppTheme.Colors.textTertiary)
                
                // Delete (on hover only)
                if isHovered {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.Colors.error.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .fill(isCurrentProject
                          ? AppTheme.Colors.primary.opacity(0.04)
                          : (isHovered ? AppTheme.Colors.surfaceHover : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .strokeBorder(
                        isCurrentProject
                            ? AppTheme.Colors.primary.opacity(0.2)
                            : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(AppTheme.Animation.quick) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button("Open") { onOpen() }
            Divider()
            Button("Show in Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.projectURL.path)
            }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }
    
    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
