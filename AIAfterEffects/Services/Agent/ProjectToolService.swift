//
//  ProjectToolService.swift
//  AIAfterEffects
//
//  Executes agentic tools against the project filesystem.
//  All paths are sandboxed to the current project folder.
//

import Foundation

// MARK: - Protocol

protocol ProjectToolServiceProtocol {
    func execute(_ call: AgentToolCall, projectURL: URL, project: Project) -> AgentToolResult
}

// MARK: - Implementation

class ProjectToolService: ProjectToolServiceProtocol {
    
    static let shared = ProjectToolService()
    
    private let fileManager = FileManager.default
    private let maxReadSize = 250_000     // ~250 KB max file size for reading
    private let defaultLineLimit = 2000   // Default max lines (matches OpenCode)
    private let maxLineLength = 2000      // Truncate individual lines longer than this
    private let maxOutputBytes = 50_000   // 50KB max output per read (matches OpenCode's truncation.ts)
    
    // MARK: - Execute
    
    func execute(_ call: AgentToolCall, projectURL: URL, project: Project) -> AgentToolResult {
        let logger = DebugLogger.shared
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Log tool invocation with arguments summary
        let argsSummary = describeArguments(call)
        logger.info("[Tool] ▶ \(call.tool.rawValue)(\(argsSummary))", category: .llm)
        
        let result: AgentToolResult
        switch call.tool {
        case .listFiles:
            result = executeListFiles(call, projectURL: projectURL)
        case .readFile:
            result = executeReadFile(call, projectURL: projectURL)
        case .writeFile:
            result = executeWriteFile(call, projectURL: projectURL)
        case .grep:
            result = executeGrep(call, projectURL: projectURL)
        case .searchReplace:
            result = executeSearchReplace(call, projectURL: projectURL)
        case .projectInfo:
            result = executeProjectInfo(call, project: project, projectURL: projectURL)
        case .updateObject:
            result = executeUpdateObject(call, projectURL: projectURL)
        case .queryObjects:
            result = executeQueryObjects(call, project: project, projectURL: projectURL)
        case .shiftTimeline:
            result = executeShiftTimeline(call, projectURL: projectURL)
        case .getReferenceDocs:
            result = executeGetReferenceDocs(call)
        }
        
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        if result.success {
            logger.success("[Tool] ✓ \(call.tool.rawValue) OK (\(String(format: "%.0f", elapsed))ms, \(result.output.count) chars)", category: .llm)
        } else {
            logger.error("[Tool] ✗ \(call.tool.rawValue) FAILED: \(result.error ?? "unknown") (\(String(format: "%.0f", elapsed))ms)", category: .llm)
        }
        
        return result
    }
    
    /// Human-readable summary of tool arguments for logging.
    private func describeArguments(_ call: AgentToolCall) -> String {
        let a = call.arguments
        switch call.tool {
        case .listFiles:
            return "path: \(a.path ?? "/"), recursive: \(a.recursive ?? false)"
        case .readFile:
            var desc = "path: \(a.path ?? "?")"
            if let offset = a.offset { desc += ", offset: \(offset)" }
            if let limit = a.limit { desc += ", limit: \(limit)" }
            return desc
        case .writeFile:
            return "path: \(a.path ?? "?"), content: \(a.content?.count ?? 0) chars"
        case .grep:
            var desc = "pattern: \"\(a.pattern ?? "?")\""
            if let path = a.path { desc += ", path: \(path)" }
            if let glob = a.glob { desc += ", glob: \(glob)" }
            return desc
        case .searchReplace:
            let searchPreview = (a.search ?? "").prefix(50)
            let replacePreview = (a.replace ?? "").prefix(50)
            return "path: \(a.path ?? "?"), search: \"\(searchPreview)\", replace: \"\(replacePreview)\", all: \(a.replaceAll ?? false)"
        case .projectInfo:
            return ""
        case .updateObject:
            let propsCount = call.arguments.properties?.count ?? 0
            return "id: \(a.objectId ?? "?"), properties: \(propsCount) fields"
        case .queryObjects:
            var desc = ""
            if let t = a.objectType { desc += "type: \(t)" }
            if let s = a.scene { desc += (desc.isEmpty ? "" : ", ") + "scene: \(s)" }
            if let id = a.objectId { desc += (desc.isEmpty ? "" : ", ") + "id: \(id)" }
            return desc
        case .shiftTimeline:
            let scenePrefix = a.sceneId.map { "\(String($0.prefix(8)))..." } ?? "?"
            let afterStr = a.afterTime.map { String(format: "%.1fs", $0) } ?? "?"
            let shiftStr = a.shiftAmount.map { String(format: "%+.1fs", $0) } ?? "?"
            return "scene: \(scenePrefix), after: \(afterStr), shift: \(shiftStr)"
        case .getReferenceDocs:
            return "topic: \(a.topic ?? "?")"
        }
    }
    
    // MARK: - list_files
    
    private func executeListFiles(_ call: AgentToolCall, projectURL: URL) -> AgentToolResult {
        let relativePath = call.arguments.path ?? ""
        let targetURL = resolveAndValidate(relativePath, projectURL: projectURL)
        
        guard let targetURL else {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false, output: "", error: "Path is outside the project folder")
        }
        
        guard fileManager.fileExists(atPath: targetURL.path) else {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false, output: "", error: "Path does not exist: \(relativePath)")
        }
        
        let recursive = call.arguments.recursive ?? false
        
        do {
            var output = ""
            if recursive {
                // Recursive tree
                output = buildTree(at: targetURL, projectURL: projectURL, indent: "")
            } else {
                // Single level listing
                let contents = try fileManager.contentsOfDirectory(
                    at: targetURL,
                    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                    options: [.skipsHiddenFiles]
                )
                
                let sorted = contents.sorted { $0.lastPathComponent < $1.lastPathComponent }
                var lines: [String] = []
                
                for item in sorted {
                    var isDir: ObjCBool = false
                    fileManager.fileExists(atPath: item.path, isDirectory: &isDir)
                    
                    let name = item.lastPathComponent
                    if isDir.boolValue {
                        lines.append("\(name)/")
                    } else {
                        let size = fileSizeString(item)
                        lines.append("\(name)  (\(size))")
                    }
                }
                
                if lines.isEmpty {
                    output = "(empty directory)"
                } else {
                    output = lines.joined(separator: "\n")
                }
            }
            
            return AgentToolResult(callId: call.id, tool: call.tool, success: true, output: output)
        } catch {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false, output: "", error: error.localizedDescription)
        }
    }
    
    // MARK: - read_file
    
    private func executeReadFile(_ call: AgentToolCall, projectURL: URL) -> AgentToolResult {
        guard let relativePath = call.arguments.path, !relativePath.isEmpty else {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false, output: "", error: "Missing 'path' argument")
        }
        
        guard let fileURL = resolveAndValidate(relativePath, projectURL: projectURL) else {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false, output: "", error: "Path is outside the project folder")
        }
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            // Suggest similar files if not found
            let suggestion = suggestSimilarFiles(relativePath, projectURL: projectURL)
            let errorMsg = "File not found: \(relativePath)" + (suggestion.isEmpty ? "" : ". Did you mean: \(suggestion)?")
            return AgentToolResult(callId: call.id, tool: call.tool, success: false, output: "", error: errorMsg)
        }
        
        let logger = DebugLogger.shared
        
        do {
            let data = try Data(contentsOf: fileURL)
            logger.debug("[Tool:read_file] File size: \(data.count) bytes (\(relativePath))", category: .llm)
            
            guard data.count <= maxReadSize else {
                logger.warning("[Tool:read_file] File too large: \(data.count) bytes > \(maxReadSize) max", category: .llm)
                return AgentToolResult(callId: call.id, tool: call.tool, success: false, output: "",
                    error: "File too large (\(data.count) bytes, max \(maxReadSize)). Use 'offset' and 'limit' to read specific sections.")
            }
            
            guard let content = String(data: data, encoding: .utf8) else {
                return AgentToolResult(callId: call.id, tool: call.tool, success: false, output: "", error: "File is not UTF-8 text")
            }
            
            let allLines = content.components(separatedBy: .newlines)
            let totalLines = allLines.count
            
            // Apply offset (1-based input → 0-based internal)
            let offset = max(0, (call.arguments.offset ?? 1) - 1)
            // Apply limit: default to defaultLineLimit if not specified
            let limit = call.arguments.limit ?? defaultLineLimit
            
            // --- OpenCode-style output: cap at maxOutputBytes (50KB) ---
            // Build output line by line, stopping at the byte limit.
            // This prevents dumping 150K+ chars that bloat the API context.
            var outputLines: [String] = []
            var byteCount = 0
            var truncatedByBytes = false
            var truncatedLineCount = 0
            var linesRead = 0
            
            for i in offset..<min(allLines.count, offset + limit) {
                let line = allLines[i]
                let displayLine: String
                if line.count > maxLineLength {
                    truncatedLineCount += 1
                    displayLine = String(line.prefix(maxLineLength)) + "..."
                } else {
                    displayLine = line
                }
                let formatted = "\(String(format: "%5d", i + 1))| \(displayLine)"
                let lineBytes = formatted.utf8.count + (outputLines.isEmpty ? 0 : 1) // +1 for newline
                
                if byteCount + lineBytes > maxOutputBytes {
                    truncatedByBytes = true
                    break
                }
                
                outputLines.append(formatted)
                byteCount += lineBytes
                linesRead += 1
            }
            
            let lastLineShown = offset + linesRead
            let hasMoreLines = lastLineShown < totalLines
            
            // For large truncated files, prepend a strategy hint BEFORE the content
            // so the model sees it first (instead of after 50K of content where it gets ignored).
            var output = ""
            if (truncatedByBytes || hasMoreLines) && totalLines > 2000 {
                output += "[STRATEGY: This file is large (\(totalLines) lines, \(data.count / 1000)KB). Do NOT read it sequentially — that wastes turns.\nWorkflow: project_info → grep(pattern: \"object_id_or_name\") → read_file(offset:LINE, limit:100) → search_replace\nCopy EXACT text from read output for search_replace — do not guess JSON formatting.]\n\n"
            }
            
            // Wrap in <file> tags (matches OpenCode read.ts format)
            output += "<file>\n"
            output += outputLines.joined(separator: "\n")
            
            if truncatedByBytes {
                output += "\n\n(Output truncated at \(maxOutputBytes / 1000)KB. Use offset: \(lastLineShown + 1) to read beyond line \(lastLineShown))"
            } else if hasMoreLines {
                output += "\n\n(File has \(totalLines) total lines. Showing \(offset + 1)-\(lastLineShown). Use offset: \(lastLineShown + 1) to continue)"
            } else {
                output += "\n\n(End of file — \(totalLines) lines total)"
            }
            output += "\n</file>"
            
            let truncReason = truncatedByBytes ? "BYTE_LIMIT" : (hasMoreLines ? "LINE_LIMIT" : "COMPLETE")
            logger.debug("[Tool:read_file] Read \(linesRead) lines (offset:\(offset + 1) limit:\(limit)) of \(totalLines) total | \(byteCount) bytes output | \(truncReason)\(truncatedLineCount > 0 ? " | \(truncatedLineCount) long lines trimmed" : "")", category: .llm)
            
            return AgentToolResult(callId: call.id, tool: call.tool, success: true, output: output)
        } catch {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false, output: "", error: error.localizedDescription)
        }
    }
    
    /// Suggest similar filenames when a file is not found.
    private func suggestSimilarFiles(_ relativePath: String, projectURL: URL) -> String {
        let targetName = (relativePath as NSString).lastPathComponent.lowercased()
        let parentPath = (relativePath as NSString).deletingLastPathComponent
        let parentURL = parentPath.isEmpty ? projectURL : projectURL.appendingPathComponent(parentPath)
        
        guard let contents = try? fileManager.contentsOfDirectory(
            at: parentURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return "" }
        
        let similar = contents
            .map { $0.lastPathComponent }
            .filter { $0.lowercased().contains(targetName.prefix(4)) || targetName.contains($0.lowercased().prefix(4)) }
            .prefix(3)
        
        return similar.joined(separator: ", ")
    }
    
    // MARK: - write_file
    
    private func executeWriteFile(_ call: AgentToolCall, projectURL: URL) -> AgentToolResult {
        guard let relativePath = call.arguments.path, !relativePath.isEmpty else {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false, output: "", error: "Missing 'path' argument")
        }
        
        guard let content = call.arguments.content else {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false, output: "", error: "Missing 'content' argument")
        }
        
        guard let fileURL = resolveAndValidate(relativePath, projectURL: projectURL) else {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false, output: "", error: "Path is outside the project folder")
        }
        
        let logger = DebugLogger.shared
        
        do {
            // Create parent directories if needed
            let parentDir = fileURL.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: parentDir.path) {
                try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
                logger.debug("[Tool:write_file] Created parent directory: \(parentDir.lastPathComponent)", category: .llm)
            }
            
            let existed = fileManager.fileExists(atPath: fileURL.path)
            
            // Safety guard: prevent accidental data loss when overwriting existing files
            // If the new content is <40% the size of the existing file, it's likely the AI
            // only saw a truncated version and is about to destroy data
            if existed {
                let existingData = try Data(contentsOf: fileURL)
                let existingSize = existingData.count
                let newSize = content.utf8.count
                if existingSize > 1000 && newSize < existingSize * 40 / 100 {
                    let shrinkPct = 100 - (newSize * 100 / existingSize)
                    logger.warning("[Tool:write_file] BLOCKED: write would shrink \(relativePath) by \(shrinkPct)% (\(existingSize) → \(newSize) bytes). Use search_replace for targeted edits instead of rewriting the entire file.", category: .llm)
                    return AgentToolResult(
                        callId: call.id, tool: call.tool, success: false, output: "",
                        error: "BLOCKED: This write would shrink \(relativePath) from \(existingSize) to \(newSize) bytes (\(shrinkPct)% data loss). You likely only saw a truncated version of the file. Use search_replace for targeted edits, or re-read the full file with read_file before rewriting."
                    )
                }
            }
            
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            
            let verb = existed ? "Updated" : "Created"
            logger.info("[Tool:write_file] \(verb) \(relativePath) (\(content.count) bytes)", category: .llm)
            return AgentToolResult(callId: call.id, tool: call.tool, success: true, output: "\(verb) \(relativePath) (\(content.count) bytes)")
        } catch {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false, output: "", error: error.localizedDescription)
        }
    }
    
    // MARK: - grep
    
    private func executeGrep(_ call: AgentToolCall, projectURL: URL) -> AgentToolResult {
        guard let pattern = call.arguments.pattern, !pattern.isEmpty else {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false, output: "", error: "Missing 'pattern' argument")
        }
        
        let searchRoot = call.arguments.path ?? ""
        guard let rootURL = resolveAndValidate(searchRoot, projectURL: projectURL) else {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false, output: "", error: "Path is outside the project folder")
        }
        
        let globPattern = call.arguments.glob   // e.g. "*.json"
        
        // Collect files
        var files: [URL] = []
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDir), !isDir.boolValue {
            // Single file
            files = [rootURL]
        } else {
            files = collectFiles(at: rootURL, glob: globPattern)
        }
        
        // Search each file (OpenCode limits to 100 matches)
        var matches: [(file: String, lineNum: Int, line: String)] = []
        let maxMatches = 100
        
        let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        
        for file in files {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: .newlines)
            
            for (i, line) in lines.enumerated() {
                let matched: Bool
                if let regex {
                    matched = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
                } else {
                    matched = line.localizedCaseInsensitiveContains(pattern)
                }
                
                if matched {
                    let relativePath = file.path.replacingOccurrences(of: projectURL.path + "/", with: "")
                    matches.append((file: relativePath, lineNum: i + 1, line: line))
                    if matches.count >= maxMatches { break }
                }
            }
            if matches.count >= maxMatches { break }
        }
        
        if matches.isEmpty {
            return AgentToolResult(callId: call.id, tool: call.tool, success: true, output: "No files found")
        }
        
        // Format output like OpenCode's grep.ts (grouped by file, line-truncated)
        let truncated = matches.count >= maxMatches
        var output = "Found \(matches.count) matches\n"
        
        var currentFile = ""
        for match in matches {
            if currentFile != match.file {
                if !currentFile.isEmpty { output += "\n" }
                currentFile = match.file
                output += "\(match.file):\n"
            }
            let line = match.line.count > maxLineLength
                ? String(match.line.prefix(maxLineLength)) + "..."
                : match.line
            output += "  Line \(match.lineNum): \(line)\n"
        }
        
        if truncated {
            output += "\n(Results truncated. Use a more specific pattern or path.)"
        }
        
        return AgentToolResult(callId: call.id, tool: call.tool, success: true, output: output.trimmingCharacters(in: .newlines))
    }
    
    // MARK: - search_replace (with OpenCode-style fuzzy matching)
    
    private func executeSearchReplace(_ call: AgentToolCall, projectURL: URL) -> AgentToolResult {
        guard let relativePath = call.arguments.path, !relativePath.isEmpty else {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false, output: "", error: "Missing 'path' argument")
        }
        
        guard let search = call.arguments.search, !search.isEmpty else {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false, output: "", error: "Missing 'search' argument")
        }
        
        guard let replace = call.arguments.replace else {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false, output: "", error: "Missing 'replace' argument")
        }
        
        guard let fileURL = resolveAndValidate(relativePath, projectURL: projectURL) else {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false, output: "", error: "Path is outside the project folder")
        }
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false, output: "", error: "File not found: \(relativePath)")
        }
        
        let logger = DebugLogger.shared
        
        do {
            var content = try String(contentsOf: fileURL, encoding: .utf8)
            let replaceAll = call.arguments.replaceAll ?? false
            
            // --- OpenCode-style fuzzy matching chain ---
            // Try replacers in order from strictest to most flexible.
            // Each replacer returns the actual string found in the file content
            // that matches the AI's search string (which may have whitespace/indentation differences).
            // OpenCode's exact replacer chain from edit.ts (9 replacers, in order):
            let replacerChain: [(name: String, fn: (String, String) -> [String])] = [
                ("exact",                FuzzyReplace.simpleReplacer),           // 1. SimpleReplacer
                ("line-trimmed",         FuzzyReplace.lineTrimmedReplacer),      // 2. LineTrimmedReplacer
                ("json-colon-normalized", FuzzyReplace.jsonColonNormalizedReplacer), // 2.5 JSON colon spacing
                ("block-anchor",         FuzzyReplace.blockAnchorReplacer),      // 3. BlockAnchorReplacer
                ("whitespace-normalized", FuzzyReplace.whitespaceNormalizedReplacer), // 4. WhitespaceNormalizedReplacer
                ("indentation-flexible", FuzzyReplace.indentationFlexibleReplacer),  // 5. IndentationFlexibleReplacer
                ("escape-normalized",    FuzzyReplace.escapeNormalizedReplacer),     // 6. EscapeNormalizedReplacer (NEW)
                ("trimmed-boundary",     FuzzyReplace.trimmedBoundaryReplacer),      // 7. TrimmedBoundaryReplacer
                ("context-aware",        FuzzyReplace.contextAwareReplacer),         // 8. ContextAwareReplacer
                ("multi-occurrence",     FuzzyReplace.multiOccurrenceReplacer),      // 9. MultiOccurrenceReplacer (NEW)
            ]
            
            var matchedSearch: String? = nil
            var usedReplacer: String = "none"
            
            for (name, replacer) in replacerChain {
                let candidates = replacer(content, search)
                
                if candidates.isEmpty { continue }
                
                if replaceAll {
                    // For replaceAll, use the first candidate match string
                    matchedSearch = candidates[0]
                    usedReplacer = name
                    break
                }
                
                // For single replace: need exactly one unique match
                // Filter to candidates that actually exist in content
                let uniqueMatches = candidates.filter { candidate in
                    let firstIdx = content.range(of: candidate)
                    guard firstIdx != nil else { return false }
                    // Check uniqueness: there should be exactly one occurrence
                    let afterFirst = content[firstIdx!.upperBound...]
                    return afterFirst.range(of: candidate) == nil
                }
                
                if uniqueMatches.count == 1 {
                    matchedSearch = uniqueMatches[0]
                    usedReplacer = name
                    break
                }
                
                // If we have matches but they're not unique, try using the first candidate
                // (same as OpenCode: if indexOf !== lastIndexOf, skip to next replacer)
                if candidates.count == 1 {
                    let candidate = candidates[0]
                    // Check if it's unique in content
                    if let firstRange = content.range(of: candidate) {
                        let afterFirst = content[firstRange.upperBound...]
                        if afterFirst.range(of: candidate) == nil {
                            matchedSearch = candidate
                            usedReplacer = name
                            break
                        }
                    }
                }
                
                // Multiple non-unique matches — try next replacer for more specificity
            }
            
            guard let actualSearch = matchedSearch else {
                logger.warning("[Tool:search_replace] Search string NOT FOUND by any replacer in \(relativePath) (\(search.count) char search)", category: .llm)
                
                // Build a helpful error with context
                var errorParts: [String] = ["Search string not found in \(relativePath)."]
                
                // Warn about short search strings — the #1 cause of failures
                if search.count < 30 {
                    errorParts.append("WARNING: Your search string is only \(search.count) chars — too short to uniquely identify content. Include the object's \"id\" and surrounding JSON context (at least 3-5 lines) to make it unique.")
                }
                
                // Find and show nearby content using partial matching
                let nearContent = suggestNearMatch(content: content, search: search)
                if !nearContent.isEmpty {
                    errorParts.append("Nearest matching content in file:\n\(nearContent)")
                }
                
                // Suggest using grep for large files
                if content.count > 80_000 {
                    errorParts.append("This file is large (\(content.count / 1000)K chars). Use the grep tool to find exact property values before search_replace. Example: grep(pattern: \"object_id_here\") to locate the object, then use enough context.")
                }
                
                errorParts.append("Tip: Include the object's \"id\" field + 3-5 surrounding lines in your search string to uniquely identify the target.")
                
                return AgentToolResult(callId: call.id, tool: call.tool, success: false, output: "", error: errorParts.joined(separator: "\n"))
            }
            
            let beforeSize = content.count
            if replaceAll {
                let occurrences = content.components(separatedBy: actualSearch).count - 1
                content = content.replacingOccurrences(of: actualSearch, with: replace)
                
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                
                let afterSize = content.count
                let sizeDelta = afterSize - beforeSize
                logger.info("[Tool:search_replace] Replaced \(occurrences) occurrence(s) in \(relativePath) via '\(usedReplacer)' | size: \(beforeSize)→\(afterSize) (\(sizeDelta >= 0 ? "+" : "")\(sizeDelta) chars)", category: .llm)
                return AgentToolResult(callId: call.id, tool: call.tool, success: true, output: "Replaced \(occurrences) occurrence\(occurrences == 1 ? "" : "s") in \(relativePath)")
            } else {
                if let range = content.range(of: actualSearch) {
                    content.replaceSubrange(range, with: replace)
                }
                
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                
                let afterSize = content.count
                let sizeDelta = afterSize - beforeSize
                logger.info("[Tool:search_replace] Replaced 1 occurrence in \(relativePath) via '\(usedReplacer)' | size: \(beforeSize)→\(afterSize) (\(sizeDelta >= 0 ? "+" : "")\(sizeDelta) chars)", category: .llm)
                return AgentToolResult(callId: call.id, tool: call.tool, success: true, output: "Replaced 1 occurrence in \(relativePath)\(usedReplacer != "exact" ? " (matched via \(usedReplacer))" : "")")
            }
        } catch {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false, output: "", error: error.localizedDescription)
        }
    }
    
    /// Suggest near matches when search_replace fails — helps the AI see what the file actually contains.
    /// Uses partial/substring matching so even short search strings like `"x" : 800` find results.
    private func suggestNearMatch(content: String, search: String) -> String {
        let contentLines = content.components(separatedBy: "\n")
        let trimmedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Strategy 1: Find lines that contain the search string as a substring
        var matches: [(line: Int, text: String)] = []
        for (i, line) in contentLines.enumerated() {
            if line.contains(trimmedSearch) || line.trimmingCharacters(in: .whitespaces).contains(trimmedSearch) {
                // Show 2 lines before and after for context
                let start = max(0, i - 2)
                let end = min(contentLines.count - 1, i + 2)
                let snippet = contentLines[start...end].enumerated().map { offset, l in
                    let lineNum = start + offset + 1
                    return "\(lineNum)|\(l)"
                }.joined(separator: "\n")
                matches.append((line: i + 1, text: snippet))
                if matches.count >= 3 { break } // Show up to 3 matches
            }
        }
        
        if !matches.isEmpty {
            let matchCount = matches.count
            var result = "Found \(matchCount) partial match\(matchCount == 1 ? "" : "es") for \"\(trimmedSearch.prefix(40))\":\n"
            for m in matches {
                result += "--- Near line \(m.line) ---\n\(m.text)\n"
            }
            if matchCount > 1 {
                result += "Multiple matches exist — include the object's \"id\" field + surrounding context to disambiguate."
            }
            return result
        }
        
        // Strategy 2: If the search is multi-line, try matching just the first non-empty line
        let searchLines = search.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if searchLines.count > 1, let firstLine = searchLines.first {
            for (i, line) in contentLines.enumerated() {
                if line.trimmingCharacters(in: .whitespaces) == firstLine {
                    let start = max(0, i - 1)
                    let end = min(contentLines.count - 1, i + min(searchLines.count + 2, 8))
                    let snippet = contentLines[start...end].enumerated().map { offset, l in
                        let lineNum = start + offset + 1
                        return "\(lineNum)|\(l)"
                    }.joined(separator: "\n")
                    return "First line matched at line \(i + 1) but full block didn't match:\n\(snippet)"
                }
            }
        }
        
        // Strategy 3: Try matching key fragments (e.g., property names like "x" from `"x" : 800`)
        // Extract quoted strings from the search to use as fragments
        let quotePattern = try? NSRegularExpression(pattern: "\"([^\"]+)\"", options: [])
        let nsSearch = trimmedSearch as NSString
        let quoteMatches = quotePattern?.matches(in: trimmedSearch, range: NSRange(location: 0, length: nsSearch.length)) ?? []
        
        for qm in quoteMatches {
            let fragment = nsSearch.substring(with: qm.range)
            // Skip very common fragments
            if ["\"type\"", "\"id\"", "\"name\""].contains(fragment) { continue }
            
            for (i, line) in contentLines.enumerated() {
                if line.contains(fragment) {
                    let start = max(0, i - 1)
                    let end = min(contentLines.count - 1, i + 3)
                    let snippet = contentLines[start...end].enumerated().map { offset, l in
                        let lineNum = start + offset + 1
                        return "\(lineNum)|\(l)"
                    }.joined(separator: "\n")
                    return "Found \"\(fragment)\" at line \(i + 1) (actual content differs from search):\n\(snippet)"
                }
            }
        }
        
        return ""
    }
    
    // MARK: - project_info
    
    private func executeProjectInfo(_ call: AgentToolCall, project: Project, projectURL: URL) -> AgentToolResult {
        // Scan project.json once for object ID → line number mapping.
        // This lets the AI jump directly to the right line instead of reading sequentially.
        let lineMap = objectLineNumbers(projectURL: projectURL)
        
        var info = "Project: \"\(project.name)\"\n"
        info += "Location: \(projectURL.path)\n"
        info += "Canvas: \(Int(project.canvas.width))x\(Int(project.canvas.height)) @\(project.canvas.fps)fps\n"
        info += "Architecture: Single-file (all scenes embedded in project.json)\n"
        info += "Scenes (\(project.sceneCount)):\n"
        
        // Collect objects grouped by type for the summary section
        var objectsByType: [String: [(sceneName: String, obj: SceneObject, line: Int?)]] = [:]
        
        for (i, scene) in project.orderedScenes.enumerated() {
            info += "  \(i + 1). \"\(scene.name)\" (id: \(scene.id), \(String(format: "%.1f", scene.duration))s, \(scene.objectCount) objects)\n"
            
            // List objects with key details including line numbers
            for (j, obj) in scene.objects.enumerated() {
                let pos = "(\(Int(obj.properties.x)),\(Int(obj.properties.y)))"
                let size = "\(Int(obj.properties.width))x\(Int(obj.properties.height))"
                let lineNum = lineMap[obj.id.uuidString]
                let lineStr = lineNum != nil ? " @line:\(lineNum!)" : ""
                var objLine = "     \(j + 1). \"\(obj.name)\" [\(obj.type.rawValue)] id:\(obj.id.uuidString) pos:\(pos) size:\(size) z:\(obj.zIndex)\(lineStr)"
                
                if let text = obj.properties.text {
                    objLine += " text:\"\(text.prefix(30))\""
                }
                
                if !obj.animations.isEmpty {
                    let animSummary = obj.animations.map { "\($0.type.rawValue)(\(String(format: "%.1f", $0.startTime))s-\(String(format: "%.1f", $0.startTime + $0.duration))s)" }
                    objLine += " anims:[\(animSummary.joined(separator: ","))]"
                }
                
                if let dep = obj.timingDependency {
                    objLine += " depends:\(dep.dependsOn.uuidString.prefix(8))(\(dep.trigger.rawValue),gap:\(String(format: "%.1f", dep.gap)))"
                }
                
                info += objLine + "\n"
                
                // Track by type
                let typeKey = obj.type.rawValue
                objectsByType[typeKey, default: []].append((sceneName: scene.name, obj: obj, line: lineNum))
            }
        }
        
        if !project.transitions.isEmpty {
            info += "Transitions:\n"
            for t in project.transitions {
                let fromName = project.scene(withId: t.fromSceneId)?.name ?? t.fromSceneId
                let toName = project.scene(withId: t.toSceneId)?.name ?? t.toSceneId
                info += "  \"\(fromName)\" → \"\(toName)\": \(t.type.rawValue) (\(String(format: "%.1f", t.duration))s)\n"
            }
        }
        
        // --- Objects grouped by type (for quick type-based editing) ---
        info += "\nObjects by type:\n"
        for (type, objects) in objectsByType.sorted(by: { $0.key < $1.key }) {
            info += "  [\(type)] (\(objects.count) objects):\n"
            for entry in objects {
                let lineStr = entry.line != nil ? " @line:\(entry.line!)" : ""
                info += "    - \"\(entry.obj.name)\" in \"\(entry.sceneName)\"\(lineStr)\n"
            }
        }
        
        // --- CRUD Workflow ---
        info += "\n--- CRUD Workflow (ALWAYS use this for ALL project.json changes) ---\n"
        info += "Step 1 — INSPECT: query_objects(type:\"text\") → returns EVERY property with full details.\n"
        info += "Step 2 — MODIFY: update_object(id:\"UUID\", properties:{...}) → surgically updates properties.\n"
        info += "• Handles ANY nesting: simple values, nested color objects, arrays, booleans.\n"
        info += "  Simple: {\"x\": 540, \"fontSize\": 48, \"text\": \"Hello\"}\n"
        info += "  Nested: {\"fillColor\": {\"red\":1,\"green\":0,\"blue\":0,\"alpha\":1}}\n"
        info += "  Mixed:  {\"shadowColor\":{\"red\":0,\"green\":0,\"blue\":0,\"alpha\":0.5}, \"shadowRadius\":10}\n"
        info += "  Object-level: {\"name\":\"Title\", \"isVisible\":true, \"zIndex\":5}\n"
        info += "• Animations: update_object(id:\"OBJ-UUID\", properties:{\"animations\":[{\"type\":\"fadeIn\",\"startTime\":5,\"duration\":0.5}]})\n"
        info += "  REPLACES the entire animations array. Use this to shift timing (change startTime values).\n"
        info += "• Scene properties: update_object(id:\"SCENE-UUID\", properties:{\"duration\":20.0})\n"
        info += "  Pass the scene's UUID to update duration, name, or backgroundColor.\n"
        info += "  IMPORTANT: When inserting slides/segments, ALWAYS use shift_timeline FIRST to push existing content forward, then create new objects in the gap. NEVER manually shift animations with update_object.\n"
        info += "  Example: shift_timeline(scene_id:\"SCENE-UUID\", after_time:12.0, shift_amount:3.0) → pushes everything at ≥12s forward by 3s and extends duration.\n"
        info += "• Transitions: query_objects(type:\"transition\") → shows all transitions with IDs.\n"
        info += "  update_object(id:\"TRANSITION-UUID\", properties:{\"type\":\"slideLeft\", \"duration\":1.0})\n"
        info += "  Types: crossfade, slideLeft, slideRight, slideUp, slideDown, wipe, zoom, dissolve, none\n"
        info += "• NEVER use search_replace for object/scene/transition changes. update_object uses full JSON parsing and cannot corrupt the file.\n"
        info += "Available object types: rectangle, circle, ellipse, polygon, line, text, icon, image, path, model3D, shader\n"
        
        // Valid easing types (complete list — AI must use ONLY these exact names)
        info += "\nValid easing types (use ONLY these exact names in animations):\n"
        info += "  " + EasingType.allCases.map { $0.rawValue }.joined(separator: ", ") + "\n"
        info += "  Parametric: cubicBezier(x1,y1,x2,y2), steps(n), springCustom(stiffness,damping,mass)\n"
        info += "  ⚠️ NEVER invent names like 'easeOutElastic' or 'easeOutBounce' — they do NOT exist.\n"
        
        // Valid animation types (complete list)
        info += "\nValid animation types (use ONLY these exact names):\n"
        info += "  " + AnimationType.allCases.map { $0.rawValue }.joined(separator: ", ") + "\n"
        
        // --- Transitions ---
        if !project.transitions.isEmpty {
            let sceneNames = Dictionary(uniqueKeysWithValues: project.orderedScenes.map { ($0.id, $0.name) })
            info += "\nTransitions (\(project.transitions.count)):\n"
            for t in project.transitions {
                let fromName = sceneNames[t.fromSceneId] ?? t.fromSceneId
                let toName = sceneNames[t.toSceneId] ?? t.toSceneId
                info += "  \"\(fromName)\" → \"\(toName)\": \(t.type.rawValue) (\(t.duration)s) id=\(t.id.uuidString)\n"
            }
        }
        
        // File tree
        info += "\nFile structure:\n"
        info += buildTree(at: projectURL, projectURL: projectURL, indent: "")
        
        return AgentToolResult(callId: call.id, tool: call.tool, success: true, output: info.trimmingCharacters(in: .newlines))
    }
    
    /// Scans project.json and builds a map of object ID → line number.
    /// This allows project_info to include exact line references so the AI
    /// can jump directly to any object with read_file(offset:LINE, limit:50).
    private func objectLineNumbers(projectURL: URL) -> [String: Int] {
        let fileURL = projectURL.appendingPathComponent("project.json")
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return [:] }
        
        let lines = content.components(separatedBy: "\n")
        var result: [String: Int] = [:]
        
        // Scan for "id" : "UUID" patterns — each object has a unique UUID
        // The regex matches the JSON id field pattern used by Swift's JSONEncoder
        let idPattern = try? NSRegularExpression(pattern: #""id"\s*:\s*"([0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12})""#, options: [])
        
        for (i, line) in lines.enumerated() {
            guard let regex = idPattern else { continue }
            let nsLine = line as NSString
            if let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) {
                let uuid = nsLine.substring(with: match.range(at: 1))
                result[uuid] = i + 1  // 1-based line number
            }
        }
        
        return result
    }
    
    // MARK: - update_object (CRUD: structural JSON update)
    
    /// Update specific properties on a scene object by ID.
    /// Uses full JSON parsing (JSONSerialization) for robust handling of ANY property
    /// structure — nested objects (shadowColor, fillColor), arrays, primitives, etc.
    /// Re-serializes with .prettyPrinted + .sortedKeys to match JSONEncoder output.
    private func executeUpdateObject(_ call: AgentToolCall, projectURL: URL) -> AgentToolResult {
        guard let objectId = call.arguments.objectId, !objectId.isEmpty else {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false,
                                  output: "", error: "Missing 'id' argument. Provide the object's UUID.")
        }
        guard let propsDict = call.arguments.properties, !propsDict.isEmpty else {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false,
                                  output: "", error: "Missing 'properties' argument. Provide a JSON object of property:value pairs.")
        }
        
        let fileURL = projectURL.appendingPathComponent("project.json")
        guard let data = try? Data(contentsOf: fileURL) else {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false,
                                  output: "", error: "Could not read project.json")
        }
        
        // Parse the entire JSON into a mutable structure
        guard var root = try? JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String: Any] else {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false,
                                  output: "", error: "Could not parse project.json as JSON dictionary.")
        }
        
        // Normalize LLM values: the LLM often sends numbers as strings (e.g. "0.4" instead of 0.4).
        // Without this, JSONDecoder would fail to decode them later.
        let normalizedProps = Self.normalizeJSONValues(propsDict) as? [String: Any] ?? propsDict
        
        // Log the incoming properties for debugging
        let propsPreview = normalizedProps.map { key, val in
            let valStr: String
            if let dict = val as? [String: Any] {
                valStr = "{\(dict.keys.sorted().joined(separator: ","))}"
            } else {
                valStr = "\(val)"
            }
            return "\(key)=\(valStr)"
        }.joined(separator: ", ")
        DebugLogger.shared.debug("[Tool:update_object] \(objectId.prefix(8))... props: \(propsPreview)", category: .llm)
        
        // Recursively find the object by UUID and update its properties
        var updatedKeys: [String] = []
        let found = Self.findAndUpdateObject(
            in: &root,
            objectId: objectId,
            newProperties: normalizedProps,
            updatedKeys: &updatedKeys
        )
        
        guard found else {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false,
                                  output: "", error: "Object with ID '\(objectId)' not found in project.json.")
        }
        
        // Re-serialize with the same formatting as JSONEncoder uses
        let writeOptions: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys]
        guard let outputData = try? JSONSerialization.data(withJSONObject: root, options: writeOptions) else {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false,
                                  output: "", error: "Failed to serialize updated JSON.")
        }
        
        // Log file size delta for debugging
        let originalSize = data.count
        let newSize = outputData.count
        DebugLogger.shared.debug("[Tool:update_object] File: \(originalSize) → \(newSize) bytes (delta: \(newSize - originalSize))", category: .llm)
        
        // Validate & re-encode: ensure the file can be decoded by JSONDecoder.
        // If JSONSerialization roundtrip introduced type issues (e.g. invalid easing strings),
        // attempt to decode → re-encode with JSONEncoder (which preserves all types correctly).
        // This is the safety net that prevents project corruption.
        let validator = JSONDecoder()
        validator.dateDecodingStrategy = .iso8601
        let finalData: Data
        do {
            let project = try validator.decode(Project.self, from: outputData)
            // Great — roundtrip succeeded. Re-encode with JSONEncoder for consistent formatting.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            finalData = (try? encoder.encode(project)) ?? outputData
        } catch {
            let reason = Self.describeDecodeFailure(error)
            DebugLogger.shared.warning("[Tool:update_object] Aborting write: updated JSON failed Project decode (\(reason))", category: .llm)
            return AgentToolResult(
                callId: call.id,
                tool: call.tool,
                success: false,
                output: "",
                error: "Update rejected to prevent project corruption. Invalid typed data after update: \(reason)"
            )
        }
        
        // Write back
        do {
            try finalData.write(to: fileURL, options: .atomic)
        } catch {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false,
                                  output: "", error: "Failed to write project.json: \(error.localizedDescription)")
        }
        
        var output = "✓ Updated \(updatedKeys.count) properties on object \(objectId):\n"
        output += updatedKeys.map { "  • \($0)" }.joined(separator: ", ")
        output += "\nNo verification needed — changes are live."
        
        return AgentToolResult(callId: call.id, tool: call.tool, success: true, output: output)
    }
    
    /// Recursively search the JSON tree for an entity with the given UUID,
    /// then merge `newProperties` into it. Handles both:
    /// - SceneObjects (has "properties" sub-dict → property keys go inside it)
    /// - Transitions/other entities (no "properties" sub-dict → all keys at top level)
    @discardableResult
    private static func findAndUpdateObject(
        in json: inout [String: Any],
        objectId: String,
        newProperties: [String: Any],
        updatedKeys: inout [String]
    ) -> Bool {
        // Check if THIS dictionary is the target entity
        if let id = json["id"] as? String, id == objectId {
            if var props = json["properties"] as? [String: Any] {
                // SceneObject: has "properties" sub-dict → route keys appropriately
                // These keys live at the object level (outside "properties"):
                let objectLevelKeys: Set<String> = [
                    "name", "isVisible", "zIndex", "type",
                    "animations", "timingDependency"
                ]
                for (key, value) in newProperties {
                    if objectLevelKeys.contains(key) {
                        json[key] = value
                    } else {
                        props[key] = value
                    }
                    if !updatedKeys.contains(key) { updatedKeys.append(key) }
                }
                json["properties"] = props
            } else {
                // Transition / Scene / other entity: no "properties" sub-dict.
                // ALL keys go directly on the entity.
                for (key, value) in newProperties {
                    json[key] = value
                    if !updatedKeys.contains(key) { updatedKeys.append(key) }
                }
            }
            return true
        }
        
        // Recurse into all values that are dicts or arrays
        for key in json.keys {
            if var childDict = json[key] as? [String: Any] {
                if findAndUpdateObject(in: &childDict, objectId: objectId, newProperties: newProperties, updatedKeys: &updatedKeys) {
                    json[key] = childDict
                    return true
                }
            } else if var childArray = json[key] as? [[String: Any]] {
                for i in childArray.indices {
                    if findAndUpdateObject(in: &childArray[i], objectId: objectId, newProperties: newProperties, updatedKeys: &updatedKeys) {
                        json[key] = childArray
                        return true
                    }
                }
            }
        }
        
        return false
    }
    
    /// Recursively normalize JSON values: convert string-encoded numbers to actual numbers,
    /// string-encoded booleans to actual booleans, and fix LLM key name mismatches.
    /// The LLM often sends {"duration": "0.4", "startTime": "15.5"} instead of {duration: 0.4, startTime: 15.5},
    /// and uses wrong key names like "animationType" instead of "type" for animations.
    private static func normalizeJSONValues(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            if let normalizedColor = normalizeColorDictionaryIfNeeded(dict) {
                return normalizedColor
            }
            
            var normalized: [String: Any] = [:]
            for (k, v) in dict {
                // Special handling: if key is "animations" and value is an array,
                // normalize each animation dict's keys and add missing defaults
                if k == "animations", let anims = v as? [[String: Any]] {
                    normalized[k] = anims.map { normalizeAnimationDict($0) }
                } else {
                    normalized[k] = normalizeJSONValues(v)
                }
            }
            return normalized
        }
        
        if let array = value as? [Any] {
            return array.map { normalizeJSONValues($0) }
        }
        
        if let str = value as? String {
            // Don't convert strings that are clearly not numbers (UUIDs, names, enum values, etc.)
            let trimmed = str.trimmingCharacters(in: .whitespaces)
            
            // Boolean strings
            if trimmed == "true" { return true }
            if trimmed == "false" { return false }
            
            // Integer strings (no decimal point)
            if !trimmed.isEmpty, trimmed.allSatisfy({ $0.isNumber || $0 == "-" }) {
                if let intVal = Int(trimmed) {
                    return intVal
                }
            }
            
            // Floating-point strings
            if !trimmed.isEmpty, trimmed.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" || $0 == "e" || $0 == "E" || $0 == "+" }) {
                if trimmed.contains(".") || trimmed.contains("e") || trimmed.contains("E") {
                    if let doubleVal = Double(trimmed) {
                        return doubleVal
                    }
                }
            }
        }
        
        return value
    }
    
    /// Convert color dictionaries from flexible LLM formats into the strict CodableColor shape:
    /// {"red": Double, "green": Double, "blue": Double, "alpha": Double}
    /// Supports:
    /// - {"hex":"#RRGGBB"} / {"hex":"#RRGGBBAA"}
    /// - {"name":"red"}
    /// - {"red":1,"green":0.5,"blue":0.2,"alpha":1}
    /// - {"r":255,"g":128,"b":32,"a":255}
    private static func normalizeColorDictionaryIfNeeded(_ raw: [String: Any]) -> [String: Any]? {
        let loweredToOriginal = Dictionary(uniqueKeysWithValues: raw.keys.map { ($0.lowercased(), $0) })
        let loweredKeys = Set(loweredToOriginal.keys)
        let supportedKeys: Set<String> = ["hex", "name", "red", "green", "blue", "alpha", "r", "g", "b", "a"]
        let hasColorHint = !loweredKeys.intersection(supportedKeys).isEmpty
        let hasOnlyColorKeys = loweredKeys.subtracting(supportedKeys).isEmpty
        guard hasColorHint, hasOnlyColorKeys else { return nil }
        
        // 1) Hex first (most common from prompt examples)
        if let hexKey = loweredToOriginal["hex"], let hex = raw[hexKey] as? String, !hex.isEmpty {
            var color = colorFromHex(hex)
            if let alpha = extractColorComponent(raw, loweredMap: loweredToOriginal, keys: ["alpha", "a"]) {
                color.alpha = alpha
            }
            return ["red": color.red, "green": color.green, "blue": color.blue, "alpha": color.alpha]
        }
        
        // 2) Named colors
        if let nameKey = loweredToOriginal["name"], let rawName = raw[nameKey] as? String {
            var color = namedColor(rawName)
            if let alpha = extractColorComponent(raw, loweredMap: loweredToOriginal, keys: ["alpha", "a"]) {
                color.alpha = alpha
            }
            return ["red": color.red, "green": color.green, "blue": color.blue, "alpha": color.alpha]
        }
        
        // 3) RGB(A) numeric channels
        if let red = extractColorComponent(raw, loweredMap: loweredToOriginal, keys: ["red", "r"]),
           let green = extractColorComponent(raw, loweredMap: loweredToOriginal, keys: ["green", "g"]),
           let blue = extractColorComponent(raw, loweredMap: loweredToOriginal, keys: ["blue", "b"]) {
            let alpha = extractColorComponent(raw, loweredMap: loweredToOriginal, keys: ["alpha", "a"]) ?? 1.0
            return ["red": red, "green": green, "blue": blue, "alpha": alpha]
        }
        
        // If it looked like a color dict but we couldn't parse it safely, leave as-is so validator can reject.
        return raw
    }
    
    private static func extractColorComponent(
        _ raw: [String: Any],
        loweredMap: [String: String],
        keys: [String]
    ) -> Double? {
        for key in keys {
            guard let originalKey = loweredMap[key] else { continue }
            let value = raw[originalKey]
            if let double = anyToDoubleOptional(value) {
                return normalizeColorChannel(double)
            }
        }
        return nil
    }
    
    private static func anyToDoubleOptional(_ val: Any?) -> Double? {
        guard let val else { return nil }
        if let n = val as? NSNumber { return n.doubleValue }
        if let i = val as? Int { return Double(i) }
        if let d = val as? Double { return d }
        if let s = val as? String, let d = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) { return d }
        return nil
    }
    
    /// Accept 0...1 or 0...255 and clamp.
    private static func normalizeColorChannel(_ value: Double) -> Double {
        let normalized = value > 1.0 ? value / 255.0 : value
        return min(max(normalized, 0.0), 1.0)
    }
    
    private static func colorFromHex(_ hex: String) -> CodableColor {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized = sanitized.replacingOccurrences(of: "#", with: "")
        
        // Expand shorthand #RGB / #RGBA into #RRGGBB / #RRGGBBAA
        if sanitized.count == 3 || sanitized.count == 4 {
            sanitized = sanitized.map { "\($0)\($0)" }.joined()
        }
        
        var rgba: UInt64 = 0
        guard Scanner(string: sanitized).scanHexInt64(&rgba) else {
            return .white
        }
        
        switch sanitized.count {
        case 8:
            let r = Double((rgba & 0xFF000000) >> 24) / 255.0
            let g = Double((rgba & 0x00FF0000) >> 16) / 255.0
            let b = Double((rgba & 0x0000FF00) >> 8) / 255.0
            let a = Double(rgba & 0x000000FF) / 255.0
            return CodableColor(red: r, green: g, blue: b, alpha: a)
        case 6:
            return CodableColor.fromHex("#\(sanitized)")
        default:
            return .white
        }
    }
    
    private static func namedColor(_ name: String) -> CodableColor {
        switch name.lowercased() {
        case "red": return .red
        case "green": return .green
        case "blue": return .blue
        case "white": return .white
        case "black": return .black
        case "yellow": return .yellow
        case "orange": return .orange
        case "purple": return .purple
        case "pink": return .pink
        case "cyan": return .cyan
        case "clear": return .clear
        default: return .white
        }
    }
    
    private static func describeDecodeFailure(_ error: Error) -> String {
        switch error {
        case let DecodingError.typeMismatch(_, context):
            return "type mismatch at \(codingPathString(context.codingPath)): \(context.debugDescription)"
        case let DecodingError.valueNotFound(_, context):
            return "value missing at \(codingPathString(context.codingPath)): \(context.debugDescription)"
        case let DecodingError.keyNotFound(key, context):
            return "missing key '\(key.stringValue)' at \(codingPathString(context.codingPath)): \(context.debugDescription)"
        case let DecodingError.dataCorrupted(context):
            return "data corrupted at \(codingPathString(context.codingPath)): \(context.debugDescription)"
        default:
            return error.localizedDescription
        }
    }
    
    private static func codingPathString(_ path: [CodingKey]) -> String {
        if path.isEmpty { return "root" }
        return path.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
    }
    
    /// Normalize an animation dictionary from the LLM:
    /// - Fix key name mismatches (animationType → type, start → startTime, repeat → repeatCount)
    /// - Convert string-encoded numbers to actual numbers
    /// - Add missing required fields with defaults (id, keyframes, easing, etc.)
    /// - Populate default keyframes when empty (critical: empty keyframes → interpolation returns 0 → objects invisible)
    private static func normalizeAnimationDict(_ raw: [String: Any]) -> [String: Any] {
        // Key mappings: LLM common names → AnimationDefinition Codable keys
        // ALL keys must be lowercase since we look up via k.lowercased()
        let keyMap: [String: String] = [
            "animationtype": "type",       // animationType → type
            "animation_type": "type",
            "start": "startTime",
            "starttime": "startTime",      // startTime → startTime (identity via lowercase)
            "start_time": "startTime",
            "repeat": "repeatCount",
            "repeatcount": "repeatCount",  // repeatCount → repeatCount
            "repeat_count": "repeatCount",
            "autoreverse": "autoReverse",  // autoReverse → autoReverse
            "auto_reverse": "autoReverse",
            "fromvalue": "fromValue",
            "from_value": "fromValue",
            "tovalue": "toValue",
            "to_value": "toValue",
        ]
        
        var normalized: [String: Any] = [:]
        
        // Remap keys and normalize values
        for (k, v) in raw {
            let canonicalKey = keyMap[k.lowercased()] ?? k
            normalized[canonicalKey] = normalizeJSONValues(v)
        }
        
        // Add required fields with defaults if missing
        if normalized["id"] == nil {
            normalized["id"] = UUID().uuidString
        }
        if normalized["keyframes"] == nil {
            normalized["keyframes"] = [] as [Any]
        }
        if normalized["easing"] == nil {
            normalized["easing"] = "easeInOut"
        }
        if normalized["repeatCount"] == nil {
            normalized["repeatCount"] = 0
        }
        if normalized["autoReverse"] == nil {
            normalized["autoReverse"] = false
        }
        if normalized["delay"] == nil {
            normalized["delay"] = 0.0
        }
        if normalized["startTime"] == nil {
            normalized["startTime"] = 0.0
        }
        if normalized["duration"] == nil {
            normalized["duration"] = 1.0
        }
        
        // CRITICAL FIX: Populate keyframes when empty.
        // The LLM always sends keyframes:[] (empty) because it can't reconstruct the complex
        // nested Keyframe structure. Without keyframes, the rendering engine's
        // interpolateKeyframes() returns 0 — making materialFade=0 (invisible),
        // scaleUp3D=0 (zero scale), etc. The 3D model effectively disappears.
        let kfArray = normalized["keyframes"] as? [Any] ?? []
        if kfArray.isEmpty {
            // Strategy 1: Convert fromValue/toValue to keyframes (LLM sometimes provides these)
            if let fromVal = normalized["fromValue"], let toVal = normalized["toValue"] {
                let fromDouble = anyToDouble(fromVal)
                let toDouble = anyToDouble(toVal)
                normalized["keyframes"] = [
                    ["id": UUID().uuidString, "time": 0.0, "value": ["type": "double", "doubleValue": fromDouble]],
                    ["id": UUID().uuidString, "time": 1.0, "value": ["type": "double", "doubleValue": toDouble]]
                ]
            }
            // Strategy 2: Use AnimationEngine's default keyframes for the type
            else if let typeStr = normalized["type"] as? String,
                    let animType = AnimationType(rawValue: typeStr) {
                let defaults = AnimationEngine().defaultKeyframes(for: animType)
                if !defaults.isEmpty {
                    normalized["keyframes"] = defaults.map { keyframeToDictionary($0) }
                }
            }
        }
        
        // Guard against a common LLM corruption pattern:
        // type="scale" with keyframes using double 0->0 (or scale 0->0),
        // which keeps objects permanently invisible.
        if let typeStr = normalized["type"] as? String, typeStr == "scale",
           let keyframes = normalized["keyframes"] as? [[String: Any]],
           isDegenerateZeroScaleKeyframes(keyframes) {
            let defaults = AnimationEngine().defaultKeyframes(for: .scale)
            if !defaults.isEmpty {
                normalized["keyframes"] = defaults.map { keyframeToDictionary($0) }
                DebugLogger.shared.warning(
                    "[Tool:update_object] Replaced degenerate scale keyframes (0->0) with safe defaults",
                    category: .llm
                )
            }
        }
        
        // Clean up fromValue/toValue — they're NOT fields on AnimationDefinition
        // and would be silently dropped by JSONDecoder, losing the data.
        normalized.removeValue(forKey: "fromValue")
        normalized.removeValue(forKey: "toValue")
        
        // CRITICAL: Validate easing values. The LLM often sends invalid easing names
        // like "easeOutElastic" (correct: "elastic") or "easeOutBounce" (correct: "bounce").
        // Invalid easing values cause JSONDecoder to fail, corrupting the entire project.
        if let easingStr = normalized["easing"] as? String {
            if EasingType(rawValue: easingStr) == nil {
                // Try common LLM mistakes: strip "easeOut"/"easeIn" prefix and check base name
                let lowered = easingStr.lowercased()
                let fixedEasing: String? = {
                    // Map common LLM hallucinated names to valid rawValues
                    let easingFixes: [String: String] = [
                        "easeoutelastic": "elastic",
                        "easeinelastic": "elastic",
                        "easeinoutelastic": "elastic",
                        "easeoutbounce": "bounce",
                        "easeinbounce": "bounce",
                        "easeinoutbounce": "bounce",
                        "easeoutspring": "spring",
                        "easeinspring": "spring",
                        "easeinoutspring": "spring",
                        "easeoutsmooth": "smooth",
                        "easeoutsharp": "sharp",
                        "easeoutpunch": "punch",
                    ]
                    if let fix = easingFixes[lowered] { return fix }
                    // Fallback: try case-insensitive match against all valid rawValues
                    return EasingType.allCases.first(where: { $0.rawValue.lowercased() == lowered })?.rawValue
                }()
                if let fixed = fixedEasing {
                    DebugLogger.shared.debug("[Tool:update_object] Fixed invalid easing '\(easingStr)' → '\(fixed)'", category: .llm)
                    normalized["easing"] = fixed
                } else {
                    DebugLogger.shared.warning("[Tool:update_object] Unknown easing '\(easingStr)', defaulting to 'easeInOut'", category: .llm)
                    normalized["easing"] = "easeInOut"
                }
            }
        }
        
        // Validate animation type. The LLM may send invalid type names that would
        // cause JSONDecoder to fail when decoding AnimationType.
        if let typeStr = normalized["type"] as? String {
            if AnimationType(rawValue: typeStr) == nil {
                // Try case-insensitive match first
                let lowered = typeStr.lowercased()
                let fixedType: String? = {
                    // Map common LLM mistakes to valid rawValues
                    let typeFixes: [String: String] = [
                        "fadein": "fadeIn",
                        "fadeout": "fadeOut",
                        "movex": "moveX",
                        "movey": "moveY",
                        "scalex": "scaleX",
                        "scaley": "scaleY",
                        "slidein": "slideIn",
                        "slideout": "slideOut",
                        "blurin": "blurIn",
                        "blurout": "blurOut",
                        "wipein": "wipeIn",
                        "wipeout": "wipeOut",
                        "clipin": "clipIn",
                        "dropin": "dropIn",
                        "riseup": "riseUp",
                        "swingin": "swingIn",
                        "elasticin": "elasticIn",
                        "elasticout": "elasticOut",
                        "snapin": "snapIn",
                        "whipin": "whipIn",
                        "zoomblur": "zoomBlur",
                        "charbychar": "charByChar",
                        "wordbyword": "wordByWord",
                        "linebyline": "lineByLine",
                        "glitchtext": "glitchText",
                        "splitreveal": "splitReveal",
                        "squashstretch": "squashStretch",
                        "followthrough": "followThrough",
                        "colorchange": "colorChange",
                        "camerazoom": "cameraZoom",
                        "camerapan": "cameraPan",
                        "cameraorbit": "cameraOrbit",
                        "camerashake": "cameraShake",
                        "camerarise": "cameraRise",
                        "cameradive": "cameraDive",
                        "cameraslide": "cameraSlide",
                        "cameraarc": "cameraArc",
                        "camerawhippan": "cameraWhipPan",
                        "materialfade": "materialFade",
                        "scaleup3d": "scaleUp3D",
                        "scaledown3d": "scaleDown3D",
                        "springbounce3d": "springBounce3D",
                        "slamdown3d": "slamDown3D",
                        "elasticspin": "elasticSpin",
                        "breathe3d": "breathe3D",
                        "popin3d": "popIn3D",
                        "rotate3dx": "rotate3DX",
                        "rotate3dy": "rotate3DY",
                        "rotate3dz": "rotate3DZ",
                        "orbit3d": "orbit3D",
                        "wobble3d": "wobble3D",
                        "flip3d": "flip3D",
                        "float3d": "float3D",
                        "swing3d": "swing3D",
                        "jelly3d": "jelly3D",
                        "heartbeat3d": "heartbeat3D",
                        "boomerang3d": "boomerang3D",
                        "glitchjitter3d": "glitchJitter3D",
                        "staggerfadein": "staggerFadeIn",
                        "staggerslideup": "staggerSlideUp",
                        "staggerscalein": "staggerScaleIn",
                        "scalerotatein": "scaleRotateIn",
                        "scalerotateout": "scaleRotateOut",
                        "blurslidein": "blurSlideIn",
                        "blurslideout": "blurSlideOut",
                        "flipreveal": "flipReveal",
                        "fliphide": "flipHide",
                        "elasticslidein": "elasticSlideIn",
                        "spiralin": "spiralIn",
                        "spiralout": "spiralOut",
                        "foldup": "foldUp",
                        "neonflicker": "neonFlicker",
                        "glowpulse": "glowPulse",
                        "morphpulse": "morphPulse",
                        "orbit2d": "orbit2D",
                        "textwave": "textWave",
                        "textrainbow": "textRainbow",
                        "textbouncein": "textBounceIn",
                        "textelasticin": "textElasticIn",
                        "trimpath": "trimPath",
                        "brightnessanim": "brightnessAnim",
                        "contrastanim": "contrastAnim",
                        "saturationanim": "saturationAnim",
                        "huerotate": "hueRotate",
                        "grayscaleanim": "grayscaleAnim",
                        "shadowanim": "shadowAnim",
                    ]
                    if let fix = typeFixes[lowered] { return fix }
                    // Try case-insensitive match against all valid rawValues
                    return AnimationType.allCases.first(where: { $0.rawValue.lowercased() == lowered })?.rawValue
                }()
                if let fixed = fixedType {
                    DebugLogger.shared.debug("[Tool:update_object] Fixed invalid animation type '\(typeStr)' → '\(fixed)'", category: .llm)
                    normalized["type"] = fixed
                } else {
                    DebugLogger.shared.warning("[Tool:update_object] Unknown animation type '\(typeStr)' — keeping as-is", category: .llm)
                }
            }
        }
        
        // Remove unknown fields that aren't part of AnimationDefinition.
        // Extra keys like "intensity" would be silently dropped by JSONDecoder
        // but could cause issues with JSONSerialization roundtrips.
        let validAnimationKeys: Set<String> = [
            "id", "type", "startTime", "duration", "easing", "keyframes",
            "repeatCount", "autoReverse", "delay"
        ]
        for key in normalized.keys where !validAnimationKeys.contains(key) {
            normalized.removeValue(forKey: key)
        }
        
        return normalized
    }
    
    /// Convert a Keyframe struct to a JSON-compatible dictionary matching KeyframeValue's Codable format.
    private static func keyframeToDictionary(_ kf: Keyframe) -> [String: Any] {
        var dict: [String: Any] = [
            "id": kf.id.uuidString,
            "time": kf.time
        ]
        switch kf.value {
        case .double(let d):
            dict["value"] = ["type": "double", "doubleValue": d]
        case .point(let x, let y):
            dict["value"] = ["type": "point", "pointX": x, "pointY": y]
        case .scale(let x, let y):
            dict["value"] = ["type": "scale", "scaleX": x, "scaleY": y]
        case .color(let c):
            dict["value"] = ["type": "color", "color": ["red": c.red, "green": c.green, "blue": c.blue, "alpha": c.alpha]]
        }
        return dict
    }
    
    /// Convert Any value to Double — handles NSNumber, Int, Double, and String representations.
    private static func anyToDouble(_ val: Any) -> Double {
        if let n = val as? NSNumber { return n.doubleValue }
        if let i = val as? Int { return Double(i) }
        if let d = val as? Double { return d }
        if let s = val as? String, let d = Double(s) { return d }
        return 0.0
    }
    
    /// Detect keyframe sets where every scale value is effectively zero.
    /// Handles both malformed .double keyframes and proper .scale payloads.
    private static func isDegenerateZeroScaleKeyframes(_ keyframes: [[String: Any]]) -> Bool {
        guard !keyframes.isEmpty else { return false }
        
        var sawScaleValue = false
        for kf in keyframes {
            guard let value = kf["value"] as? [String: Any] else { continue }
            if let valueType = value["type"] as? String, valueType == "double" {
                let d = anyToDouble(value["doubleValue"] as Any)
                sawScaleValue = true
                if abs(d) > 0.0001 { return false }
            } else {
                let sx = anyToDouble(value["scaleX"] as Any)
                let sy = anyToDouble(value["scaleY"] as Any)
                sawScaleValue = true
                if abs(sx) > 0.0001 || abs(sy) > 0.0001 { return false }
            }
        }
        
        return sawScaleValue
    }
    
    // MARK: - shift_timeline (bulk animation time shift)
    
    /// Shift ALL animations at or after a given time forward (or backward) in a scene.
    /// Uses safe Codable encoding/decoding — avoids JSONSerialization roundtrip that can corrupt types.
    /// This is the correct tool for inserting new slides: shift existing content, then create new objects in the gap.
    private func executeShiftTimeline(_ call: AgentToolCall, projectURL: URL) -> AgentToolResult {
        guard let sceneId = call.arguments.sceneId, !sceneId.isEmpty else {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false,
                                  output: "", error: "Missing 'scene_id' argument. Provide the scene's UUID from project_info.")
        }
        guard let afterTime = call.arguments.afterTime else {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false,
                                  output: "", error: "Missing 'after_time' argument. Provide the time threshold in seconds.")
        }
        guard let shiftAmount = call.arguments.shiftAmount, shiftAmount != 0 else {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false,
                                  output: "", error: "Missing or zero 'shift_amount'. Provide how many seconds to shift (positive = forward).")
        }
        
        let shouldExtendDuration = call.arguments.extendDuration ?? true
        let fileURL = projectURL.appendingPathComponent("project.json")
        
        // Load project using proper Codable decoding (preserves all types correctly)
        guard let data = try? Data(contentsOf: fileURL) else {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false,
                                  output: "", error: "Could not read project.json")
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var project = try? decoder.decode(Project.self, from: data) else {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false,
                                  output: "", error: "Could not decode project.json. The file may be corrupted.")
        }
        
        // Find the target scene
        guard let sceneIndex = project.scenes.firstIndex(where: { $0.id == sceneId }) else {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false,
                                  output: "", error: "Scene with ID '\(sceneId)' not found. Check the UUID from project_info.")
        }
        
        var scene = project.scenes[sceneIndex]
        var totalShifted = 0
        var affectedObjects: [String] = []
        
        // Shift animations on every object in the scene
        for objIdx in scene.objects.indices {
            var obj = scene.objects[objIdx]
            var objectShifted = 0
            
            for animIdx in obj.animations.indices {
                if obj.animations[animIdx].startTime >= afterTime {
                    obj.animations[animIdx].startTime += shiftAmount
                    objectShifted += 1
                }
            }
            
            if objectShifted > 0 {
                affectedObjects.append("\"\(obj.name)\" (\(objectShifted) animations)")
                totalShifted += objectShifted
                scene.objects[objIdx] = obj
            }
        }
        
        // Extend scene duration if requested
        let oldDuration = scene.duration
        if shouldExtendDuration {
            scene.duration += shiftAmount
        }
        
        project.scenes[sceneIndex] = scene
        project.updatedAt = Date()
        
        // Save using proper Codable encoding (preserves EasingType, KeyframeValue, etc.)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let outputData = try? encoder.encode(project) else {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false,
                                  output: "", error: "Failed to encode project after shift.")
        }
        
        do {
            try outputData.write(to: fileURL, options: .atomic)
        } catch {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false,
                                  output: "", error: "Failed to write project.json: \(error.localizedDescription)")
        }
        
        DebugLogger.shared.info("[Tool:shift_timeline] Shifted \(totalShifted) animations on \(affectedObjects.count) objects by \(String(format: "%+.1f", shiftAmount))s (after \(String(format: "%.1f", afterTime))s). Duration: \(String(format: "%.1f", oldDuration))→\(String(format: "%.1f", scene.duration))s", category: .llm)
        
        var output = "✓ Shifted \(totalShifted) animations by \(String(format: "%+.1f", shiftAmount))s (all at or after \(String(format: "%.1f", afterTime))s)\n"
        output += "Affected objects:\n"
        for desc in affectedObjects {
            output += "  • \(desc)\n"
        }
        if shouldExtendDuration {
            output += "Scene duration: \(String(format: "%.1f", oldDuration))s → \(String(format: "%.1f", scene.duration))s\n"
        }
        output += "Timeline is ready — now create new objects in the \(String(format: "%.1f", afterTime))–\(String(format: "%.1f", afterTime + shiftAmount))s gap."
        
        return AgentToolResult(callId: call.id, tool: call.tool, success: true, output: output)
    }
    
    // MARK: - query_objects (CRUD: read objects with filters)
    
    /// Query scene objects with optional type/scene/id filters.
    /// Returns COMPREHENSIVE property details — every nested property is shown.
    /// Uses dual strategy: typed Project model first, JSONSerialization fallback for robustness.
    private func executeQueryObjects(_ call: AgentToolCall, project: Project, projectURL: URL) -> AgentToolResult {
        let typeFilter = call.arguments.objectType
        let nameFilter = call.arguments.objectName
        let sceneFilter = call.arguments.scene
        let idFilter = call.arguments.objectId
        
        // Strategy 1: Try loading typed Project model from disk (fresh data)
        if let loaded = try? ProjectFileService.shared.loadProject(at: projectURL) {
            return queryFromTypedProject(call, project: loaded, typeFilter: typeFilter, nameFilter: nameFilter, sceneFilter: sceneFilter, idFilter: idFilter)
        }
        
        // Strategy 2: Parse raw JSON with JSONSerialization (format-agnostic, always works)
        let fileURL = projectURL.appendingPathComponent("project.json")
        if let data = try? Data(contentsOf: fileURL),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            DebugLogger.shared.info("[Tool:query_objects] Using JSONSerialization fallback (typed model unavailable)", category: .llm)
            return queryFromRawJSON(call, root: root, typeFilter: typeFilter, nameFilter: nameFilter, sceneFilter: sceneFilter, idFilter: idFilter)
        }
        
        // Strategy 3: Last resort — use in-memory model (may be stale)
        DebugLogger.shared.warning("[Tool:query_objects] Both disk strategies failed, using in-memory model", category: .llm)
        return queryFromTypedProject(call, project: project, typeFilter: typeFilter, nameFilter: nameFilter, sceneFilter: sceneFilter, idFilter: idFilter)
    }
    
    // MARK: - Query from typed Project model (rich, comprehensive output)
    
    private func queryFromTypedProject(_ call: AgentToolCall, project: Project, typeFilter: String?, nameFilter: String?, sceneFilter: String?, idFilter: String?) -> AgentToolResult {
        let canvasW = project.canvas.width
        let canvasH = project.canvas.height
        var results: [String] = []
        
        for (sceneIdx, scene) in project.orderedScenes.enumerated() {
            if let sf = sceneFilter, !scene.name.lowercased().contains(sf.lowercased()) { continue }
            
            for obj in scene.objects {
                if let tf = typeFilter, obj.type.rawValue.lowercased() != tf.lowercased() { continue }
                if let nf = nameFilter, !obj.name.lowercased().contains(nf.lowercased()) { continue }
                if let idf = idFilter, obj.id.uuidString != idf { continue }
                
                let p = obj.properties
                var info = "─── \"\(obj.name)\" [\(obj.type.rawValue)] ───\n"
                info += "  ID: \(obj.id.uuidString)\n"
                info += "  Scene: \"\(scene.name)\" (scene \(sceneIdx + 1))\n"
                info += "  Visible: \(obj.isVisible) | zIndex: \(obj.zIndex)\n"
                
                // Transform
                info += "  Position: x=\(p.x), y=\(p.y)\n"
                info += "  Size: width=\(p.width), height=\(p.height)\n"
                info += "  Anchor: (\(p.anchorX), \(p.anchorY))\n"
                info += "  Rotation: \(p.rotation)° | Scale: (\(p.scaleX), \(p.scaleY))\n"
                info += "  Opacity: \(p.opacity) | CornerRadius: \(p.cornerRadius)\n"
                
                // Canvas bounds check
                let rightEdge = p.x + p.width
                let bottomEdge = p.y + p.height
                if p.x < 0 || p.y < 0 || rightEdge > canvasW || bottomEdge > canvasH {
                    info += "  ⚠️ OUT OF BOUNDS (canvas: \(Int(canvasW))×\(Int(canvasH)))\n"
                }
                
                // Colors (full detail with raw values for update_object)
                info += "  fillColor: \(describeColorFull(p.fillColor))\n"
                info += "  strokeColor: \(describeColorFull(p.strokeColor)) | strokeWidth: \(p.strokeWidth)\n"
                
                // Shadow (always show — important for visual design)
                if let sc = p.shadowColor {
                    info += "  shadowColor: \(describeColorFull(sc))\n"
                } else {
                    info += "  shadowColor: null\n"
                }
                info += "  shadowRadius: \(p.shadowRadius) | shadowOffset: (\(p.shadowOffsetX), \(p.shadowOffsetY))\n"
                
                // Text-specific
                if obj.type == .text {
                    info += "  text: \"\(p.text ?? "")\"\n"
                    info += "  fontSize: \(p.fontSize ?? 24) | fontName: \"\(p.fontName ?? "default")\" | fontWeight: \"\(p.fontWeight ?? "regular")\"\n"
                    info += "  textAlignment: \"\(p.textAlignment ?? "left")\"\n"
                }
                
                // Icon-specific
                if obj.type == .icon {
                    info += "  iconName: \"\(p.iconName ?? "none")\"\n"
                    if let sz = p.iconSize { info += "  iconSize: \(sz)\n" }
                }
                
                // Image-specific
                if obj.type == .image {
                    let hasImage = p.imageData?.isEmpty == false
                    info += "  imageData: \(hasImage ? "attached (\(p.imageData!.count) chars)" : "none")\n"
                }
                
                // Polygon-specific
                if obj.type == .polygon {
                    info += "  sides: \(p.sides ?? 6)\n"
                }
                
                // Path-specific
                if obj.type == .path {
                    info += "  closePath: \(p.closePath ?? false)\n"
                    if let lc = p.lineCap { info += "  lineCap: \"\(lc)\"\n" }
                    if let lj = p.lineJoin { info += "  lineJoin: \"\(lj)\"\n" }
                    if let dp = p.dashPattern, !dp.isEmpty { info += "  dashPattern: \(dp)\n" }
                    if let dph = p.dashPhase { info += "  dashPhase: \(dph)\n" }
                    if let ts = p.trimStart { info += "  trimStart: \(ts)\n" }
                    if let te = p.trimEnd { info += "  trimEnd: \(te)\n" }
                    if let to = p.trimOffset { info += "  trimOffset: \(to)\n" }
                    if let pd = p.pathData {
                        info += "  pathData: \(pd.count) commands\n"
                        for (ci, cmd) in pd.prefix(10).enumerated() {
                            info += "    [\(ci)] \(cmd.command)"
                            if let x = cmd.x, let y = cmd.y { info += " (\(x), \(y))" }
                            if let cx1 = cmd.cx1, let cy1 = cmd.cy1 { info += " cp1(\(cx1),\(cy1))" }
                            if let cx2 = cmd.cx2, let cy2 = cmd.cy2 { info += " cp2(\(cx2),\(cy2))" }
                            info += "\n"
                        }
                        if pd.count > 10 { info += "    ... \(pd.count - 10) more commands\n" }
                    }
                }
                
                // 3D Model
                if obj.type == .model3D {
                    info += "  modelAssetId: \"\(p.modelAssetId ?? "none")\"\n"
                    if let fp = p.modelFilePath { info += "  modelFilePath: \"\(fp)\"\n" }
                    info += "  3D rotation: (\(p.rotationX ?? 0)°, \(p.rotationY ?? 0)°, \(p.rotationZ ?? 0)°)\n"
                    if let sz = p.scaleZ { info += "  scaleZ: \(sz)\n" }
                    info += "  camera: distance=\(p.cameraDistance ?? 0), angleX=\(p.cameraAngleX ?? 0), angleY=\(p.cameraAngleY ?? 0), targetX=\(p.cameraTargetX ?? 0), targetY=\(p.cameraTargetY ?? 0), targetZ=\(p.cameraTargetZ ?? 0)\n"
                    if let env = p.environmentLighting { info += "  environmentLighting: \"\(env)\"\n" }
                }
                
                // Shader
                if obj.type == .shader {
                    let hasCode = p.shaderCode?.isEmpty == false
                    info += "  shaderCode: \(hasCode ? "\"\(p.shaderCode!.prefix(80))...\"" : "none")\n"
                    if let p1 = p.shaderParam1 { info += "  shaderParam1: \(p1)\n" }
                    if let p2 = p.shaderParam2 { info += "  shaderParam2: \(p2)\n" }
                    if let p3 = p.shaderParam3 { info += "  shaderParam3: \(p3)\n" }
                    if let p4 = p.shaderParam4 { info += "  shaderParam4: \(p4)\n" }
                }
                
                // Visual effects (only show non-defaults to save space)
                var effects: [String] = []
                if p.blurRadius > 0 { effects.append("blur=\(p.blurRadius)") }
                if p.brightness != 0 { effects.append("brightness=\(p.brightness)") }
                if p.contrast != 1 { effects.append("contrast=\(p.contrast)") }
                if p.saturation != 1 { effects.append("saturation=\(p.saturation)") }
                if p.hueRotation != 0 { effects.append("hue=\(p.hueRotation)°") }
                if p.grayscale > 0 { effects.append("grayscale=\(p.grayscale)") }
                if p.colorInvert { effects.append("colorInvert=true") }
                if let bm = p.blendMode { effects.append("blendMode=\"\(bm)\"") }
                if !effects.isEmpty {
                    info += "  Effects: \(effects.joined(separator: ", "))\n"
                }
                
                // Timing dependency
                if let dep = obj.timingDependency {
                    info += "  timingDependency: dependsOn=\(dep.dependsOn.uuidString), trigger=\(dep.trigger.rawValue), gap=\(dep.gap)s\n"
                }
                
                // Animations (detailed)
                if !obj.animations.isEmpty {
                    info += "  Animations (\(obj.animations.count)):\n"
                    for anim in obj.animations {
                        info += "    - \(anim.type.rawValue): start=\(anim.startTime)s, dur=\(anim.duration)s, delay=\(anim.delay)s"
                        if anim.repeatCount != 0 { info += ", repeat=\(anim.repeatCount)" }
                        if anim.autoReverse { info += ", autoReverse" }
                        info += "\n"
                    }
                }
                
                results.append(info)
            }
        }
        
        // Include transitions when: type filter is "transition", or no type/id filter is set
        let showTransitions = typeFilter?.lowercased() == "transition" || (typeFilter == nil && idFilter == nil)
        var transitionResults: [String] = []
        
        if showTransitions && !project.transitions.isEmpty {
            let sceneNames = Dictionary(uniqueKeysWithValues: project.orderedScenes.map { ($0.id, $0.name) })
            
            for t in project.transitions {
                let fromName = sceneNames[t.fromSceneId] ?? t.fromSceneId
                let toName = sceneNames[t.toSceneId] ?? t.toSceneId
                var info = "─── Transition [\(t.type.rawValue)] ───\n"
                info += "  ID: \(t.id.uuidString)\n"
                info += "  From: \"\(fromName)\" → To: \"\(toName)\"\n"
                info += "  type: \"\(t.type.rawValue)\"\n"
                info += "  duration: \(t.duration)s\n"
                info += "  Available types: crossfade, slideLeft, slideRight, slideUp, slideDown, wipe, zoom, dissolve, none\n"
                info += "  Update with: update_object(id:\"\(t.id.uuidString)\", properties:{\"type\":\"slideLeft\", \"duration\":1.0})\n"
                transitionResults.append(info)
            }
        }
        
        // Also check if a specific ID matches a transition
        if let idf = idFilter {
            for t in project.transitions where t.id.uuidString == idf {
                let sceneNames = Dictionary(uniqueKeysWithValues: project.orderedScenes.map { ($0.id, $0.name) })
                let fromName = sceneNames[t.fromSceneId] ?? t.fromSceneId
                let toName = sceneNames[t.toSceneId] ?? t.toSceneId
                var info = "─── Transition [\(t.type.rawValue)] ───\n"
                info += "  ID: \(t.id.uuidString)\n"
                info += "  From: \"\(fromName)\" → To: \"\(toName)\"\n"
                info += "  type: \"\(t.type.rawValue)\"\n"
                info += "  duration: \(t.duration)s\n"
                info += "  Available types: crossfade, slideLeft, slideRight, slideUp, slideDown, wipe, zoom, dissolve, none\n"
                transitionResults.append(info)
            }
        }
        
        let allResults = results + transitionResults
        
        if allResults.isEmpty {
            return AgentToolResult(callId: call.id, tool: call.tool, success: true,
                                  output: "No objects found matching: \(filterDescription(typeFilter, nameFilter, sceneFilter, idFilter))")
        }
        
        var output = "Found \(results.count) objects"
        if !transitionResults.isEmpty { output += " + \(transitionResults.count) transitions" }
        output += " (canvas: \(Int(canvasW))×\(Int(canvasH))):\n\n"
        output += allResults.joined(separator: "\n")
        return AgentToolResult(callId: call.id, tool: call.tool, success: true, output: output)
    }
    
    // MARK: - Query from raw JSON (JSONSerialization fallback — format-agnostic)
    
    /// When the typed Project model can't load (legacy format, schema changes, etc.),
    /// this parses the raw JSON and walks the structure to find and display objects.
    /// This is the "always works" fallback — it handles ANY valid JSON structure.
    private func queryFromRawJSON(_ call: AgentToolCall, root: [String: Any], typeFilter: String?, nameFilter: String?, sceneFilter: String?, idFilter: String?) -> AgentToolResult {
        let canvas = root["canvas"] as? [String: Any]
        let canvasW = canvas?["width"] as? Double ?? 1920
        let canvasH = canvas?["height"] as? Double ?? 1080
        
        var results: [String] = []
        
        // Walk: root.scenes[].objects[]
        guard let scenes = root["scenes"] as? [[String: Any]] else {
            return AgentToolResult(callId: call.id, tool: call.tool, success: false,
                                  output: "", error: "No 'scenes' array found in project.json")
        }
        
        for (sceneIdx, scene) in scenes.enumerated() {
            let sceneName = scene["name"] as? String ?? "Scene \(sceneIdx + 1)"
            if let sf = sceneFilter, !sceneName.lowercased().contains(sf.lowercased()) { continue }
            
            guard let objects = scene["objects"] as? [[String: Any]] else { continue }
            
            for obj in objects {
                let objType = obj["type"] as? String ?? "unknown"
                let objId = obj["id"] as? String ?? "?"
                let objName = obj["name"] as? String ?? "Untitled"
                let isVisible = obj["isVisible"] as? Bool ?? true
                let zIndex = obj["zIndex"] as? Int ?? 0
                
                if let tf = typeFilter, objType.lowercased() != tf.lowercased() { continue }
                if let nf = nameFilter, !objName.lowercased().contains(nf.lowercased()) { continue }
                if let idf = idFilter, objId != idf { continue }
                
                var info = "─── \"\(objName)\" [\(objType)] ───\n"
                info += "  ID: \(objId)\n"
                info += "  Scene: \"\(sceneName)\" (scene \(sceneIdx + 1))\n"
                info += "  Visible: \(isVisible) | zIndex: \(zIndex)\n"
                
                // Dump ALL properties from the "properties" dict — every key-value pair
                if let props = obj["properties"] as? [String: Any] {
                    let sortedKeys = props.keys.sorted()
                    for key in sortedKeys {
                        let value = props[key]!
                        info += "  \(key): \(formatJSONValue(value))\n"
                    }
                }
                
                // Animations
                if let anims = obj["animations"] as? [[String: Any]], !anims.isEmpty {
                    info += "  Animations (\(anims.count)):\n"
                    for anim in anims {
                        let animType = anim["type"] as? String ?? "?"
                        let start = anim["startTime"] as? Double ?? 0
                        let dur = anim["duration"] as? Double ?? 0
                        let delay = anim["delay"] as? Double ?? 0
                        info += "    - \(animType): start=\(start)s, dur=\(dur)s, delay=\(delay)s\n"
                    }
                }
                
                // Timing dependency
                if let dep = obj["timingDependency"] as? [String: Any] {
                    let depId = dep["dependsOn"] as? String ?? "?"
                    let trigger = dep["trigger"] as? String ?? "?"
                    let gap = dep["gap"] as? Double ?? 0
                    info += "  timingDependency: dependsOn=\(depId), trigger=\(trigger), gap=\(gap)s\n"
                }
                
                results.append(info)
            }
        }
        
        // Transitions (raw JSON fallback)
        var transitionResults: [String] = []
        let showTransitions = typeFilter?.lowercased() == "transition" || (typeFilter == nil && idFilter == nil)
        
        if let transitions = root["transitions"] as? [[String: Any]] {
            let sceneNameMap: [String: String] = {
                var map: [String: String] = [:]
                for s in scenes {
                    if let sid = s["id"] as? String, let sname = s["name"] as? String { map[sid] = sname }
                }
                return map
            }()
            
            for t in transitions {
                let tId = t["id"] as? String ?? "?"
                let tType = t["type"] as? String ?? "?"
                let tDuration = t["duration"] as? Double ?? 0
                let fromId = t["fromSceneId"] as? String ?? "?"
                let toId = t["toSceneId"] as? String ?? "?"
                
                // Filter
                if let idf = idFilter, tId != idf { if !showTransitions { continue } else if tId != idf { continue } }
                if !showTransitions && idFilter == nil { continue }
                
                var info = "─── Transition [\(tType)] ───\n"
                info += "  ID: \(tId)\n"
                info += "  From: \"\(sceneNameMap[fromId] ?? fromId)\" → To: \"\(sceneNameMap[toId] ?? toId)\"\n"
                info += "  type: \"\(tType)\" | duration: \(tDuration)s\n"
                transitionResults.append(info)
            }
        }
        
        let allResults = results + transitionResults
        
        if allResults.isEmpty {
            return AgentToolResult(callId: call.id, tool: call.tool, success: true,
                                  output: "No objects found matching: \(filterDescription(typeFilter, nameFilter, sceneFilter, idFilter))")
        }
        
        var output = "Found \(results.count) objects"
        if !transitionResults.isEmpty { output += " + \(transitionResults.count) transitions" }
        output += " (canvas: \(Int(canvasW))×\(Int(canvasH))) [raw JSON mode]:\n\n"
        output += allResults.joined(separator: "\n")
        return AgentToolResult(callId: call.id, tool: call.tool, success: true, output: output)
    }
    
    // MARK: - Query Helpers
    
    /// Describe a CodableColor with both human-readable AND raw values for update_object.
    private func describeColorFull(_ color: CodableColor) -> String {
        let r = Int(color.red * 255)
        let g = Int(color.green * 255)
        let b = Int(color.blue * 255)
        if color.alpha < 0.01 { return "transparent {red:\(color.red), green:\(color.green), blue:\(color.blue), alpha:\(color.alpha)}" }
        return "rgb(\(r),\(g),\(b)" + (color.alpha < 1 ? " a=\(String(format: "%.2f", color.alpha))" : "") + ") {red:\(color.red), green:\(color.green), blue:\(color.blue), alpha:\(color.alpha)}"
    }
    
    /// Format a raw JSON value for human-readable display. Handles nested dicts and arrays.
    private func formatJSONValue(_ value: Any) -> String {
        if let dict = value as? [String: Any] {
            let pairs = dict.keys.sorted().map { key -> String in
                let v = dict[key]!
                return "\(key): \(formatJSONValueShort(v))"
            }
            return "{ \(pairs.joined(separator: ", ")) }"
        }
        if let arr = value as? [Any] {
            if arr.count <= 5 {
                return "[\(arr.map { formatJSONValueShort($0) }.joined(separator: ", "))]"
            }
            return "[\(arr.prefix(3).map { formatJSONValueShort($0) }.joined(separator: ", "))... (\(arr.count) items)]"
        }
        return formatJSONValueShort(value)
    }
    
    /// Short format for a JSON value (no deep nesting).
    private func formatJSONValueShort(_ value: Any) -> String {
        if let s = value as? String { return "\"\(s)\"" }
        if let n = value as? NSNumber {
            if CFBooleanGetTypeID() == CFGetTypeID(n) { return n.boolValue ? "true" : "false" }
            if let d = value as? Double, d != d.rounded(.towardZero) { return "\(d)" }
            if let i = value as? Int { return "\(i)" }
            return "\(n)"
        }
        if value is NSNull { return "null" }
        if let d = value as? [String: Any] { return "{...(\(d.count) keys)}" }
        if let a = value as? [Any] { return "[...(\(a.count) items)]" }
        return "\(value)"
    }
    
    /// Build a description of active query filters.
    private func filterDescription(_ type: String?, _ name: String?, _ scene: String?, _ id: String?) -> String {
        var desc = "all objects"
        if let tf = type { desc = "type=\(tf)" }
        if let nf = name { desc += " name=\(nf)" }
        if let sf = scene { desc += " scene=\(sf)" }
        if let idf = id { desc = "id=\(idf)" }
        return desc
    }
    
    // MARK: - Reference Docs
    
    private func executeGetReferenceDocs(_ call: AgentToolCall) -> AgentToolResult {
        guard let topic = call.arguments.topic else {
            let topics = PromptBuilder.referenceDocTopics.joined(separator: ", ")
            return AgentToolResult(callId: call.id, tool: call.tool, success: false,
                                  output: "", error: "Missing 'topic' parameter. Available: \(topics)")
        }
        
        if let doc = PromptBuilder.referenceDoc(for: topic) {
            return AgentToolResult(callId: call.id, tool: call.tool, success: true, output: doc)
        }
        
        let topics = PromptBuilder.referenceDocTopics.joined(separator: ", ")
        return AgentToolResult(callId: call.id, tool: call.tool, success: false,
                              output: "", error: "Unknown topic '\(topic)'. Available: \(topics)")
    }
    
    // MARK: - Security / Sandbox
    
    /// Resolve a relative path within the project and validate it doesn't escape.
    /// Uses canonical path resolution to defeat all traversal tricks (../, symlinks, encoding).
    private func resolveAndValidate(_ relativePath: String, projectURL: URL) -> URL? {
        // 1. Strip any path traversal components and leading slashes
        let components = relativePath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "/")
            .filter { component in
                let c = component.trimmingCharacters(in: .whitespaces)
                // Remove empty, ".", "..", and any percent-encoded traversals
                if c.isEmpty || c == "." || c == ".." { return false }
                if c.removingPercentEncoding == ".." { return false }
                return true
            }
        
        // 2. Build the resolved URL from safe components
        var resolved = projectURL
        for component in components {
            resolved = resolved.appendingPathComponent(component)
        }
        
        // 3. Canonicalize both paths (resolves symlinks) and compare
        let canonicalProject = projectURL.standardizedFileURL.resolvingSymlinksInPath().path
        let canonicalResolved = resolved.standardizedFileURL.resolvingSymlinksInPath().path
        
        // Must be exactly the project dir, or inside it (with "/" separator)
        guard canonicalResolved == canonicalProject ||
              canonicalResolved.hasPrefix(canonicalProject + "/") else {
            DebugLogger.shared.error("[Agent] BLOCKED path escape: \(relativePath) → \(canonicalResolved) (project: \(canonicalProject))", category: .llm)
            return nil
        }
        
        // 4. Block access to known sensitive patterns
        // IMPORTANT: Only check the RELATIVE portion (path within the project),
        // not the full absolute path — because sandboxed apps live under
        // /Users/.../Library/Containers/... which would false-positive on "/library/".
        let relativePortionLower = canonicalResolved
            .replacingOccurrences(of: canonicalProject, with: "")
            .lowercased()
        let blockedPatterns = [
            ".app/", ".xcodeproj", ".pbxproj", ".swift",
            ".git/", ".checkpoints/", ".env", "keychain", ".ssh/"
        ]
        for pattern in blockedPatterns {
            if relativePortionLower.contains(pattern) {
                DebugLogger.shared.error("[Agent] BLOCKED sensitive path: \(relativePath) (matched: \(pattern))", category: .llm)
                return nil
            }
        }
        
        return resolved
    }
    
    /// Build an indented file tree string.
    private func buildTree(at url: URL, projectURL: URL, indent: String, maxDepth: Int = 4) -> String {
        guard maxDepth > 0 else { return indent + "... (truncated)\n" }
        
        var output = ""
        
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return output }
        
        let sorted = contents.sorted { $0.lastPathComponent < $1.lastPathComponent }
        
        for (i, item) in sorted.enumerated() {
            let isLast = i == sorted.count - 1
            let prefix = isLast ? "└── " : "├── "
            let childIndent = indent + (isLast ? "    " : "│   ")
            
            var isDir: ObjCBool = false
            fileManager.fileExists(atPath: item.path, isDirectory: &isDir)
            
            if isDir.boolValue {
                output += indent + prefix + item.lastPathComponent + "/\n"
                output += buildTree(at: item, projectURL: projectURL, indent: childIndent, maxDepth: maxDepth - 1)
            } else {
                let size = fileSizeString(item)
                output += indent + prefix + item.lastPathComponent + "  (\(size))\n"
            }
        }
        
        return output
    }
    
    /// Collect all text files under a directory, optionally matching a glob.
    private func collectFiles(at url: URL, glob: String?) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        
        var files: [URL] = []
        let maxFiles = 100
        
        while let item = enumerator.nextObject() as? URL {
            guard files.count < maxFiles else { break }
            
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: item.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            
            // Check glob
            if let glob {
                let name = item.lastPathComponent
                if !matchesGlob(name, pattern: glob) { continue }
            }
            
            files.append(item)
        }
        
        return files
    }
    
    /// Simple glob matching (supports * and ? wildcards).
    private func matchesGlob(_ name: String, pattern: String) -> Bool {
        let regexPattern = "^" + NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")
            + "$"
        return name.range(of: regexPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
    
    /// Human-readable file size.
    private func fileSizeString(_ url: URL) -> String {
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64 else { return "?" }
        
        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return "\(size / 1024) KB" }
        return String(format: "%.1f MB", Double(size) / 1_048_576)
    }
}

// MARK: - Fuzzy Replace (ported from OpenCode's edit.ts)
//
// OpenCode uses a chain of progressively more flexible matching strategies
// so that search_replace succeeds even when the AI's search string has minor
// whitespace, indentation, or formatting differences from the actual file content.
// See: https://github.com/sst/opencode/blob/dev/packages/opencode/src/tool/edit.ts

enum FuzzyReplace {
    
    // MARK: 1. Simple (exact match)
    
    /// Returns the search string itself if it exists in content.
    static func simpleReplacer(content: String, find: String) -> [String] {
        if content.contains(find) {
            return [find]
        }
        return []
    }
    
    // MARK: 2. Line-Trimmed
    
    /// Matches blocks of lines where each line matches after trimming whitespace.
    /// Returns the actual (untrimmed) text from the file.
    static func lineTrimmedReplacer(content: String, find: String) -> [String] {
        let originalLines = content.components(separatedBy: "\n")
        var searchLines = find.components(separatedBy: "\n")
        
        // Remove trailing empty line if present
        if let last = searchLines.last, last.isEmpty {
            searchLines.removeLast()
        }
        
        guard !searchLines.isEmpty else { return [] }
        
        var results: [String] = []
        
        for i in 0...(max(0, originalLines.count - searchLines.count)) {
            guard i + searchLines.count <= originalLines.count else { break }
            
            var matches = true
            for j in 0..<searchLines.count {
                let originalTrimmed = originalLines[i + j].trimmingCharacters(in: .whitespaces)
                let searchTrimmed = searchLines[j].trimmingCharacters(in: .whitespaces)
                if originalTrimmed != searchTrimmed {
                    matches = false
                    break
                }
            }
            
            if matches {
                let matchedLines = originalLines[i..<(i + searchLines.count)]
                results.append(matchedLines.joined(separator: "\n"))
            }
        }
        
        return results
    }
    
    // MARK: 2.5. JSON Colon Normalized
    
    /// Handles the common JSON formatting difference where Swift's JSONEncoder
    /// uses `"key" : "value"` (spaced colons) but most LLMs output `"key": "value"` (compact).
    /// Normalizes JSON colon spacing + trims line whitespace before comparing, then
    /// returns the actual (untouched) text from the file.
    static func jsonColonNormalizedReplacer(content: String, find: String) -> [String] {
        // Normalize JSON colon spacing: `" : "` or `": "` or `" :"` → `": "`
        // The regex targets a closing quote, optional spaces, colon, optional spaces
        // and replaces with `": ` — the compact form most LLMs use.
        let colonRegex = try? NSRegularExpression(pattern: "\"\\s*:\\s*", options: [])
        
        let normalizeJsonColons: (String) -> String = { line in
            guard let regex = colonRegex else { return line }
            let range = NSRange(line.startIndex..., in: line)
            return regex.stringByReplacingMatches(in: line, range: range, withTemplate: "\": ")
        }
        
        let originalLines = content.components(separatedBy: "\n")
        var searchLines = find.components(separatedBy: "\n")
        
        // Remove trailing empty line if present
        if let last = searchLines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            searchLines.removeLast()
        }
        
        guard !searchLines.isEmpty else { return [] }
        
        var results: [String] = []
        
        for i in 0...(max(0, originalLines.count - searchLines.count)) {
            guard i + searchLines.count <= originalLines.count else { break }
            
            var matches = true
            for j in 0..<searchLines.count {
                let normalizedOriginal = normalizeJsonColons(originalLines[i + j])
                    .trimmingCharacters(in: .whitespaces)
                let normalizedSearch = normalizeJsonColons(searchLines[j])
                    .trimmingCharacters(in: .whitespaces)
                if normalizedOriginal != normalizedSearch {
                    matches = false
                    break
                }
            }
            
            if matches {
                let matchedLines = originalLines[i..<(i + searchLines.count)]
                results.append(matchedLines.joined(separator: "\n"))
            }
        }
        
        return results
    }
    
    // MARK: 3. Block Anchor
    
    /// Uses first and last lines as "anchors" and checks middle content similarity
    /// via Levenshtein distance. Handles cases where the AI's middle content is
    /// slightly different (e.g., from truncation or hallucination).
    static func blockAnchorReplacer(content: String, find: String) -> [String] {
        let originalLines = content.components(separatedBy: "\n")
        var searchLines = find.components(separatedBy: "\n")
        
        guard searchLines.count >= 3 else { return [] }
        
        if let last = searchLines.last, last.isEmpty {
            searchLines.removeLast()
        }
        
        let firstLineSearch = searchLines[0].trimmingCharacters(in: .whitespaces)
        let lastLineSearch = searchLines.last!.trimmingCharacters(in: .whitespaces)
        
        // Collect all candidate positions where both anchors match
        struct Candidate {
            let startLine: Int
            let endLine: Int
        }
        
        var candidates: [Candidate] = []
        for i in 0..<originalLines.count {
            guard originalLines[i].trimmingCharacters(in: .whitespaces) == firstLineSearch else { continue }
            
            for j in (i + 2)..<originalLines.count {
                if originalLines[j].trimmingCharacters(in: .whitespaces) == lastLineSearch {
                    candidates.append(Candidate(startLine: i, endLine: j))
                    break
                }
            }
        }
        
        guard !candidates.isEmpty else { return [] }
        
        let singleThreshold: Double = 0.0
        let multipleThreshold: Double = 0.3
        
        if candidates.count == 1 {
            let c = candidates[0]
            let actualBlockSize = c.endLine - c.startLine + 1
            let linesToCheck = min(searchLines.count - 2, actualBlockSize - 2)
            
            var similarity: Double = linesToCheck > 0 ? 0 : 1.0
            if linesToCheck > 0 {
                for j in 1..<min(searchLines.count - 1, actualBlockSize - 1) {
                    let orig = originalLines[c.startLine + j].trimmingCharacters(in: .whitespaces)
                    let search = searchLines[j].trimmingCharacters(in: .whitespaces)
                    let maxLen = max(orig.count, search.count)
                    if maxLen == 0 { continue }
                    let dist = levenshteinDistance(orig, search)
                    similarity += (1.0 - Double(dist) / Double(maxLen)) / Double(linesToCheck)
                    if similarity >= singleThreshold { break }
                }
            }
            
            if similarity >= singleThreshold {
                let matched = originalLines[c.startLine...c.endLine].joined(separator: "\n")
                return [matched]
            }
            return []
        }
        
        // Multiple candidates — pick the best by similarity
        var bestMatch: Candidate? = nil
        var maxSimilarity: Double = -1
        
        for c in candidates {
            let actualBlockSize = c.endLine - c.startLine + 1
            let linesToCheck = min(searchLines.count - 2, actualBlockSize - 2)
            
            var similarity: Double = linesToCheck > 0 ? 0 : 1.0
            if linesToCheck > 0 {
                for j in 1..<min(searchLines.count - 1, actualBlockSize - 1) {
                    let orig = originalLines[c.startLine + j].trimmingCharacters(in: .whitespaces)
                    let search = searchLines[j].trimmingCharacters(in: .whitespaces)
                    let maxLen = max(orig.count, search.count)
                    if maxLen == 0 { continue }
                    let dist = levenshteinDistance(orig, search)
                    similarity += 1.0 - Double(dist) / Double(maxLen)
                }
                similarity /= Double(linesToCheck)
            }
            
            if similarity > maxSimilarity {
                maxSimilarity = similarity
                bestMatch = c
            }
        }
        
        if maxSimilarity >= multipleThreshold, let best = bestMatch {
            let matched = originalLines[best.startLine...best.endLine].joined(separator: "\n")
            return [matched]
        }
        
        return []
    }
    
    // MARK: 4. Whitespace Normalized
    
    /// Normalizes all whitespace to single spaces before matching.
    static func whitespaceNormalizedReplacer(content: String, find: String) -> [String] {
        let normalize: (String) -> String = { text in
            text.components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        
        let normalizedFind = normalize(find)
        let contentLines = content.components(separatedBy: "\n")
        var results: [String] = []
        
        // Single line matches
        for line in contentLines {
            if normalize(line) == normalizedFind {
                results.append(line)
            }
        }
        
        // Multi-line matches
        let findLines = find.components(separatedBy: "\n")
        if findLines.count > 1 {
            for i in 0...(max(0, contentLines.count - findLines.count)) {
                guard i + findLines.count <= contentLines.count else { break }
                let block = contentLines[i..<(i + findLines.count)].joined(separator: "\n")
                if normalize(block) == normalizedFind {
                    results.append(block)
                }
            }
        }
        
        return results
    }
    
    // MARK: 5. Indentation Flexible
    
    /// Removes minimum indentation from both search and content blocks before comparing.
    static func indentationFlexibleReplacer(content: String, find: String) -> [String] {
        let removeIndentation: (String) -> String = { text in
            let lines = text.components(separatedBy: "\n")
            let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard !nonEmpty.isEmpty else { return text }
            
            let minIndent = nonEmpty.map { line -> Int in
                let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
                return line.count - trimmed.count
            }.min() ?? 0
            
            return lines.map { line in
                if line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
                return String(line.dropFirst(min(minIndent, line.count)))
            }.joined(separator: "\n")
        }
        
        let normalizedFind = removeIndentation(find)
        let contentLines = content.components(separatedBy: "\n")
        let findLines = find.components(separatedBy: "\n")
        
        var results: [String] = []
        
        for i in 0...(max(0, contentLines.count - findLines.count)) {
            guard i + findLines.count <= contentLines.count else { break }
            let block = contentLines[i..<(i + findLines.count)].joined(separator: "\n")
            if removeIndentation(block) == normalizedFind {
                results.append(block)
            }
        }
        
        return results
    }
    
    // MARK: 6. Escape Normalized (from OpenCode edit.ts)
    
    /// Handles escaped characters — unescapes \\n, \\t, \\r, \\", \\', \\\\ etc.
    /// and tries matching the unescaped version against the content.
    static func escapeNormalizedReplacer(content: String, find: String) -> [String] {
        let unescape: (String) -> String = { str in
            var result = str
            result = result.replacingOccurrences(of: "\\n", with: "\n")
            result = result.replacingOccurrences(of: "\\t", with: "\t")
            result = result.replacingOccurrences(of: "\\r", with: "\r")
            result = result.replacingOccurrences(of: "\\'", with: "'")
            result = result.replacingOccurrences(of: "\\\"", with: "\"")
            result = result.replacingOccurrences(of: "\\\\", with: "\\")
            return result
        }
        
        let unescapedFind = unescape(find)
        
        var results: [String] = []
        
        // Try direct match with unescaped find string
        if content.contains(unescapedFind) {
            results.append(unescapedFind)
        }
        
        // Try finding escaped versions in content that match unescaped find
        let contentLines = content.components(separatedBy: "\n")
        let findLines = unescapedFind.components(separatedBy: "\n")
        
        if findLines.count > 1 {
            for i in 0...(max(0, contentLines.count - findLines.count)) {
                guard i + findLines.count <= contentLines.count else { break }
                let block = contentLines[i..<(i + findLines.count)].joined(separator: "\n")
                let unescapedBlock = unescape(block)
                
                if unescapedBlock == unescapedFind && !results.contains(block) {
                    results.append(block)
                }
            }
        }
        
        return results
    }
    
    // MARK: 7. Trimmed Boundary (originally #6 in our chain, now #7 to match OpenCode order)
    
    /// Trims the search string's leading/trailing whitespace and tries matching.
    static func trimmedBoundaryReplacer(content: String, find: String) -> [String] {
        let trimmedFind = find.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedFind != find else { return [] } // Already trimmed, skip
        
        var results: [String] = []
        
        // Direct substring match
        if content.contains(trimmedFind) {
            results.append(trimmedFind)
        }
        
        // Block match
        let contentLines = content.components(separatedBy: "\n")
        let findLines = find.components(separatedBy: "\n")
        
        for i in 0...(max(0, contentLines.count - findLines.count)) {
            guard i + findLines.count <= contentLines.count else { break }
            let block = contentLines[i..<(i + findLines.count)].joined(separator: "\n")
            if block.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedFind {
                results.append(block)
            }
        }
        
        return results
    }
    
    // MARK: 8. Context Aware
    
    /// Uses first/last lines as context anchors with a 50% similarity threshold for middle lines.
    static func contextAwareReplacer(content: String, find: String) -> [String] {
        var findLines = find.components(separatedBy: "\n")
        guard findLines.count >= 3 else { return [] }
        
        if let last = findLines.last, last.isEmpty {
            findLines.removeLast()
        }
        
        let contentLines = content.components(separatedBy: "\n")
        let firstLine = findLines[0].trimmingCharacters(in: .whitespaces)
        let lastLine = findLines.last!.trimmingCharacters(in: .whitespaces)
        
        var results: [String] = []
        
        for i in 0..<contentLines.count {
            guard contentLines[i].trimmingCharacters(in: .whitespaces) == firstLine else { continue }
            
            for j in (i + 2)..<contentLines.count {
                guard contentLines[j].trimmingCharacters(in: .whitespaces) == lastLine else { continue }
                
                let blockLines = Array(contentLines[i...j])
                
                // Check if block has the same number of lines
                guard blockLines.count == findLines.count else { break }
                
                // Check middle content similarity (at least 50%)
                var matchingLines = 0
                var totalNonEmpty = 0
                
                for k in 1..<(blockLines.count - 1) {
                    let blockLine = blockLines[k].trimmingCharacters(in: .whitespaces)
                    let findLine = findLines[k].trimmingCharacters(in: .whitespaces)
                    
                    if !blockLine.isEmpty || !findLine.isEmpty {
                        totalNonEmpty += 1
                        if blockLine == findLine {
                            matchingLines += 1
                        }
                    }
                }
                
                if totalNonEmpty == 0 || Double(matchingLines) / Double(totalNonEmpty) >= 0.5 {
                    results.append(blockLines.joined(separator: "\n"))
                }
                break
            }
        }
        
        return results
    }
    
    // MARK: 9. Multi-Occurrence (from OpenCode edit.ts)
    
    /// Yields all exact match positions — allows the replace function
    /// to handle replaceAll correctly when other replacers only yield unique matches.
    static func multiOccurrenceReplacer(content: String, find: String) -> [String] {
        var results: [String] = []
        var searchRange = content.startIndex..<content.endIndex
        
        while let range = content.range(of: find, range: searchRange) {
            results.append(String(content[range]))
            searchRange = range.upperBound..<content.endIndex
        }
        
        return results
    }
    
    // MARK: - Levenshtein Distance
    
    /// Standard Levenshtein edit distance algorithm.
    private static func levenshteinDistance(_ a: String, _ b: String) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        
        let aChars = Array(a)
        let bChars = Array(b)
        let aLen = aChars.count
        let bLen = bChars.count
        
        // Use two-row optimization for memory efficiency
        var prevRow = Array(0...bLen)
        var currRow = Array(repeating: 0, count: bLen + 1)
        
        for i in 1...aLen {
            currRow[0] = i
            for j in 1...bLen {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                currRow[j] = min(
                    prevRow[j] + 1,      // deletion
                    currRow[j - 1] + 1,  // insertion
                    prevRow[j - 1] + cost // substitution
                )
            }
            swap(&prevRow, &currRow)
        }
        
        return prevRow[bLen]
    }
}
