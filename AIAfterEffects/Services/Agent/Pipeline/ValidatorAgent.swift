//
//  ValidatorAgent.swift
//  AIAfterEffects
//
//  Technical QA agent — reviews scene object positions (clipping, bounds),
//  animation timing (order, overlaps, logic), and outputs specific fix actions.
//  Runs AFTER the Executor produces actions but BEFORE the Critic reviews quality.
//
//  Two-phase approach:
//  Phase 1: Programmatic position fixing (instant, reliable)
//  Phase 2: LLM timing/logic review (catches sequencing issues code can't)
//

import Foundation

struct ValidatorAgent {
    
    // MARK: - Public API
    
    struct ValidationResult {
        let fixedCommands: SceneCommands
        let positionFixCount: Int
        let timingIssues: [String]
        let timingFixes: String?
    }
    
    static func run(
        commands: SceneCommands,
        canvasWidth: Int,
        canvasHeight: Int,
        brief: PipelineBrief?
    ) async -> ValidationResult {
        let logger = DebugLogger.shared
        logger.info("[Pipeline:Validator] Starting scene validation...", category: .llm)
        
        // Phase 1: Programmatic position fixes
        let (fixedCommands, posFixCount) = fixPositions(
            commands: commands,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight
        )
        
        if posFixCount > 0 {
            logger.success("[Pipeline:Validator] Fixed \(posFixCount) position issues", category: .llm)
        } else {
            logger.info("[Pipeline:Validator] No position issues found", category: .llm)
        }
        
        // Phase 2: LLM timing/logic review
        let actionsSummary = buildActionsSummary(fixedCommands, canvasWidth: canvasWidth, canvasHeight: canvasHeight)
        let (timingIssues, timingFixes) = await reviewTimingAndLogic(
            actionsSummary: actionsSummary,
            brief: brief,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight
        )
        
        if !timingIssues.isEmpty {
            logger.warning("[Pipeline:Validator] Found \(timingIssues.count) timing/logic issues", category: .llm)
        } else {
            logger.success("[Pipeline:Validator] Timing and logic validated ✓", category: .llm)
        }
        
        return ValidationResult(
            fixedCommands: fixedCommands,
            positionFixCount: posFixCount,
            timingIssues: timingIssues,
            timingFixes: timingFixes
        )
    }
    
    // MARK: - Phase 1: Programmatic Position Fixing
    
    private static func fixPositions(
        commands: SceneCommands,
        canvasWidth: Int,
        canvasHeight: Int
    ) -> (SceneCommands, Int) {
        guard var actions = commands.actions else {
            return (commands, 0)
        }
        
        let cw = Double(canvasWidth)
        let ch = Double(canvasHeight)
        let margin: Double = 20
        var fixCount = 0
        
        for i in 0..<actions.count {
            guard actions[i].type == .createObject,
                  var params = actions[i].parameters else { continue }
            
            let objType = params.objectType ?? params.type ?? ""
            guard let x = params.x, let y = params.y else { continue }
            
            let w = params.width ?? estimateWidth(for: objType, params: params)
            let h = params.height ?? estimateHeight(for: objType, params: params)
            
            guard w > 0, h > 0 else { continue }
            
            // Canvas-filling objects (shaders, fullscreen overlays) should not be adjusted
            if w >= cw * 0.95 && h >= ch * 0.95 { continue }
            
            let alignment = params.textAlignment ?? "center"
            
            var newX = x
            var newY = y
            var fixed = false
            
            if objType == "text" || objType == "image" {
                // Text/image objects are centered at (x, y).
                // For left-aligned text, the visual content starts at x - w/2.
                // Fix: ensure the visual left edge has enough margin.
                let halfW = w / 2.0
                let halfH = h / 2.0
                
                if alignment == "left" {
                    // Left-aligned: text extends to the right from center
                    // Visual left edge = x - halfW, visual right edge = x + halfW
                    // To make text START at the desired x, set center to x + halfW
                    if x - halfW < margin {
                        newX = halfW + margin
                        fixed = true
                    }
                } else if alignment == "right" {
                    if x + halfW > cw - margin {
                        newX = cw - halfW - margin
                        fixed = true
                    }
                } else {
                    // Center aligned
                    if x - halfW < margin {
                        newX = halfW + margin
                        fixed = true
                    }
                    if x + halfW > cw - margin {
                        newX = cw - halfW - margin
                        fixed = true
                    }
                }
                
                if y - halfH < margin {
                    newY = halfH + margin
                    fixed = true
                }
                if y + halfH > ch - margin {
                    newY = ch - halfH - margin
                    fixed = true
                }
            } else if objType != "model3D" && objType != "shader" {
                // Rectangles, circles, paths — centered at (x, y)
                let halfW = w / 2.0
                let halfH = h / 2.0
                
                if x - halfW < -halfW * 0.5 {
                    newX = halfW + margin
                    fixed = true
                }
                if x + halfW > cw + halfW * 0.5 {
                    newX = cw - halfW - margin
                    fixed = true
                }
                if y - halfH < -halfH * 0.5 {
                    newY = halfH + margin
                    fixed = true
                }
                if y + halfH > ch + halfH * 0.5 {
                    newY = ch - halfH - margin
                    fixed = true
                }
            }
            
            if fixed {
                params.x = round(newX)
                params.y = round(newY)
                actions[i] = SceneAction(type: actions[i].type, target: actions[i].target, parameters: params)
                fixCount += 1
            }
        }
        
        var fixedCommands = commands
        fixedCommands.actions = actions
        return (fixedCommands, fixCount)
    }
    
    private static func estimateWidth(for objectType: String, params: ActionParameters) -> Double {
        if objectType == "text" {
            let fontSize = params.fontSize ?? 24
            let text = params.text ?? params.content ?? ""
            let charCount = max(Double(text.count), 1)
            return charCount * fontSize * 0.6
        }
        return params.width ?? 100
    }
    
    private static func estimateHeight(for objectType: String, params: ActionParameters) -> Double {
        if objectType == "text" {
            let fontSize = params.fontSize ?? 24
            return fontSize * 1.2
        }
        return params.height ?? 100
    }
    
    // MARK: - Phase 2: LLM Timing/Logic Review
    
    private static func reviewTimingAndLogic(
        actionsSummary: String,
        brief: PipelineBrief?,
        canvasWidth: Int,
        canvasHeight: Int
    ) async -> ([String], String?) {
        let prompt = buildTimingPrompt(canvasWidth: canvasWidth, canvasHeight: canvasHeight, brief: brief)
        
        do {
            let response = try await callLLM(
                systemPrompt: prompt,
                userMessage: actionsSummary,
                temperature: 0.15,
                maxTokens: 1500
            )
            
            guard let text = response, !text.isEmpty else {
                return ([], nil)
            }
            
            return parseTimingReview(text)
        } catch {
            DebugLogger.shared.warning("[Pipeline:Validator] Timing review failed: \(error.localizedDescription)", category: .llm)
            return ([], nil)
        }
    }
    
    // MARK: - Actions Summary Builder
    
    private static func buildActionsSummary(_ commands: SceneCommands, canvasWidth: Int, canvasHeight: Int) -> String {
        guard let actions = commands.actions else { return "No actions" }
        
        var summary = "Canvas: \(canvasWidth)×\(canvasHeight)px\n\n"
        
        // Group: created objects with positions
        var objects: [(idx: Int, id: String, type: String, x: Double, y: Double, w: Double, h: Double, fontSize: Double?)] = []
        // Group: animations with timing
        var animations: [(idx: Int, target: String, anim: String, start: Double, dur: Double, easing: String?)] = []
        // Group: presets
        var presets: [(idx: Int, target: String, preset: String, start: Double)] = []
        
        for (i, action) in actions.enumerated() {
            let p = action.parameters
            
            switch action.type {
            case .createObject:
                let id = p?.name ?? action.target ?? "obj_\(i)"
                let objType = p?.objectType ?? p?.type ?? "unknown"
                objects.append((
                    idx: i,
                    id: id,
                    type: objType,
                    x: p?.x ?? 0,
                    y: p?.y ?? 0,
                    w: p?.width ?? estimateWidth(for: objType, params: p ?? ActionParameters()),
                    h: p?.height ?? estimateHeight(for: objType, params: p ?? ActionParameters()),
                    fontSize: p?.fontSize
                ))
                
            case .addAnimation:
                let target = p?.targetId ?? action.target ?? ""
                animations.append((
                    idx: i,
                    target: target,
                    anim: p?.animationType ?? "unknown",
                    start: p?.startTime ?? 0,
                    dur: p?.duration ?? 0,
                    easing: p?.easing
                ))
                
            case .applyPreset:
                let target = p?.targetId ?? action.target ?? ""
                presets.append((
                    idx: i,
                    target: target,
                    preset: p?.presetName ?? "unknown",
                    start: p?.startTime ?? 0
                ))
                
            default: break
            }
        }
        
        summary += "## Objects (\(objects.count))\n"
        for obj in objects {
            var line = "- \"\(obj.id)\" [\(obj.type)] at (\(Int(obj.x)), \(Int(obj.y))) size \(Int(obj.w))×\(Int(obj.h))"
            if let fs = obj.fontSize { line += " fontSize=\(Int(fs))" }
            summary += line + "\n"
        }
        
        summary += "\n## Animations (\(animations.count)) — sorted by startTime\n"
        let sortedAnims = animations.sorted { $0.start < $1.start }
        for anim in sortedAnims {
            summary += "- [\(String(format: "%.1f", anim.start))s-\(String(format: "%.1f", anim.start + anim.dur))s] \"\(anim.target)\" → \(anim.anim) (\(String(format: "%.1f", anim.dur))s)"
            if let e = anim.easing { summary += " [\(e)]" }
            summary += "\n"
        }
        
        if !presets.isEmpty {
            summary += "\n## Presets (\(presets.count))\n"
            for p in presets.sorted(by: { $0.start < $1.start }) {
                summary += "- [\(String(format: "%.1f", p.start))s] \"\(p.target)\" → \(p.preset)\n"
            }
        }
        
        return summary
    }
    
    // MARK: - Timing Prompt
    
    private static func buildTimingPrompt(canvasWidth: Int, canvasHeight: Int, brief: PipelineBrief?) -> String {
        let durationHint = brief?.directive.targetDuration ?? 15
        
        return """
        You are a technical QA validator for motion graphics scenes. You review the TIMING \
        and LOGIC of animations — NOT the creative quality (a separate reviewer handles that).

        Your job: find bugs, broken sequences, and timing conflicts that would look wrong on screen.

        ## Canvas: \(canvasWidth)×\(canvasHeight)px
        ## Target Duration: ~\(Int(durationHint))s

        ## CHECK THESE (in order of importance)

        ### T1. Animation Before Object Exists
        If an animation targets an object, the object's createObject action must come BEFORE \
        the animation action in the action list. If not → ISSUE.

        ### T2. fadeOut Before Entrance Completes
        If an object has a fadeIn/entrance animation starting at Xs with duration Ds, \
        a fadeOut must NOT start before X+D. Otherwise the object fades out before it fully appears.

        ### T3. Overlapping Conflicting Animations
        Two fade animations on the same object at the same time = conflict. \
        Two scale animations on the same object at the same time = conflict. \
        Different animation types (fade + move) are fine overlapping.

        ### T4. Animations After Scene Duration
        If target duration is ~\(Int(durationHint))s, animations starting after \(Int(durationHint) + 2)s \
        won't be seen. Flag these.

        ### T5. Missing Entrance Animations
        If an object is created with opacity=0 but has no fadeIn or entrance animation, \
        it will be invisible forever. Flag it.

        ### T6. Rest Beats With New Objects
        If the motion score indicates a REST beat at time T, no new objects should appear \
        during that window. Check if objects are created/animated during planned rest periods.

        ### T7. Stagger Timing Issues
        Stagger animations should have increasing startTime offsets. If all stagger items \
        start at the same time, the stagger effect is lost.

        ### T8. Procedural Effect Validation
        `applyEffect` actions come in two forms:
        A) GPU shader effects (particles, fire, smoke, sparks, shockwaves, etc.) — these MUST have `shaderCode` with valid Metal shader body. The AI writes the shader code with full creative control.
        B) Non-shader effects (trail, motionPath, spring, pathMorph) — validated by params.
        
        For ALL applyEffect:
        - startTime must be within scene duration
        For shader effects (A):
        - shaderCode must be present and non-empty
        - shaderCode should end with a `return float4(...)` statement
        - shaderParam1 should be the effect start time, shaderParam2 the lifetime/duration
        For motionPath: controlPoints array needs at least 2 points
        For spring: effectStiffness > 0 and effectDamping > 0
        For pathMorph: targetShapePreset must be valid

        ### T9. Shape Preset Validation
        If an object uses `shapePreset`, verify the preset name is valid: arrow, arrowCurved, \
        star, triangle, teardrop, ring, cross, heart, burst, chevron, lightning, crescent, \
        diamond, hexagon, octagon, speechBubble, droplet.

        ### T10. Orphan Objects (No Purpose)
        If an object is created but has NO animations, NO preset, and NO clear narrative role, \
        it is an orphan. "Glow" circles, accent shapes, or decorative elements that persist after \
        their effect ends are orphans. Every visible element must either animate or serve as a \
        permanent backdrop/label. Objects with no exit animation that outlive their usefulness \
        clutter the scene.

        ### T11. Trail Without Parent Motion
        `applyEffect` with effectType="trail" creates ghost copies that follow a parent object's \
        motion. If the trail targets an object with NO moveX/moveY animations, the trail particles \
        just sit at the origin doing nothing. Flag this as a bug.

        ## OUTPUT FORMAT (plain text)

        If no issues found:
        VALIDATED: No timing or logic issues detected.

        If issues found:
        ISSUES FOUND: [count]

        Issues:
        - [T-number] [object_id]: description of the problem

        Fixes:
        - Change [object_id] [animation_type] startTime from [X]s to [Y]s
        - Add fadeIn to [object_id] at [X]s with duration [D]s
        - Remove conflicting animation [animation_type] on [object_id] at [X]s

        Be precise. Only flag actual bugs — not stylistic preferences.
        """
    }
    
    // MARK: - Parse Timing Review
    
    private static func parseTimingReview(_ text: String) -> ([String], String?) {
        let lowered = text.lowercased()
        
        if lowered.contains("validated") && lowered.contains("no timing") || lowered.contains("no issues") {
            return ([], nil)
        }
        
        var issues: [String] = []
        var fixes: [String] = []
        var inIssues = false
        var inFixes = false
        
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            
            if lower.hasPrefix("issues:") || lower.hasPrefix("### issues") {
                inIssues = true
                inFixes = false
                continue
            }
            if lower.hasPrefix("fixes:") || lower.hasPrefix("### fixes") || lower.hasPrefix("fix:") {
                inFixes = true
                inIssues = false
                continue
            }
            
            if inIssues && (trimmed.hasPrefix("-") || trimmed.hasPrefix("•") || trimmed.hasPrefix("*")) {
                let content = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                if !content.isEmpty { issues.append(content) }
            }
            if inFixes && (trimmed.hasPrefix("-") || trimmed.hasPrefix("•") || trimmed.hasPrefix("*")) {
                let content = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                if !content.isEmpty { fixes.append(content) }
            }
        }
        
        let fixText = fixes.isEmpty ? nil : fixes.joined(separator: "\n")
        return (issues, fixText)
    }
}
