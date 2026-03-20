//
//  CreativePipeline.swift
//  AIAfterEffects
//
//  Orchestrator that runs the 5-agent creative pipeline sequentially:
//  Director → Designer → Choreographer → (Executor handled by AgentLoopService) → Critic
//
//  Returns a PipelineBrief that replaces the old String plan, giving the Executor
//  structured creative direction instead of freeform text.
//
//  If any stage fails, the pipeline aborts and the request surfaces an error
//  instead of silently downgrading to the legacy planner.
//

import Foundation

struct CreativePipeline {
    
    /// Runs the pre-execution creative pipeline (Director → Designer → Choreographer).
    /// The Executor and Critic stages are handled by AgentLoopService since they
    /// wrap the existing multi-turn tool loop.
    ///
    /// - Returns: A `PipelineBrief` bundling all agent outputs.
    static func run(
        userMessage: String,
        attachments: [ChatAttachment],
        sceneState: SceneState,
        attachmentInfos: [AttachmentInfo],
        project: Project?,
        currentSceneIndex: Int,
        onStageChange: @escaping (PipelineStage) -> Void
    ) async throws -> PipelineBrief {
        let logger = DebugLogger.shared
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let cw = Int(sceneState.canvasWidth)
        let ch = Int(sceneState.canvasHeight)
        
        let has3DModelAttached = userMessage.contains("[Attached 3D Model")
        
        var sceneStateSummary = sceneState.describe()
        if !has3DModelAttached {
            sceneStateSummary += "\n⚠️ NO 3D MODEL ATTACHED. The user only provided 2D images. "
            sceneStateSummary += "Do NOT plan for or reference any 3D model, model3D object, or 3D animations. "
            sceneStateSummary += "Use ONLY the attached images and 2D elements (text, shapes, effects). "
            sceneStateSummary += "Ignore any existing model3D objects from previous sessions."
        }
        
        let attachmentSummary = attachmentInfos.map { info in
            let fitted = info.fittedSize(canvasWidth: sceneState.canvasWidth, canvasHeight: sceneState.canvasHeight)
            return "Image \(info.index): \"\(info.filename)\" \(info.width)×\(info.height)px (fits \(fitted.width)×\(fitted.height))"
        }.joined(separator: "\n")
        
        // Existing objects summary for choreographer (filter out model3D if no 3D model attached)
        var existingObjectsSummary = ""
        if let project = project {
            let sceneIdx = min(currentSceneIndex, project.orderedScenes.count - 1)
            if sceneIdx >= 0, sceneIdx < project.orderedScenes.count {
                let scene = project.orderedScenes[sceneIdx]
                for obj in scene.objects {
                    if !has3DModelAttached && obj.type == .model3D { continue }
                    existingObjectsSummary += "- \"\(obj.name)\" [\(obj.type.rawValue)] id=\(obj.id.uuidString)\n"
                }
            }
        }
        
        // ── Stage 1: Director ──
        onStageChange(.director)
        logger.info("[Pipeline] ── Stage 1/3: Director ──", category: .llm)
        
        let imageURLs = attachments.map { $0.dataURL }
        
        guard let directive = await DirectorAgent.run(
            userMessage: userMessage,
            sceneStateSummary: sceneStateSummary,
            attachmentSummary: attachmentSummary,
            canvasWidth: cw,
            canvasHeight: ch,
            attachmentImageURLs: imageURLs
        ) else {
            logger.error("[Pipeline] Director failed — aborting request", category: .llm)
            throw CreativePipelineError.stageFailed(.director)
        }
        
        let directorTime = CFAbsoluteTimeGetCurrent() - startTime
        logger.info("[Pipeline] Director done in \(String(format: "%.1f", directorTime))s", category: .llm)
        
        // ── Stage 2: Designer ──
        onStageChange(.designer)
        logger.info("[Pipeline] ── Stage 2/3: Designer ──", category: .llm)
        
        guard let visualSystem = await DesignerAgent.run(
            userMessage: userMessage,
            directive: directive,
            canvasWidth: cw,
            canvasHeight: ch,
            attachmentSummary: attachmentSummary,
            attachmentImageURLs: imageURLs
        ) else {
            logger.error("[Pipeline] Designer failed — aborting request", category: .llm)
            throw CreativePipelineError.stageFailed(.designer)
        }
        
        let designerTime = CFAbsoluteTimeGetCurrent() - startTime
        logger.info("[Pipeline] Designer done in \(String(format: "%.1f", designerTime - directorTime))s (total \(String(format: "%.1f", designerTime))s)", category: .llm)
        
        // ── Stage 3: Choreographer ──
        onStageChange(.choreographer)
        logger.info("[Pipeline] ── Stage 3/3: Choreographer ──", category: .llm)
        
        guard let motionScore = await ChoreographerAgent.run(
            userMessage: userMessage,
            directive: directive,
            visualSystem: visualSystem,
            canvasWidth: cw,
            canvasHeight: ch,
            existingObjectsSummary: existingObjectsSummary,
            has3DModel: has3DModelAttached
        ) else {
            logger.error("[Pipeline] Choreographer failed — aborting request", category: .llm)
            throw CreativePipelineError.stageFailed(.choreographer)
        }
        
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        logger.info("[Pipeline] All 3 pre-execution stages done in \(String(format: "%.1f", totalTime))s", category: .llm)
        logger.success("[Pipeline] Brief ready: \(motionScore.beats.count) beats, \(motionScore.uniqueAnimationTypes.count) unique anims, \(motionScore.restBeatCount) rests", category: .llm)
        
        return PipelineBrief(
            directive: directive,
            visualSystem: visualSystem,
            motionScore: motionScore,
            has3DModelAttached: has3DModelAttached
        )
    }
    
    /// Runs the Validator agent post-execution to check positions and timing.
    /// Returns a ValidationResult with fixed commands and any timing issues.
    static func runValidator(
        commands: SceneCommands,
        canvasWidth: Int,
        canvasHeight: Int,
        brief: PipelineBrief?,
        onStageChange: @escaping (PipelineStage) -> Void
    ) async -> ValidatorAgent.ValidationResult {
        onStageChange(.validator)
        let logger = DebugLogger.shared
        logger.info("[Pipeline] ── Post-Execution: Validator ──", category: .llm)
        
        let result = await ValidatorAgent.run(
            commands: commands,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight,
            brief: brief
        )
        
        return result
    }
    
    /// Runs the Critic agent post-execution to review the output quality.
    /// Returns ReviewNotes with patch instructions if revision is needed.
    static func runCritic(
        brief: PipelineBrief,
        executedCommandsSummary: String,
        onStageChange: @escaping (PipelineStage) -> Void
    ) async -> ReviewNotes? {
        onStageChange(.critic)
        let logger = DebugLogger.shared
        logger.info("[Pipeline] ── Post-Execution: Critic ──", category: .llm)
        
        let review = await CriticAgent.run(
            directive: brief.directive,
            motionScore: brief.motionScore,
            executedCommandsSummary: executedCommandsSummary
        )
        
        return review
    }
}
