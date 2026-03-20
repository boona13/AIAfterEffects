//
//  AnimatedTextView.swift
//  AIAfterEffects
//
//  Advanced typography animations for text objects
//

import SwiftUI
import AppKit

struct TextAnimationEffect {
    let progress: Double
    let rawProgress: Double
    let intensity: Double
    let duration: Double
}

struct TextAnimationState {
    var typewriter: TextAnimationEffect?
    var charByChar: TextAnimationEffect?
    var wordByWord: TextAnimationEffect?
    var lineByLine: TextAnimationEffect?
    var scramble: TextAnimationEffect?
    var wave: TextAnimationEffect?
    var glitchText: TextAnimationEffect?
    
    var isEmpty: Bool {
        typewriter == nil &&
        charByChar == nil &&
        wordByWord == nil &&
        lineByLine == nil &&
        scramble == nil &&
        wave == nil &&
        glitchText == nil
    }
    
    static let supportedTypes: Set<AnimationType> = [
        .typewriter, .charByChar, .wordByWord, .lineByLine,
        .scramble, .wave, .glitchText
    ]
    
    mutating func update(effect: TextAnimationEffect, for type: AnimationType) {
        switch type {
        case .typewriter:
            typewriter = effect
        case .charByChar:
            charByChar = effect
        case .wordByWord:
            wordByWord = effect
        case .lineByLine:
            lineByLine = effect
        case .scramble:
            scramble = effect
        case .wave:
            wave = effect
        case .glitchText:
            glitchText = effect
        default:
            break
        }
    }
}

struct AnimatedTextView: View {
    let properties: AnimatedProperties
    let objectProperties: ObjectProperties
    let animationState: TextAnimationState
    let currentTime: Double
    var tracking: Double = 0
    
    var body: some View {
        let text = objectProperties.text ?? "Text"
        let font = resolveFont()
        let baseColor = properties.fillColor.color
        
        if animationState.isEmpty || text.isEmpty {
            Text(text)
                .font(font)
                .kerning(tracking)
                .foregroundColor(baseColor)
                .multilineTextAlignment(textAlignment)
        } else {
            let glyphs = TextGlyphs(text: text)
            if glyphs.totalCount > 240 {
                Text(text)
                    .font(font)
                    .kerning(tracking)
                    .foregroundColor(baseColor)
                    .multilineTextAlignment(textAlignment)
            } else {
                VStack(alignment: horizontalAlignment, spacing: lineSpacing) {
                    ForEach(glyphs.lines) { line in
                        HStack(spacing: tracking) {
                            ForEach(line.glyphs) { glyph in
                                glyphView(
                                    glyph,
                                    metrics: glyphs,
                                    font: font,
                                    baseColor: baseColor
                                )
                            }
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func glyphView(
        _ glyph: TextGlyph,
        metrics: TextGlyphs,
        font: Font,
        baseColor: Color
    ) -> some View {
        let style = glyphStyle(for: glyph, metrics: metrics)
        let glitchStrength = glitchStrengthValue()
        
        let baseText = Text(style.displayChar)
            .font(font)
            .foregroundColor(baseColor)
            .opacity(style.opacity)
            .scaleEffect(style.scale)
            .rotationEffect(.degrees(style.rotation))
            .offset(x: style.offset.width, y: style.offset.height)
        
        if glitchStrength > 0.05 && !glyph.isWhitespace {
            let offsets = glitchOffsets(for: glyph, strength: glitchStrength)
            ZStack {
                Text(style.displayChar)
                    .font(font)
                    .foregroundColor(.red)
                    .opacity(style.opacity * 0.7)
                    .offset(
                        x: style.offset.width + offsets.red.width,
                        y: style.offset.height + offsets.red.height
                    )
                Text(style.displayChar)
                    .font(font)
                    .foregroundColor(.blue)
                    .opacity(style.opacity * 0.6)
                    .offset(
                        x: style.offset.width + offsets.blue.width,
                        y: style.offset.height + offsets.blue.height
                    )
                baseText
            }
        } else {
            baseText
        }
    }
    
    private func glyphStyle(for glyph: TextGlyph, metrics: TextGlyphs) -> GlyphStyle {
        var style = GlyphStyle(displayChar: glyph.char)
        let fontSize = objectProperties.fontSize ?? 48
        
        if let reveal = primaryRevealEffect() {
            let localProgress = revealProgress(
                for: glyph,
                metrics: metrics,
                effect: reveal.effect,
                type: reveal.type
            )
            let intensity = max(0.6, reveal.effect.intensity)
            
            switch reveal.type {
            case .typewriter:
                style.opacity = localProgress > 0 ? 1 : 0
                
            case .charByChar:
                style.opacity = localProgress
                style.offset.height += (1 - localProgress) * fontSize * 0.35 * intensity
                style.scale *= 0.85 + 0.15 * localProgress
                style.rotation += (1 - localProgress) * -4 * intensity
                
            case .wordByWord:
                style.opacity = localProgress
                style.offset.height += (1 - localProgress) * fontSize * 0.45 * intensity
                style.scale *= 0.9 + 0.1 * localProgress
                
            case .lineByLine:
                style.opacity = localProgress
                style.offset.height += (1 - localProgress) * fontSize * 0.6 * intensity
                style.scale *= 0.95 + 0.05 * localProgress
                
            case .scramble:
                if glyph.isWhitespace {
                    style.opacity = 1
                } else if localProgress >= 1 {
                    style.opacity = 1
                } else {
                    style.displayChar = scrambleCharacter(for: glyph)
                    style.opacity = 0.85
                }
            }
        }
        
        if let wave = animationState.wave {
            let baseAmplitude = min(20, max(4, fontSize * 0.35))
            let strength = max(0.2, min(1.4, wave.intensity))
            let phase = Double(glyph.index) * 0.45 + currentTime * 6
            let waveOffset = sin(phase) * baseAmplitude * strength * wave.progress
            style.offset.height += waveOffset
        }
        
        if let glitch = animationState.glitchText, glitch.intensity > 0.05 {
            let strength = glitchStrengthValue()
            let phase = currentTime * 24 + Double(glyph.index) * 0.7
            style.offset.width += sin(phase) * 2.2 * strength
            style.offset.height += cos(phase * 1.3) * 1.4 * strength
        }
        
        style.opacity = min(max(style.opacity, 0), 1)
        return style
    }
    
    private func primaryRevealEffect() -> (type: RevealType, effect: TextAnimationEffect)? {
        if let effect = animationState.typewriter {
            return (.typewriter, effect)
        }
        if let effect = animationState.charByChar {
            return (.charByChar, effect)
        }
        if let effect = animationState.wordByWord {
            return (.wordByWord, effect)
        }
        if let effect = animationState.lineByLine {
            return (.lineByLine, effect)
        }
        if let effect = animationState.scramble {
            return (.scramble, effect)
        }
        return nil
    }
    
    private func revealProgress(
        for glyph: TextGlyph,
        metrics: TextGlyphs,
        effect: TextAnimationEffect,
        type: RevealType
    ) -> Double {
        let unitIndex: Int
        let unitCount: Int
        
        switch type {
        case .typewriter, .charByChar, .scramble:
            unitIndex = glyph.index
            unitCount = metrics.totalCount
        case .wordByWord:
            unitIndex = glyph.wordIndex
            unitCount = metrics.wordCount
        case .lineByLine:
            unitIndex = glyph.lineIndex
            unitCount = metrics.lineCount
        }
        
        guard unitCount > 0 else { return 1 }
        let local = effect.progress * Double(unitCount) - Double(unitIndex)
        return min(max(local, 0), 1)
    }
    
    private func scrambleCharacter(for glyph: TextGlyph) -> String {
        let seed = glyph.index + Int(currentTime * 30)
        let pool = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#$%&*+")
        let index = abs(seed) % max(pool.count, 1)
        return String(pool[index])
    }
    
    private func glitchStrengthValue() -> Double {
        guard let glitch = animationState.glitchText else { return 0 }
        return min(1, max(0, glitch.intensity / 12))
    }
    
    private func glitchOffsets(
        for glyph: TextGlyph,
        strength: Double
    ) -> (red: CGSize, blue: CGSize) {
        let phase = currentTime * 18 + Double(glyph.index) * 1.3
        let offsetX = sin(phase) * 6 * strength
        let offsetY = cos(phase * 0.9) * 2.5 * strength
        return (
            red: CGSize(width: offsetX, height: -offsetY),
            blue: CGSize(width: -offsetX, height: offsetY)
        )
    }
    
    private var lineSpacing: Double {
        let size = objectProperties.fontSize ?? 48
        return max(4, size * 0.22)
    }
    
    private enum RevealType {
        case typewriter
        case charByChar
        case wordByWord
        case lineByLine
        case scramble
    }
    
    private var horizontalAlignment: HorizontalAlignment {
        switch objectProperties.textAlignment?.lowercased() {
        case "left":
            return .leading
        case "right":
            return .trailing
        default:
            return .center
        }
    }
    
    private var textAlignment: TextAlignment {
        switch objectProperties.textAlignment?.lowercased() {
        case "left":
            return .leading
        case "right":
            return .trailing
        default:
            return .center
        }
    }
    
    private func resolveFont() -> Font {
        let size = objectProperties.fontSize ?? 48
        
        if let fontName = objectProperties.fontName, fontName.lowercased() != "sf pro" {
            if let resolvedName = findFontName(family: fontName, weight: objectProperties.fontWeight) {
                return .custom(resolvedName, size: size)
            }
            return .custom(fontName, size: size)
        }
        return .system(size: size, weight: fontWeight)
    }
    
    /// Find the exact PostScript/full name for a font family + weight combination
    private func findFontName(family: String, weight: String?) -> String? {
        let fontManager = NSFontManager.shared
        
        guard let members = fontManager.availableMembers(ofFontFamily: family) else {
            return nil
        }
        
        let targetWeight = mapWeightToNSFontWeight(weight)
        
        var bestMatch: String?
        var bestWeightDiff = Int.max
        
        for member in members {
            guard let postScriptName = member[0] as? String,
                  let fontWeight = member[2] as? Int else { continue }
            
            let weightDiff = abs(fontWeight - targetWeight)
            if weightDiff < bestWeightDiff {
                bestWeightDiff = weightDiff
                bestMatch = postScriptName
            }
        }
        
        return bestMatch
    }
    
    /// Map font weight string to NSFont weight value (0-15 scale, 5 = regular)
    private func mapWeightToNSFontWeight(_ weight: String?) -> Int {
        guard let weight = weight?.lowercased() else { return 5 }
        
        switch weight {
        case "thin", "hairline", "100": return 2
        case "ultralight", "extralight", "200": return 3
        case "light", "300": return 4
        case "regular", "normal", "400", "book": return 5
        case "medium", "500": return 6
        case "semibold", "demibold", "600": return 8
        case "bold", "700": return 9
        case "extrabold", "ultrabold", "800": return 10
        case "black", "heavy", "900": return 12
        default: return 5
        }
    }
    
    private var fontWeight: Font.Weight {
        switch objectProperties.fontWeight?.lowercased() {
        case "bold", "700": return .bold
        case "semibold", "demibold", "600": return .semibold
        case "medium", "500": return .medium
        case "light", "300": return .light
        case "thin", "100": return .thin
        case "heavy": return .heavy
        case "black", "900": return .black
        case "ultralight", "extralight", "200": return .ultraLight
        default: return .regular
        }
    }
}

private struct GlyphStyle {
    var displayChar: String
    var opacity: Double = 1
    var offset: CGSize = .zero
    var scale: Double = 1
    var rotation: Double = 0
}

private struct TextGlyph: Identifiable {
    let id: Int
    let char: String
    let index: Int
    let wordIndex: Int
    let lineIndex: Int
    let isWhitespace: Bool
}

private struct TextGlyphLine: Identifiable {
    let id: Int
    let glyphs: [TextGlyph]
}

private struct TextGlyphs {
    let glyphs: [TextGlyph]
    let lines: [TextGlyphLine]
    let totalCount: Int
    let wordCount: Int
    let lineCount: Int
    
    init(text: String) {
        var glyphs: [TextGlyph] = []
        var lineBuckets: [[TextGlyph]] = [[]]
        var lineIndex = 0
        var wordIndex = -1
        var inWord = false
        
        for char in text {
            if char == "\n" {
                lineIndex += 1
                inWord = false
                if lineBuckets.count <= lineIndex {
                    lineBuckets.append([])
                }
                continue
            }
            
            let isWhitespace = char.isWhitespace
            if isWhitespace {
                inWord = false
            } else if !inWord {
                wordIndex += 1
                inWord = true
            }
            
            let safeWordIndex = max(wordIndex, 0)
            let glyph = TextGlyph(
                id: glyphs.count,
                char: String(char),
                index: glyphs.count,
                wordIndex: safeWordIndex,
                lineIndex: lineIndex,
                isWhitespace: isWhitespace
            )
            glyphs.append(glyph)
            
            if lineBuckets.count <= lineIndex {
                lineBuckets.append([])
            }
            lineBuckets[lineIndex].append(glyph)
        }
        
        self.glyphs = glyphs
        self.lines = lineBuckets.enumerated().map { index, line in
            TextGlyphLine(id: index, glyphs: line)
        }
        self.totalCount = max(glyphs.count, 1)
        self.wordCount = max(wordIndex + 1, 1)
        self.lineCount = max(self.lines.count, 1)
    }
}
