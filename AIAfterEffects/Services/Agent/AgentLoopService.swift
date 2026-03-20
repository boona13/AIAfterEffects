//
//  AgentLoopService.swift
//  AIAfterEffects
//
//  Orchestrates the multi-turn agentic loop using native OpenRouter function calling:
//    1. User sends message → AI responds with native tool_calls OR final text
//    2. If tool_calls → execute them, send results as role:"tool" messages, repeat
//    3. If final text → parse for optional scene actions, return LLMResponse
//
//  Tools are defined as structured API parameters (OpenAI-compatible format).
//  The model returns tool_calls as native response objects, not embedded text.
//

import Foundation

// MARK: - Protocol

protocol AgentLoopServiceProtocol {
    func run(
        userMessage: String,
        attachments: [ChatAttachment],
        conversationHistory: [ChatMessage],
        sceneState: SceneState,
        project: Project,
        projectURL: URL,
        currentSceneIndex: Int,
        onToolActivity: @escaping ([ToolActivity]) -> Void,
        onPipelineStageChange: @escaping (PipelineStage) -> Void
    ) async throws -> LLMResponse
}

// MARK: - Implementation

@MainActor
class AgentLoopService: AgentLoopServiceProtocol {
    
    static let shared = AgentLoopService()
    
    private let toolService: ProjectToolServiceProtocol
    private let maxTurns = 12
    
    init(toolService: ProjectToolServiceProtocol = ProjectToolService.shared) {
        self.toolService = toolService
    }
    
    // MARK: - Main Loop
    
    func run(
        userMessage: String,
        attachments: [ChatAttachment],
        conversationHistory: [ChatMessage],
        sceneState: SceneState,
        project: Project,
        projectURL: URL,
        currentSceneIndex: Int,
        onToolActivity: @escaping ([ToolActivity]) -> Void,
        onPipelineStageChange: @escaping (PipelineStage) -> Void = { _ in }
    ) async throws -> LLMResponse {
        
        let logger = DebugLogger.shared
        
        // --- Intent Classification (fast LLM call, ~200 token prompt, 10 max output tokens) ---
        let intent = await classifyIntent(userMessage)
        logger.info("[Agent] Intent: \(intent == .question ? "QUESTION" : "IMPLEMENTATION")", category: .llm)
        
        // Quick path for informational questions — no planning, no tools, single LLM call
        if intent == .question && attachments.isEmpty {
            return try await handleQuickQuestion(
                userMessage: userMessage,
                conversationHistory: conversationHistory,
                sceneState: sceneState,
                project: project,
                currentSceneIndex: currentSceneIndex
            )
        }
        
        // --- Full Implementation Pipeline ---
        let pipelineStart = CFAbsoluteTimeGetCurrent()
        let state = AgentLoopState()
        logger.info("[Agent] ═══════════════════════════════════════", category: .llm)
        logger.info("[Agent] Starting IMPLEMENTATION pipeline for: \"\(userMessage.prefix(80))\"", category: .llm)
        
        // --- Context Compaction (runs once before everything else) ---
        // Summarizes older messages via LLM instead of truncating them
        let compactedHistory = await ContextCompactionService.shared.prepareForSubmission(
            history: conversationHistory,
            sceneState: sceneState
        )
        logger.info("[Agent] History: \(conversationHistory.count) messages → \(compactedHistory.count) after compaction", category: .llm)
        
        // Compacted history used by the creative pipeline and initial API messages
        let agentHistory = compactedHistory
        
        // --- Creative Pipeline ---
        // Runs Director → Designer → Choreographer for new requests.
        // If a stage fails, stop the request instead of downgrading to the legacy planner.
        // Skips entirely for follow-up requests.
        let attachmentInfos = PromptBuilder.extractAttachmentInfos(from: attachments)
        
        let sceneHasObjects = !sceneState.objects.isEmpty
        let hasConversationHistory = compactedHistory.count >= 4
        let isFollowUp = sceneHasObjects && hasConversationHistory
        
        var pipelineBrief: PipelineBrief? = nil
        
        if isFollowUp {
            logger.info("[Agent] FOLLOW-UP MODE — scene has \(sceneState.objects.count) objects, \(compactedHistory.count) messages. Skipping creative pipeline.", category: .llm)
        } else {
            do {
                pipelineBrief = try await CreativePipeline.run(
                    userMessage: userMessage,
                    attachments: attachments,
                    sceneState: sceneState,
                    attachmentInfos: attachmentInfos,
                    project: project,
                    currentSceneIndex: currentSceneIndex,
                    onStageChange: onPipelineStageChange
                )
                logger.success("[Agent] Creative pipeline produced a structured brief", category: .llm)
            } catch {
                logger.error("[Agent] Creative pipeline failed — aborting request: \(error.localizedDescription)", category: .llm)
                throw error
            }
        }
        
        // --- Build initial API message history ---
        onPipelineStageChange(.executor)
        var systemPrompt = PromptBuilder.buildAgentSystemPrompt(
            sceneState: sceneState,
            project: project,
            currentSceneIndex: currentSceneIndex,
            plan: nil,
            brief: pipelineBrief,
            attachmentInfos: attachmentInfos,
            available3DAssets: AssetManagerService.shared.assets,
            isFollowUp: isFollowUp
        )
        
        // --- Follow-up mode: inject strong modification directive at the TOP ---
        if isFollowUp {
            let objectNames = sceneState.objects.map { "\"\($0.name)\"" }.joined(separator: ", ")
            let followUpDirective = """
            
            ╔══════════════════════════════════════════════════════════════════╗
            ║  ⚠️  FOLLOW-UP MODE — MODIFICATION ONLY ⚠️                      ║
            ║                                                                  ║
            ║  The scene ALREADY has \(sceneState.objects.count) objects. DO NOT regenerate the scene.       ║
            ║  DO NOT clear or recreate existing objects.                       ║
            ║  ONLY make the SPECIFIC changes the user requested.              ║
            ╚══════════════════════════════════════════════════════════════════╝
            
            ## EXISTING OBJECTS (do NOT recreate these):
            \(objectNames)
            
            ## FOLLOW-UP ACTION RULES:
            1. Use `updateProperties` to change properties on existing objects (color, size, position, text, etc.)
            2. Use `updateAnimation` to modify existing animations (timing, easing, duration)
            3. Use `addAnimation` to add NEW animations to existing objects
            4. Use `removeAnimation` to remove specific animations
            5. Use `deleteObject` to remove objects the user wants gone
            6. Use `createObject` ONLY if the user explicitly asks to ADD something new
            7. Use `clearScene` ONLY if the user explicitly asks to start over
            
            ## WHAT YOU MUST NEVER DO:
            - NEVER use `clearScene` unless explicitly asked
            - NEVER recreate objects that already exist
            - NEVER send the entire scene as new actions
            - NEVER change objects the user didn't mention
            - NEVER re-run the whole design — the design already exists
            
            The user's message below is a MODIFICATION request. Read it carefully and 
            apply ONLY the minimal changes needed. Preserve everything else.
            
            """
            systemPrompt = followUpDirective + systemPrompt
        }
        
        // Inject lightweight project summary + CRUD workflow into system prompt.
        do {
            let canvas = project.canvas
            systemPrompt += "\n\n## Project Summary (canvas: \(Int(canvas.width))×\(Int(canvas.height)))\n"
            
            if isFollowUp {
                systemPrompt += "CRITICAL — Use CRUD tools for ALL object modifications:\n"
                systemPrompt += "• query_objects(type:\"text\") → returns full properties for matching objects.\n"
                systemPrompt += "• update_object(id:\"UUID\", properties:{\"x\":540, \"y\":480}) → directly sets property values.\n"
                systemPrompt += "• shift_timeline(scene_id:\"UUID\", after_time:12.0, shift_amount:3.0) → pushes ALL animations at ≥12s forward by 3s. Use this when INSERTING new slides/segments between existing content. NEVER manually shift animation startTimes with update_object.\n"
                systemPrompt += "• Workflow: query_objects → update_object. That's it. No read_file needed.\n"
                systemPrompt += "• ONLY modify objects the user explicitly asks about. Do NOT \"fix\" objects the user didn't mention.\n\n"
            } else if pipelineBrief != nil {
                systemPrompt += "You have a creative brief. Generate your ENTIRE scene as a single JSON response with \"actions\" array.\n"
                systemPrompt += "Do NOT call tools like update_object or project_info. Output JSON directly.\n\n"
            } else {
                systemPrompt += "Generate your scene as a single JSON response with \"actions\" array.\n\n"
            }
            
            // Lightweight scene/object index (names + IDs only, no properties)
            for (i, scene) in project.orderedScenes.enumerated() {
                systemPrompt += "Scene \(i + 1): \"\(scene.name)\" (id=\(scene.id), \(String(format: "%.1f", scene.duration))s, \(scene.objects.count) objects)\n"
                for obj in scene.objects {
                    systemPrompt += "  • \"\(obj.name)\" [\(obj.type.rawValue)] id=\(obj.id.uuidString)\n"
                }
            }
        }
        
        var apiMessages: [AnyOpenRouterMessage] = []
        apiMessages.append(OpenRouterMessage(role: "system", content: .text(systemPrompt)).asAny)
        
        // Add compacted conversation history
        for msg in agentHistory {
            if msg.isLoading { continue }
            let role: String
            switch msg.role {
            case .user: role = "user"
            case .assistant: role = "assistant"
            case .system: role = "system"
            }
            apiMessages.append(OpenRouterMessage(role: role, content: .text(msg.content)).asAny)
        }
        
        // Add current user message (with attachments on first turn)
        if !attachments.isEmpty {
            var parts: [OpenRouterMessagePart] = []
            let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { parts.append(.text(trimmed)) }
            for attachment in attachments {
                parts.append(.image(url: attachment.dataURL))
            }
            apiMessages.append(OpenRouterMessage(role: "user", content: .parts(parts)).asAny)
        } else {
            apiMessages.append(OpenRouterMessage(role: "user", content: .text(userMessage)).asAny)
        }
        
        // --- Progressive tool availability ---
        // Start WITHOUT read_file — the AI should use query_objects + update_object.
        // read_file is only unlocked after the AI has tried CRUD tools and explicitly needs
        // raw file access (e.g., for non-object data or debugging).
        var readFileUnlocked = false
        var crudToolUsed = false  // Track if the AI has used query_objects or update_object
        var failedUpdateCount = 0  // Track failed update_object calls
        
        func currentTools() -> [OpenRouterTool] {
            if readFileUnlocked {
                return AgentTool.openRouterToolDefinitions()
            } else {
                return AgentTool.openRouterToolDefinitions(excluding: [.readFile])
            }
        }
        
        let initialTools = currentTools()
        logger.info("[Agent] System prompt: \(systemPrompt.count) chars | API messages: \(apiMessages.count) | Tools: \(initialTools.count) definitions (read_file: withheld)", category: .llm)
        
        // --- Agent loop with native tool calling ---
        var consecutiveReadTurns = 0  // Track turns without edits to nudge the LLM
        var attemptedActionRecovery = false // One-shot retry when model claims edits but returns no actions/tools
        var pendingFreshJSONRetry = false
        var remainingFreshJSONRetries = pipelineBrief != nil ? 2 : 0
        let allowLayoutEdits = Self.requestAllowsLayoutEdits(userMessage)
        var executorResult: LLMResponse? = nil
        executorLoop: for turn in 0..<maxTurns {
            let turnStart = CFAbsoluteTimeGetCurrent()
            
            // Prune old tool outputs before each API call (mirrors OpenCode's compaction.ts)
            // This prevents the request body from growing without bound across turns.
            if turn > 0 {
                pruneToolOutputs(&apiMessages)
            }
            
            let isPipelineJSONTurn = (turn == 0 && pipelineBrief != nil) || pendingFreshJSONRetry
            pendingFreshJSONRetry = false
            let tools = isPipelineJSONTurn ? [] : currentTools()
            logger.info("[Agent] ─── Turn \(turn + 1)/\(maxTurns) ─── (\(apiMessages.count) messages in context, read_file: \(readFileUnlocked ? "unlocked" : "withheld")\(isPipelineJSONTurn ? ", tools: NONE (pipeline JSON mode)" : ""))", category: .llm)
            
            let choice = try await sendNativeToolRequest(
                messages: apiMessages,
                tools: tools
            )
            
            let responseMsg = choice.message
            let finishReason = choice.finishReason ?? "stop"
            let responseText = extractResponseText(from: choice)
            
            let turnElapsed = (CFAbsoluteTimeGetCurrent() - turnStart) * 1000
            
            // Check for native tool_calls in the response
            if let nativeToolCalls = responseMsg?.toolCalls, !nativeToolCalls.isEmpty {
                let toolNames = nativeToolCalls.map { $0.function.name }.joined(separator: ", ")
                logger.info("[Agent] API responded in \(String(format: "%.0f", turnElapsed))ms → \(nativeToolCalls.count) tool_calls: [\(toolNames)] (finish: \(finishReason))", category: .llm)
                
                // Log assistant text if also present
                if !responseText.isEmpty {
                    let assistantText = responseText
                    logger.debug("[Agent] Assistant also said: \"\(assistantText.prefix(150))\"", category: .llm)
                }
                
                // Append the assistant's tool-call message to API history
                let toolCallRequests = nativeToolCalls.map { tc in
                    OpenRouterToolCallRequest(
                        id: tc.id,
                        type: tc.type,
                        function: OpenRouterFunctionCallRequest(
                            name: tc.function.name,
                            arguments: tc.function.arguments
                        )
                    )
                }
                apiMessages.append(.assistantToolCalls(
                    OpenRouterAssistantToolCallMessage(role: "assistant", toolCalls: toolCallRequests)
                ))
                
                // Execute tools — parallel when multiple, like the Vercel AI SDK does.
                // The AI SDK runs all tool execute() functions concurrently via Promise.all.
                // We do the same with Swift's TaskGroup for true parallel execution.
                
                // Parse all tool calls first
                struct ParsedCall {
                    let tc: OpenRouterToolCallResponse
                    let agentTool: AgentTool
                    let call: AgentToolCall
                }
                
                // Build the set of currently withheld tools
                let withheldTools: Set<AgentTool> = readFileUnlocked ? [] : [.readFile]
                
                var parsedCalls: [ParsedCall] = []
                for tc in nativeToolCalls {
                    let funcName = tc.function.name
                    guard let agentTool = AgentTool.from(functionName: funcName) else {
                        logger.warning("[Agent] Unknown tool: \(funcName)", category: .llm)
                        apiMessages.append(.toolResult(
                            OpenRouterToolResultMessage(role: "tool", toolCallId: tc.id, content: "Error: Unknown tool '\(funcName)'")
                        ))
                        continue
                    }
                    // Reject tool calls for tools not currently offered
                    if withheldTools.contains(agentTool) {
                        logger.warning("[Agent] BLOCKED hallucinated call to withheld tool: \(funcName)", category: .llm)
                        apiMessages.append(.toolResult(
                            OpenRouterToolResultMessage(role: "tool", toolCallId: tc.id,
                                content: "Error: '\(funcName)' is not available. Use query_objects to inspect objects and update_object to modify them.")
                        ))
                        continue
                    }
                    let args = AgentTool.parseArguments(functionName: funcName, jsonString: tc.function.arguments)
                    
                    // Guardrail: for non-layout requests, block spatial rewrites that can "break" scenes.
                    if agentTool == .updateObject,
                       let props = args.properties,
                       !allowLayoutEdits,
                       Self.containsLayoutOnlyEdit(in: props) {
                        logger.warning("[Agent] BLOCKED out-of-scope layout update_object for non-layout request", category: .llm)
                        apiMessages.append(.toolResult(
                            OpenRouterToolResultMessage(
                                role: "tool",
                                toolCallId: tc.id,
                                content: "Error: Layout edits (x/y/zIndex/size transforms) are blocked for this request. Only edit requested fields (e.g. opacity/animations)."
                            )
                        ))
                        continue
                    }
                    
                    let call = AgentToolCall(id: tc.id, tool: agentTool, arguments: args)
                    parsedCalls.append(ParsedCall(tc: tc, agentTool: agentTool, call: call))
                }
                
                // Execute all parsed tools (parallel if multiple, sequential if write operations involved)
                var agentToolCalls: [AgentToolCall] = []
                var agentToolResults: [AgentToolResult] = []
                
                // Check if any tool is a write operation — if so, run sequentially to avoid race conditions
                let hasWriteOps = parsedCalls.contains { $0.agentTool == .writeFile || $0.agentTool == .searchReplace || $0.agentTool == .updateObject }
                
                if parsedCalls.count > 1 && !hasWriteOps {
                    // Parallel execution for read-only tools (like the AI SDK's Promise.all)
                    logger.info("[Agent] Executing \(parsedCalls.count) tools in PARALLEL", category: .llm)
                    let results: [(call: AgentToolCall, result: AgentToolResult)] = await withTaskGroup(
                        of: (Int, AgentToolCall, AgentToolResult).self
                    ) { group in
                        for (index, parsed) in parsedCalls.enumerated() {
                            group.addTask {
                                let result = self.toolService.execute(parsed.call, projectURL: projectURL, project: project)
                                return (index, parsed.call, result)
                            }
                        }
                        var ordered: [(Int, AgentToolCall, AgentToolResult)] = []
                        for await item in group {
                            ordered.append(item)
                        }
                        // Preserve original order for deterministic API messages
                        return ordered.sorted { $0.0 < $1.0 }.map { ($0.1, $0.2) }
                    }
                    
                    for (call, result) in results {
                        agentToolCalls.append(call)
                        agentToolResults.append(result)
                    }
                } else {
                    // Sequential execution (single tool or write operations present)
                    for parsed in parsedCalls {
                        let result = toolService.execute(parsed.call, projectURL: projectURL, project: project)
                        agentToolCalls.append(parsed.call)
                        agentToolResults.append(result)
                    }
                }
                
                // Append all tool results to API messages
                // NOTE: No head+tail truncation here. OpenCode caps output at the TOOL level
                // (50KB for read_file, line-limited for grep) and relies on the model using
                // grep + read_file(offset/limit) for large content. This is cleaner and
                // prevents the model from hallucinating content from mangled truncated output.
                for (i, parsed) in parsedCalls.enumerated() {
                    let result = agentToolResults[i]
                    let output = result.success ? result.output : "Error: \(result.error ?? "Unknown")"
                    logger.debug("[Agent] Tool \(parsed.tc.function.name): \(result.success ? "OK" : "FAIL") | \(output.count) chars", category: .llm)
                    
                    apiMessages.append(.toolResult(
                        OpenRouterToolResultMessage(role: "tool", toolCallId: parsed.tc.id, content: output)
                    ))
                }
                
                // Track state for UI
                state.turns.append((call: agentToolCalls, results: agentToolResults))
                onToolActivity(state.allActivities)
                
                // --- Progressive read_file unlock ---
                // Track CRUD tool usage and failures to decide when to unlock read_file.
                for (i, call) in agentToolCalls.enumerated() {
                    if call.tool == .queryObjects || call.tool == .updateObject {
                        crudToolUsed = true
                    }
                    if call.tool == .updateObject && !agentToolResults[i].success {
                        failedUpdateCount += 1
                    }
                }
                
                // Unlock read_file if:
                // (a) The AI has used CRUD tools AND update_object failed 3+ times (might need raw JSON inspection), OR
                // (b) We're past turn 6 and the AI might need read_file for non-object data, OR
                // (c) The AI explicitly tried query_objects and still couldn't resolve the task
                if !readFileUnlocked {
                    if failedUpdateCount >= 3 {
                        readFileUnlocked = true
                        logger.info("[Agent] read_file UNLOCKED: \(failedUpdateCount) update_object failures — may need raw JSON inspection", category: .llm)
                    } else if turn >= 6 && crudToolUsed {
                        readFileUnlocked = true
                        logger.info("[Agent] read_file UNLOCKED: turn \(turn + 1) with CRUD tools already used", category: .llm)
                    }
                }
                
                // --- Read-loop detection (escalating) ---
                // Prevents the LLM from burning all turns reading a large file sequentially.
                // Level 1 (3+ reads): Nudge message urging CRUD tools.
                // Level 2 (5+ reads): Replace the tool result with a hard block.
                let isReadOnlyTurn = agentToolCalls.allSatisfy { call in
                    [AgentTool.readFile, .grep, .listFiles, .projectInfo, .queryObjects].contains(call.tool)
                }
                if isReadOnlyTurn {
                    consecutiveReadTurns += 1
                } else {
                    consecutiveReadTurns = 0
                }
                
                let remainingTurns = maxTurns - turn - 1
                
                if consecutiveReadTurns >= 5 {
                    // HARD BLOCK: Replace the most recent tool result(s) with a refusal.
                    for i in stride(from: apiMessages.count - 1, through: max(0, apiMessages.count - agentToolResults.count), by: -1) {
                        if case .toolResult(let toolMsg) = apiMessages[i] {
                            apiMessages[i] = .toolResult(
                                OpenRouterToolResultMessage(
                                    role: "tool",
                                    toolCallId: toolMsg.toolCallId,
                                    content: "READ BLOCKED: You have spent \(consecutiveReadTurns) turns without making edits. \(remainingTurns) turns left. Use update_object to modify object properties NOW. Example: update_object(id:\"UUID\", properties:{\"x\":540,\"y\":480}). No more reads until you make an edit."
                                )
                            )
                            break
                        }
                    }
                    logger.warning("[Agent] Read BLOCKED after \(consecutiveReadTurns) consecutive reads (\(remainingTurns) turns left)", category: .llm)
                } else if consecutiveReadTurns >= 3 {
                    let nudge = "⚠️ TURN BUDGET: \(consecutiveReadTurns) turns spent reading, \(remainingTurns) left. Use update_object(id:\"UUID\", properties:{...}) to make edits NOW."
                    apiMessages.append(OpenRouterMessage(role: "user", content: .text(nudge)).asAny)
                    logger.warning("[Agent] Read-loop nudge after \(consecutiveReadTurns) reads (\(remainingTurns) turns left)", category: .llm)
                }
                
                // Continue the loop — model will see tool results and decide next action
                continue
            }
            
            // --- No tool calls → this is the final text response ---
            let textContent = responseText
            let totalElapsed = (CFAbsoluteTimeGetCurrent() - pipelineStart)
            logger.info("[Agent] API responded in \(String(format: "%.0f", turnElapsed))ms → FINAL TEXT (\(textContent.count) chars, finish: \(finishReason))", category: .llm)
            logger.debug("[Agent] Final text preview: \"\(textContent.prefix(200))\(textContent.count > 200 ? "..." : "")\"", category: .llm)
            
            // Parse first, even if finish_reason == "length". Some providers report
            // truncation even when the JSON object itself is already complete.
            if let commands = parseTextForSceneCommands(textContent) {
                let actionCount = commands.actions?.count ?? 0
                logger.success("[Agent] ✓ Pipeline complete with \(actionCount) actions after \(state.turnCount) tool turns | Total: \(String(format: "%.1f", totalElapsed))s", category: .llm)
                state.isComplete = true
                state.finalMessage = commands.message
                state.finalCommands = commands
                executorResult = LLMResponse(
                    textResponse: commands.message ?? textContent,
                    commands: commands
                )
                break executorLoop
            }
            
            // Handle truncated responses (finish_reason: "length").
            // In pipeline JSON mode, restart from scratch instead of continuing junk.
            if finishReason == "length" && turn < maxTurns - 1 {
                if isPipelineJSONTurn && remainingFreshJSONRetries > 0 {
                    remainingFreshJSONRetries -= 1
                    pendingFreshJSONRetry = true
                    logger.warning("[Agent] JSON-mode response was truncated before valid parse. Requesting a fresh JSON restart...", category: .llm)
                    apiMessages.append(OpenRouterMessage(role: "user", content: .text("""
Ignore your previous incomplete response and START OVER from scratch.
Return ONLY one complete valid JSON object in this exact shape:
{"message":"...", "actions":[ ... ]}

Rules:
- No prose before or after the JSON
- No markdown fences
- No placeholders
- Include executable actions only
- Do not continue the previous text; rewrite the full JSON cleanly from the beginning
""")).asAny)
                } else {
                    logger.warning("[Agent] Response truncated (finish: length). Asking model to continue...", category: .llm)
                    apiMessages.append(OpenRouterMessage(role: "assistant", content: .text(textContent)).asAny)
                    apiMessages.append(OpenRouterMessage(role: "user", content: .text("Your response was cut off. Continue from where you stopped. Output ONLY the remaining JSON, starting exactly where you left off.")).asAny)
                }
                continue
            }
            
            // Recovery path: model returned final prose/JSON-like text but no executable actions/tool calls.
            // Request a strict actionable response once before accepting text-only output.
            if !attemptedActionRecovery && turn < maxTurns - 1 {
                attemptedActionRecovery = true
                if isPipelineJSONTurn && remainingFreshJSONRetries > 0 {
                    remainingFreshJSONRetries -= 1
                    pendingFreshJSONRetry = true
                    logger.warning("[Agent] JSON-mode response had no executable actions. Requesting a fresh JSON restart...", category: .llm)
                    apiMessages.append(OpenRouterMessage(role: "user", content: .text("""
Ignore your previous response and START OVER from scratch.
Return ONLY valid JSON in this exact shape:
{"message":"...", "actions":[ ... ]}

Requirements:
- Include at least ONE action that performs the requested change
- No prose before or after the JSON
- No markdown fences
- Do not continue or reference the previous malformed response
""")).asAny)
                } else {
                    logger.warning("[Agent] Final text had no executable actions. Requesting strict actionable JSON retry...", category: .llm)
                    
                    // Preserve the assistant output in context, then force format+action compliance.
                    apiMessages.append(OpenRouterMessage(role: "assistant", content: .text(textContent)).asAny)
                    apiMessages.append(OpenRouterMessage(role: "user", content: .text("""
Your previous response did not include executable actions or tool calls.
Return ONLY valid JSON (no markdown fences) in this exact shape:
{"message":"...", "actions":[ ... ]}

Requirements:
- Include at least ONE action that performs the requested change, OR issue tool_calls.
- Do NOT claim edits are done unless the actions/tool_calls actually perform them.
""")).asAny)
                }
                continue
            }
            
            // Plain text response (informational or confirmation)
            logger.success("[Agent] ✓ Pipeline complete (text-only) after \(state.turnCount) tool turns | Total: \(String(format: "%.1f", totalElapsed))s", category: .llm)
            state.isComplete = true
            executorResult = LLMResponse(textResponse: textContent, commands: state.finalCommands)
            break executorLoop
        }
        
        // Reached max turns — fallback result
        if executorResult == nil {
            let totalElapsed = (CFAbsoluteTimeGetCurrent() - pipelineStart)
            logger.warning("[Agent] ✗ Reached max turns (\(maxTurns)) after \(String(format: "%.1f", totalElapsed))s", category: .llm)
            executorResult = LLMResponse(
                textResponse: state.finalMessage ?? "I've done my best exploring the project. Here's what I found.",
                commands: state.finalCommands
            )
        }
        
        var finalResponse = executorResult!
        
        // --- Validator Phase (position + timing QA) ---
        // Programmatically fixes clipped objects, then LLM-reviews animation timing/logic.
        if let commands = finalResponse.commands {
            let cw = Int(sceneState.canvasWidth)
            let ch = Int(sceneState.canvasHeight)
            
            let validation = await CreativePipeline.runValidator(
                commands: commands,
                canvasWidth: cw,
                canvasHeight: ch,
                brief: pipelineBrief,
                onStageChange: onPipelineStageChange
            )
            
            finalResponse = LLMResponse(
                textResponse: finalResponse.textResponse,
                commands: validation.fixedCommands
            )
            
            if validation.positionFixCount > 0 {
                logger.success("[Agent] Validator fixed \(validation.positionFixCount) position issues", category: .llm)
            }
            
            // If timing issues found, inject them into the critic patch context
            if !validation.timingIssues.isEmpty, let fixes = validation.timingFixes {
                logger.warning("[Agent] Validator found \(validation.timingIssues.count) timing issues — will include in critic patch", category: .llm)
                
                onPipelineStageChange(.executor)
                apiMessages.append(OpenRouterMessage(role: "assistant", content: .text(finalResponse.textResponse)).asAny)
                apiMessages.append(OpenRouterMessage(role: "user", content: .text("""
                The technical validator found timing/logic bugs. Fix these BEFORE the quality review:
                
                \(fixes)
                
                Respond with fix actions in JSON: {"message":"Fixed timing issues", "actions":[...]}
                """)).asAny)
                
                do {
                    let fixChoice = try await sendNativeToolRequest(
                        messages: apiMessages,
                        tools: currentTools()
                    )
                    let fixContent = extractResponseText(from: fixChoice)
                    if !fixContent.isEmpty,
                       let fixCommands = parseTextForSceneCommands(fixContent) {
                        // Merge timing fixes with the position-fixed commands
                        var mergedActions = finalResponse.commands?.actions ?? []
                        if let fixActions = fixCommands.actions {
                            mergedActions.append(contentsOf: fixActions)
                        }
                        var merged = finalResponse.commands ?? SceneCommands()
                        merged.actions = mergedActions
                        finalResponse = LLMResponse(
                            textResponse: fixCommands.message ?? finalResponse.textResponse,
                            commands: merged
                        )
                        logger.success("[Agent] Validator timing fixes applied", category: .llm)
                    }
                } catch {
                    logger.warning("[Agent] Validator timing fix round failed: \(error.localizedDescription)", category: .llm)
                }
            }
        }
        
        // --- Skeleton Check (programmatic pre-Critic) ---
        if let brief = pipelineBrief, let commands = finalResponse.commands {
            let actionCount = commands.actions?.count ?? 0
            let objectCount = commands.actions?.filter { $0.type == .createObject }.count ?? 0
            let minActions = max(brief.motionScore.beats.count * 8, 60)
            let minObjects = max(brief.motionScore.beats.count * 2, 15)
            
            if actionCount < minActions || objectCount < minObjects {
                logger.warning("[Agent] ⚠️ Skeleton scene detected: \(actionCount) actions, \(objectCount) objects (need \(minActions)+/\(minObjects)+). Requesting expansion.", category: .llm)
                onPipelineStageChange(.executor)
                
                let existingObjectIDs = (commands.actions ?? [])
                    .filter { $0.type == .createObject }
                    .compactMap { $0.target ?? $0.parameters?.id ?? $0.parameters?.name }
                let objectList = existingObjectIDs.joined(separator: ", ")
                
                apiMessages.append(OpenRouterMessage(role: "assistant", content: .text(finalResponse.textResponse)).asAny)
                apiMessages.append(OpenRouterMessage(role: "user", content: .text("""
                ⚠️ INSUFFICIENT OUTPUT. You produced only \(actionCount) actions and \(objectCount) objects.
                The motion score has \(brief.motionScore.beats.count) beats — you need at LEAST \(minActions) actions and \(minObjects) objects.
                
                EXISTING OBJECTS (DO NOT recreate these): \(objectList)
                
                You MUST add NEW objects with UNIQUE IDs. For each beat in the motion score, add what the beat is actually missing:
                - Environment layers (shaders, gradients, or lighting shifts that deepen the space)
                - Compositional connectors (accent lines, framing shapes, contour geometry, guided negative space)
                - Optional procedural systems only when justified by the concept
                - Decorative shapes that reinforce the motion language
                - Additional text overlays with varied animations when the beat calls for them
                
                SPATIAL RULE: New objects should be positioned RELATIVE to the action. If the hero \
                locks at center, secondary systems can radiate, orbit, or phase-lock from center. If text appears, accent lines \
                or geometric guides can frame it. Objects must feel connected to the same scene, not randomly placed.

                IMPORTANT: Do NOT default to sparks, debris, explosions, or cheap radial particle bursts. \
                If you use procedural VFX, make them feel mathematically designed and concept-specific.
                
                Output ONLY new objects and their animations:
                {"message":"Expanding scene...", "actions":[... ONLY new createObject + addAnimation ...]}
                """)).asAny)
                
                do {
                    let expandChoice = try await sendNativeToolRequest(
                        messages: apiMessages,
                        tools: []
                    )
                    
                    let expandContent = extractResponseText(from: expandChoice)
                    
                    if !expandContent.isEmpty,
                       let expandCommands = parseTextForSceneCommands(expandContent),
                       let expandActions = expandCommands.actions, !expandActions.isEmpty {
                        let filteredActions = expandActions.filter { action in
                            if action.type == .createObject {
                                let newID = action.target ?? action.parameters?.id ?? action.parameters?.name ?? ""
                                return !existingObjectIDs.contains(newID)
                            }
                            return true
                        }
                        let dupCount = expandActions.count - filteredActions.count
                        if dupCount > 0 {
                            logger.info("[Agent] Filtered out \(dupCount) duplicate createObject actions from expansion", category: .llm)
                        }
                        var existingActions = finalResponse.commands?.actions ?? []
                        existingActions.append(contentsOf: filteredActions)
                        let merged = SceneCommands(message: finalResponse.commands?.message, actions: existingActions)
                        finalResponse = LLMResponse(textResponse: finalResponse.textResponse, commands: merged)
                        logger.success("[Agent] Scene expanded: +\(filteredActions.count) actions → \(existingActions.count) total", category: .llm)
                    } else {
                        logger.warning("[Agent] Expansion returned no parseable text content (finish: \(expandChoice.finishReason ?? "nil"))", category: .llm)
                    }
                } catch {
                    logger.warning("[Agent] Scene expansion failed: \(error.localizedDescription)", category: .llm)
                }
            }
        }
        
        // --- Critic Phase (post-execution quality review) ---
        // Only runs when the creative pipeline produced a brief. One patch round max.
        if let brief = pipelineBrief, let commands = finalResponse.commands {
            let commandsSummary = summarizeCommandsForCritic(commands, activities: state.allActivities)
            
            if let review = await CreativePipeline.runCritic(
                brief: brief,
                executedCommandsSummary: commandsSummary,
                onStageChange: onPipelineStageChange
            ), review.needsRevision {
                // Build patch instructions: use explicit instructions if available,
                // otherwise synthesize from issues list + raw text
                let patchText = review.patchInstructions
                    ?? review.issues.joined(separator: "\n")
                    ?? review.rawText.prefix(800).description
                
                logger.info("[Agent] ── Critic Patch Round ── (\(review.issues.count) issues)", category: .llm)
                onPipelineStageChange(.executor)
                
                apiMessages.append(OpenRouterMessage(role: "assistant", content: .text(finalResponse.textResponse)).asAny)
                apiMessages.append(OpenRouterMessage(role: "user", content: .text("""
                The quality reviewer flagged these issues. Apply ONLY the specific fixes below.
                
                ⚠️ CRITICAL RULES:
                - Output ONLY the fix actions (addAnimation, updateProperties, modifyObject, applyPreset).
                - Do NOT regenerate createObject actions — all objects already exist.
                - Do NOT output a full scene rebuild. MAX 30 actions.
                - If the fix requires removing an animation, use updateProperties to reset it.
                - You may use query_objects ONCE to inspect current state, then output fixes.
                
                \(patchText)
                
                Issues: \(review.issues.joined(separator: "; "))
                
                Respond with ONLY the fix JSON:
                {"message":"Critic fixes: ...", "actions":[... max 30 targeted fix actions ...]}
                """)).asAny)
                
                let maxPatchTurns = 5
                do {
                    for patchTurn in 0..<maxPatchTurns {
                        let patchChoice = try await sendNativeToolRequest(
                            messages: apiMessages,
                            tools: currentTools()
                        )
                        
                        if let patchToolCalls = patchChoice.message?.toolCalls, !patchToolCalls.isEmpty {
                            var toolResults: [(id: String, result: String)] = []
                            for tc in patchToolCalls {
                                guard let tool = AgentTool.from(functionName: tc.function.name) else { continue }
                                let args = AgentTool.parseArguments(functionName: tc.function.name, jsonString: tc.function.arguments)
                                let call = AgentToolCall(id: tc.id, tool: tool, arguments: args)
                                let result = toolService.execute(call, projectURL: projectURL, project: project)
                                toolResults.append((id: tc.id, result: result.output))
                                logger.info("[Agent:Patch:\(patchTurn+1)] \(tool.functionName) → \(result.success ? "✓" : "✗")", category: .llm)
                            }
                            
                            let patchTCRequests = patchToolCalls.map { tc in
                                OpenRouterToolCallRequest(
                                    id: tc.id, type: tc.type,
                                    function: OpenRouterFunctionCallRequest(name: tc.function.name, arguments: tc.function.arguments)
                                )
                            }
                            apiMessages.append(.assistantToolCalls(
                                OpenRouterAssistantToolCallMessage(role: "assistant", toolCalls: patchTCRequests)
                            ))
                            for tr in toolResults {
                                apiMessages.append(.toolResult(OpenRouterToolResultMessage(role: "tool", toolCallId: tr.id, content: tr.result)))
                            }
                            continue
                        } else {
                            let patchContent = extractResponseText(from: patchChoice)
                            guard !patchContent.isEmpty else { break }
                            if let patchCommands = parseTextForSceneCommands(patchContent),
                               let patchActions = patchCommands.actions, !patchActions.isEmpty {
                                let existingActions = finalResponse.commands?.actions ?? []
                                if patchActions.count > existingActions.count / 2 {
                                    logger.warning("[Agent] Critic patch produced \(patchActions.count) actions (too many — likely a rebuild). Keeping only non-createObject fixes.", category: .llm)
                                    let fixOnly = patchActions.filter { $0.type != .createObject }
                                    var merged = SceneCommands(message: finalResponse.commands?.message, actions: existingActions + fixOnly)
                                    merged.message = patchCommands.message ?? finalResponse.commands?.message
                                    finalResponse = LLMResponse(
                                        textResponse: finalResponse.textResponse,
                                        commands: merged
                                    )
                                } else {
                                    let merged = SceneCommands(message: patchCommands.message ?? finalResponse.commands?.message, actions: existingActions + patchActions)
                                    finalResponse = LLMResponse(
                                        textResponse: finalResponse.textResponse,
                                        commands: merged
                                    )
                                }
                                logger.success("[Agent] Critic patch produced \(patchActions.count) fix actions (merged into \(finalResponse.commands?.actions?.count ?? 0) total)", category: .llm)
                            }
                            break
                        }
                    }
                    logger.success("[Agent] Critic patch round completed", category: .llm)
                } catch {
                    logger.warning("[Agent] Critic patch round failed: \(error.localizedDescription) — using original result", category: .llm)
                }
            } else {
                logger.success("[Agent] Critic approved the execution ✓", category: .llm)
            }
        }
        
        return finalResponse
    }
    
    // MARK: - Tool Output Pruning (mirrors OpenCode's compaction.ts)
    
    /// Prunes old tool result outputs from API messages to keep context manageable.
    /// OpenCode keeps the last PRUNE_PROTECT (40K chars) of tool results intact,
    /// then replaces older tool results with "[TOOL OUTPUT PRUNED]".
    /// This prevents the API request from growing without bound across turns.
    private let pruneProtectChars = 40_000  // Keep this much tool output from recent turns
    private let pruneMinimumChars = 20_000  // Only prune if we'd reclaim at least this much
    
    private func pruneToolOutputs(_ messages: inout [AnyOpenRouterMessage]) {
        let logger = DebugLogger.shared
        
        // Find the index of the most recent assistantToolCalls message.
        // Tool results after this index are from the CURRENT turn and must always
        // be protected — otherwise the LLM can't see its own tool results and
        // will re-read the same files, wasting turns.
        var lastAssistantToolCallIdx = -1
        for i in stride(from: messages.count - 1, through: 0, by: -1) {
            if case .assistantToolCalls = messages[i] {
                lastAssistantToolCallIdx = i
                break
            }
        }
        
        // Walk backwards through messages, tracking tool output chars
        var totalToolChars = 0
        var olderToolChars = 0      // Only counts chars from previous turns
        var protectedToolChars = 0
        var toPruneIndices: [Int] = []
        
        for i in stride(from: messages.count - 1, through: 0, by: -1) {
            // Only prune tool result messages
            guard case .toolResult(let toolMsg) = messages[i] else { continue }
            
            let outputSize = toolMsg.content.count
            totalToolChars += outputSize
            
            if i > lastAssistantToolCallIdx {
                // Current turn's tool results — always protect
                protectedToolChars += outputSize
            } else {
                // Older turn's tool results — protect up to threshold
                olderToolChars += outputSize
                if olderToolChars <= pruneProtectChars {
                    protectedToolChars += outputSize
                } else {
                    toPruneIndices.append(i)
                }
            }
        }
        
        let reclaimable = toPruneIndices.reduce(0) { sum, idx in
            if case .toolResult(let msg) = messages[idx] {
                return sum + msg.content.count
            }
            return sum
        }
        
        guard reclaimable >= pruneMinimumChars else { return }
        
        // Prune old tool outputs
        var pruned = 0
        for idx in toPruneIndices {
            if case .toolResult(let toolMsg) = messages[idx] {
                let original = toolMsg.content.count
                messages[idx] = .toolResult(
                    OpenRouterToolResultMessage(
                        role: "tool",
                        toolCallId: toolMsg.toolCallId,
                        content: "[TOOL OUTPUT PRUNED — \(original) chars removed to save context]"
                    )
                )
                pruned += original
            }
        }
        
        logger.info("[Agent:Prune] Pruned \(toPruneIndices.count) old tool outputs, reclaimed ~\(pruned / 1000)K chars (protected last \(protectedToolChars / 1000)K chars)", category: .llm)
    }
    
    // MARK: - LLM Communication (Native Function Calling)
    
    /// Sends a request to OpenRouter with native tool definitions.
    /// Returns the full `OpenRouterChoice` so the caller can inspect `tool_calls` and `finishReason`.
    private func sendNativeToolRequest(
        messages: [AnyOpenRouterMessage],
        tools: [OpenRouterTool]
    ) async throws -> OpenRouterChoice {
        let logger = DebugLogger.shared
        
        guard OpenRouterConfig.isDebugProxy || !OpenRouterConfig.apiKey.isEmpty else {
            throw OpenRouterError.missingAPIKey
        }
        
        let encoder = JSONEncoder()
        
        let body = OpenRouterRequestBody(
            model: OpenRouterConfig.selectedModel,
            messages: messages,
            temperature: 0.7,
            maxTokens: 32768,
            tools: tools.isEmpty ? nil : tools,
            toolChoice: tools.isEmpty ? nil : "auto"
        )
        
        var request = URLRequest(url: URL(string: OpenRouterConfig.baseURL)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(OpenRouterConfig.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("AIAfterEffects/1.0", forHTTPHeaderField: "HTTP-Referer")
        request.addValue("AI After Effects macOS App", forHTTPHeaderField: "X-Title")
        request.httpBody = try encoder.encode(body)
        
        let requestSize = request.httpBody?.count ?? 0
        logger.debug("[Agent:API] Sending request: model=\(OpenRouterConfig.selectedModel) | body=\(requestSize) bytes | \(messages.count) messages | \(tools.count) tools", category: .network)
        
        let apiStart = CFAbsoluteTimeGetCurrent()
        let (data, response) = try await URLSession.shared.data(for: request)
        let apiElapsed = (CFAbsoluteTimeGetCurrent() - apiStart) * 1000
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let rawBody = String(data: data, encoding: .utf8) ?? ""
            let errorMessage = OpenRouterService.parseAPIErrorMessage(statusCode: statusCode, body: rawBody)
            logger.error("[Agent:API] HTTP \(statusCode) after \(String(format: "%.0f", apiElapsed))ms: \(errorMessage.prefix(200))", category: .network)
            throw OpenRouterError.apiError(statusCode: statusCode, message: errorMessage)
        }
        
        logger.debug("[Agent:API] Response: HTTP \(httpResponse.statusCode) | \(data.count) bytes | \(String(format: "%.0f", apiElapsed))ms", category: .network)
        
        let decoder = JSONDecoder()
        let apiResponse = try decoder.decode(OpenRouterAPIResponse.self, from: data)
        
        guard let choice = apiResponse.choices.first else {
            logger.error("[Agent:API] Empty response (no choices)", category: .network)
            throw OpenRouterError.emptyResponse
        }
        
        // Log what the API returned
        let hasToolCalls = choice.message?.toolCalls?.isEmpty == false
        let hasContent = choice.message?.content?.textValue?.isEmpty == false
        logger.debug("[Agent:API] Choice: finish=\(choice.finishReason ?? "nil") | toolCalls=\(hasToolCalls) | hasContent=\(hasContent)", category: .network)
        
        return choice
    }
    
    // MARK: - Critic Support
    
    /// Builds a concise summary of executed commands and tool activities for the Critic agent.
    private func summarizeCommandsForCritic(_ commands: SceneCommands, activities: [ToolActivity]) -> String {
        var summary = ""
        
        if let actions = commands.actions {
            summary += "## Executed Actions (\(actions.count) total)\n"
            for (i, action) in actions.enumerated() {
                var line = "\(i + 1). \(action.type.rawValue)"
                if let target = action.target { line += " → \"\(target)\"" }
                if let p = action.parameters {
                    var parts: [String] = []
                    if let name = p.name { parts.append("name=\"\(name)\"") }
                    if let objType = p.objectType ?? p.type { parts.append("type=\(objType)") }
                    if let anim = p.animationType { parts.append("anim=\(anim)") }
                    if let dur = p.duration { parts.append("dur=\(dur)s") }
                    if let start = p.startTime { parts.append("start=\(start)s") }
                    if let easing = p.easing { parts.append("easing=\(easing)") }
                    if let font = p.fontSize { parts.append("fontSize=\(font)") }
                    if let text = p.text ?? p.content { parts.append("text=\"\(text.prefix(30))\"") }
                    if !parts.isEmpty { line += " {\(parts.joined(separator: ", "))}" }
                }
                summary += line + "\n"
            }
        }
        
        let toolCalls = activities.filter { $0.status == .success }
        if !toolCalls.isEmpty {
            summary += "\n## Tool Calls (\(toolCalls.count) successful)\n"
            for activity in toolCalls.suffix(10) {
                summary += "- \(activity.tool.functionName): \(activity.summary)\n"
            }
        }
        
        if let msg = commands.message {
            summary += "\n## Assistant Message\n\(msg)\n"
        }
        
        return summary
    }
    
    // MARK: - Final Answer Parsing
    
    /// Tries to parse the model's final text response for scene commands.
    /// The model may embed a JSON block with `actions` in its text response.
    private func parseTextForSceneCommands(_ content: String) -> SceneCommands? {
        guard let jsonString = extractJSON(from: content) else {
            DebugLogger.shared.warning("[Agent] Could not extract JSON from final text response", category: .parsing)
            return nil
        }
        guard let jsonData = jsonString.data(using: .utf8) else {
            DebugLogger.shared.warning("[Agent] Extracted JSON could not be encoded as UTF-8", category: .parsing)
            return nil
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        // Try decoding as SceneCommands
        do {
            let commands = try decoder.decode(SceneCommands.self, from: jsonData)
            let actionCount = commands.actions?.count ?? 0
            if actionCount > 0 {
                DebugLogger.shared.info("[Agent] Parsed final JSON with \(actionCount) actions", category: .parsing)
                return commands
            } else {
                DebugLogger.shared.warning("[Agent] Final JSON decoded but actions were empty", category: .parsing)
            }
        } catch {
            DebugLogger.shared.logParsingError(
                "[Agent] Failed to decode final commands JSON: \(error)",
                json: String(jsonString.prefix(500))
            )
        }
        
        return nil
    }
    
    // MARK: - JSON Extraction
    
    private func extractJSON(from content: String) -> String? {
        // Try ```json ... ``` first
        if let start = content.range(of: "```json"),
           let end = content.range(of: "```", range: start.upperBound..<content.endIndex) {
            let json = String(content[start.upperBound..<end.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if json.hasPrefix("{") { return json }
        }
        
        // Try ``` ... ```
        if let start = content.range(of: "```"),
           let end = content.range(of: "```", range: start.upperBound..<content.endIndex) {
            let json = String(content[start.upperBound..<end.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if json.hasPrefix("{") { return json }
        }
        
        // Try raw JSON (find first { and matching })
        if let braceStart = content.firstIndex(of: "{") {
            if let braceEnd = findMatchingBrace(in: content, from: braceStart) {
                return String(content[braceStart...braceEnd])
            }
        }
        
        return nil
    }
    
    private func findMatchingBrace(in string: String, from startIndex: String.Index) -> String.Index? {
        var depth = 0
        var index = startIndex
        var inString = false
        var escapeNext = false
        
        while index < string.endIndex {
            let char = string[index]
            if escapeNext { escapeNext = false }
            else if char == "\\" { escapeNext = true }
            else if char == "\"" { inString.toggle() }
            else if !inString {
                if char == "{" { depth += 1 }
                else if char == "}" {
                    depth -= 1
                    if depth == 0 { return index }
                }
            }
            index = string.index(after: index)
        }
        return nil
    }
    
    private func extractMessageField(from content: String) -> String? {
        let pattern = #""message"\s*:\s*"([^"]+)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
           let range = Range(match.range(at: 1), in: content) {
            return String(content[range])
        }
        return nil
    }
    
    private func extractResponseText(from choice: OpenRouterChoice) -> String {
        let text = choice.message?.content?.textValue ?? choice.text ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Request Scope Guardrails
    
    /// True when user intent explicitly asks for repositioning/layering/layout changes.
    private static func requestAllowsLayoutEdits(_ message: String) -> Bool {
        let lower = message.lowercased()
        let layoutSignals = [
            "position", "reposition", "move ", "grid", "layout", "arrange",
            "align", "center", "left", "right", "top", "bottom",
            "zindex", "z-index", "layer", "front", "back", "behind",
            "x=", "y=", "width", "height", "size", "scale", "rotate"
        ]
        return layoutSignals.contains { lower.contains($0) }
    }
    
    /// For non-layout requests, block edits that ONLY touch spatial/layout fields.
    /// If the call includes non-layout fields too (e.g. opacity + x), still block because
    /// these mixed updates are a common way models accidentally break scenes.
    private static func containsLayoutOnlyEdit(in properties: [String: Any]) -> Bool {
        let layoutKeys: Set<String> = [
            "x", "y", "zIndex", "width", "height", "rotation", "scaleX", "scaleY"
        ]
        let keys = Set(properties.keys)
        return !keys.intersection(layoutKeys).isEmpty
    }
    
    /// Safety-net fallback: if the agent loop's internal history grows too large
    /// (due to many tool-call rounds), trim to keep things manageable.
    /// Main compaction is done once at the start of run() via ContextCompactionService.
    private func trimAgentLoopHistory(_ history: [ChatMessage]) -> [ChatMessage] {
        let filtered = history.filter { !$0.isLoading }
        let maxMessages = 40  // Generous for agent mode (tool turns add up)
        
        if filtered.count <= maxMessages { return filtered }
        
        let first = Array(filtered.prefix(2))
        let recent = Array(filtered.suffix(maxMessages - 2))
        return first + recent
    }
    
    // MARK: - Intent Classification
    
    /// Classifies user intent as `.question` (info request) or `.implementation` (create/edit/animate).
    /// Uses a fast LLM call first; falls back to local analysis if the model returns empty.
    enum UserIntent {
        case question       // "What texts are in scene 2?", "How many objects?"
        case implementation // "Add a bouncing ball", "Make the title bigger"
    }
    
    func classifyIntent(_ message: String) async -> UserIntent {
        let logger = DebugLogger.shared
        
        // Step 1: Try LLM classification
        if OpenRouterConfig.isDebugProxy || !OpenRouterConfig.apiKey.isEmpty {
            if let llmIntent = await llmClassifyIntent(message) {
                return llmIntent
            }
        }
        
        // Step 2: LLM returned empty or failed — use local analysis as fallback
        let fallbackIntent = localClassifyIntent(message)
        logger.info("[Agent] Classifier fallback (local): \(fallbackIntent == .question ? "QUESTION" : "IMPLEMENTATION") for: \"\(message.prefix(60))\"", category: .llm)
        return fallbackIntent
    }
    
    // MARK: - LLM-based Intent Classification
    
    /// Attempts to classify intent via a lightweight LLM call.
    /// Returns nil if the model fails to produce a usable response.
    private func llmClassifyIntent(_ message: String) async -> UserIntent? {
        let logger = DebugLogger.shared
        
        do {
            let encoder = JSONEncoder()
            
            // Two-message format: system instruction + user's actual message.
            // Using temperature > 0 because some models (Gemini) return empty at 0.0.
            let systemPrompt = """
            You are a message classifier. Respond with exactly one word: QUESTION or ACTION.
            
            QUESTION — the user wants to know, see, list, describe, inspect, or ask about something.
            ACTION — the user wants to create, edit, modify, delete, animate, move, resize, speed up, slow down, or change something.
            
            Respond with one word only.
            """
            
            let body = OpenRouterRequestBody(
                model: OpenRouterConfig.selectedModel,
                messages: [
                    OpenRouterMessage(role: "system", content: .text(systemPrompt)).asAny,
                    OpenRouterMessage(role: "user", content: .text(message)).asAny
                ],
                temperature: 0.3,
                maxTokens: 256
            )
            
            var request = URLRequest(url: URL(string: OpenRouterConfig.baseURL)!)
            request.httpMethod = "POST"
            request.addValue("Bearer \(OpenRouterConfig.apiKey)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("AIAfterEffects/1.0", forHTTPHeaderField: "HTTP-Referer")
            request.addValue("AI After Effects macOS App", forHTTPHeaderField: "X-Title")
            request.httpBody = try encoder.encode(body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                logger.warning("[Agent] Classifier HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)", category: .llm)
                return nil
            }
            
            let decoder = JSONDecoder()
            let apiResponse = try decoder.decode(OpenRouterAPIResponse.self, from: data)
            
            let rawClassifierContent = apiResponse.choices.first?.message?.content?.textValue
                ?? apiResponse.choices.first?.text
                ?? ""
            let content = rawClassifierContent
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            
            logger.info("[Agent] Classifier LLM raw: \"\(content)\" for: \"\(message.prefix(60))\"", category: .llm)
            
            guard !content.isEmpty else {
                logger.warning("[Agent] Classifier LLM returned empty", category: .llm)
                return nil // Trigger fallback
            }
            
            // Parse strictly: prefer exact/word-level matches first.
            // Avoid loose checks like contains("I"), which can misclassify noisy outputs.
            let tokens = Set(
                content
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { !$0.isEmpty }
                    .map { $0.uppercased() }
            )
            
            if tokens.contains("QUESTION") || content == "Q" || content.hasPrefix("QUESTION") {
                logger.info("[Agent] → QUESTION (LLM)", category: .llm)
                return .question
            }
            if tokens.contains("ACTION") || content == "A" || content.hasPrefix("ACTION") {
                logger.info("[Agent] → IMPLEMENTATION (LLM)", category: .llm)
                return .implementation
            }
            
            logger.warning("[Agent] Classifier LLM unrecognized: \"\(content)\"", category: .llm)
            return nil // Trigger fallback
            
        } catch {
            logger.warning("[Agent] Classifier LLM error: \(error.localizedDescription)", category: .llm)
            return nil // Trigger fallback
        }
    }
    
    // MARK: - Local Intent Classification (Fallback)
    
    /// Fast local analysis when the LLM classifier fails to respond.
    /// Checks for clear action verbs vs. question patterns.
    private func localClassifyIntent(_ message: String) -> UserIntent {
        let lower = message.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Greetings / small talk should not trigger edit pipelines.
        let greetingOnly = [
            "hi", "hey", "hello", "yo", "sup", "good morning", "good afternoon", "good evening"
        ]
        if greetingOnly.contains(lower) {
            return .question
        }
        
        // Clear modification intent — verbs that imply changing the project
        let actionPhrases = [
            "make ", "create ", "add ", "change ", "update ", "delete ", "remove ",
            "speed up", "slow down", "move ", "resize ", "animate ", "set ",
            "modify ", "edit ", "replace ", "duplicate ", "apply ", "increase ",
            "decrease ", "scale ", "rotate ", "fade ", "flip ",
            "can you make", "can you add", "can you change", "can you create",
            "can you update", "can you set", "can you move", "can you delete",
            "can you speed", "can you slow", "can you edit", "can you apply",
            "i want to", "i need to", "please make", "please add", "please change",
            "let's make", "let's add", "let's create"
        ]
        
        for phrase in actionPhrases {
            if lower.contains(phrase) {
                return .implementation
            }
        }
        
        // Clear question intent — asking about existing state
        let questionPhrases = [
            "what ", "how many", "how is", "how does", "where is",
            "which ", "do we have", "does it have", "is there",
            "tell me about", "describe ", "show me", "list ",
            "what's ", "what are", "who "
        ]
        
        for phrase in questionPhrases {
            if lower.contains(phrase) {
                return .question
            }
        }
        
        // Ends with "?" and no action words → likely a question
        if lower.hasSuffix("?") {
            return .question
        }
        
        // Default to implementation (more capable, safe for ambiguous requests)
        return .implementation
    }
    
    // MARK: - Quick Question Handler
    
    /// Handles simple informational questions with a single lightweight LLM call.
    /// No planning pass, no tool loop, no heavy animation/preset docs.
    func handleQuickQuestion(
        userMessage: String,
        conversationHistory: [ChatMessage],
        sceneState: SceneState,
        project: Project,
        currentSceneIndex: Int
    ) async throws -> LLMResponse {
        let logger = DebugLogger.shared
        logger.info("[Agent] Quick question path — lightweight single-call", category: .llm)
        
        guard OpenRouterConfig.isDebugProxy || !OpenRouterConfig.apiKey.isEmpty else {
            throw OpenRouterError.missingAPIKey
        }
        
        // Compact history (same as full pipeline)
        let compactedHistory = await ContextCompactionService.shared.prepareForSubmission(
            history: conversationHistory,
            sceneState: sceneState
        )
        
        // Build minimal prompt
        let systemPrompt = PromptBuilder.buildQuickAnswerPrompt(
            sceneState: sceneState,
            project: project,
            currentSceneIndex: currentSceneIndex
        )
        
        // Build messages
        var messages: [AnyOpenRouterMessage] = []
        messages.append(OpenRouterMessage(role: "system", content: .text(systemPrompt)).asAny)
        
        for msg in compactedHistory {
            if msg.isLoading { continue }
            let role: String
            switch msg.role {
            case .user: role = "user"
            case .assistant: role = "assistant"
            case .system: role = "system"
            }
            messages.append(OpenRouterMessage(role: role, content: .text(msg.content)).asAny)
        }
        
        messages.append(OpenRouterMessage(role: "user", content: .text(userMessage)).asAny)
        
        // Single LLM call with low max tokens
        let encoder = JSONEncoder()
        
        let body = OpenRouterRequestBody(
            model: OpenRouterConfig.selectedModel,
            messages: messages,
            temperature: 0.3,
            maxTokens: 1024
        )
        
        var request = URLRequest(url: URL(string: OpenRouterConfig.baseURL)!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(OpenRouterConfig.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("AIAfterEffects/1.0", forHTTPHeaderField: "HTTP-Referer")
        request.addValue("AI After Effects macOS App", forHTTPHeaderField: "X-Title")
        request.httpBody = try encoder.encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let rawBody = String(data: data, encoding: .utf8) ?? ""
            let errorMessage = OpenRouterService.parseAPIErrorMessage(statusCode: statusCode, body: rawBody)
            throw OpenRouterError.apiError(statusCode: statusCode, message: errorMessage)
        }
        
        let decoder = JSONDecoder()
        let apiResponse = try decoder.decode(OpenRouterAPIResponse.self, from: data)
        
        guard let content = apiResponse.choices.first?.message?.content?.textValue,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenRouterError.emptyResponse
        }
        
        let answer = content.trimmingCharacters(in: .whitespacesAndNewlines)
        logger.success("[Agent] Quick answer returned (\(answer.count) chars)", category: .llm)
        
        return LLMResponse(textResponse: answer, commands: nil)
    }
}
