//
//  WelcomeView.swift
//  AIAfterEffects
//
//  Compact, elegant welcome screen — centered single-column layout.
//

import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var projectManager: ProjectManager
    @State private var showNewProjectSheet = false
    @State private var hoveredProjectId: UUID?
    
    /// Only show the 4 most recent projects
    private var recentProjects: [ProjectSummary] {
        Array(projectManager.projectList.prefix(4))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // ── Main content card ──
            VStack(spacing: AppTheme.Spacing.xxl) {
                // Logo + title
                VStack(spacing: AppTheme.Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.xl)
                            .fill(AppTheme.Colors.primary)
                            .frame(width: 56, height: 56)
                        
                        Image(systemName: "sparkles")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white)
                    }
                    
                    VStack(spacing: AppTheme.Spacing.xxs) {
                        Text("AI After Effects")
                            .font(AppTheme.Typography.title1)
                            .foregroundColor(AppTheme.Colors.textPrimary)
                        
                        Text("Cursor for Motion")
                            .font(AppTheme.Typography.caption)
                            .foregroundColor(AppTheme.Colors.textTertiary)
                    }
                }
                
                // ── Action buttons (horizontal) ──
                HStack(spacing: AppTheme.Spacing.sm) {
                    WelcomeActionButton(
                        icon: "plus",
                        title: "New Project"
                    ) {
                        showNewProjectSheet = true
                    }
                    
                    WelcomeActionButton(
                        icon: "folder",
                        title: "Open..."
                    ) {
                        openProjectFromDisk()
                    }
                    
                    if !projectManager.projectList.isEmpty {
                        WelcomeActionButton(
                            icon: "square.grid.2x2",
                            title: "All Projects"
                        ) {
                            projectManager.showProjectBrowser = true
                        }
                    }
                }
                
                // ── Recent projects (max 4) ──
                if !recentProjects.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text("Recent")
                            .font(AppTheme.Typography.captionMedium)
                            .foregroundColor(AppTheme.Colors.textTertiary)
                            .padding(.leading, AppTheme.Spacing.xxs)
                        
                        VStack(spacing: AppTheme.Spacing.xxs) {
                            ForEach(recentProjects, id: \.id) { project in
                                recentProjectRow(project)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(AppTheme.Spacing.xxxl)
            .frame(width: 420)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.xxl)
                    .fill(AppTheme.Colors.surface)
                    .shadow(color: Color.black.opacity(0.06), radius: 24, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.xxl)
                    .strokeBorder(AppTheme.Colors.border.opacity(0.5), lineWidth: 1)
            )
            
            Spacer()
            
            // Version
            Text("v1.0")
                .font(AppTheme.Typography.micro)
                .foregroundColor(AppTheme.Colors.textTertiary)
                .padding(.bottom, AppTheme.Spacing.lg)
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(AppTheme.Colors.background)
        .sheet(isPresented: $showNewProjectSheet) {
            NewProjectSheet()
        }
        .sheet(isPresented: $projectManager.showProjectBrowser) {
            ProjectBrowserView(mode: .sheet)
        }
    }
    
    // MARK: - Recent Project Row
    
    private func recentProjectRow(_ project: ProjectSummary) -> some View {
        Button(action: {
            projectManager.openProject(at: project.projectURL)
            projectManager.showWelcome = false
        }) {
            HStack(spacing: AppTheme.Spacing.md) {
                // Project icon
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .fill(AppTheme.Colors.backgroundSecondary)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "film")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppTheme.Colors.textTertiary)
                    )
                
                // Name + meta
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(AppTheme.Typography.bodyMedium)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                    
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Text(project.canvasSize)
                            .font(AppTheme.Typography.micro)
                            .foregroundColor(AppTheme.Colors.textTertiary)
                        
                        Text("·")
                            .foregroundColor(AppTheme.Colors.textTertiary)
                        
                        Text("\(project.sceneCount) scene\(project.sceneCount == 1 ? "" : "s")")
                            .font(AppTheme.Typography.micro)
                            .foregroundColor(AppTheme.Colors.textTertiary)
                    }
                }
                
                Spacer()
                
                // Time ago
                Text(timeAgo(project.updatedAt))
                    .font(AppTheme.Typography.micro)
                    .foregroundColor(AppTheme.Colors.textTertiary)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .fill(hoveredProjectId == project.id ? AppTheme.Colors.backgroundSecondary : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { h in
            hoveredProjectId = h ? project.id : nil
        }
    }
    
    // MARK: - Helpers
    
    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        let days = Int(interval / 86400)
        if days == 1 { return "1d ago" }
        if days < 30 { return "\(days)d ago" }
        return "\(days / 30)mo ago"
    }
    
    private func openProjectFromDisk() {
        let panel = NSOpenPanel()
        panel.title = "Open Project Folder"
        panel.message = "Select a folder containing a project.json file"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        
        guard panel.runModal() == .OK, let url = panel.url else { return }
        
        let projectFile = url.appendingPathComponent("project.json")
        if FileManager.default.fileExists(atPath: projectFile.path) {
            projectManager.openProject(at: url)
            projectManager.showWelcome = false
        } else {
            let alert = NSAlert()
            alert.messageText = "Not a Valid Project"
            alert.informativeText = "The selected folder doesn't contain a project.json file."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

// MARK: - Welcome Action Button (compact pill)

private struct WelcomeActionButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                
                Text(title)
                    .font(AppTheme.Typography.captionMedium)
            }
            .foregroundColor(AppTheme.Colors.textPrimary)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.full)
                    .fill(isHovered ? AppTheme.Colors.backgroundSecondary : AppTheme.Colors.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.full)
                    .strokeBorder(AppTheme.Colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - New Project Sheet

struct NewProjectSheet: View {
    @EnvironmentObject var projectManager: ProjectManager
    @Environment(\.dismiss) private var dismiss
    
    /// Optional callback fired after the project is successfully created
    var onProjectCreated: (() -> Void)? = nil
    
    @State private var projectName = ""
    @State private var selectedPreset: CanvasPreset = .fullHD
    @State private var saveLocation: URL? = nil
    
    private var defaultLocation: URL {
        ProjectFileService.shared.projectsBaseURL()
    }
    
    private var displayLocation: String {
        let url = saveLocation ?? defaultLocation
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Project")
                    .font(AppTheme.Typography.title2)
                    .foregroundColor(AppTheme.Colors.textPrimary)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(AppTheme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(AppTheme.Spacing.xxl)
            
            ThemedDivider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
                    // Project name
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text("Project Name")
                            .font(AppTheme.Typography.headline)
                            .foregroundColor(AppTheme.Colors.textSecondary)
                        
                        TextField("My Awesome Video", text: $projectName)
                            .textFieldStyle(.plain)
                            .font(AppTheme.Typography.title3)
                            .foregroundColor(AppTheme.Colors.textPrimary)
                            .padding(AppTheme.Spacing.md)
                            .background(AppTheme.Colors.surface)
                            .cornerRadius(AppTheme.Radius.md)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                                    .stroke(AppTheme.Colors.border, lineWidth: 1)
                            )
                    }
                    
                    // Save location
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text("Save Location")
                            .font(AppTheme.Typography.headline)
                            .foregroundColor(AppTheme.Colors.textSecondary)
                        
                        HStack(spacing: AppTheme.Spacing.sm) {
                            Image(systemName: "folder")
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "D4956B"))
                            
                            Text(displayLocation)
                                .font(AppTheme.Typography.mono)
                                .foregroundColor(AppTheme.Colors.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            Spacer()
                            
                            Button("Choose...") { pickSaveLocation() }
                                .buttonStyle(.plain)
                                .font(AppTheme.Typography.captionMedium)
                                .foregroundColor(AppTheme.Colors.textSecondary)
                                .padding(.horizontal, AppTheme.Spacing.md)
                                .padding(.vertical, AppTheme.Spacing.xxs)
                                .background(AppTheme.Colors.backgroundSecondary)
                                .cornerRadius(AppTheme.Radius.sm)
                        }
                        .padding(AppTheme.Spacing.md)
                        .background(AppTheme.Colors.surface)
                        .cornerRadius(AppTheme.Radius.md)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                                .stroke(AppTheme.Colors.border, lineWidth: 1)
                        )
                    }
                    
                    // Canvas size
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text("Canvas Size")
                            .font(AppTheme.Typography.headline)
                            .foregroundColor(AppTheme.Colors.textSecondary)
                        
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 160, maximum: 200), spacing: AppTheme.Spacing.sm)
                        ], spacing: AppTheme.Spacing.sm) {
                            ForEach(CanvasPreset.allCases, id: \.self) { preset in
                                CanvasPresetCard(
                                    preset: preset,
                                    isSelected: selectedPreset == preset
                                ) {
                                    selectedPreset = preset
                                }
                            }
                        }
                    }
                }
                .padding(AppTheme.Spacing.xxl)
            }
            
            ThemedDivider()
            
            // Footer
            HStack {
                Spacer()
                
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(AppTheme.Colors.textSecondary)
                    .padding(.horizontal, AppTheme.Spacing.xl)
                    .padding(.vertical, AppTheme.Spacing.sm)
                
                Button(action: createProject) {
                    Text("Create Project")
                        .font(AppTheme.Typography.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, AppTheme.Spacing.xl)
                        .padding(.vertical, AppTheme.Spacing.sm)
                        .background(AppTheme.Colors.primary)
                        .cornerRadius(AppTheme.Radius.full)
                }
                .buttonStyle(.plain)
                .disabled(projectName.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(projectName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1.0)
            }
            .padding(AppTheme.Spacing.xxl)
        }
        .frame(width: 560, height: 620)
        .background(AppTheme.Colors.background)
    }
    
    private func pickSaveLocation() {
        let panel = NSOpenPanel()
        panel.title = "Choose Save Location"
        panel.message = "Select a folder where the project will be created"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        
        if panel.runModal() == .OK, let url = panel.url {
            saveLocation = url
        }
    }
    
    private func createProject() {
        let name = projectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        
        let canvas = CanvasConfig(
            width: Double(selectedPreset.width),
            height: Double(selectedPreset.height)
        )
        
        if let location = saveLocation {
            projectManager.createNewProject(name: name, canvas: canvas, at: location)
        } else {
            projectManager.createNewProject(name: name, canvas: canvas)
        }
        projectManager.showWelcome = false
        onProjectCreated?()
        dismiss()
    }
}

// MARK: - Canvas Presets

enum CanvasPreset: CaseIterable, Hashable {
    case fullHD, uhd4k, hd720, reelsPortrait, instagramSquare, instagramPost, facebookCover, presentation4x3
    
    var label: String {
        switch self {
        case .fullHD:          return "Full HD 16:9"
        case .uhd4k:           return "4K UHD"
        case .hd720:           return "HD 720p"
        case .reelsPortrait:   return "Reels / TikTok"
        case .instagramSquare: return "Square 1:1"
        case .instagramPost:   return "Instagram 4:5"
        case .facebookCover:   return "Facebook Cover"
        case .presentation4x3: return "Presentation 4:3"
        }
    }
    
    var dimensionLabel: String { "\(width) x \(height)" }
    
    var width: Int {
        switch self {
        case .fullHD: return 1920; case .uhd4k: return 3840; case .hd720: return 1280
        case .reelsPortrait: return 1080; case .instagramSquare: return 1080; case .instagramPost: return 1080
        case .facebookCover: return 1200; case .presentation4x3: return 1024
        }
    }
    
    var height: Int {
        switch self {
        case .fullHD: return 1080; case .uhd4k: return 2160; case .hd720: return 720
        case .reelsPortrait: return 1920; case .instagramSquare: return 1080; case .instagramPost: return 1350
        case .facebookCover: return 628; case .presentation4x3: return 768
        }
    }
    
    var icon: String {
        switch self {
        case .fullHD, .uhd4k, .hd720:               return "tv"
        case .reelsPortrait:                          return "iphone"
        case .instagramSquare, .instagramPost:        return "camera"
        case .facebookCover:                          return "rectangle.landscape.rotate"
        case .presentation4x3:                        return "rectangle.on.rectangle"
        }
    }
}

// MARK: - Canvas Preset Card

private struct CanvasPresetCard: View {
    let preset: CanvasPreset
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: preset.icon)
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? AppTheme.Colors.primary : AppTheme.Colors.textTertiary)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.label)
                        .font(AppTheme.Typography.captionMedium)
                        .foregroundColor(AppTheme.Colors.textPrimary)
                    Text(preset.dimensionLabel)
                        .font(AppTheme.Typography.micro)
                        .foregroundColor(AppTheme.Colors.textTertiary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.Colors.primary)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .fill(isSelected ? AppTheme.Colors.primary.opacity(0.06) : (isHovered ? AppTheme.Colors.surfaceHover : AppTheme.Colors.background))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .strokeBorder(isSelected ? AppTheme.Colors.primary.opacity(0.3) : AppTheme.Colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
