//
//  ProjectFileService.swift
//  AIAfterEffects
//
//  Reads and writes project files to the filesystem.
//  Each project is a single folder containing project.json (with all scene data inline)
//  and an assets/ folder for images and 3D models.
//
//  Filesystem layout (v2 — single-file):
//    ~/Documents/AIAfterEffects/
//    └── ProjectName/
//        ├── project.json       (everything: canvas, scenes+objects, transitions)
//        └── assets/
//            ├── images/
//            └── models/
//

import Foundation

// MARK: - Protocol

protocol ProjectFileServiceProtocol {
    func createProject(name: String, canvas: CanvasConfig) throws -> (Project, URL)
    func createProject(name: String, canvas: CanvasConfig, at parentURL: URL) throws -> (Project, URL)
    func loadProject(at url: URL) throws -> Project
    func saveProject(_ project: Project, at url: URL) throws
    func listProjects() throws -> [ProjectSummary]
    func deleteProject(at url: URL) throws
    func projectsBaseURL() -> URL
}

// MARK: - Implementation

class ProjectFileService: ProjectFileServiceProtocol {
    
    static let shared = ProjectFileService()
    
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - Base Directory
    
    func projectsBaseURL() -> URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsURL.appendingPathComponent("AIAfterEffects", isDirectory: true)
    }
    
    private func ensureBaseDirectory() throws {
        let baseURL = projectsBaseURL()
        if !fileManager.fileExists(atPath: baseURL.path) {
            try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Project CRUD
    
    /// Create project in the default location (~/Documents/AIAfterEffects/)
    func createProject(name: String, canvas: CanvasConfig = CanvasConfig()) throws -> (Project, URL) {
        try ensureBaseDirectory()
        let parentURL = projectsBaseURL()
        return try createProject(name: name, canvas: canvas, at: parentURL)
    }
    
    /// Create project at a user-chosen parent directory
    func createProject(name: String, canvas: CanvasConfig = CanvasConfig(), at parentURL: URL) throws -> (Project, URL) {
        var project = Project.newProject(name: name)
        project.canvas = canvas
        
        // Create project folder inside the parent
        let sanitizedName = sanitizeFileName(name)
        var projectURL = parentURL.appendingPathComponent(sanitizedName, isDirectory: true)
        
        // Handle name collisions
        var counter = 1
        while fileManager.fileExists(atPath: projectURL.path) {
            projectURL = parentURL.appendingPathComponent("\(sanitizedName)_\(counter)", isDirectory: true)
            counter += 1
        }
        
        // Create directory structure (no scenes/ folder — scenes are in project.json)
        try fileManager.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: projectURL.appendingPathComponent("assets/images", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: projectURL.appendingPathComponent("assets/models", isDirectory: true), withIntermediateDirectories: true)
        
        // Save project.json (includes the default scene inline)
        try saveProject(project, at: projectURL)
        
        return (project, projectURL)
    }
    
    func loadProject(at url: URL) throws -> Project {
        let projectFileURL = url.appendingPathComponent("project.json")
        guard fileManager.fileExists(atPath: projectFileURL.path) else {
            throw ProjectFileError.projectNotFound(url.lastPathComponent)
        }
        let data = try Data(contentsOf: projectFileURL)
        let hasLegacyScenesDir = fileManager.fileExists(atPath: url.appendingPathComponent("scenes").path)
        
        // Try decoding as new format (scenes embedded inline with objects)
        do {
            let project = try decoder.decode(Project.self, from: data)
            // If any scene has objects, this is definitely new format — return it.
            // The scenes/ directory may still exist as a leftover from legacy migration,
            // but that doesn't mean the data is legacy format.
            let scenesHaveObjects = project.scenes.contains { !$0.objects.isEmpty }
            
            if scenesHaveObjects || !hasLegacyScenesDir {
                return project
            }
            // Decoded OK but scenes are empty AND legacy dir exists → try migration below
        } catch {
            // Decode failed. Only attempt legacy migration if scenes/ directory exists.
            // Otherwise, this is a new-format file with a decode error — surface it.
            if !hasLegacyScenesDir {
                print("[ProjectFileService] Failed to decode project.json (new format): \(error.localizedDescription)")
                throw error
            }
            // Fall through to legacy migration
        }
        
        // Old format detected (decoded scenes are empty AND scenes/ directory exists) — migrate
        return try migrateFromLegacy(data: data, projectURL: url)
    }
    
    func saveProject(_ project: Project, at url: URL) throws {
        let projectFileURL = url.appendingPathComponent("project.json")
        let data = try encoder.encode(project)
        try data.write(to: projectFileURL, options: .atomic)
    }
    
    // MARK: - Migration from Legacy (v1 → v2)
    
    /// Migrate a project from old multi-file format to new single-file format.
    private func migrateFromLegacy(data: Data, projectURL: URL) throws -> Project {
        print("[ProjectFileService] Migrating legacy project at \(projectURL.lastPathComponent)...")
        
        // Decode as legacy format
        let legacy = try decoder.decode(LegacyProject.self, from: data)
        
        // Build new scenes by loading each scene file and embedding it
        var scenes: [SceneFile] = []
        for ref in legacy.scenes.sorted(by: { $0.order < $1.order }) {
            let sceneURL = projectURL.appendingPathComponent("scenes").appendingPathComponent(ref.fileName)
            if fileManager.fileExists(atPath: sceneURL.path),
               let sceneData = try? Data(contentsOf: sceneURL),
               var scene = try? decoder.decode(SceneFile.self, from: sceneData) {
                scene.order = ref.order
                scenes.append(scene)
            } else {
                // Scene file missing or corrupt — create empty placeholder
                scenes.append(SceneFile(id: ref.id, name: ref.name, order: ref.order, duration: ref.duration))
            }
        }
        
        // Build the new project
        let project = Project(
            id: legacy.id,
            name: legacy.name,
            canvas: legacy.canvas,
            scenes: scenes,
            transitions: legacy.transitions,
            globals: legacy.globals,
            createdAt: legacy.createdAt,
            updatedAt: legacy.updatedAt
        )
        
        // Save the new format
        try saveProject(project, at: projectURL)
        
        // Clean up old scenes/ directory
        let scenesDir = projectURL.appendingPathComponent("scenes")
        if fileManager.fileExists(atPath: scenesDir.path) {
            try? fileManager.removeItem(at: scenesDir)
            print("[ProjectFileService] Removed legacy scenes/ directory")
        }
        
        print("[ProjectFileService] Migration complete — \(scenes.count) scenes embedded in project.json")
        return project
    }
    
    // MARK: - Project Listing
    
    func listProjects() throws -> [ProjectSummary] {
        try ensureBaseDirectory()
        let baseURL = projectsBaseURL()
        
        let contents = try fileManager.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        
        var summaries: [ProjectSummary] = []
        
        for folderURL in contents {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            
            // Check if it has a project.json
            let projectFile = folderURL.appendingPathComponent("project.json")
            guard fileManager.fileExists(atPath: projectFile.path) else { continue }
            
            do {
                let project = try loadProject(at: folderURL)
                summaries.append(ProjectSummary(from: project, url: folderURL))
            } catch {
                // Skip corrupted projects
                continue
            }
        }
        
        return summaries.sorted { $0.updatedAt > $1.updatedAt }
    }
    
    func deleteProject(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw ProjectFileError.projectNotFound(url.lastPathComponent)
        }
        try fileManager.removeItem(at: url)
    }
    
    // MARK: - Helpers
    
    private func sanitizeFileName(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let sanitized = name.components(separatedBy: invalidChars).joined(separator: "_")
        return sanitized.isEmpty ? "Untitled" : sanitized
    }
}

// MARK: - Errors

enum ProjectFileError: LocalizedError {
    case projectNotFound(String)
    case sceneNotFound(String)
    case cannotDeleteLastScene
    case invalidProjectStructure
    
    var errorDescription: String? {
        switch self {
        case .projectNotFound(let name):
            return "Project '\(name)' not found"
        case .sceneNotFound(let name):
            return "Scene '\(name)' not found"
        case .cannotDeleteLastScene:
            return "Cannot delete the last scene in a project"
        case .invalidProjectStructure:
            return "Invalid project folder structure"
        }
    }
}
