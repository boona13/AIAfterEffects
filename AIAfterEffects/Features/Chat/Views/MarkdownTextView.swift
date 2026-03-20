//
//  MarkdownTextView.swift
//  AIAfterEffects
//
//  Renders Markdown content (bold, italic, bullets, numbered lists, code blocks)
//  as properly formatted SwiftUI views.
//

import SwiftUI

struct MarkdownTextView: View {
    let content: String
    let foregroundColor: Color
    let font: Font
    
    init(_ content: String, foregroundColor: Color = .primary, font: Font = .body) {
        self.content = content
        self.foregroundColor = foregroundColor
        self.font = font
    }
    
    var body: some View {
        let blocks = Self.parseBlocks(content)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
    }
    
    // MARK: - Block Types
    
    enum MarkdownBlock: Equatable {
        case paragraph(String)
        case bullet(String)
        case numbered(Int, String)
        case code(String)
    }
    
    // MARK: - Block Rendering
    
    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            inlineMarkdownText(text)
            
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\u{2022}")
                    .font(font)
                    .foregroundColor(foregroundColor.opacity(0.5))
                inlineMarkdownText(text)
            }
            .padding(.leading, 4)
            
        case .numbered(let num, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(num).")
                    .font(font)
                    .foregroundColor(foregroundColor.opacity(0.6))
                    .frame(minWidth: 20, alignment: .trailing)
                inlineMarkdownText(text)
            }
            .padding(.leading, 4)
            
        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(AppTheme.Colors.textPrimary.opacity(0.85))
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.Colors.background)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(AppTheme.Colors.border, lineWidth: 1)
            )
        }
    }
    
    // MARK: - Inline Markdown → Attributed Text
    
    @ViewBuilder
    private func inlineMarkdownText(_ text: String) -> some View {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let attributed = try? AttributedString(markdown: text, options: options) {
            Text(attributed)
                .font(font)
                .foregroundColor(foregroundColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(text)
                .font(font)
                .foregroundColor(foregroundColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    // MARK: - Parser
    
    static func parseBlocks(_ content: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = content.components(separatedBy: "\n")
        var paragraphLines: [String] = []
        var inCodeBlock = false
        var codeLines: [String] = []
        
        func flushParagraph() {
            let joined = paragraphLines.joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                blocks.append(.paragraph(joined))
            }
            paragraphLines.removeAll()
        }
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // --- Code fence ---
            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                    inCodeBlock = false
                } else {
                    flushParagraph()
                    inCodeBlock = true
                }
                continue
            }
            
            if inCodeBlock {
                codeLines.append(line)
                continue
            }
            
            // --- Bullet: * item, - item, • item ---
            if let bulletMatch = trimmed.bulletContent {
                flushParagraph()
                blocks.append(.bullet(bulletMatch))
                continue
            }
            
            // --- Numbered list: 1. item, 2) item ---
            if let (num, text) = trimmed.numberedContent {
                flushParagraph()
                blocks.append(.numbered(num, text))
                continue
            }
            
            // --- Empty line = paragraph break ---
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }
            
            // --- Regular text (accumulate into paragraph) ---
            paragraphLines.append(trimmed)
        }
        
        // Flush remaining
        if inCodeBlock && !codeLines.isEmpty {
            blocks.append(.code(codeLines.joined(separator: "\n")))
        }
        flushParagraph()
        
        return blocks
    }
}

// MARK: - String Helpers

private extension String {
    /// Returns the text after the bullet marker, or nil if not a bullet line.
    var bulletContent: String? {
        let trimmed = self.trimmingCharacters(in: .whitespaces)
        for prefix in ["* ", "- ", "• "] {
            if trimmed.hasPrefix(prefix) {
                let text = String(trimmed.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespaces)
                return text.isEmpty ? nil : text
            }
        }
        return nil
    }
    
    /// Returns (number, text) if this is a numbered list item, otherwise nil.
    var numberedContent: (Int, String)? {
        let trimmed = self.trimmingCharacters(in: .whitespaces)
        // Match patterns like "1. text" or "1) text"
        guard let firstChar = trimmed.first, firstChar.isNumber else { return nil }
        
        // Find the end of the number
        var numEnd = trimmed.startIndex
        while numEnd < trimmed.endIndex && trimmed[numEnd].isNumber {
            numEnd = trimmed.index(after: numEnd)
        }
        
        guard numEnd < trimmed.endIndex else { return nil }
        let separator = trimmed[numEnd]
        guard separator == "." || separator == ")" else { return nil }
        
        let afterSep = trimmed.index(after: numEnd)
        guard afterSep < trimmed.endIndex,
              trimmed[afterSep] == " " else { return nil }
        
        guard let num = Int(trimmed[trimmed.startIndex..<numEnd]) else { return nil }
        
        let text = String(trimmed[trimmed.index(after: afterSep)...])
            .trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (num, text)
    }
}

// MARK: - Preview

#Preview("Markdown Rendering") {
    ScrollView {
        MarkdownTextView(
            """
            In Scene 2, there is one text object:
            
            *  **"chapter_title"**: Displays the text **"Chapter One"**. It uses the **Montserrat** font (Bold) at size **120** and is positioned at the center of the canvas (540, 540).
            
            Here's a code example:
            ```
            let x = 42
            print(x)
            ```
            
            And a numbered list:
            1. First item with **bold**
            2. Second item with *italic*
            3. Third item
            """,
            foregroundColor: AppTheme.Colors.textPrimary,
            font: .system(size: 13)
        )
        .padding()
        .background(AppTheme.Colors.surface)
        .cornerRadius(12)
        .padding()
    }
    .frame(width: 400, height: 500)
    .background(AppTheme.Colors.background)
}
