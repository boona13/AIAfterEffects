//
//  DebugLogger.swift
//  AIAfterEffects
//
//  Centralized debug logging system that writes to a file
//  File is cleared on each app launch for fresh debugging
//

import Foundation
import AppKit

// MARK: - Log Level

enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
    case success = "SUCCESS"
    
    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .success: return "✅"
        }
    }
}

// MARK: - Log Category

enum LogCategory: String {
    case app = "APP"
    case llm = "LLM"
    case chat = "CHAT"
    case canvas = "CANVAS"
    case animation = "ANIM"
    case session = "SESSION"
    case parsing = "PARSE"
    case network = "NET"
    case ui = "UI"
    case fonts = "FONTS"
}

// MARK: - Debug Logger

class DebugLogger {
    static let shared = DebugLogger()
    
    private let fileManager = FileManager.default
    private let dateFormatter: DateFormatter
    private let timestampFormatter: DateFormatter
    private var logFileURL: URL?
    private let queue = DispatchQueue(label: "com.aiaftereffects.logger", qos: .utility)
    
    // In-memory log buffer for quick access
    private var logBuffer: [String] = []
    private let maxBufferSize = 1000
    
    private init() {
        // Setup date formatters
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        timestampFormatter = DateFormatter()
        timestampFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        
        // Setup log file
        setupLogFile()
        
        // Log app start
        logAppStart()
    }
    
    // MARK: - Setup
    
    private func setupLogFile() {
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ Could not find documents directory")
            return
        }
        
        let logsDirectory = documentsPath.appendingPathComponent("AIAfterEffects_Logs", isDirectory: true)
        
        // Create logs directory if needed
        if !fileManager.fileExists(atPath: logsDirectory.path) {
            try? fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        }
        
        // Log file path - always use the same name so it's easy to find
        logFileURL = logsDirectory.appendingPathComponent("debug_log.txt")
        
        // Clear the log file on app start
        clearLogFile()
        
        print("📝 Debug log file: \(logFileURL?.path ?? "unknown")")
    }
    
    private func clearLogFile() {
        guard let url = logFileURL else { return }
        
        // Delete existing file
        try? fileManager.removeItem(at: url)
        
        // Create fresh empty file
        fileManager.createFile(atPath: url.path, contents: nil)
        
        // Clear buffer
        logBuffer.removeAll()
    }
    
    private func logAppStart() {
        let separator = String(repeating: "=", count: 60)
        let header = """
        \(separator)
        AI AFTER EFFECTS - DEBUG LOG
        Started: \(dateFormatter.string(from: Date()))
        App Version: 1.0.0
        \(separator)
        
        """
        writeToFile(header)
    }
    
    // MARK: - Public Logging Methods
    
    func log(_ message: String, level: LogLevel = .info, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
        let timestamp = dateFormatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let location = "\(fileName):\(line)"
        
        let formattedMessage = "[\(timestamp)] \(level.emoji) [\(level.rawValue)] [\(category.rawValue)] \(message) (\(location))"
        
        // Print to console
        print(formattedMessage)
        
        // Write to file
        queue.async { [weak self] in
            self?.writeToFile(formattedMessage + "\n")
            self?.addToBuffer(formattedMessage)
        }
    }
    
    // Convenience methods
    func debug(_ message: String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, category: category, file: file, function: function, line: line)
    }
    
    func info(_ message: String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, category: category, file: file, function: function, line: line)
    }
    
    func warning(_ message: String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, category: category, file: file, function: function, line: line)
    }
    
    func error(_ message: String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, category: category, file: file, function: function, line: line)
    }
    
    func success(_ message: String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .success, category: category, file: file, function: function, line: line)
    }
    
    // MARK: - Specialized Logging
    
    func logLLMRequest(userMessage: String, model: String, historyCount: Int) {
        let separator = String(repeating: "-", count: 40)
        let message = """
        
        \(separator)
        LLM REQUEST
        Model: \(model)
        History: \(historyCount) messages
        User: \(userMessage)
        \(separator)
        """
        log(message, level: .info, category: .llm)
    }
    
    func logLLMResponse(response: String, parsed: Bool, actionsCount: Int) {
        let separator = String(repeating: "-", count: 40)
        let truncatedResponse = response.count > 500 ? String(response.prefix(500)) + "..." : response
        let message = """
        
        \(separator)
        LLM RESPONSE
        Parsed: \(parsed ? "✅ Yes" : "❌ No")
        Actions: \(actionsCount)
        Response: \(truncatedResponse)
        \(separator)
        """
        log(message, level: parsed ? .success : .warning, category: .llm)
    }
    
    func logSceneCommand(action: String, target: String?, parameters: String?) {
        var message = "Action: \(action)"
        if let target = target {
            message += " | Target: \(target)"
        }
        if let params = parameters {
            let truncated = params.count > 200 ? String(params.prefix(200)) + "..." : params
            message += " | Params: \(truncated)"
        }
        log(message, level: .debug, category: .canvas)
    }
    
    func logAnimation(type: String, object: String, duration: Double, result: String) {
        log("Animation '\(type)' on '\(object)' (duration: \(duration)s) - \(result)", level: .info, category: .animation)
    }
    
    func logParsingError(_ error: String, json: String?) {
        var message = "Parsing Error: \(error)"
        if let json = json {
            let truncated = json.count > 300 ? String(json.prefix(300)) + "..." : json
            message += "\nJSON: \(truncated)"
        }
        log(message, level: .error, category: .parsing)
    }
    
    // MARK: - File Operations
    
    private func writeToFile(_ text: String) {
        guard let url = logFileURL else { return }
        
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            if let data = text.data(using: .utf8) {
                handle.write(data)
            }
            try? handle.close()
        } else {
            // File might not exist, create it
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    
    private func addToBuffer(_ message: String) {
        logBuffer.append(message)
        if logBuffer.count > maxBufferSize {
            logBuffer.removeFirst(logBuffer.count - maxBufferSize)
        }
    }
    
    // MARK: - Log Access
    
    /// Get the path to the log file
    var logFilePath: String? {
        logFileURL?.path
    }
    
    /// Get recent logs from buffer
    func getRecentLogs(count: Int = 100) -> [String] {
        Array(logBuffer.suffix(count))
    }
    
    /// Read entire log file
    func readLogFile() -> String? {
        guard let url = logFileURL else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
    
    /// Open log file in Finder
    func openLogInFinder() {
        guard let url = logFileURL else { return }
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }
    
    /// Copy log file path to clipboard
    func copyLogPathToClipboard() {
        guard let path = logFilePath else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }
}

// MARK: - Global Convenience Functions

/// Quick log function
func Log(_ message: String, level: LogLevel = .info, category: LogCategory = .app) {
    DebugLogger.shared.log(message, level: level, category: category)
}
