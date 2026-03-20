//
//  Project.swift
//  AIAfterEffects
//
//  Project model — the master manifest for a multi-scene motion project.
//  Stored as project.json at the root of each project folder.
//  All scene data (objects, animations) is embedded inline — no separate scene files.
//

import Foundation

// MARK: - Project

struct Project: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var canvas: CanvasConfig
    var scenes: [SceneFile]               // Full scene data, inline
    var transitions: [SceneTransition]    // Transitions between scenes
    var globals: ProjectGlobals           // Shared style variables
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        name: String = "Untitled Project",
        canvas: CanvasConfig = CanvasConfig(),
        scenes: [SceneFile] = [],
        transitions: [SceneTransition] = [],
        globals: ProjectGlobals = ProjectGlobals(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.canvas = canvas
        self.scenes = scenes
        self.transitions = transitions
        self.globals = globals
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    /// Creates a default new project with one empty scene
    static func newProject(name: String = "Untitled Project") -> Project {
        let sceneId = UUID().uuidString
        let scene = SceneFile(
            id: sceneId,
            name: "Scene 1",
            order: 0,
            duration: 12.0
        )
        return Project(
            name: name,
            scenes: [scene]
        )
    }
    
    /// Total duration of all scenes (excluding transitions)
    var totalDuration: Double {
        scenes.reduce(0) { $0 + $1.duration }
    }
    
    /// Number of scenes
    var sceneCount: Int {
        scenes.count
    }
    
    /// Get scene by ID
    func scene(withId id: String) -> SceneFile? {
        scenes.first { $0.id == id }
    }
    
    /// Get scene index by ID
    func sceneIndex(withId id: String) -> Int? {
        orderedScenes.firstIndex { $0.id == id }
    }
    
    /// Sorted scenes by order
    var orderedScenes: [SceneFile] {
        scenes.sorted { $0.order < $1.order }
    }
    
    /// Get transition between two scenes
    func transition(from fromId: String, to toId: String) -> SceneTransition? {
        transitions.first { $0.fromSceneId == fromId && $0.toSceneId == toId }
    }
    
    /// Mark as updated
    mutating func touch() {
        updatedAt = Date()
    }
}

// MARK: - Canvas Config

/// Shared canvas configuration across all scenes in a project
struct CanvasConfig: Codable, Equatable {
    var width: Double
    var height: Double
    var fps: Int
    
    init(
        width: Double = 1920,
        height: Double = 1080,
        fps: Int = 60
    ) {
        self.width = width
        self.height = height
        self.fps = fps
    }
}

// MARK: - Scene Transition

/// Transition between two scenes
struct SceneTransition: Codable, Identifiable, Equatable {
    let id: UUID
    var fromSceneId: String
    var toSceneId: String
    var type: TransitionType
    var duration: Double
    
    init(
        id: UUID = UUID(),
        fromSceneId: String,
        toSceneId: String,
        type: TransitionType = .crossfade,
        duration: Double = 0.8
    ) {
        self.id = id
        self.fromSceneId = fromSceneId
        self.toSceneId = toSceneId
        self.type = type
        self.duration = duration
    }
}

// MARK: - Transition Type

enum TransitionType: String, Codable, Equatable, CaseIterable {
    case crossfade
    case slideLeft
    case slideRight
    case slideUp
    case slideDown
    case wipe
    case zoom
    case dissolve
    case none
}

// MARK: - Project Globals

/// Shared style variables accessible across all scenes
struct ProjectGlobals: Codable, Equatable {
    var primaryColor: CodableColor?
    var secondaryColor: CodableColor?
    var fontFamily: String?
    var accentColor: CodableColor?
    
    init(
        primaryColor: CodableColor? = nil,
        secondaryColor: CodableColor? = nil,
        fontFamily: String? = nil,
        accentColor: CodableColor? = nil
    ) {
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.fontFamily = fontFamily
        self.accentColor = accentColor
    }
}

// MARK: - Project Summary (for listing)

struct ProjectSummary: Identifiable, Codable {
    let id: UUID
    let name: String
    let sceneCount: Int
    let createdAt: Date
    let updatedAt: Date
    let canvasSize: String   // e.g. "1920x1080"
    let projectURL: URL
    
    init(from project: Project, url: URL) {
        self.id = project.id
        self.name = project.name
        self.sceneCount = project.sceneCount
        self.createdAt = project.createdAt
        self.updatedAt = project.updatedAt
        self.canvasSize = "\(Int(project.canvas.width))x\(Int(project.canvas.height))"
        self.projectURL = url
    }
}

// MARK: - Legacy Support

/// Lightweight scene reference from the OLD project.json format (pre-v2).
/// Used ONLY for migration: decoding old project.json files that reference separate scene files.
struct LegacySceneReference: Codable {
    let id: String
    var fileName: String
    var name: String
    var duration: Double
    var order: Int
}

/// Old project format with separate scene file references.
/// Used ONLY for migration in ProjectFileService.
struct LegacyProject: Codable {
    let id: UUID
    var name: String
    var canvas: CanvasConfig
    var scenes: [LegacySceneReference]
    var transitions: [SceneTransition]
    var globals: ProjectGlobals
    var createdAt: Date
    var updatedAt: Date
}
