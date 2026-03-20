//
//  GoogleFontsService.swift
//  AIAfterEffects
//
//  Lightweight Google Fonts loader for macOS
//

import Foundation
import AppKit
import CoreText

actor GoogleFontsService {
    static let shared = GoogleFontsService()
    
    private var loadedFontVariants: Set<String> = [] // Track family+weight combinations
    private var loadingFontVariants: Set<String> = [] // Track in-progress loads
    private let fileManager = FileManager.default
    private let logger = DebugLogger.shared
    
    private var fontsDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("AIAfterEffects/Fonts", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    func ensureFontLoaded(family: String, weight: String = "Regular") async {
        let normalized = family.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        
        let numericWeight = mapWeightToNumeric(weight)
        let variantKey = "\(normalized)-\(numericWeight)" // Track by family+weight
        
        // Already loaded this specific variant
        if loadedFontVariants.contains(variantKey) {
            logger.debug("Font '\(variantKey)' already loaded", category: .fonts)
            return
        }
        
        // Check if system has this font family (any weight)
        if isFontAvailable(family: normalized) && loadedFontVariants.isEmpty {
            loadedFontVariants.insert(variantKey)
            logger.debug("Font '\(normalized)' available in system", category: .fonts)
            return
        }
        
        // Prevent duplicate concurrent loads of same variant
        if loadingFontVariants.contains(variantKey) {
            logger.debug("Font '\(variantKey)' already loading, skipping", category: .fonts)
            return
        }
        loadingFontVariants.insert(variantKey)
        
        defer { loadingFontVariants.remove(variantKey) }
        logger.info("Loading Google Font: '\(normalized)' weight \(numericWeight)", category: .fonts)
        
        do {
            // Fetch CSS with TTF-compatible user agent (important for macOS!)
            let cssURL = googleFontsCSSURL(family: normalized, weight: numericWeight)
            let css = try await fetchCSS(from: cssURL)
            
            // Extract TTF URL from CSS — fallback to weight 400 if requested weight unavailable
            var fontURL = extractTTFURL(from: css)
            if fontURL == nil && numericWeight != "400" {
                logger.info("Weight \(numericWeight) unavailable for '\(normalized)', falling back to 400", category: .fonts)
                let fallbackCSS = try await fetchCSS(from: googleFontsCSSURL(family: normalized, weight: "400"))
                fontURL = extractTTFURL(from: fallbackCSS)
            }
            guard let fontURL else {
                logger.warning("No TTF URL found in CSS for '\(normalized)'", category: .fonts)
                return
            }
            
            logger.debug("Found font URL: \(fontURL.absoluteString)", category: .fonts)
            
            // Download font file if not cached
            let fileURL = fontsDirectory.appendingPathComponent("\(normalized)-\(numericWeight).ttf")
            if !fileManager.fileExists(atPath: fileURL.path) {
                let data = try await fetchData(from: fontURL)
                try data.write(to: fileURL)
                logger.debug("Downloaded font to: \(fileURL.path)", category: .fonts)
            } else {
                logger.debug("Using cached font: \(fileURL.path)", category: .fonts)
            }
            
            // Register font with CoreText
            var errorRef: Unmanaged<CFError>?
            let success = CTFontManagerRegisterFontsForURL(fileURL as CFURL, .process, &errorRef)
            
            if success {
                loadedFontVariants.insert(variantKey)
                logger.success("Registered font '\(variantKey)'", category: .fonts)
            } else if let error = errorRef?.takeRetainedValue() {
                let errorDesc = CFErrorCopyDescription(error) as String? ?? "Unknown error"
                // Error code 105 means font is already registered - that's fine
                if CFErrorGetCode(error) == 105 {
                    loadedFontVariants.insert(variantKey)
                    logger.debug("Font '\(variantKey)' was already registered", category: .fonts)
                } else {
                    logger.error("Failed to register font '\(variantKey)': \(errorDesc)", category: .fonts)
                }
            }
        } catch {
            logger.error("Font loading failed for '\(normalized)': \(error.localizedDescription)", category: .fonts)
        }
    }
    
    /// Convert weight names to numeric values for Google Fonts API
    private func mapWeightToNumeric(_ weight: String) -> String {
        switch weight.lowercased() {
        case "thin", "hairline": return "100"
        case "extralight", "ultralight", "extra-light", "ultra-light": return "200"
        case "light": return "300"
        case "regular", "normal", "book": return "400"
        case "medium": return "500"
        case "semibold", "semi-bold", "demibold", "demi-bold": return "600"
        case "bold": return "700"
        case "extrabold", "extra-bold", "ultrabold", "ultra-bold": return "800"
        case "black", "heavy": return "900"
        default:
            // If it's already numeric, return as-is
            if Int(weight) != nil { return weight }
            return "400" // Default to regular
        }
    }
    
    private func googleFontsCSSURL(family: String, weight: String) -> URL {
        let encodedFamily = family.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? family.replacingOccurrences(of: " ", with: "+")
        let urlString = "https://fonts.googleapis.com/css2?family=\(encodedFamily):wght@\(weight)"
        return URL(string: urlString)!
    }
    
    /// Fetch CSS with a user agent that requests TTF format (not woff2)
    /// macOS CoreText doesn't support woff2, so we need TTF
    private func fetchCSS(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        // This user agent causes Google Fonts to return TTF URLs instead of woff2
        request.setValue("Safari/537.36", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            logger.debug("Google Fonts CSS response: \(httpResponse.statusCode)", category: .fonts)
        }
        
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    private func fetchData(from url: URL) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }
    
    /// Extract TTF URL from Google Fonts CSS response
    private func extractTTFURL(from css: String) -> URL? {
        // Try TTF first
        let ttfPattern = #"url\((https:[^)]+\.ttf)\)"#
        if let url = extractURL(from: css, pattern: ttfPattern) {
            return url
        }
        
        // Fallback to woff (might work on some macOS versions)
        let woffPattern = #"url\((https:[^)]+\.woff)\)"#
        if let url = extractURL(from: css, pattern: woffPattern) {
            return url
        }
        
        // Last resort: try woff2 (usually won't work on macOS)
        let woff2Pattern = #"url\((https:[^)]+\.woff2)\)"#
        return extractURL(from: css, pattern: woff2Pattern)
    }
    
    private func extractURL(from css: String, pattern: String) -> URL? {
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: css, options: [], range: NSRange(css.startIndex..., in: css)),
           let range = Range(match.range(at: 1), in: css) {
            return URL(string: String(css[range]))
        }
        return nil
    }
    
    private func isFontAvailable(family: String) -> Bool {
        NSFontManager.shared.availableFontFamilies.contains { $0.caseInsensitiveCompare(family) == .orderedSame }
    }
}
