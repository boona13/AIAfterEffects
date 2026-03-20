//
//  AgentModels.swift
//  AIAfterEffects
//
//  Data models for the AI agentic tool-use system.
//  The AI can call tools to explore the project folder, read/write scene files,
//  and search/replace content — like a mini Cursor IDE for motion.
//

import Foundation

// MARK: - Tool Definition

/// Every tool the AI agent can invoke.
enum AgentTool: String, Codable, CaseIterable {
    case listFiles       // List files/folders in a directory
    case readFile        // Read the full contents of a file
    case writeFile       // Overwrite or create a file
    case grep            // Search file contents with a regex/string pattern
    case searchReplace   // Find & replace text inside a file
    case projectInfo     // Get high-level project summary (scenes, canvas, etc.)
    case updateObject    // CRUD: Update specific properties on an object by ID
    case queryObjects    // CRUD: Query objects by type/scene with full properties
    case shiftTimeline   // Shift all animations at/after a given time forward or backward
    case getReferenceDocs // On-demand reference documentation (examples, presets, easing)
}

// MARK: - Native OpenRouter Tool Definitions

extension AgentTool {
    
    /// The snake_case name used in the OpenRouter function calling API.
    var functionName: String { rawValue.toSnakeCase() }
    
    /// Generates OpenRouter-format tool definitions, optionally excluding specific tools.
    static func openRouterToolDefinitions(excluding: Set<AgentTool> = []) -> [OpenRouterTool] {
        return allToolDefinitions().filter { def in
            guard let tool = AgentTool.from(functionName: def.function.name) else { return true }
            return !excluding.contains(tool)
        }
    }
    
    /// Full list of all tool definitions.
    private static func allToolDefinitions() -> [OpenRouterTool] {
        return [
            OpenRouterTool(
                name: "list_files",
                description: "List files and folders in a directory within the project.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "path": [
                            "type": "string",
                            "description": "Relative path inside the project (e.g. \"/\" or \"assets/\"). Defaults to project root."
                        ] as [String: Any],
                        "recursive": [
                            "type": "boolean",
                            "description": "If true, list all files recursively. Default false."
                        ] as [String: Any]
                    ] as [String: Any],
                    "required": [] as [String]
                ] as [String: Any]
            ),
            OpenRouterTool(
                name: "read_file",
                description: "Reads a file from the project. For object properties, use query_objects and update_object instead — they are faster and safer. Only use read_file for non-object files or when you need raw JSON inspection. Results use line-numbered format: 00001| content.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "path": [
                            "type": "string",
                            "description": "Relative path to the file (e.g. \"project.json\")."
                        ] as [String: Any],
                        "offset": [
                            "type": "integer",
                            "description": "Line number to start reading from (0-based). Default: 0."
                        ] as [String: Any],
                        "limit": [
                            "type": "integer",
                            "description": "Number of lines to read. Default: 2000."
                        ] as [String: Any]
                    ] as [String: Any],
                    "required": ["path"] as [String]
                ] as [String: Any]
            ),
            OpenRouterTool(
                name: "write_file",
                description: "Create or overwrite a file. ALWAYS prefer search_replace for editing existing files. NEVER write new files unless explicitly required. Will FAIL if new content is <40% the size of existing file (safety guard against truncated output).",
                parameters: [
                    "type": "object",
                    "properties": [
                        "path": [
                            "type": "string",
                            "description": "Relative path to the file to write."
                        ] as [String: Any],
                        "content": [
                            "type": "string",
                            "description": "Full file content to write."
                        ] as [String: Any]
                    ] as [String: Any],
                    "required": ["path", "content"] as [String]
                ] as [String: Any]
            ),
            OpenRouterTool(
                name: "grep",
                description: "Search file contents with a regex pattern. Use this to find objects, properties, or text in large files BEFORE using search_replace. Results are sorted by modification time, limited to 100 matches.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "pattern": [
                            "type": "string",
                            "description": "Regex or literal search string."
                        ] as [String: Any],
                        "path": [
                            "type": "string",
                            "description": "Directory to search in (relative). Defaults to project root."
                        ] as [String: Any],
                        "glob": [
                            "type": "string",
                            "description": "File glob filter (e.g. \"*.json\")."
                        ] as [String: Any]
                    ] as [String: Any],
                    "required": ["pattern"] as [String]
                ] as [String: Any]
            ),
            OpenRouterTool(
                name: "search_replace",
                description: "Performs exact string replacements in files. WARNING: Do NOT use this for object property changes — use update_object instead, which is faster and cannot corrupt JSON. Only use search_replace for non-property edits (e.g. changing scene names, transitions, or non-object JSON fields).",
                parameters: [
                    "type": "object",
                    "properties": [
                        "path": [
                            "type": "string",
                            "description": "Relative path to the file to modify."
                        ] as [String: Any],
                        "search": [
                            "type": "string",
                            "description": "Exact string to find in the file."
                        ] as [String: Any],
                        "replace": [
                            "type": "string",
                            "description": "Replacement string."
                        ] as [String: Any],
                        "replace_all": [
                            "type": "boolean",
                            "description": "If true, replace all occurrences. Default false (first only)."
                        ] as [String: Any]
                    ] as [String: Any],
                    "required": ["path", "search", "replace"] as [String]
                ] as [String: Any]
            ),
            OpenRouterTool(
                name: "project_info",
                description: "Get a full summary of the project including scenes, canvas size, transitions, and file tree.",
                parameters: [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ] as [String: Any]
            ),
            OpenRouterTool(
                name: "update_object",
                description: "PREFERRED: Update properties on a scene object, scene, or transition by ID. Uses full JSON parsing — handles ANY nesting depth. For objects: pass property-level fields (x, y, fillColor, etc.) or object-level fields (name, isVisible, zIndex, animations, timingDependency). For scenes: pass the SCENE's UUID to update scene-level fields (duration, name, backgroundColor). For transitions: pass type/duration. ALWAYS use this instead of search_replace for ANY project.json modification.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "id": [
                            "type": "string",
                            "description": "UUID of the target entity — an object, scene, or transition (from project_info or query_objects)."
                        ] as [String: Any],
                        "properties": [
                            "type": "object",
                            "description": "Key-value pairs to update. Supports ALL property types including nested objects. For scene objects: {\"x\": 540, \"fontSize\": 48}, {\"fillColor\": {\"red\": 1, \"green\": 0, \"blue\": 0, \"alpha\": 1}}, {\"shadowColor\": {\"red\": 0, \"green\": 0, \"blue\": 0, \"alpha\": 0.5}, \"shadowRadius\": 10}, {\"name\": \"Title\", \"isVisible\": true}. Animations: {\"animations\": [{\"type\":\"fadeIn\",\"startTime\":5.0,\"duration\":0.5}]} — replaces the ENTIRE animations array. For scenes (pass scene UUID): {\"duration\": 20.0, \"name\": \"My Scene\"}. For transitions: {\"type\": \"slideLeft\", \"duration\": 1.0}. Object properties: x, y, width, height, rotation, scaleX/Y, anchorX/Y, opacity, cornerRadius, fillColor, strokeColor, strokeWidth, text, fontSize, fontName, fontWeight, textAlignment, iconName, iconSize, sides, blurRadius, brightness, contrast, saturation, hueRotation, grayscale, blendMode, shadowColor, shadowRadius, shadowOffsetX/Y, colorInvert, modelAssetId, rotationX/Y/Z, cameraDistance, cameraAngleX/Y, environmentLighting, shaderCode, shaderParam1-4, closePath, lineCap, lineJoin, dashPattern, trimStart/End/Offset. Object-level: name, isVisible, zIndex, animations, timingDependency. Scene-level: duration, name, backgroundColor. Transition: type, duration."
                        ] as [String: Any]
                    ] as [String: Any],
                    "required": ["id", "properties"] as [String]
                ] as [String: Any]
            ),
            OpenRouterTool(
                name: "query_objects",
                description: "Query scene objects and transitions with optional filters. Returns COMPREHENSIVE details for every property — including nested objects (colors with r/g/b/a), shadow, 3D, shader, path data, animations, timing, and transitions between scenes. Always reads fresh from disk. Use this to inspect objects/transitions before update_object.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "type": [
                            "type": "string",
                            "description": "Filter by type: rectangle, circle, ellipse, polygon, line, text, icon, image, path, model3D, shader, transition."
                        ] as [String: Any],
                        "name": [
                            "type": "string",
                            "description": "Filter by object name (partial match, case-insensitive). E.g. 'logo' matches 'nike_logo_mark'."
                        ] as [String: Any],
                        "scene": [
                            "type": "string",
                            "description": "Filter by scene name (partial match, case-insensitive)."
                        ] as [String: Any],
                        "id": [
                            "type": "string",
                            "description": "Get a specific object by UUID."
                        ] as [String: Any]
                    ] as [String: Any],
                    "required": [] as [String]
                ] as [String: Any]
            ),
            OpenRouterTool(
                name: "shift_timeline",
                description: "Shift ALL animations at or after a given time forward (or backward) in a scene. Use this when inserting a new slide/segment: call shift_timeline to push existing content forward, then create new objects in the gap. Also extends the scene duration automatically. Uses safe Codable encoding — never corrupts the project file.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "scene_id": [
                            "type": "string",
                            "description": "UUID of the scene to modify. Get from project_info."
                        ] as [String: Any],
                        "after_time": [
                            "type": "number",
                            "description": "The time threshold in seconds. All animations with startTime >= this value will be shifted."
                        ] as [String: Any],
                        "shift_amount": [
                            "type": "number",
                            "description": "Seconds to shift forward (positive) or backward (negative). E.g. 3.0 shifts everything 3s later."
                        ] as [String: Any],
                        "extend_duration": [
                            "type": "boolean",
                            "description": "If true (default), also increases the scene duration by shift_amount."
                        ] as [String: Any]
                    ] as [String: Any],
                    "required": ["scene_id", "after_time", "shift_amount"] as [String]
                ] as [String: Any]
            ),
            OpenRouterTool(
                name: "get_reference_docs",
                description: "Get detailed reference documentation and examples on demand. Topics: '3d_examples' (3D model animation combos), 'shader_examples' (Metal shader code patterns), 'path_examples' (custom path shapes + draw-on), 'preset_guide' (which preset for which use case), 'easing_types' (all valid easing names), 'follow_up_examples' (how to handle modification requests).",
                parameters: [
                    "type": "object",
                    "properties": [
                        "topic": [
                            "type": "string",
                            "description": "Topic to look up: 3d_examples, shader_examples, path_examples, preset_guide, easing_types, follow_up_examples"
                        ] as [String: Any]
                    ] as [String: Any],
                    "required": ["topic"] as [String]
                ] as [String: Any]
            )
        ]
    }
    
    /// Map an OpenRouter function name back to an AgentTool.
    static func from(functionName: String) -> AgentTool? {
        switch functionName {
        case "list_files":      return .listFiles
        case "read_file":       return .readFile
        case "write_file":      return .writeFile
        case "grep":            return .grep
        case "search_replace":  return .searchReplace
        case "project_info":    return .projectInfo
        case "update_object":   return .updateObject
        case "query_objects":   return .queryObjects
        case "shift_timeline":      return .shiftTimeline
        case "get_reference_docs":  return .getReferenceDocs
        default:                    return nil
        }
    }
    
    /// Parse a JSON arguments string from the API into ToolArguments.
    static func parseArguments(functionName: String, jsonString: String) -> ToolArguments {
        var args = ToolArguments()
        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return args
        }
        args.path = dict["path"] as? String
        args.recursive = dict["recursive"] as? Bool
        args.offset = dict["offset"] as? Int
        args.limit = dict["limit"] as? Int
        args.content = dict["content"] as? String
        args.pattern = dict["pattern"] as? String
        args.glob = dict["glob"] as? String
        args.search = dict["search"] as? String
        args.replace = dict["replace"] as? String
        args.replaceAll = dict["replace_all"] as? Bool ?? dict["replaceAll"] as? Bool
        
        // CRUD tools
        args.objectId = dict["id"] as? String
        args.objectType = dict["type"] as? String
        args.objectName = dict["name"] as? String
        args.scene = dict["scene"] as? String
        args.properties = dict["properties"] as? [String: Any]
        
        // shiftTimeline
        args.sceneId = dict["scene_id"] as? String
        args.afterTime = dict["after_time"] as? Double
        args.shiftAmount = dict["shift_amount"] as? Double
        args.extendDuration = dict["extend_duration"] as? Bool
        
        // getReferenceDocs
        args.topic = dict["topic"] as? String
        return args
    }
}

private extension String {
    /// Convert camelCase to snake_case (e.g. "listFiles" → "list_files").
    func toSnakeCase() -> String {
        var result = ""
        for (i, char) in self.enumerated() {
            if char.isUppercase && i > 0 {
                result += "_"
            }
            result += String(char).lowercased()
        }
        return result
    }
}

// MARK: - Tool Call (AI → App)

/// A single tool invocation requested by the AI inside its JSON response.
struct AgentToolCall: Codable, Identifiable {
    let id: String           // Unique call ID (for correlating results)
    let tool: AgentTool
    let arguments: ToolArguments
    
    init(id: String = UUID().uuidString, tool: AgentTool, arguments: ToolArguments) {
        self.id = id
        self.tool = tool
        self.arguments = arguments
    }
}

// MARK: - Tool Arguments (flexible union)

/// Arguments for any tool. Only the relevant fields for the given tool are non-nil.
struct ToolArguments: Codable {
    // listFiles
    var path: String?              // Relative path inside project (e.g. "scenes/")
    var recursive: Bool?           // Default false
    
    // readFile
    // uses `path`
    var offset: Int?               // Optional line offset (1-based)
    var limit: Int?                // Optional max lines to return
    
    // writeFile
    // uses `path`
    var content: String?           // Full file content to write
    
    // grep
    var pattern: String?           // Regex or literal search string
    var glob: String?              // File glob filter (e.g. "*.json")
    // uses `path` as search root
    
    // searchReplace
    // uses `path` (file to modify)
    var search: String?            // Exact string to find
    var replace: String?           // Replacement string
    var replaceAll: Bool?          // Default false — replace first occurrence
    
    // updateObject
    var objectId: String?          // Object UUID to update
    var properties: [String: Any]? // Key-value pairs of properties to set
    
    // queryObjects
    var objectType: String?        // Filter by SceneObjectType (e.g. "text")
    var objectName: String?        // Filter by object name (partial, case-insensitive)
    var scene: String?             // Filter by scene name (partial, case-insensitive)
    // uses objectId for single-object query too
    
    // shiftTimeline
    var sceneId: String?           // Scene UUID to modify
    var afterTime: Double?         // Shift animations at/after this time
    var shiftAmount: Double?       // How many seconds to shift (positive = forward)
    var extendDuration: Bool?      // Also extend scene duration (default true)
    
    // getReferenceDocs
    var topic: String?             // Reference documentation topic
    
    init() {}
    
    // Custom Codable conformance because [String: Any] is not Codable
    enum CodingKeys: String, CodingKey {
        case path, recursive, offset, limit, content, pattern, glob
        case search, replace, replaceAll, objectId, objectType, objectName, scene
        case sceneId, afterTime, shiftAmount, extendDuration, topic
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decodeIfPresent(String.self, forKey: .path)
        recursive = try c.decodeIfPresent(Bool.self, forKey: .recursive)
        offset = try c.decodeIfPresent(Int.self, forKey: .offset)
        limit = try c.decodeIfPresent(Int.self, forKey: .limit)
        content = try c.decodeIfPresent(String.self, forKey: .content)
        pattern = try c.decodeIfPresent(String.self, forKey: .pattern)
        glob = try c.decodeIfPresent(String.self, forKey: .glob)
        search = try c.decodeIfPresent(String.self, forKey: .search)
        replace = try c.decodeIfPresent(String.self, forKey: .replace)
        replaceAll = try c.decodeIfPresent(Bool.self, forKey: .replaceAll)
        objectId = try c.decodeIfPresent(String.self, forKey: .objectId)
        objectType = try c.decodeIfPresent(String.self, forKey: .objectType)
        objectName = try c.decodeIfPresent(String.self, forKey: .objectName)
        scene = try c.decodeIfPresent(String.self, forKey: .scene)
        sceneId = try c.decodeIfPresent(String.self, forKey: .sceneId)
        afterTime = try c.decodeIfPresent(Double.self, forKey: .afterTime)
        shiftAmount = try c.decodeIfPresent(Double.self, forKey: .shiftAmount)
        extendDuration = try c.decodeIfPresent(Bool.self, forKey: .extendDuration)
        topic = try c.decodeIfPresent(String.self, forKey: .topic)
        properties = nil // Parsed separately via JSONSerialization
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(path, forKey: .path)
        try c.encodeIfPresent(recursive, forKey: .recursive)
        try c.encodeIfPresent(offset, forKey: .offset)
        try c.encodeIfPresent(limit, forKey: .limit)
        try c.encodeIfPresent(content, forKey: .content)
        try c.encodeIfPresent(pattern, forKey: .pattern)
        try c.encodeIfPresent(glob, forKey: .glob)
        try c.encodeIfPresent(search, forKey: .search)
        try c.encodeIfPresent(replace, forKey: .replace)
        try c.encodeIfPresent(replaceAll, forKey: .replaceAll)
        try c.encodeIfPresent(objectId, forKey: .objectId)
        try c.encodeIfPresent(objectType, forKey: .objectType)
        try c.encodeIfPresent(objectName, forKey: .objectName)
        try c.encodeIfPresent(scene, forKey: .scene)
        try c.encodeIfPresent(sceneId, forKey: .sceneId)
        try c.encodeIfPresent(afterTime, forKey: .afterTime)
        try c.encodeIfPresent(shiftAmount, forKey: .shiftAmount)
        try c.encodeIfPresent(extendDuration, forKey: .extendDuration)
        try c.encodeIfPresent(topic, forKey: .topic)
    }
}

// MARK: - Tool Result (App → AI)

/// The result of executing a tool, sent back into the conversation.
struct AgentToolResult: Codable, Identifiable {
    let id: String               // Matches the AgentToolCall.id
    let tool: AgentTool
    let success: Bool
    let output: String           // Textual output (file listing, file contents, match count, etc.)
    let error: String?           // Error message if success == false
    
    init(callId: String, tool: AgentTool, success: Bool, output: String, error: String? = nil) {
        self.id = callId
        self.tool = tool
        self.success = success
        self.output = output
        self.error = error
    }
}

// MARK: - Agentic LLM Response

/// An extended response format the AI can use when it needs tools.
/// The AI returns EITHER:
///   - A normal `SceneCommands` (final answer with scene actions), OR
///   - An array of `AgentToolCall` (requesting tool execution, triggers another round)
struct AgentResponse: Codable {
    var message: String?             // Text message to display
    var toolCalls: [AgentToolCall]?  // Tool invocations (if non-nil, we execute & loop)
    var actions: [SceneAction]?      // Scene commands (final answer)
    
    /// True when the AI wants to call tools (not done yet)
    var needsToolExecution: Bool {
        toolCalls != nil && !(toolCalls?.isEmpty ?? true)
    }
}

// MARK: - Agent Loop State

/// Tracks the state of a multi-turn agentic interaction.
class AgentLoopState {
    var turns: [(call: [AgentToolCall], results: [AgentToolResult])] = []
    var maxTurns: Int = 10
    var isComplete: Bool = false
    var finalMessage: String?
    var finalCommands: SceneCommands?
    
    var turnCount: Int { turns.count }
    var hasReachedLimit: Bool { turnCount >= maxTurns }
    
    /// Flat list of all tool activities for the UI.
    var allActivities: [ToolActivity] {
        var activities: [ToolActivity] = []
        for turn in turns {
            for call in turn.call {
                let result = turn.results.first { $0.id == call.id }
                activities.append(ToolActivity(
                    tool: call.tool,
                    arguments: call.arguments,
                    result: result,
                    status: result != nil ? (result!.success ? .success : .failed) : .running
                ))
            }
        }
        return activities
    }
}

// MARK: - Tool Activity (for UI)

/// A single tool execution event shown in the chat UI.
struct ToolActivity: Identifiable {
    let id = UUID()
    let tool: AgentTool
    let arguments: ToolArguments
    let result: AgentToolResult?
    let status: ToolActivityStatus
    
    /// Human-readable summary of what this tool call does.
    var summary: String {
        switch tool {
        case .listFiles:
            return "Listing \(arguments.path ?? "/")"
        case .readFile:
            return "Reading \(arguments.path ?? "file")"
        case .writeFile:
            return "Writing \(arguments.path ?? "file")"
        case .grep:
            return "Searching for \"\(arguments.pattern ?? "")\" in \(arguments.path ?? "project")"
        case .searchReplace:
            return "Replacing in \(arguments.path ?? "file")"
        case .projectInfo:
            return "Getting project info"
        case .updateObject:
            let count = arguments.properties?.count ?? 0
            return "Updating \(count) properties on object"
        case .queryObjects:
            return "Querying \(arguments.objectType ?? "all") objects"
        case .shiftTimeline:
            let amount = arguments.shiftAmount.map { String(format: "%.1fs", $0) } ?? "?"
            return "Shifting timeline by \(amount)"
        case .getReferenceDocs:
            return "Looking up \(arguments.topic ?? "docs")"
        }
    }
    
    /// SF Symbol for the tool type.
    var iconName: String {
        switch tool {
        case .listFiles:       return "folder.fill"
        case .readFile:        return "doc.text.fill"
        case .writeFile:       return "square.and.pencil"
        case .grep:            return "magnifyingglass"
        case .searchReplace:   return "arrow.left.arrow.right"
        case .projectInfo:     return "info.circle.fill"
        case .updateObject:    return "pencil.circle.fill"
        case .queryObjects:    return "eye.circle.fill"
        case .shiftTimeline:   return "clock.arrow.2.circlepath"
        case .getReferenceDocs: return "book.fill"
        }
    }
}

enum ToolActivityStatus {
    case running
    case success
    case failed
}
