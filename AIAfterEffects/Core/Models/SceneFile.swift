//
//  SceneFile.swift
//  AIAfterEffects
//
//  SceneFile — a single scene within a project, stored inline in project.json.
//  Contains objects, animations, and scene-specific settings.
//  Canvas dimensions live in the parent Project (shared across scenes).
//

import Foundation

// MARK: - Scene File

struct SceneFile: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var order: Int                         // Display order (0-based)
    var duration: Double                   // Scene duration in seconds
    var backgroundColor: CodableColor
    var objects: [SceneObject]
    
    // MARK: - Standard Init
    
    init(
        id: String = UUID().uuidString,
        name: String = "Scene 1",
        order: Int = 0,
        duration: Double = 12.0,
        backgroundColor: CodableColor = CodableColor(red: 0.96, green: 0.95, blue: 0.94),
        objects: [SceneObject] = []
    ) {
        self.id = id
        self.name = name
        self.order = order
        self.duration = duration
        self.backgroundColor = backgroundColor
        self.objects = objects
    }
    
    /// Create a SceneFile from an existing SceneState (migration helper)
    init(from sceneState: SceneState, id: String = UUID().uuidString, name: String = "Scene 1", order: Int = 0) {
        self.id = id
        self.name = name
        self.order = order
        self.duration = sceneState.duration
        self.backgroundColor = sceneState.backgroundColor
        self.objects = sceneState.objects
    }
    
    // MARK: - Codable (backward-compatible)
    
    // Decodes both old format (no order field) and new format (with order).
    // When decoding from old project.json SceneReference entries (which have fileName/no objects),
    // objects defaults to [] and backgroundColor gets a default value.
    
    enum CodingKeys: String, CodingKey {
        case id, name, order, duration, backgroundColor, objects
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        duration = try container.decodeIfPresent(Double.self, forKey: .duration) ?? 12.0
        var bg = try container.decodeIfPresent(CodableColor.self, forKey: .backgroundColor)
            ?? CodableColor(red: 0.96, green: 0.95, blue: 0.94)
        // Migrate old dark default (0.1, 0.1, 0.1) to new light default
        if bg.red < 0.15 && bg.green < 0.15 && bg.blue < 0.15 {
            bg = CodableColor(red: 0.96, green: 0.95, blue: 0.94)
        }
        backgroundColor = bg
        objects = try container.decodeIfPresent([SceneObject].self, forKey: .objects) ?? []
    }
    
    // MARK: - Conversion
    
    /// Convert to a SceneState for backward compatibility with existing rendering
    func toSceneState(canvas: CanvasConfig) -> SceneState {
        SceneState(
            objects: objects,
            canvasWidth: canvas.width,
            canvasHeight: canvas.height,
            backgroundColor: backgroundColor,
            duration: duration,
            fps: canvas.fps
        )
    }
    
    /// Create a default empty scene
    static func empty(name: String = "Scene 1", order: Int = 0) -> SceneFile {
        SceneFile(name: name, order: order)
    }
    
    /// Object count
    var objectCount: Int {
        objects.count
    }
    
    /// Whether the scene has any content
    var isEmpty: Bool {
        objects.isEmpty
    }
}
