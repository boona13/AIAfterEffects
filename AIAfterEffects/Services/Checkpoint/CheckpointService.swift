//
//  CheckpointService.swift
//  AIAfterEffects
//
//  File-based checkpoint service for project versioning.
//  Stores snapshots of project files in a .checkpoints/ directory inside the project.
//  No git dependency — works fully inside App Sandbox.
//

import Foundation

// MARK: - Protocol

protocol CheckpointServiceProtocol {
    /// Initialize the checkpoint system in the project folder (idempotent)
    func initializeRepo(at projectURL: URL) async -> Bool
    
    /// Create a checkpoint (file snapshot) for the current project state
    func createCheckpoint(
        at projectURL: URL,
        message: String,
        messageId: UUID
    ) async -> Checkpoint?
    
    /// List all checkpoints for the project
    func listCheckpoints(at projectURL: URL, limit: Int) async -> [Checkpoint]
    
    /// Revert the project to a specific checkpoint
    func revertToCheckpoint(
        at projectURL: URL,
        checkpointId: String
    ) async -> RevertResult
    
    /// Get a diff summary for a checkpoint
    func diffForCheckpoint(at projectURL: URL, checkpointId: String) async -> CheckpointDiff?
}

// MARK: - Implementation

class CheckpointService: CheckpointServiceProtocol {
    
    static let shared = CheckpointService()
    
    private let fm = FileManager.default
    private let checkpointsDirName = ".checkpoints"
    private let manifestFileName = "manifest.json"
    
    /// Directories/files to exclude from snapshots
    private let excludedNames: Set<String> = [
        ".checkpoints", "chats", ".DS_Store", ".git", ".gitignore"
    ]
    
    private init() {}
    
    // MARK: - Initialization
    
    func initializeRepo(at projectURL: URL) async -> Bool {
        let checkpointsDir = projectURL.appendingPathComponent(checkpointsDirName)
        
        // Create .checkpoints/ if missing
        if !fm.fileExists(atPath: checkpointsDir.path) {
            do {
                try fm.createDirectory(at: checkpointsDir, withIntermediateDirectories: true)
            } catch {
                print("[CheckpointService] Failed to create .checkpoints dir: \(error)")
                return false
            }
        }
        
        // Create manifest if missing
        let manifestURL = checkpointsDir.appendingPathComponent(manifestFileName)
        if !fm.fileExists(atPath: manifestURL.path) {
            let manifest = CheckpointManifest.empty()
            saveManifest(manifest, at: projectURL)
            
            // Create a baseline snapshot (the initial project state)
            let baselineId = generateShortId()
            let fullId = UUID().uuidString
            let snapshotDir = checkpointsDir.appendingPathComponent(fullId)
            
            do {
                try snapshotFiles(from: projectURL, to: snapshotDir)
                var updatedManifest = manifest
                updatedManifest.baselineId = baselineId
                
                let baseline = Checkpoint(
                    id: baselineId,
                    fullHash: fullId,
                    messageId: UUID(),
                    message: "Initial project state",
                    timestamp: Date(),
                    filesChanged: countProjectFiles(at: projectURL)
                )
                updatedManifest.checkpoints.insert(baseline, at: 0)
                saveManifest(updatedManifest, at: projectURL)
            } catch {
                print("[CheckpointService] Failed to create baseline snapshot: \(error)")
                // Not fatal — we can still create checkpoints
            }
        }
        
        return true
    }
    
    // MARK: - Create Checkpoint
    
    func createCheckpoint(
        at projectURL: URL,
        message: String,
        messageId: UUID
    ) async -> Checkpoint? {
        let checkpointsDir = projectURL.appendingPathComponent(checkpointsDirName)
        
        // Ensure initialized
        if !fm.fileExists(atPath: checkpointsDir.path) {
            guard await initializeRepo(at: projectURL) else {
                print("[CheckpointService] Failed to initialize checkpoint system")
                return nil
            }
        }
        
        // Load manifest
        var manifest = loadManifest(at: projectURL)
        
        // Compare current files against the most recent snapshot
        let latestCheckpoint = manifest.checkpoints.first
        let latestSnapshotDir: URL? = latestCheckpoint.map {
            checkpointsDir.appendingPathComponent($0.fullHash)
        }
        
        let changedFiles = detectChangedFiles(
            projectDir: projectURL,
            previousSnapshot: latestSnapshotDir
        )
        
        // Allow creating a checkpoint even with no changes — the user needs a revert
        // point for every message. If files haven't changed, we still snapshot the
        // current state so the user can revert back to it later.
        if changedFiles.isEmpty {
            print("[CheckpointService] No file changes, but creating snapshot as revert point")
        } else {
            print("[CheckpointService] Detected \(changedFiles.count) changed files: \(changedFiles)")
        }
        
        // Create new snapshot
        let shortId = generateShortId()
        let fullId = UUID().uuidString
        let snapshotDir = checkpointsDir.appendingPathComponent(fullId)
        
        do {
            try snapshotFiles(from: projectURL, to: snapshotDir)
        } catch {
            print("[CheckpointService] Failed to create snapshot: \(error)")
            return nil
        }
        
        let checkpoint = Checkpoint(
            id: shortId,
            fullHash: fullId,
            messageId: messageId,
            message: message,
            timestamp: Date(),
            filesChanged: changedFiles.count
        )
        
        // Insert at the beginning (most recent first)
        manifest.checkpoints.insert(checkpoint, at: 0)
        
        // Prune old checkpoints (keep last 50)
        if manifest.checkpoints.count > 50 {
            let removed = manifest.checkpoints.suffix(from: 50)
            for old in removed {
                let oldDir = checkpointsDir.appendingPathComponent(old.fullHash)
                try? fm.removeItem(at: oldDir)
            }
            manifest.checkpoints = Array(manifest.checkpoints.prefix(50))
        }
        
        saveManifest(manifest, at: projectURL)
        
        print("[CheckpointService] Created checkpoint \(shortId) (\(changedFiles.count) files changed)")
        return checkpoint
    }
    
    // MARK: - List Checkpoints
    
    func listCheckpoints(at projectURL: URL, limit: Int = 50) async -> [Checkpoint] {
        let manifest = loadManifest(at: projectURL)
        // Skip the baseline "Initial project state" — users don't need to see it
        let userCheckpoints = manifest.checkpoints.filter { $0.messageId != UUID() }
        return Array(userCheckpoints.prefix(limit))
    }
    
    // MARK: - Revert to Checkpoint
    
    func revertToCheckpoint(
        at projectURL: URL,
        checkpointId: String
    ) async -> RevertResult {
        let checkpointsDir = projectURL.appendingPathComponent(checkpointsDirName)
        let manifest = loadManifest(at: projectURL)
        
        // Find the target checkpoint
        guard let target = manifest.checkpoints.first(where: {
            $0.id == checkpointId || $0.fullHash == checkpointId
        }) else {
            return .failed("Checkpoint \(checkpointId) not found")
        }
        
        let snapshotDir = checkpointsDir.appendingPathComponent(target.fullHash)
        guard fm.fileExists(atPath: snapshotDir.path) else {
            return .failed("Snapshot data for checkpoint \(checkpointId) is missing")
        }
        
        // First, auto-save current state as a "before revert" checkpoint
        let _ = await createCheckpoint(
            at: projectURL,
            message: "Auto-save before revert to \(checkpointId)",
            messageId: UUID()
        )
        
        // Restore files from the snapshot
        do {
            try restoreFiles(from: snapshotDir, to: projectURL)
        } catch {
            return .failed("Failed to restore files: \(error.localizedDescription)")
        }
        
        return .succeeded(target)
    }
    
    // MARK: - Diff
    
    func diffForCheckpoint(at projectURL: URL, checkpointId: String) async -> CheckpointDiff? {
        let checkpointsDir = projectURL.appendingPathComponent(checkpointsDirName)
        let manifest = loadManifest(at: projectURL)
        
        guard let target = manifest.checkpoints.first(where: {
            $0.id == checkpointId || $0.fullHash == checkpointId
        }) else { return nil }
        
        // Find the checkpoint just before this one
        guard let idx = manifest.checkpoints.firstIndex(where: { $0.id == target.id }),
              idx + 1 < manifest.checkpoints.count else {
            return CheckpointDiff(
                filesChanged: [],
                insertions: 0,
                deletions: 0,
                summary: "Initial checkpoint"
            )
        }
        
        let previous = manifest.checkpoints[idx + 1]
        let currentDir = checkpointsDir.appendingPathComponent(target.fullHash)
        let previousDir = checkpointsDir.appendingPathComponent(previous.fullHash)
        
        let changed = detectChangedFilesBetweenSnapshots(
            snapshot1: previousDir,
            snapshot2: currentDir
        )
        
        return CheckpointDiff(
            filesChanged: changed,
            insertions: 0,
            deletions: 0,
            summary: "\(changed.count) file\(changed.count == 1 ? "" : "s") changed"
        )
    }
    
    // MARK: - File Snapshot Helpers
    
    /// Copy all project files (excluding checkpoints, chats, etc.) into the snapshot directory.
    private func snapshotFiles(from projectDir: URL, to snapshotDir: URL) throws {
        try fm.createDirectory(at: snapshotDir, withIntermediateDirectories: true)
        
        let contents = try fm.contentsOfDirectory(
            at: projectDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        
        for item in contents {
            let name = item.lastPathComponent
            if excludedNames.contains(name) { continue }
            
            let dest = snapshotDir.appendingPathComponent(name)
            try fm.copyItem(at: item, to: dest)
        }
    }
    
    /// Restore files from a snapshot directory back into the project directory.
    private func restoreFiles(from snapshotDir: URL, to projectDir: URL) throws {
        // First, remove existing project files (but NOT checkpoints, chats, etc.)
        let existing = try fm.contentsOfDirectory(
            at: projectDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        
        for item in existing {
            let name = item.lastPathComponent
            if excludedNames.contains(name) { continue }
            try fm.removeItem(at: item)
        }
        
        // Copy snapshot files into project directory
        let snapshotContents = try fm.contentsOfDirectory(
            at: snapshotDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        
        for item in snapshotContents {
            let dest = projectDir.appendingPathComponent(item.lastPathComponent)
            try fm.copyItem(at: item, to: dest)
        }
    }
    
    /// Compare the current project files against a previous snapshot.
    /// Returns list of relative paths that differ.
    private func detectChangedFiles(
        projectDir: URL,
        previousSnapshot: URL?
    ) -> [String] {
        guard let previousSnapshot else {
            // No previous snapshot — everything is "new"
            return collectRelativeFilePaths(at: projectDir)
        }
        
        let currentFiles = collectFileHashes(at: projectDir)
        let previousFiles = collectFileHashes(at: previousSnapshot)
        
        var changed: [String] = []
        
        // Files that are new or modified
        for (path, hash) in currentFiles {
            if previousFiles[path] != hash {
                changed.append(path)
            }
        }
        
        // Files that were deleted
        for path in previousFiles.keys {
            if currentFiles[path] == nil {
                changed.append(path)
            }
        }
        
        return changed
    }
    
    /// Compare two snapshot directories.
    private func detectChangedFilesBetweenSnapshots(
        snapshot1: URL,
        snapshot2: URL
    ) -> [String] {
        let files1 = collectFileHashes(at: snapshot1)
        let files2 = collectFileHashes(at: snapshot2)
        
        var changed: [String] = []
        
        for (path, hash) in files2 {
            if files1[path] != hash {
                changed.append(path)
            }
        }
        
        for path in files1.keys {
            if files2[path] == nil {
                changed.append(path)
            }
        }
        
        return changed
    }
    
    /// Collect relative file paths from a directory, excluding checkpoint/chat dirs.
    private func collectRelativeFilePaths(at dir: URL) -> [String] {
        var paths: [String] = []
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return paths }
        
        for case let fileURL as URL in enumerator {
            // Skip excluded directories
            let relativePath = fileURL.path.replacingOccurrences(of: dir.path + "/", with: "")
            let topLevel = relativePath.components(separatedBy: "/").first ?? ""
            if excludedNames.contains(topLevel) {
                enumerator.skipDescendants()
                continue
            }
            
            let isFile = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            if isFile {
                paths.append(relativePath)
            }
        }
        
        return paths
    }
    
    /// Collect file paths and their size+modification date as a quick hash.
    /// Uses file size + modification date as a fast change-detection proxy.
    private func collectFileHashes(at dir: URL) -> [String: String] {
        var hashes: [String: String] = [:]
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return hashes }
        
        for case let fileURL as URL in enumerator {
            let relativePath = fileURL.path.replacingOccurrences(of: dir.path + "/", with: "")
            let topLevel = relativePath.components(separatedBy: "/").first ?? ""
            if excludedNames.contains(topLevel) {
                enumerator.skipDescendants()
                continue
            }
            
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            
            // Use actual file content hash for accurate detection
            if let data = try? Data(contentsOf: fileURL) {
                let hash = data.hashValue
                hashes[relativePath] = "\(data.count):\(hash)"
            }
        }
        
        return hashes
    }
    
    /// Count project files (excluding checkpoints etc.)
    private func countProjectFiles(at projectDir: URL) -> Int {
        collectRelativeFilePaths(at: projectDir).count
    }
    
    // MARK: - Manifest Management
    
    private func loadManifest(at projectURL: URL) -> CheckpointManifest {
        let manifestURL = projectURL
            .appendingPathComponent(checkpointsDirName)
            .appendingPathComponent(manifestFileName)
        
        guard let data = try? Data(contentsOf: manifestURL) else {
            return .empty()
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        guard let manifest = try? decoder.decode(CheckpointManifest.self, from: data) else {
            print("[CheckpointService] Failed to decode manifest at \(manifestURL.path)")
            return .empty()
        }
        
        return manifest
    }
    
    private func saveManifest(_ manifest: CheckpointManifest, at projectURL: URL) {
        let manifestURL = projectURL
            .appendingPathComponent(checkpointsDirName)
            .appendingPathComponent(manifestFileName)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        guard let data = try? encoder.encode(manifest) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }
    
    // MARK: - ID Generation
    
    /// Generate a short hex ID (7 chars) similar to git short hashes.
    private func generateShortId() -> String {
        let uuid = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return String(uuid.prefix(7))
    }
}
