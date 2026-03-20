//
//  ObjectContextAttachment.swift
//  AIAfterEffects
//
//  Lightweight reference to a scene object for providing focused context to the LLM.
//  Unlike ChatAttachment (which carries binary data), this just stores an ID + metadata
//  so the system can fetch full details from the live scene when building the prompt.
//

import Foundation

struct ObjectContextAttachment: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let objectId: UUID
    let objectName: String
    let objectType: SceneObjectType
    let sceneName: String
    
    init(object: SceneObject, sceneName: String) {
        self.id = UUID()
        self.objectId = object.id
        self.objectName = object.name
        self.objectType = object.type
        self.sceneName = sceneName
    }
    
    var displayIcon: String {
        switch objectType {
        case .text:      return "textformat"
        case .rectangle: return "rectangle.fill"
        case .circle:    return "circle.fill"
        case .ellipse:   return "oval.fill"
        case .polygon:   return "pentagon.fill"
        case .line:      return "line.diagonal"
        case .icon:      return "star.fill"
        case .image:     return "photo.fill"
        case .path:      return "scribble.variable"
        case .model3D:   return "cube.fill"
        case .shader:    return "sparkle"
        case .particleSystem: return "sparkles"
        }
    }
}
