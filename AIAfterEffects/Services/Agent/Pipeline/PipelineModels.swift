//
//  PipelineModels.swift
//  AIAfterEffects
//
//  Data models shared across the multi-agent creative pipeline.
//  Each agent produces one of these as output, feeding into the next.
//

import Foundation

// MARK: - Pipeline Stage

enum PipelineStage: String, CaseIterable {
    case director = "Creative Director"
    case designer = "Art Director"
    case choreographer = "Choreographer"
    case executor = "Executor"
    case validator = "QA Validator"
    case critic = "Reviewer"
    
    var iconName: String {
        switch self {
        case .director: return "lightbulb.fill"
        case .designer: return "paintpalette.fill"
        case .choreographer: return "music.note.list"
        case .executor: return "hammer.fill"
        case .validator: return "checkmark.shield.fill"
        case .critic: return "eye.fill"
        }
    }
    
    var activityLabel: String {
        switch self {
        case .director: return "Defining creative vision..."
        case .designer: return "Crafting visual system..."
        case .choreographer: return "Composing motion score..."
        case .executor: return "Building the scene..."
        case .validator: return "Validating positions & timing..."
        case .critic: return "Reviewing quality..."
        }
    }
}

enum CreativePipelineError: LocalizedError {
    case stageFailed(PipelineStage)
    
    var errorDescription: String? {
        switch self {
        case .stageFailed(let stage):
            return "The \(stage.rawValue) stage did not return a usable result, so the request was stopped."
        }
    }
}

// MARK: - Director Output

struct CreativeDirective {
    let concept: String
    let emotionalArc: String
    let metaphor: String
    let tone: [String]
    let climaxDescription: String
    let targetDuration: Double
    let rawText: String
    
    static func parse(from text: String) -> CreativeDirective {
        let lowered = text.lowercased()
        
        let concept = extractField(named: "concept", from: text) ?? "Dynamic motion sequence"
        let arc = extractField(named: "emotional_arc", from: text)
            ?? extractField(named: "arc", from: text)
            ?? "Build tension, reveal hero, develop, climax, resolve"
        let metaphor = extractField(named: "metaphor", from: text) ?? "Unveiling"
        let toneRaw = extractField(named: "tone", from: text) ?? "bold, cinematic, energetic"
        let tone = toneRaw.components(separatedBy: CharacterSet(charactersIn: ",;"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let climax = extractField(named: "climax", from: text) ?? "Impact moment at the two-thirds mark"
        
        var duration: Double = 14.0
        if let dStr = extractField(named: "duration", from: text),
           let d = Double(dStr.replacingOccurrences(of: "s", with: "").trimmingCharacters(in: .whitespaces)) {
            duration = d
        } else if lowered.contains("short") || lowered.contains("6s") {
            duration = 8.0
        } else if lowered.contains("long") || lowered.contains("20") {
            duration = 20.0
        }
        
        return CreativeDirective(
            concept: concept,
            emotionalArc: arc,
            metaphor: metaphor,
            tone: tone,
            climaxDescription: climax,
            targetDuration: duration,
            rawText: text
        )
    }
}

// MARK: - Designer Output

struct VisualSystem {
    let headlineFont: String
    let headlineWeight: String
    let bodyFont: String
    let colorPalette: [String]
    let accentColor: String
    let backgroundColors: [String]
    let layoutNotes: String
    let hierarchyNotes: String
    let particleShapes: [String]
    let rawText: String
    
    static func parse(from text: String) -> VisualSystem {
        let headlineFont = extractField(named: "headline_font", from: text)
            ?? extractField(named: "headlinefont", from: text)
            ?? extractField(named: "headline font", from: text)
            ?? "Montserrat"
        let headlineWeight = extractField(named: "headline_weight", from: text)
            ?? extractField(named: "weight", from: text)
            ?? "Bold"
        let bodyFont = extractField(named: "body_font", from: text)
            ?? extractField(named: "bodyfont", from: text)
            ?? extractField(named: "body font", from: text)
            ?? "Roboto"
        
        // Extract ALL hex colors from the entire text (robust fallback)
        let allHexColors = extractAllHexColors(from: text)
        
        let paletteRaw = extractField(named: "palette", from: text)
            ?? extractField(named: "color_palette", from: text)
            ?? extractField(named: "color palette", from: text)
        
        var palette: [String]
        if let raw = paletteRaw {
            palette = extractHexColorsFromLine(raw)
        } else {
            palette = []
        }
        // Fallback: use all hex colors found in the text (deduplicated)
        if palette.isEmpty {
            palette = Array(allHexColors.prefix(7))
        }
        
        let accentRaw = extractField(named: "accent", from: text)
            ?? extractField(named: "accent_color", from: text)
            ?? extractField(named: "accent color", from: text)
        let accent = accentRaw.flatMap { extractHexColorsFromLine($0).first }
            ?? palette.dropFirst(2).first
            ?? "#FF4500"
        
        let bgRaw = extractField(named: "backgrounds", from: text)
            ?? extractField(named: "background_colors", from: text)
            ?? extractField(named: "background colors", from: text)
            ?? extractField(named: "background", from: text)
        var backgrounds: [String]
        if let raw = bgRaw {
            backgrounds = extractHexColorsFromLine(raw)
        } else {
            backgrounds = []
        }
        if backgrounds.isEmpty, let firstDark = allHexColors.first(where: { isColorDark($0) }) {
            backgrounds = [firstDark]
        }
        
        let layout = extractField(named: "layout", from: text) ?? "Hero center, text right-third"
        let hierarchy = extractField(named: "hierarchy", from: text) ?? "Headline 80-110px, body 28-36px, accent 14-18px"
        
        let particleShapesRaw = extractField(named: "particle_shapes", from: text)
            ?? extractField(named: "particleshapes", from: text)
            ?? extractField(named: "particle shapes", from: text)
        let particleShapes: [String]
        if let raw = particleShapesRaw {
            particleShapes = raw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        } else {
            particleShapes = ["circle", "star"]
        }
        
        return VisualSystem(
            headlineFont: headlineFont,
            headlineWeight: headlineWeight,
            bodyFont: bodyFont,
            colorPalette: palette.isEmpty ? ["#FFFFFF", "#000000", "#FF4500"] : palette,
            accentColor: accent,
            backgroundColors: backgrounds.isEmpty ? ["#050508"] : backgrounds,
            layoutNotes: layout,
            hierarchyNotes: hierarchy,
            particleShapes: particleShapes,
            rawText: text
        )
    }
}

// MARK: - Choreographer Output

struct MotionBeat {
    let label: String
    let timeRange: String
    let dynamics: String
    let emotion: String
    let motionIntent: String
    let uniqueAnimations: [String]
    let isRestBeat: Bool
}

struct MotionScore {
    let beats: [MotionBeat]
    let impactMoments: [String]
    let overallDynamics: String
    let rawText: String
    
    var restBeatCount: Int { beats.filter(\.isRestBeat).count }
    var uniqueAnimationTypes: Set<String> {
        Set(beats.flatMap(\.uniqueAnimations).map { $0.lowercased() })
    }
    
    static func parse(from text: String) -> MotionScore {
        var beats: [MotionBeat] = []
        var impacts: [String] = []
        
        let lines = text.components(separatedBy: .newlines)
        var currentLabel = ""
        var currentTime = ""
        var currentDynamics = ""
        var currentEmotion = ""
        var currentIntent = ""
        var currentAnims: [String] = []
        var currentBodyLines: [String] = []
        var inBeat = false
        
        func flushBeat() {
            guard inBeat, !currentLabel.isEmpty else { return }
            
            // If animations list is empty, scan the body text for known animation names
            if currentAnims.isEmpty {
                currentAnims = extractKnownAnimations(from: currentBodyLines.joined(separator: " "))
            }
            
            // Try to extract dynamics from body if not found in a labeled field
            if currentDynamics.isEmpty {
                for dyn in ["ff", "f", "mf", "mp", "p", "pp", "fortissimo", "forte", "mezzo-forte", "mezzo-piano", "piano", "pianissimo"] {
                    if currentBodyLines.joined(separator: " ").lowercased().contains(dyn) {
                        currentDynamics = dyn; break
                    }
                }
            }
            
            let allText = (currentIntent + " " + currentBodyLines.joined(separator: " ")).lowercased()
            let isRest = allText.contains("rest") || allText.contains("hold")
                || allText.contains("stillness") || allText.contains("pause")
                || allText.contains("breath") || allText.contains("silence")
            
            beats.append(MotionBeat(
                label: currentLabel, timeRange: currentTime,
                dynamics: currentDynamics, emotion: currentEmotion,
                motionIntent: currentIntent.isEmpty ? currentBodyLines.joined(separator: " ") : currentIntent,
                uniqueAnimations: currentAnims,
                isRestBeat: isRest
            ))
        }
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let stripped = stripMarkdown(trimmed)
            let low = stripped.lowercased()
            
            // Detect beat headers with multiple patterns:
            // "Beat 1:", "## Beat 1", "### Beat 1:", "**Beat 1:**", "1. Beat:", "1) VOID [0-2s]"
            let isBeatHeader = low.hasPrefix("beat ")
                || low.hasPrefix("beat:")
                || (trimmed.hasPrefix("#") && low.contains("beat"))
                || (trimmed.hasPrefix("**") && low.contains("beat"))
                || matchesNumberedBeat(trimmed)
            
            if isBeatHeader {
                flushBeat()
                inBeat = true
                currentLabel = stripped
                    .replacingOccurrences(of: "Beat ", with: "", options: .caseInsensitive)
                currentLabel = "Beat " + currentLabel.trimmingCharacters(in: CharacterSet(charactersIn: "#*-:. ").union(.decimalDigits))
                    .trimmingCharacters(in: .whitespaces)
                if currentLabel == "Beat " { currentLabel = stripped }
                currentTime = ""
                currentDynamics = ""
                currentEmotion = ""
                currentIntent = ""
                currentAnims = []
                currentBodyLines = []
                
                // Try to extract time range from the header itself: [0-2s], [0s-2s], (0-2s)
                if let timeRange = extractTimeRange(from: trimmed) {
                    currentTime = timeRange
                }
                // Try to extract dynamics from header: — pp, — f (forte)
                for dyn in ["pp", "p", "mp", "mf", "f", "ff"] {
                    let dynPatterns = [" \(dyn) ", " \(dyn)(", "— \(dyn)", "- \(dyn)", "(\(dyn))"]
                    for dp in dynPatterns {
                        if low.contains(dp) { currentDynamics = dyn; break }
                    }
                    if !currentDynamics.isEmpty { break }
                }
                continue
            }
            
            guard inBeat else {
                if low.contains("impact") || low.contains("flash") { impacts.append(trimmed) }
                continue
            }
            
            // Extract labeled fields with flexible matching
            let fieldValue = extractFlexibleField(named: "time", from: trimmed)
                ?? extractFlexibleField(named: "time range", from: trimmed)
            if let val = fieldValue, !val.isEmpty { currentTime = val }
            
            if let val = extractFlexibleField(named: "dynamics", from: trimmed), !val.isEmpty { currentDynamics = val }
            if let val = extractFlexibleField(named: "emotion", from: trimmed), !val.isEmpty { currentEmotion = val }
            
            if let val = extractFlexibleField(named: "motion", from: trimmed)
                ?? extractFlexibleField(named: "motion intent", from: trimmed)
                ?? extractFlexibleField(named: "intent", from: trimmed)
                ?? extractFlexibleField(named: "description", from: trimmed), !val.isEmpty {
                currentIntent = val
            }
            
            if let val = extractFlexibleField(named: "animations", from: trimmed)
                ?? extractFlexibleField(named: "unique animations", from: trimmed)
                ?? extractFlexibleField(named: "animation types", from: trimmed), !val.isEmpty {
                currentAnims = val.components(separatedBy: CharacterSet(charactersIn: ",;"))
                    .map { stripMarkdown($0).trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
            
            if low.contains("impact") || low.contains("flash") { impacts.append(trimmed) }
            currentBodyLines.append(stripped)
        }
        
        flushBeat()
        
        // Fallback: if parsing yielded 0 beats, inject the raw text as a single beat
        // so the Executor at least gets the choreographer's guidance
        if beats.isEmpty {
            let allAnims = extractKnownAnimations(from: text)
            beats.append(MotionBeat(
                label: "Full Sequence", timeRange: "0s-14s",
                dynamics: "mf", emotion: "",
                motionIntent: String(text.prefix(2000)),
                uniqueAnimations: allAnims,
                isRestBeat: false
            ))
        }
        
        return MotionScore(
            beats: beats,
            impactMoments: impacts,
            overallDynamics: beats.map(\.dynamics).joined(separator: " → "),
            rawText: text
        )
    }
}

// MARK: - Critic Output

struct ReviewNotes {
    let issues: [String]
    let suggestions: [String]
    let needsRevision: Bool
    let patchInstructions: String?
    let rawText: String
    
    static func parse(from text: String) -> ReviewNotes {
        var issues: [String] = []
        var suggestions: [String] = []
        var patchLines: [String] = []
        
        let lines = text.components(separatedBy: .newlines)
        var currentSection = "" // "issues", "suggestions", "patch", or ""
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let low = trimmed.lowercased()
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "##", with: "")
                .trimmingCharacters(in: .whitespaces)
            
            // Detect section headers (flexible: handles markdown bold, headers, etc.)
            if low.hasPrefix("issue") || low.hasPrefix("problem") || low.hasPrefix("flag")
                || low.contains("blocking") {
                currentSection = "issues"; continue
            }
            if low.hasPrefix("suggestion") || low.hasPrefix("improve") || low.hasPrefix("recommend")
                || low.contains("nice to have") || low.contains("non-blocking") {
                currentSection = "suggestions"; continue
            }
            if low.hasPrefix("patch") || low.hasPrefix("fix") || low.hasPrefix("revision")
                || low.contains("fix instruction") || low.contains("specific fix") {
                currentSection = "patch"; continue
            }
            
            // Extract bullet items or numbered items
            let isBullet = trimmed.hasPrefix("-") || trimmed.hasPrefix("*") || trimmed.hasPrefix("•")
            let isNumbered = trimmed.first?.isNumber == true && trimmed.dropFirst(3).first == "." || trimmed.dropFirst(2).first == "."
            
            if isBullet || isNumbered {
                var content = trimmed
                if isBullet { content = String(content.dropFirst()).trimmingCharacters(in: .whitespaces) }
                else if isNumbered, let dotIdx = content.firstIndex(of: ".") {
                    content = String(content[content.index(after: dotIdx)...]).trimmingCharacters(in: .whitespaces)
                }
                content = content.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
                
                switch currentSection {
                case "issues": issues.append(content)
                case "suggestions": suggestions.append(content)
                case "patch": patchLines.append(content)
                default:
                    // No section header yet — infer from content
                    let contentLow = content.lowercased()
                    if contentLow.contains("replace") || contentLow.contains("change") || contentLow.contains("fix")
                        || contentLow.contains("swap") || contentLow.contains("use ") {
                        issues.append(content)
                        patchLines.append(content)
                    }
                }
            }
        }
        
        let patchInstructions: String? = patchLines.isEmpty ? nil : patchLines.joined(separator: "\n")
        
        let lowered = text.lowercased()
        let isApproved = lowered.contains("approved") && !lowered.contains("not approved")
        let needsRevision = !isApproved && (
            !issues.isEmpty
            || lowered.contains("needs revision")
            || lowered.contains("needs fix")
            || lowered.contains("must fix")
            || (lowered.contains("revise") && !lowered.contains("no revis"))
        )
        
        return ReviewNotes(
            issues: issues,
            suggestions: suggestions,
            needsRevision: needsRevision,
            patchInstructions: patchInstructions,
            rawText: text
        )
    }
}

// MARK: - Pipeline Brief (bundles all agent outputs)

struct PipelineBrief {
    let directive: CreativeDirective
    let visualSystem: VisualSystem
    let motionScore: MotionScore
    var has3DModelAttached: Bool = true
    
    func asSystemPromptSection() -> String {
        var section = ""
        
        section += "## ⚡ EXECUTION MODE: JSON OUTPUT ONLY\n"
        section += "You have a structured creative brief from the pipeline. "
        section += "Generate your ENTIRE scene as a single JSON response with a \"message\" and \"actions\" array. "
        section += "Do NOT call any tools (update_object, project_info, query_objects, etc.). Just output JSON.\n\n"
        
        section += "## Creative Directive (from Director)\n"
        section += "Concept: \(directive.concept)\n"
        section += "Emotional Arc: \(directive.emotionalArc)\n"
        section += "Metaphor: \(directive.metaphor)\n"
        section += "Tone: \(directive.tone.joined(separator: ", "))\n"
        section += "Climax: \(directive.climaxDescription)\n"
        section += "Target Duration: \(directive.targetDuration)s\n\n"
        
        section += "## Visual System (from Art Director)\n"
        section += "Headline: \(visualSystem.headlineFont) \(visualSystem.headlineWeight)\n"
        section += "Body: \(visualSystem.bodyFont)\n"
        section += "Palette: \(visualSystem.colorPalette.joined(separator: ", "))\n"
        section += "Accent: \(visualSystem.accentColor)\n"
        section += "Backgrounds: \(visualSystem.backgroundColors.joined(separator: " → "))\n"
        section += "Particle shapes: \(visualSystem.particleShapes.joined(separator: ", "))\n"
        section += "Layout: \(visualSystem.layoutNotes)\n"
        section += "Hierarchy: \(visualSystem.hierarchyNotes)\n\n"
        
        if !has3DModelAttached {
            section += "## ⚠️ CRITICAL: NO 3D MODEL\n"
            section += "The user did NOT attach a 3D model. Do NOT create any model3D objects. "
            section += "Do NOT use modelAssetId. Use ONLY 2D elements: images (via attachmentIndex), "
            section += "text, shapes, shaders, and effects. Ignore any model3D objects from previous sessions.\n\n"
        }
        
        section += "## Motion Score (from Choreographer)\n"
        section += "Follow this score PRECISELY. Each beat defines what happens and when.\n\n"
        for beat in motionScore.beats {
            section += "### \(beat.label)"
            if !beat.timeRange.isEmpty { section += " [\(beat.timeRange)]" }
            if !beat.dynamics.isEmpty { section += " — \(beat.dynamics)" }
            section += "\n"
            if !beat.emotion.isEmpty { section += "Emotion: \(beat.emotion)\n" }
            if !beat.motionIntent.isEmpty { section += "Motion: \(beat.motionIntent)\n" }
            if !beat.uniqueAnimations.isEmpty { section += "Animations: \(beat.uniqueAnimations.joined(separator: ", "))\n" }
            if beat.isRestBeat { section += "⚡ REST BEAT — hold, do not add new elements\n" }
            section += "\n"
        }
        
        if !motionScore.impactMoments.isEmpty {
            section += "Impact Moments: \(motionScore.impactMoments.joined(separator: "; "))\n\n"
        }
        
        let minObjects = max(motionScore.beats.count * 3, 20)
        let minActions = max(motionScore.beats.count * 12, 80)
        
        section += "## EXECUTION RULES\n"
        section += "⚠️ MINIMUM OUTPUT REQUIRED: at least \(minObjects) objects and \(minActions) actions total.\n"
        section += "Each beat should produce 3-8 objects (text, shapes, effects, procedural layers, decorative layers) "
        section += "and 8-15 actions (createObject + addAnimation + applyPreset). A 25s cinematic with only "
        section += "a 3D model and a few text labels is UNACCEPTABLE.\n\n"
        section += "1. Execute EVERY beat from the motion score. Do NOT skip or combine beats. "
        section += "The creative decisions are ALREADY MADE — your job is to EXECUTE them faithfully.\n"
        section += "2. For EACH beat, create the environment layers, compositional accents, procedural systems, "
        section += "decorative shapes, and text overlays described in the motion intent. Do NOT inject default sparks or explosions unless the beat truly calls for them.\n"
        section += "3. Use the EXACT animation types listed in each beat — do NOT substitute with fadeIn/slideUp.\n"
        section += "4. Use the EXACT colors from the visual system palette — do NOT default to #000000/#FFFFFF.\n"
        section += "5. Use the EXACT fonts specified — do NOT fall back to system defaults.\n"
        section += "6. Add background animations (backgroundShift, colorCycle, shader overlays) as specified.\n"
        section += "7. REST beats mean NO new objects appear — only holds or subtle effects.\n"
        section += "8. Climax beat must feel DIFFERENT — sharper, denser, quieter, or more precise according to the concept. Use the treatment the score calls for, not a default flash/explosion package.\n"
        section += "9. Vary stagger offsets between beats — do NOT use 0.1s everywhere.\n"
        section += "10. NEVER use fadeIn for more than 2 objects total. NEVER use slideUp for more than 2 objects total.\n"
        section += "11. 🚫 NEVER set repeatCount:-1 on 3D model animations (levitate, breathe3D, float3D, wobble3D, etc.). "
        section += "Infinite loops create a cheap DVD-screensaver bouncing effect. "
        section += "Instead, use DIRECTED transitions: give each animation a clear fromValue→toValue with smooth easing "
        section += "(easeOutCubic, easeInOutSine). The model should move TO a destination, not bounce forever.\n"
        section += "12. repeatCount:-1 is ONLY acceptable for background/atmosphere (neonPulse on text, shimmer on procedural fields, "
        section += "rotate on decorative rings). NEVER on the hero model or images.\n\n"
        
        section += "## VISUAL STORYTELLING (what separates cinematic from amateur)\n"
        section += "Objects must feel CONNECTED to the same scene — not randomly placed.\n\n"
        section += "### Cause and Effect\n"
        section += "Every major action should produce a coherent reaction in the scene. "
        section += "A move can trigger a field ripple, a lighting shift, a geometric echo, a camera response, or a procedural system that inherits the source motion. "
        section += "Do NOT default to sparks, debris, or screen flashes unless the concept explicitly wants violent impact.\n\n"
        section += "### Spatial Relationships\n"
        section += "- Procedural systems should originate FROM, orbit AROUND, trace, or phase-lock to the hero object when the concept calls for them — not float at random positions.\n"
        section += "- Text should be framed by accent elements (thin lines above/below, glowing dots at corners, subtle rectangles).\n"
        section += "- Light beams, contours, ripples, or mathematical fields should align with the subject's motion or composition, not appear as random filler.\n"
        section += "- Ground elements (cracks, shadows, reflections) should be positioned BELOW the model.\n"
        section += "- If you use particles or shards, make them physically or mathematically coherent: attractors, orbitals, curl fields, spirals, wavefronts, interference rings, or controlled fracture paths.\n\n"
        section += "### Layered Environment\n"
        section += "Build the scene in visual DEPTH layers:\n"
        section += "- Background (z:0-2): Shaders, gradient overlays, slow-drifting textures\n"
        section += "- Mid-ground (z:3-8): Procedural systems, light shafts, environmental effects, decorative shapes\n"
        section += "- Subject (z:9-12): The 3D model and its direct effects (rings, ground elements)\n"
        section += "- Foreground (z:13-25): Text, UI elements, accent graphics\n"
        section += "- Overlay (z:50+): Screen flashes, vignettes, full-screen effects\n\n"
        section += "### Mood Continuity\n"
        section += "Colors should shift with the emotional arc. Dark/cold palette for tension → warm/bright for impact → "
        section += "cool/confident for resolve. Use propertyChange animations on shader opacity or backgroundShift to evolve the mood.\n\n"
        
        section += "## ⚡ PROCEDURAL EFFECTS (use applyEffect for complex motion)\n"
        section += "Use `applyEffect` only when it genuinely improves the beat. When you use procedural VFX, prefer mathematically structured motion over generic spark bursts:\n"
        section += "- `particleBurst`: Only when the concept truly needs particulate breakup; make it structured and intentional, not a default explosion\n"
        section += "- `splash`: Water impact with radial droplets on parabolic trajectories\n"
        section += "- `shatter`: Object breaks into spinning fragments with gravity\n"
        section += "- `trail`: Ghost copies following motion with delay and fade. REQUIRES target object to have moveX/moveY animations — otherwise creates static orphan circles!\n"
        section += "- `motionPath`: Object follows smooth bezier ARC (curved, not straight)\n"
        section += "- `spring`: Natural overshoot + settle physics (much better than easeOut)\n"
        section += "- `pathMorph`: Shape smoothly transforms into another shape\n\n"
        section += "If you use particles, design them like a mathematician and a VFX artist: orbital rings, lissajous trails, spiral attractors, curl-noise drift, interference waves, or controlled fracture paths. Avoid generic fireworks/sparks unless explicitly justified.\n\n"
        section += "Shape presets for path objects: arrow, star, triangle, teardrop, ring, cross, heart, "
        section += "burst, chevron, lightning, crescent, diamond, droplet, speechBubble\n"
        section += "Example: {\"type\":\"createObject\",\"parameters\":{\"objectType\":\"path\",\"name\":\"my_arrow\","
        section += "\"shapePreset\":\"arrow\",\"x\":540,\"y\":540,\"width\":200,\"height\":80,\"fillColor\":{\"hex\":\"#FF4444\"}}}\n"
        
        return section
    }
}

// MARK: - Parsing Helpers

/// Extracts a field value from text by searching for "name:" patterns.
/// Handles bold markdown, quotes, backticks, and various formatting.
private func extractField(named name: String, from text: String) -> String? {
    let stripped = name.lowercased().replacingOccurrences(of: "_", with: "[ _]?")
    
    // Build regex pattern: optional markdown bold/quotes around the name, then colon, then value
    let patterns = [
        "\\*{0,2}\(stripped)\\*{0,2}\\s*:\\s*(.+)",
        "\"\(stripped)\"\\s*:\\s*\"?(.+?)\"?(?:,|$)",
    ]
    
    for pattern in patterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           match.numberOfRanges > 1,
           let valueRange = Range(match.range(at: 1), in: text) {
            let raw = String(text[valueRange])
            let value = raw.prefix(while: { $0 != "\n" })
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`*"))
            if !value.isEmpty { return value }
        }
    }
    return nil
}

/// Flexible field extraction for MotionScore beat bodies.
/// Handles **field:** value, - field: value, field: value formats.
private func extractFlexibleField(named name: String, from line: String) -> String? {
    let low = line.lowercased()
    let target = name.lowercased()
    guard low.contains(target) else { return nil }
    
    // Strip markdown bold markers for cleaner matching
    let cleaned = line
        .replacingOccurrences(of: "**", with: "")
        .replacingOccurrences(of: "__", with: "")
    
    guard let nameRange = cleaned.range(of: name, options: .caseInsensitive) else { return nil }
    let afterName = cleaned[nameRange.upperBound...]
    
    // Look for a colon separator after the field name
    if let colonIdx = afterName.firstIndex(of: ":") {
        let value = afterName[afterName.index(after: colonIdx)...]
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`*"))
        if !value.isEmpty { return value }
    }
    return nil
}

/// Strips markdown formatting (bold, italic, headers, backticks) from a string.
private func stripMarkdown(_ text: String) -> String {
    text.replacingOccurrences(of: "**", with: "")
        .replacingOccurrences(of: "__", with: "")
        .replacingOccurrences(of: "`", with: "")
        .replacingOccurrences(of: "###", with: "")
        .replacingOccurrences(of: "##", with: "")
        .replacingOccurrences(of: "# ", with: "")
        .trimmingCharacters(in: .whitespaces)
}

/// Checks if a line looks like a numbered beat: "1.", "1)", "1:", etc.
private func matchesNumberedBeat(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard let first = trimmed.first, first.isNumber else { return false }
    // Must be a short number prefix followed by a separator
    let prefix = trimmed.prefix(4)
    return prefix.contains(".") || prefix.contains(")") || prefix.contains(":")
}

/// Extracts a time range like "0-2s", "0s-2s", "0.0-2.5s" from text.
private func extractTimeRange(from text: String) -> String? {
    let pattern = "\\[?\\(?(\\d+\\.?\\d*s?)\\s*[-–—]\\s*(\\d+\\.?\\d*s?)\\]?\\)?"
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let r1 = Range(match.range(at: 1), in: text),
          let r2 = Range(match.range(at: 2), in: text) else { return nil }
    return "\(text[r1])-\(text[r2])"
}

/// Extracts all #RRGGBB hex color codes from the entire text.
private func extractAllHexColors(from text: String) -> [String] {
    let pattern = "#[0-9A-Fa-f]{6}"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    var seen = Set<String>()
    var result: [String] = []
    for m in matches {
        if let range = Range(m.range, in: text) {
            let hex = String(text[range]).uppercased()
            if !seen.contains(hex) {
                seen.insert(hex)
                result.append(hex)
            }
        }
    }
    return result
}

/// Extracts hex colors from a single line (comma-separated or space-separated).
private func extractHexColorsFromLine(_ line: String) -> [String] {
    extractAllHexColors(from: line)
}

/// Simple heuristic: a hex color is "dark" if its RGB components average below 0x60.
private func isColorDark(_ hex: String) -> Bool {
    let cleaned = hex.replacingOccurrences(of: "#", with: "")
    guard cleaned.count == 6, let val = UInt32(cleaned, radix: 16) else { return true }
    let r = (val >> 16) & 0xFF
    let g = (val >> 8) & 0xFF
    let b = val & 0xFF
    return (r + g + b) / 3 < 0x60
}

/// Known animation type names to scan for in unstructured text.
private let knownAnimationTypes: Set<String> = [
    "fadeIn", "slideUp", "slideDown", "slideLeft", "slideRight", "scaleIn", "scaleUp",
    "rotateIn", "flipIn", "bounceIn", "elasticIn", "dropIn", "riseUp", "clipIn", "expandIn",
    "typewriter", "charByChar", "wordByWord", "lineByLine", "scrambleMorph", "glitchReveal",
    "splitFlip", "whipIn", "materialFade", "staggerScaleIn", "staggerSlideUp", "staggerSlideDown",
    "staggerSlideLeft", "staggerSlideRight", "staggerFadeIn", "staggerFlipIn",
    "neonFlicker", "cinematicStretch", "impactSlam", "cleanMinimal", "energyBurst",
    "springEntrance", "pathDrawOn", "spiralIn", "shatterAssemble", "matrixReveal",
    "revealWipe", "blurIn", "popIn", "waveEntrance", "glowPulseIn", "snapScale",
    "zoomPan", "cameraPan", "dollyZoom", "parallaxFloat", "orbitCamera", "spiralZoom",
    "smoothTrack", "whipPan", "verticalDrift", "horizontalDrift",
    "screenFlash", "backgroundShift", "particleBurst", "shakeRumble",
    "pulseGlow", "neonPulse", "colorCycle", "breathe", "float", "glitch", "flicker",
    "flash", "spin", "heartbeat", "rubberBand", "jelly3D", "pendulum", "flickerFade",
    "morphBlob", "shimmer", "lensFlare", "whipReveal", "heroRise",
    "fadeOut", "scaleOut", "slideOut", "cameraShake", "turntable",
]

/// Scans text for known animation type names (case-insensitive).
private func extractKnownAnimations(from text: String) -> [String] {
    let lowered = text.lowercased()
    var found: [String] = []
    for anim in knownAnimationTypes {
        if lowered.contains(anim.lowercased()) {
            found.append(anim)
        }
    }
    return found
}
