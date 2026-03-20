//
//  CheckpointModels.swift
//  AIAfterEffects
//
//  Data models for the file-based checkpoint system.
//

import Foundation

/// A single checkpoint — a snapshot of the project's files at a point in time.
struct Checkpoint: Identifiable, Codable, Equatable {
    /// Short unique ID (7 hex chars, generated from UUID)
    let id: String
    
    /// Full UUID for the snapshot folder
    let fullHash: String
    
    /// The chat message ID that triggered this checkpoint
    let messageId: UUID
    
    /// Human-readable description (e.g. "Updated title text in scene 1")
    let message: String
    
    /// When the checkpoint was created
    let timestamp: Date
    
    /// Number of files changed in this snapshot
    let filesChanged: Int
    
    static func == (lhs: Checkpoint, rhs: Checkpoint) -> Bool {
        lhs.id == rhs.id
    }
}

/// Result of a revert operation
struct RevertResult {
    let success: Bool
    let checkpoint: Checkpoint?
    let error: String?
    
    static func succeeded(_ checkpoint: Checkpoint) -> RevertResult {
        RevertResult(success: true, checkpoint: checkpoint, error: nil)
    }
    
    static func failed(_ error: String) -> RevertResult {
        RevertResult(success: false, checkpoint: nil, error: error)
    }
}

/// Diff summary for a checkpoint
struct CheckpointDiff {
    let filesChanged: [String]
    let insertions: Int
    let deletions: Int
    let summary: String
}

/// On-disk manifest stored in .checkpoints/manifest.json
struct CheckpointManifest: Codable {
    var checkpoints: [Checkpoint]
    var baselineId: String?  // The "initial state" snapshot ID
    
    static func empty() -> CheckpointManifest {
        CheckpointManifest(checkpoints: [], baselineId: nil)
    }
}
