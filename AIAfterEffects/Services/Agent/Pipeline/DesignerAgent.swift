//
//  DesignerAgent.swift
//  AIAfterEffects
//
//  Art Director agent — defines fonts, colors, palette, layout, and visual hierarchy.
//  Single LLM call, fast model, moderate temperature for grounded design decisions.
//

import Foundation

struct DesignerAgent {
    
    static func run(
        userMessage: String,
        directive: CreativeDirective,
        canvasWidth: Int,
        canvasHeight: Int,
        attachmentSummary: String,
        attachmentImageURLs: [String] = []
    ) async -> VisualSystem? {
        let logger = DebugLogger.shared
        logger.info("[Pipeline:Designer] Crafting visual system...", category: .llm)
        
        let prompt = buildPrompt(
            directive: directive,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight,
            attachmentSummary: attachmentSummary,
            hasImages: !attachmentImageURLs.isEmpty
        )
        
        do {
            let response = try await callLLM(
                systemPrompt: prompt,
                userMessage: "Creative directive:\n\(directive.rawText)\n\nOriginal brief: \(userMessage)",
                imageDataURLs: attachmentImageURLs,
                temperature: 0.5,
                maxTokens: 1000
            )
            
            guard let text = response, !text.isEmpty else {
                logger.warning("[Pipeline:Designer] Empty response", category: .llm)
                return nil
            }
            
            logger.debug("[Pipeline:Designer] Raw response (\(text.count) chars): \(text.prefix(500))...", category: .llm)
            
            let system = VisualSystem.parse(from: text)
            logger.success("[Pipeline:Designer] Fonts: \(system.headlineFont)/\(system.bodyFont), Palette: \(system.colorPalette.joined(separator: ", ")), Accent: \(system.accentColor)", category: .llm)
            return system
            
        } catch {
            logger.warning("[Pipeline:Designer] Failed: \(error.localizedDescription)", category: .llm)
            return nil
        }
    }
    
    // MARK: - Prompt
    
    private static func buildPrompt(
        directive: CreativeDirective,
        canvasWidth: Int,
        canvasHeight: Int,
        attachmentSummary: String,
        hasImages: Bool
    ) -> String {
        let orientation = canvasWidth > canvasHeight ? "landscape" : canvasHeight > canvasWidth ? "portrait" : "square"
        
        return """
        You are an Art Director specializing in motion graphics and broadcast design. \
        You've designed visual systems for award-winning broadcast and digital campaigns. \
        Your work has been featured on Motionographer and Behance.

        You receive a creative directive and translate it into a DISTINCTIVE visual system. \
        Not a generic corporate palette — a SPECIFIC, INTENTIONAL design choice that amplifies \
        the emotional arc.

        \(hasImages ? """
        ## ⚡ VISUAL REFERENCE IMAGES ATTACHED
        The user's images/3D model preview are attached to this message. \
        STUDY THEM CAREFULLY before choosing colors. Your palette MUST complement and \
        harmonize with the dominant colors in the attached visuals. \
        Extract the key hues from the images and build your palette around them — \
        the accent color should either contrast with or amplify the strongest color in the visuals.
        """ : "")

        ## Creative Directive
        Concept: \(directive.concept)
        Emotional Arc: \(directive.emotionalArc)
        Metaphor: \(directive.metaphor)
        Tone: \(directive.tone.joined(separator: ", "))
        Climax: \(directive.climaxDescription)
        Duration: \(directive.targetDuration)s

        ## Canvas: \(canvasWidth)×\(canvasHeight)px (\(orientation)), Center: (\(canvasWidth/2), \(canvasHeight/2))
        \(attachmentSummary.isEmpty ? "" : "## Attachments\n\(attachmentSummary)\n")

        ## ANTI-GENERIC RULES
        - NO default black-on-white. Even "clean minimal" needs a design POINT OF VIEW.
        - Background colors must SHIFT during the sequence (dark→mid→dark or warm→cool→warm). Static bg = amateur.
        - The accent color must POP against the background. Test it mentally: would it glow?
        - Palette needs a DARK and a LIGHT — for contrast, depth, and readability.
        - Layout must be ASYMMETRIC or have deliberate tension — centered-everything looks like a PowerPoint.

        ## FONT LIBRARY (choose ONLY from these — they are guaranteed available)
        Headlines (support Bold/Black): Oswald, Archivo Black, Poppins, Montserrat, Inter, \
        Space Grotesk, Barlow Condensed, Big Shoulders Display, Teko, Rajdhani
        Headlines (ONLY Regular weight — do NOT set Bold): Bebas Neue, Anton, Black Ops One, \
        Rubik Mono One, Passion One, Bungee, Righteous, Russo One, Press Start 2P, \
        Orbitron, Audiowide, Bowlby One SC, Ultra, Saira Extra Condensed
        Body: Inter, Roboto, Poppins, Space Grotesk, Work Sans, DM Sans, Outfit, \
        Nunito Sans, Source Sans 3, Barlow, Manrope, Plus Jakarta Sans, Lexend
        
        ⚠️ DO NOT use fonts outside this list. They will fail to load.
        ⚠️ If you pick a font from the "ONLY Regular" group, set headline_weight to "Regular".

        ## DECORATIVE SHAPE PRESETS (for accent elements)
        arrow, arrowCurved, star, triangle, teardrop, ring, cross, heart, burst, \
        chevron, lightning, crescent, diamond, hexagon, octagon, speechBubble, droplet
        
        ## VFX COLOR GUIDANCE
        Particle and VFX effects (sparks, fire, smoke, energy beams, shockwaves) are rendered \
        as custom GPU shaders where the AI has FULL creative control. Your accent color and palette \
        will be passed to the shader as color1/color2. Choose colors that create STUNNING gradients \
        and glow effects (e.g., warm orange→gold for fire, cyan→white for energy, deep red→pink for love).

        ## Output Format
        Write your OWN values for each field. Do NOT copy descriptions — replace with real design choices.

        headline_font: <font name from the list above>
        headline_weight: <Regular, Bold, Black, or ExtraBold — check weight availability above!>
        body_font: <font name from the list above>
        palette: <5 hex colors with roles, like: #0A0A0A background, #F5F0EB text, #FF3D00 accent, #00D4FF secondary, #1A1A2E deep>
        accent_color: <one hex color that pops>
        background_colors: <2-3 hex colors for background shift over time>
        layout: <spatial arrangement description>
        hierarchy: <type scale with specific px sizes>
        particle_shapes: <1-3 shape presets that fit the concept, like: star, burst, diamond>

        IMPORTANT: Write actual hex colors, font names, and descriptions. Do NOT output angle brackets.
        """
    }
}
