//
//  Gizmo3DEnvironmentView.swift
//  AIAfterEffects
//
//  Full-viewport 3D editing environment with SceneKit-based gizmos,
//  camera orbit controls, and grid floor. Activated when the user
//  enters 3D edit mode for a model3D object.
//

import SwiftUI
import SceneKit

// MARK: - 3D Environment View

struct Gizmo3DEnvironmentView: View {
    @ObservedObject var gizmoVM: GizmoViewModel
    @ObservedObject var canvasVM: CanvasViewModel
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Full SceneKit viewport
            Gizmo3DSceneView(gizmoVM: gizmoVM, canvasVM: canvasVM)
            
            // Overlay controls
            VStack(alignment: .trailing, spacing: 12) {
                // Top row: mode label + exit button
                HStack(spacing: 12) {
                    // Mode label
                    HStack(spacing: 8) {
                        Image(systemName: "cube.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("3D Edit Mode")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: "007AFF").opacity(0.9))
                    )
                    
                    // Exit button — prominent and easy to click
                    Button(action: { gizmoVM.exit3DEditMode() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Exit 3D")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.red.opacity(0.8))
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                // Current mode indicator (bottom right)
                HStack(spacing: 6) {
                    Image(systemName: gizmoVM.activeMode.icon)
                        .font(.system(size: 12))
                    Text(gizmoVM.activeMode.rawValue.capitalized)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.5))
                )
            }
            .padding(16)
        }
        .background(Color.black.opacity(0.02))
    }
}

// MARK: - SceneKit 3D Scene View (NSViewRepresentable)

struct Gizmo3DSceneView: NSViewRepresentable {
    @ObservedObject var gizmoVM: GizmoViewModel
    @ObservedObject var canvasVM: CanvasViewModel
    
    func makeNSView(context: Context) -> GizmoSCNView {
        let scnView = SCNView()
        scnView.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 1.0)
        scnView.autoenablesDefaultLighting = false
        scnView.allowsCameraControl = false // We handle camera ourselves
        scnView.antialiasingMode = .multisampling4X
        scnView.showsStatistics = false
        
        let scene = SCNScene()
        scnView.scene = scene
        
        // Setup camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.automaticallyAdjustsZRange = true
        cameraNode.camera?.fieldOfView = 45
        cameraNode.name = "editCamera"
        scene.rootNode.addChildNode(cameraNode)
        
        // Setup lights
        setupLighting(scene: scene)
        
        // Add grid floor
        let grid = GizmoNodeFactory.makeGridFloor()
        grid.position = SCNVector3(0, -1, 0)
        scene.rootNode.addChildNode(grid)
        
        // Load the 3D model
        if let object = gizmoVM.selectedObject {
            context.coordinator.loadModelForEditing(object: object, into: scene)
            
            // Initialize camera from the object's existing camera properties
            // so the 3D environment opens with the same view as the 2D canvas.
            // Also apply camera animations at the current time so the angle matches
            // exactly what the user sees on the 2D canvas.
            let props = object.properties
            var camDist = CGFloat(props.cameraDistance ?? 5.0)
            var camPitchDeg = CGFloat(props.cameraAngleX ?? 15)
            var camYawDeg = CGFloat(props.cameraAngleY ?? 0)
            
            // Evaluate camera animations at current time so the 3D view
            // opens at the exact same camera angle as the 2D canvas.
            let currentTime = canvasVM.currentTime
            for animation in object.animations {
                let progress = context.coordinator.calculateAnimProgress(animation: animation, currentTime: currentTime)
                guard progress >= 0 else { continue }
                let eased = EasingHelper.apply(animation.easing, to: progress)
                let value = context.coordinator.interpolateKF(animation.keyframes, at: eased)
                
                switch animation.type {
                case .cameraZoom, .cameraPushPull:
                    camDist = CGFloat(value)
                case .cameraPan, .cameraWhipPan:
                    camYawDeg += CGFloat(value)
                case .cameraRise, .cameraDive, .cameraPedestal, .cameraRocket:
                    camPitchDeg = CGFloat(value)
                case .cameraShake:
                    let shakeVal = CGFloat(value)
                    camPitchDeg += shakeVal
                    camYawDeg += shakeVal * 0.7
                default:
                    break
                }
            }
            
            context.coordinator.cameraDistance = camDist
            context.coordinator.cameraPitch = camPitchDeg * .pi / 180
            // Negate the yaw: the 2D renderer convention is "positive angle = camera RIGHT",
            // but for 3D orbit we use "positive yaw = camera LEFT" (grab-rotate feel).
            // The negation here + negation in syncCameraToProperties keeps them in sync.
            context.coordinator.cameraYaw = -camYawDeg * .pi / 180
        }
        
        // Add gizmo (default: translation)
        let gizmo = gizmoForCurrentMode()
        gizmo.name = "gizmo_root"
        scene.rootNode.addChildNode(gizmo)
        
        // Position camera from the initialized values
        context.coordinator.resetCamera(cameraNode: cameraNode)
        context.coordinator.scnView = scnView
        context.coordinator.gizmoVM = gizmoVM
        context.coordinator.canvasVM = canvasVM
        
        // Add gesture recognizers
        // Left-click drag: orbit camera or drag gizmo
        let panGesture = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.buttonMask = 0x1 // Left button
        scnView.addGestureRecognizer(panGesture)
        
        // Right-click drag: pan camera
        let rightPanGesture = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleRightPan(_:)))
        rightPanGesture.buttonMask = 0x2 // Right button
        scnView.addGestureRecognizer(rightPanGesture)
        
        // Middle-click drag: pan camera (Blender-style)
        let middlePanGesture = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleRightPan(_:)))
        middlePanGesture.buttonMask = 0x4 // Middle button
        scnView.addGestureRecognizer(middlePanGesture)
        
        let clickGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        scnView.addGestureRecognizer(clickGesture)
        
        // Use a custom NSView subclass to capture scroll events
        let scrollView = GizmoSCNView(coordinator: context.coordinator)
        scrollView.backgroundColor = scnView.backgroundColor
        scrollView.autoenablesDefaultLighting = scnView.autoenablesDefaultLighting
        scrollView.allowsCameraControl = false
        scrollView.antialiasingMode = scnView.antialiasingMode
        scrollView.showsStatistics = false
        scrollView.scene = scene
        
        // Move gesture recognizers to the new view
        for gesture in scnView.gestureRecognizers {
            scnView.removeGestureRecognizer(gesture)
        }
        scrollView.addGestureRecognizer(panGesture)
        scrollView.addGestureRecognizer(rightPanGesture)
        scrollView.addGestureRecognizer(middlePanGesture)
        scrollView.addGestureRecognizer(clickGesture)
        
        context.coordinator.scnView = scrollView
        
        return scrollView
    }
    
    func updateNSView(_ scnView: GizmoSCNView, context: Context) {
        guard let scene = scnView.scene else { return }
        
        context.coordinator.gizmoVM = gizmoVM
        context.coordinator.canvasVM = canvasVM
        
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        SCNTransaction.disableActions = true
        
        // Update gizmo type if mode changed
        let currentGizmoName = scene.rootNode.childNode(withName: "gizmo_root", recursively: false)?.childNodes.first?.name ?? ""
        let expectedPrefix = "gizmo_\(gizmoVM.activeMode.rawValue)"
        
        if !currentGizmoName.hasPrefix(expectedPrefix.replacingOccurrences(of: "move", with: "translation"))
            && !currentGizmoName.hasPrefix(expectedPrefix) {
            // Remove old gizmo
            scene.rootNode.childNode(withName: "gizmo_root", recursively: false)?.removeFromParentNode()
            
            // Add new gizmo
            let newGizmo = gizmoForCurrentMode()
            newGizmo.name = "gizmo_root"
            scene.rootNode.addChildNode(newGizmo)
            
            // Position the new gizmo at the model's current position
            if let modelNode = context.coordinator.modelNode {
                newGizmo.position = modelNode.position
            }
        }
        
        // Update model transform from current properties — but ONLY if model
        // properties actually changed. Camera orbit/zoom only change camera angles,
        // which shouldn't re-apply model transforms (this would overwrite the initial
        // animation-inclusive transform or cause unnecessary resets).
        if let modelNode = context.coordinator.modelNode,
           let object = canvasVM.selectedObject {
            let newFingerprint = context.coordinator.modelFingerprint(for: object.properties)
            if newFingerprint != context.coordinator.lastModelFingerprint {
                updateModelFromProperties(modelNode: modelNode, object: object, coordinator: context.coordinator)
                context.coordinator.lastModelFingerprint = newFingerprint
            }
        }
        
        SCNTransaction.commit()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    // MARK: - Setup
    
    private func setupLighting(scene: SCNScene) {
        // Ambient
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 600
        ambient.light?.color = NSColor.white
        scene.rootNode.addChildNode(ambient)
        
        // Key light
        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light?.type = .directional
        keyLight.light?.intensity = 1000
        keyLight.light?.castsShadow = true
        keyLight.light?.shadowMode = .forward
        keyLight.light?.shadowSampleCount = 8
        keyLight.eulerAngles = SCNVector3(-CGFloat.pi / 3, CGFloat.pi / 4, 0)
        scene.rootNode.addChildNode(keyLight)
        
        // Fill light
        let fillLight = SCNNode()
        fillLight.light = SCNLight()
        fillLight.light?.type = .directional
        fillLight.light?.intensity = 400
        fillLight.eulerAngles = SCNVector3(-CGFloat.pi / 6, -CGFloat.pi / 3, 0)
        scene.rootNode.addChildNode(fillLight)
    }
    
    private func gizmoForCurrentMode() -> SCNNode {
        switch gizmoVM.activeMode {
        case .move:
            return GizmoNodeFactory.makeTranslationGizmo()
        case .rotate:
            return GizmoNodeFactory.makeRotationGizmo()
        case .scale:
            return GizmoNodeFactory.makeScaleGizmo()
        }
    }
    
    private func updateModelFromProperties(modelNode: SCNNode, object: SceneObject, coordinator: Coordinator) {
        let props = object.properties
        let normScale = coordinator.normalizationScale
        
        // Position
        let posX = CGFloat(props.position3DX ?? 0)
        let posY = CGFloat(props.position3DY ?? 0)
        let posZ = CGFloat(props.position3DZ ?? 0)
        modelNode.position = SCNVector3(posX, posY, posZ)
        
        // Rotation
        let rotX = CGFloat(props.rotationX ?? 0) * .pi / 180
        let rotY = CGFloat(props.rotationY ?? 0) * .pi / 180
        let rotZ = CGFloat(props.rotationZ ?? 0) * .pi / 180
        modelNode.eulerAngles = SCNVector3(rotX, rotY, rotZ)
        
        // Scale
        let sx = CGFloat(props.scaleX) * normScale
        let sy = CGFloat(props.scaleY) * normScale
        let sz = CGFloat(props.scaleZ ?? 1.0) * normScale
        modelNode.scale = SCNVector3(sx, sy, sz)
        
        // Move the gizmo to match the model position
        if let gizmoRoot = coordinator.scnView?.scene?.rootNode.childNode(withName: "gizmo_root", recursively: false) {
            gizmoRoot.position = SCNVector3(posX, posY, posZ)
        }
    }
    
    // MARK: - Coordinator
    
    @MainActor
    class Coordinator: NSObject {
        var scnView: SCNView?
        var modelNode: SCNNode?
        var normalizationScale: CGFloat = 1.0
        var gizmoVM: GizmoViewModel?
        var canvasVM: CanvasViewModel?
        
        // Camera orbit state
        var cameraDistance: CGFloat = 5.0
        var cameraYaw: CGFloat = CGFloat.pi / 6   // Horizontal angle
        var cameraPitch: CGFloat = CGFloat.pi / 8  // Vertical angle
        // cameraTarget is no longer stored here — the orbit center is always
        // derived from the model's position3D via modelOrbitCenter().
        
        // Drag state for gizmo interaction
        var isDraggingGizmo = false
        var activeHandle: GizmoHandle3D?
        var dragStartPoint: CGPoint = .zero
        var dragStartProperties: ObjectProperties?
        var dragPlaneNormal: SCNVector3 = SCNVector3(0, 1, 0)
        var dragStartWorldPoint: SCNVector3 = SCNVector3Zero
        
        /// Fingerprint of model-related properties (position, rotation, scale).
        /// Used to skip redundant updateModelFromProperties calls when only
        /// camera properties changed (zoom/orbit).
        var lastModelFingerprint: String = ""
        
        /// Compute a fingerprint for the model-related properties.
        func modelFingerprint(for props: ObjectProperties) -> String {
            let pos = "\(props.position3DX ?? 0),\(props.position3DY ?? 0),\(props.position3DZ ?? 0)"
            let rot = "\(props.rotationX ?? 0),\(props.rotationY ?? 0),\(props.rotationZ ?? 0)"
            let scl = "\(props.scaleX),\(props.scaleY),\(props.scaleZ ?? 1)"
            return "\(pos)|\(rot)|\(scl)"
        }
        
        func resetCamera(cameraNode: SCNNode) {
            updateCameraPosition(cameraNode: cameraNode)
        }
        
        /// Write current orbit camera angles back to the object properties
        /// so the 2D canvas preview matches the 3D environment view.
        func syncCameraToProperties() {
            guard let objectId = canvasVM?.selectedObjectId,
                  let vm = canvasVM,
                  let idx = vm.sceneState.objects.firstIndex(where: { $0.id == objectId }) else { return }
            
            // Convert radians back to degrees (matching the 2D renderer's convention).
            // Negate the yaw: internally we use "positive yaw = camera LEFT" for natural orbit,
            // but the 2D renderer uses "positive angle = camera RIGHT".
            vm.sceneState.objects[idx].properties.cameraAngleX = Double(cameraPitch * 180.0 / CGFloat.pi)
            vm.sceneState.objects[idx].properties.cameraAngleY = Double(-cameraYaw * 180.0 / CGFloat.pi)
            vm.sceneState.objects[idx].properties.cameraDistance = Double(cameraDistance)
            vm.gizmoPropertyChangeCounter &+= 1
        }
        
        /// Returns the model's current position3D as the orbit center.
        /// The camera always orbits around the model, so it stays centered.
        func modelOrbitCenter() -> (CGFloat, CGFloat, CGFloat) {
            guard let objectId = canvasVM?.selectedObjectId,
                  let vm = canvasVM,
                  let obj = vm.sceneState.objects.first(where: { $0.id == objectId }) else {
                return (0, 0, 0)
            }
            return (
                CGFloat(obj.properties.position3DX ?? 0),
                CGFloat(obj.properties.position3DY ?? 0),
                CGFloat(obj.properties.position3DZ ?? 0)
            )
        }
        
        nonisolated func updateCameraPosition(cameraNode: SCNNode? = nil) {
            MainActor.assumeIsolated {
                let camNode = cameraNode ?? scnView?.scene?.rootNode.childNode(withName: "editCamera", recursively: false)
                guard let cam = camNode else { return }
                
                // Orbit center = model position (so the model always stays centered)
                let (cx, cy, cz) = modelOrbitCenter()
                
                // Negate X so that increasing cameraYaw moves the camera LEFT,
                // producing a "grab-rotate" orbit feel (drag right → scene rotates right).
                // The sync/init also negate the yaw so the 2D renderer matches.
                let x = -cameraDistance * cos(cameraPitch) * sin(cameraYaw)
                let y = cameraDistance * sin(cameraPitch)
                let z = cameraDistance * cos(cameraPitch) * cos(cameraYaw)
                
                let targetSCN = SCNVector3(cx, cy, cz)
                cam.position = SCNVector3(cx + x, cy + y, cz + z)
                cam.look(at: targetSCN)
            }
        }
        
        // MARK: - Model Loading
        
        func loadModelForEditing(object: SceneObject, into scene: SCNScene) {
            var modelURL: URL?
            if let assetId = object.properties.modelAssetId {
                modelURL = AssetManagerService.shared.modelFileURL(for: assetId)
            } else if let filePath = object.properties.modelFilePath {
                modelURL = URL(fileURLWithPath: filePath)
            }
            
            guard let url = modelURL, FileManager.default.fileExists(atPath: url.path) else { return }
            
            // Capture the object for use in the closure
            let capturedObject = object
            
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                do {
                    let loadedScene = try SCNScene(url: url, options: [.checkConsistency: true])
                    
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        
                        let container = SCNNode()
                        container.name = "modelContainer"
                        
                        for child in loadedScene.rootNode.childNodes {
                            container.addChildNode(child.clone())
                        }
                        
                        // Normalize model
                        let (minBound, maxBound) = container.boundingBox
                        let sizeX = maxBound.x - minBound.x
                        let sizeY = maxBound.y - minBound.y
                        let sizeZ = maxBound.z - minBound.z
                        let maxDim = max(sizeX, max(sizeY, sizeZ))
                        
                        let centerX = (minBound.x + maxBound.x) / 2
                        let centerY = (minBound.y + maxBound.y) / 2
                        let centerZ = (minBound.z + maxBound.z) / 2
                        container.pivot = SCNMatrix4MakeTranslation(centerX, centerY, centerZ)
                        
                        if maxDim > 0 {
                            let scale = 2.0 / maxDim
                            container.scale = SCNVector3(scale, scale, scale)
                            self.normalizationScale = CGFloat(scale)
                        }
                        
                        self.modelNode = container
                        scene.rootNode.addChildNode(container)
                        
                        // Apply the object's transform immediately after loading
                        // so the model matches its appearance on the 2D canvas.
                        self.applyInitialTransform(to: container, object: capturedObject)
                        
                        // Set a sentinel fingerprint so that updateNSView does NOT
                        // overwrite the animation-inclusive transform with base-only
                        // properties until the user actually modifies the model via gizmo.
                        self.lastModelFingerprint = self.modelFingerprint(for: capturedObject.properties)
                    }
                } catch {
                    print("[Gizmo3D] Failed to load model: \(error)")
                }
            }
        }
        
        /// Apply position, rotation, and scale from the object properties
        /// right after the model loads, so it matches the 2D canvas view.
        private func applyInitialTransform(to node: SCNNode, object: SceneObject) {
            let props = object.properties
            let normScale = normalizationScale
            
            // Position (mutable so animations can offset)
            var posX = CGFloat(props.position3DX ?? 0)
            var posY = CGFloat(props.position3DY ?? 0)
            var posZ = CGFloat(props.position3DZ ?? 0)
            
            // Rotation from base properties
            var rotX = CGFloat(props.rotationX ?? 0) * .pi / 180
            var rotY = CGFloat(props.rotationY ?? 0) * .pi / 180
            var rotZ = CGFloat(props.rotationZ ?? 0) * .pi / 180
            
            // Base scale factors
            var sfx: CGFloat = 1.0
            var sfy: CGFloat = 1.0
            var sfz: CGFloat = 1.0
            
            // Also include animation rotation/position/scale at the current time
            // so the 3D view matches exactly what's shown on the 2D canvas.
            // This mirrors the evaluation logic in Model3DRendererView.updateModelTransform.
            if let vm = canvasVM {
                let currentTime = vm.currentTime
                for animation in object.animations {
                    let progress = calculateAnimProgress(animation: animation, currentTime: currentTime)
                    guard progress >= 0 else { continue }
                    let eased = EasingHelper.apply(animation.easing, to: progress)
                    let value = interpolateKF(animation.keyframes, at: eased)
                    
                    switch animation.type {
                    // Rotation animations
                    case .rotate3DX:
                        rotX += CGFloat(value) * .pi / 180
                    case .rotate3DY, .turntable, .revolveSlow:
                        rotY += CGFloat(value) * .pi / 180
                    case .rotate3DZ:
                        rotZ += CGFloat(value) * .pi / 180
                    case .wobble3D, .flip3D, .headNod:
                        rotX += CGFloat(value) * .pi / 180
                    case .cradle, .elasticSpin, .headShake:
                        rotY += CGFloat(value) * .pi / 180
                    case .swing3D:
                        rotZ += CGFloat(value) * .pi / 180
                    case .rockAndRoll:
                        let angle = CGFloat(value) * .pi / 180
                        rotX += angle
                        rotZ += angle * 0.7
                    case .tumble:
                        let baseAngle = CGFloat(value) * .pi / 180
                        rotX += baseAngle
                        rotY += baseAngle * 1.3
                        rotZ += baseAngle * 0.7
                    case .barrelRoll:
                        rotZ += CGFloat(value) * .pi / 180
                    case .corkscrew:
                        let p = CGFloat(value)
                        rotY += p * 2 * .pi * 2
                        posY += (p - 1.0) * 1.5
                    // Position animations
                    case .float3D, .levitate:
                        posY += CGFloat(value) / 100.0
                    case .orbit3D:
                        let angle = CGFloat(value) * .pi / 180
                        posX += sin(angle) * 1.0
                        posZ += cos(angle) * 1.0
                    case .springBounce3D, .slamDown3D:
                        posY += CGFloat(value) / 100.0
                    case .magnetPull:
                        posZ += CGFloat(value) / 100.0 * 2
                    case .magnetPush:
                        posZ -= CGFloat(value) / 100.0 * 2
                    // Scale animations
                    case .scaleUp3D, .scaleDown3D:
                        let f = CGFloat(value)
                        sfx *= f; sfy *= f; sfz *= f
                    case .breathe3D:
                        let f = CGFloat(value)
                        sfx *= f; sfy *= f; sfz *= f
                    case .popIn3D:
                        let f = CGFloat(value)
                        sfx *= f; sfy *= f; sfz *= f
                    // 3D Position/Scale keyframe tracks
                    case .move3DX:
                        posX += CGFloat(value)
                    case .move3DY:
                        posY += CGFloat(value)
                    case .move3DZ:
                        posZ += CGFloat(value)
                    case .scale3DZ:
                        sfz *= CGFloat(value)
                    default:
                        break
                    }
                }
            }
            
            node.position = SCNVector3(posX, posY, posZ)
            node.eulerAngles = SCNVector3(rotX, rotY, rotZ)
            
            // Scale: base property scales * normalization * animation scale factors
            let sx = CGFloat(props.scaleX) * normScale * sfx
            let sy = CGFloat(props.scaleY) * normScale * sfy
            let sz = CGFloat(props.scaleZ ?? 1.0) * normScale * sfz
            node.scale = SCNVector3(sx, sy, sz)
            
            // Move gizmo to match
            if let gizmoRoot = scnView?.scene?.rootNode.childNode(withName: "gizmo_root", recursively: false) {
                gizmoRoot.position = node.position
            }
        }
        
        // MARK: - Animation Helpers (lightweight copies for initial transform)
        
        func calculateAnimProgress(animation: AnimationDefinition, currentTime: Double) -> Double {
            let start = animation.startTime + animation.delay
            let dur = animation.duration
            guard dur > 0 else { return -1 }
            let elapsed = currentTime - start
            if elapsed < 0 { return -1 }
            
            let raw = elapsed / dur
            if animation.repeatCount > 1 {
                let totalDur = dur * Double(animation.repeatCount)
                if elapsed >= totalDur { return animation.autoReverse ? 0 : 1 }
                let cycleProgress = raw.truncatingRemainder(dividingBy: 1.0)
                let cycleIndex = Int(raw)
                if animation.autoReverse && cycleIndex % 2 == 1 {
                    return 1.0 - cycleProgress
                }
                return cycleProgress
            }
            return min(raw, 1.0)
        }
        
        func interpolateKF(_ keyframes: [Keyframe], at progress: Double) -> Double {
            guard !keyframes.isEmpty else { return 0 }
            if keyframes.count == 1 {
                if case .double(let v) = keyframes[0].value { return v }
                return 0
            }
            
            // Find surrounding keyframes
            let sorted = keyframes.sorted(by: { (a: Keyframe, b: Keyframe) in a.time < b.time })
            
            // Before first
            if progress <= sorted[0].time {
                if case .double(let v) = sorted[0].value { return v }
                return 0
            }
            // After last
            if progress >= sorted[sorted.count - 1].time {
                if case .double(let v) = sorted[sorted.count - 1].value { return v }
                return 0
            }
            
            // Find segment
            for i in 0..<(sorted.count - 1) {
                let k0 = sorted[i]
                let k1 = sorted[i + 1]
                if progress >= k0.time && progress <= k1.time {
                    let segLen = k1.time - k0.time
                    guard segLen > 0 else {
                        if case .double(let v) = k0.value { return v }
                        return 0
                    }
                    let t = (progress - k0.time) / segLen
                    if case .double(let v0) = k0.value, case .double(let v1) = k1.value {
                        return v0 + (v1 - v0) * t
                    }
                }
            }
            
            if case .double(let v) = sorted.last?.value { return v }
            return 0
        }
        
        // MARK: - Gesture Handlers
        
        @objc func handlePan(_ gesture: NSPanGestureRecognizer) {
            guard let scnView = scnView else { return }
            let location = gesture.location(in: scnView)
            let translation = gesture.translation(in: scnView)
            
            switch gesture.state {
            case .began:
                // Check if we hit a gizmo
                let hitResults = scnView.hitTest(location, options: [
                    .searchMode: SCNHitTestSearchMode.all.rawValue
                ])
                
                if let gizmoHit = hitResults.first(where: { hit in
                    GizmoNodeFactory.handle3D(from: hit.node.name) != nil
                }) {
                    let handle = GizmoNodeFactory.handle3D(from: gizmoHit.node.name)!
                    isDraggingGizmo = true
                    activeHandle = handle
                    dragStartPoint = location
                    dragStartWorldPoint = gizmoHit.worldCoordinates
                    
                    // Snapshot properties for undo
                    if let obj = canvasVM?.selectedObject {
                        dragStartProperties = obj.properties
                    }
                    
                    // Highlight the active axis
                    if let gizmoRoot = scnView.scene?.rootNode.childNode(withName: "gizmo_root", recursively: false) {
                        if let nodeName = gizmoHit.node.name {
                            GizmoNodeFactory.highlightNode(named: nodeName, in: gizmoRoot)
                        }
                    }
                }
                
            case .changed:
                if isDraggingGizmo, let handle = activeHandle {
                    handleGizmoDrag(handle: handle, translation: translation, location: location)
                } else {
                    // Camera controls:
                    //   Left drag            → Orbit (rotate around target)
                    //   Shift+drag           → Pan (move target)
                    //   Right-click drag     → Pan (handled by handleRightPan)
                    let isShiftDown = NSEvent.modifierFlags.contains(.shift)
                    
                    if isShiftDown {
                        // Pan camera target (camera-relative)
                        panCameraRelative(dx: -translation.x, dy: translation.y)
                    } else {
                        // Orbit camera ("grab and rotate" convention):
                        // Drag right → yaw increases → sin(yaw) increases → camera moves right
                        //   internally, but camera formula uses sin(yaw) which, combined with
                        //   the negated init/sync, produces the correct visual direction.
                        let sensitivity: CGFloat = 0.005
                        cameraYaw += translation.x * sensitivity
                        cameraPitch = max(-CGFloat.pi / 2.1, min(CGFloat.pi / 2.1, cameraPitch + translation.y * sensitivity))
                    }
                    updateCameraPosition()
                    syncCameraToProperties()
                    gesture.setTranslation(.zero, in: scnView)
                }
                
            case .ended, .cancelled:
                if isDraggingGizmo {
                    // Record undo
                    if let objectId = canvasVM?.selectedObjectId,
                       let oldProps = dragStartProperties,
                       let vm = canvasVM {
                        let currentProps = vm.sceneState.objects.first(where: { $0.id == objectId })?.properties
                        if let current = currentProps, current != oldProps {
                            vm.recordGizmoUndo(objectId: objectId, oldProperties: oldProps)
                        }
                    }
                    
                    // Reset highlights
                    if let gizmoRoot = scnView.scene?.rootNode.childNode(withName: "gizmo_root", recursively: false) {
                        GizmoNodeFactory.resetHighlights(in: gizmoRoot)
                    }
                    
                    isDraggingGizmo = false
                    activeHandle = nil
                    dragStartProperties = nil
                }
                
            default:
                break
            }
        }
        
        /// Camera-relative pan: moves the model's position3D so the model stays centered
        /// in the viewport while its world-space position changes.
        func panCameraRelative(dx: CGFloat, dy: CGFloat) {
            guard let objectId = canvasVM?.selectedObjectId,
                  let vm = canvasVM,
                  let idx = vm.sceneState.objects.firstIndex(where: { $0.id == objectId }) else { return }
            
            let sensitivity: CGFloat = 0.005 * cameraDistance // Scale with distance for natural feel
            
            // Camera right vector (perpendicular to look direction, in XZ plane)
            let rightX = cos(cameraYaw)
            let rightZ = sin(cameraYaw)
            
            // Camera up vector (accounts for pitch)
            let upX = -sin(cameraPitch) * sin(cameraYaw)
            let upY = cos(cameraPitch)
            let upZ = sin(cameraPitch) * cos(cameraYaw)
            
            // Move the model's position3D along camera right/up.
            // The orbit center automatically follows (modelOrbitCenter reads position3D),
            // so the model always stays centered in the viewport.
            let deltaX = Double((rightX * dx + upX * dy) * sensitivity)
            let deltaY = Double((upY * dy) * sensitivity)
            let deltaZ = Double((rightZ * dx + upZ * dy) * sensitivity)
            
            vm.sceneState.objects[idx].properties.position3DX = (vm.sceneState.objects[idx].properties.position3DX ?? 0) + deltaX
            vm.sceneState.objects[idx].properties.position3DY = (vm.sceneState.objects[idx].properties.position3DY ?? 0) + deltaY
            vm.sceneState.objects[idx].properties.position3DZ = (vm.sceneState.objects[idx].properties.position3DZ ?? 0) + deltaZ
            
            // Update SceneKit nodes to match
            if let modelNode = modelNode {
                modelNode.position = SCNVector3(
                    vm.sceneState.objects[idx].properties.position3DX ?? 0,
                    vm.sceneState.objects[idx].properties.position3DY ?? 0,
                    vm.sceneState.objects[idx].properties.position3DZ ?? 0
                )
            }
            if let gizmoRoot = scnView?.scene?.rootNode.childNode(withName: "gizmo_root", recursively: false) {
                gizmoRoot.position = modelNode?.position ?? SCNVector3Zero
            }
            
            // Update fingerprint so updateNSView doesn't fight us
            lastModelFingerprint = modelFingerprint(for: vm.sceneState.objects[idx].properties)
            
            updateCameraPosition()
            vm.gizmoPropertyChangeCounter &+= 1
        }
        
        /// Right-click or middle-click drag → pan camera (move target)
        @objc func handleRightPan(_ gesture: NSPanGestureRecognizer) {
            guard let scnView = scnView else { return }
            let translation = gesture.translation(in: scnView)
            
            if gesture.state == .changed {
                panCameraRelative(dx: -translation.x, dy: translation.y)
                gesture.setTranslation(.zero, in: scnView)
            }
        }
        
        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            // Click without drag — could be used for selection
        }
        
        // Scroll wheel is handled by GizmoSCNView.scrollWheel(with:)
        
        // MARK: - Camera-Aware Axis Projection
        
        /// Project a world-space unit axis direction onto 2D screen space,
        /// returning a normalised 2D direction vector.
        /// This lets us map screen drag → world axis regardless of camera angle.
        private func screenDirection(forWorldAxis axis: SCNVector3) -> CGPoint {
            guard let scnView = scnView else { return CGPoint(x: 1, y: 0) }
            
            let origin = modelNode?.position ?? SCNVector3Zero
            let screenOrigin = scnView.projectPoint(origin)
            let screenTip = scnView.projectPoint(SCNVector3(
                origin.x + axis.x,
                origin.y + axis.y,
                origin.z + axis.z
            ))
            
            let dx = CGFloat(screenTip.x - screenOrigin.x)
            let dy = CGFloat(screenTip.y - screenOrigin.y)
            let length = sqrt(dx * dx + dy * dy)
            guard length > 0.001 else { return .zero }
            return CGPoint(x: dx / length, y: dy / length)
        }
        
        /// Dot product of a screen drag with the projected world axis.
        /// Used for **translation** and **scale**: how much the drag moves along the axis.
        private func dotWithAxis(_ translation: CGPoint, axis: SCNVector3) -> CGFloat {
            let dir = screenDirection(forWorldAxis: axis)
            return translation.x * dir.x + translation.y * dir.y
        }
        
        /// 2D cross product of the projected axis with the screen drag.
        /// Used for **rotation**: the perpendicular component drives rotation around the axis.
        private func crossWithAxis(_ translation: CGPoint, axis: SCNVector3) -> CGFloat {
            let dir = screenDirection(forWorldAxis: axis)
            // axisDir × dragDir  (z-component of 3D cross in the screen plane)
            return dir.x * translation.y - dir.y * translation.x
        }
        
        // MARK: - Gizmo Drag Math
        
        private func handleGizmoDrag(handle: GizmoHandle3D, translation: CGPoint, location: CGPoint) {
            guard let startProps = dragStartProperties,
                  let objectId = canvasVM?.selectedObjectId,
                  let vm = canvasVM else { return }
            
            var newProps = startProps
            
            // Sensitivity scales screen pixels to scene units.
            // Adjusted by camera distance so movement feels consistent at any zoom.
            let distanceFactor = cameraDistance / 5.0
            let moveSensitivity = 0.01 * distanceFactor
            let rotateSensitivity: CGFloat = 0.5
            let scaleSensitivity: CGFloat = 0.005
            
            // World axis unit vectors
            let worldX = SCNVector3(1, 0, 0)
            let worldY = SCNVector3(0, 1, 0)
            let worldZ = SCNVector3(0, 0, 1)
            
            switch handle {
            // ── Center handle — behavior depends on active gizmo mode ──
            case .center:
                let activeMode = gizmoVM?.activeMode ?? .move
                if activeMode == .scale {
                    // Uniform scale: drag right/up = bigger, drag left/down = smaller
                    let delta = Double((translation.x + translation.y) * scaleSensitivity * 0.5)
                    newProps.scaleX = max(0.01, startProps.scaleX + delta)
                    newProps.scaleY = max(0.01, startProps.scaleY + delta)
                    newProps.scaleZ = max(0.01, (startProps.scaleZ ?? 1.0) + delta)
                } else {
                    // Free move — decompose screen drag into all three world axes
                    let dx = Double(dotWithAxis(translation, axis: worldX) * moveSensitivity)
                    let dy = Double(dotWithAxis(translation, axis: worldY) * moveSensitivity)
                    let dz = Double(dotWithAxis(translation, axis: worldZ) * moveSensitivity)
                    newProps.position3DX = (startProps.position3DX ?? 0) + dx
                    newProps.position3DY = (startProps.position3DY ?? 0) + dy
                    newProps.position3DZ = (startProps.position3DZ ?? 0) + dz
                }
                
            // ── Translation (camera-aware) ──
            case .axisX:
                let delta = Double(dotWithAxis(translation, axis: worldX) * moveSensitivity)
                newProps.position3DX = (startProps.position3DX ?? 0) + delta
                
            case .axisY:
                let delta = Double(dotWithAxis(translation, axis: worldY) * moveSensitivity)
                newProps.position3DY = (startProps.position3DY ?? 0) + delta
                
            case .axisZ:
                let delta = Double(dotWithAxis(translation, axis: worldZ) * moveSensitivity)
                newProps.position3DZ = (startProps.position3DZ ?? 0) + delta
                
            case .planeXY:
                let dx = Double(dotWithAxis(translation, axis: worldX) * moveSensitivity)
                let dy = Double(dotWithAxis(translation, axis: worldY) * moveSensitivity)
                newProps.position3DX = (startProps.position3DX ?? 0) + dx
                newProps.position3DY = (startProps.position3DY ?? 0) + dy
                
            case .planeXZ:
                let dx = Double(dotWithAxis(translation, axis: worldX) * moveSensitivity)
                let dz = Double(dotWithAxis(translation, axis: worldZ) * moveSensitivity)
                newProps.position3DX = (startProps.position3DX ?? 0) + dx
                newProps.position3DZ = (startProps.position3DZ ?? 0) + dz
                
            case .planeYZ:
                let dy = Double(dotWithAxis(translation, axis: worldY) * moveSensitivity)
                let dz = Double(dotWithAxis(translation, axis: worldZ) * moveSensitivity)
                newProps.position3DY = (startProps.position3DY ?? 0) + dy
                newProps.position3DZ = (startProps.position3DZ ?? 0) + dz
                
            // ── Rotation (camera-aware) ──
            // The perpendicular component of the drag relative to the projected axis
            // drives rotation, so it works naturally from any camera angle.
            case .ringX:
                let delta = Double(crossWithAxis(translation, axis: worldX) * rotateSensitivity)
                newProps.rotationX = (startProps.rotationX ?? 0) + delta
                
            case .ringY:
                let delta = Double(crossWithAxis(translation, axis: worldY) * rotateSensitivity)
                newProps.rotationY = (startProps.rotationY ?? 0) + delta
                
            case .ringZ:
                let delta = Double(crossWithAxis(translation, axis: worldZ) * rotateSensitivity)
                newProps.rotationZ = (startProps.rotationZ ?? 0) + delta
                
            case .trackball:
                let deltaY = Double(crossWithAxis(translation, axis: worldX) * rotateSensitivity * 0.5)
                let deltaX = Double(crossWithAxis(translation, axis: worldY) * rotateSensitivity * 0.5)
                newProps.rotationY = (startProps.rotationY ?? 0) + deltaX
                newProps.rotationX = (startProps.rotationX ?? 0) + deltaY
                
            // ── Scale (camera-aware) ──
            case .scaleX:
                let delta = Double(dotWithAxis(translation, axis: worldX) * scaleSensitivity)
                newProps.scaleX = max(0.01, startProps.scaleX + delta)
                
            case .scaleY:
                let delta = Double(dotWithAxis(translation, axis: worldY) * scaleSensitivity)
                newProps.scaleY = max(0.01, startProps.scaleY + delta)
                
            case .scaleZ:
                let delta = Double(dotWithAxis(translation, axis: worldZ) * scaleSensitivity)
                newProps.scaleZ = max(0.01, (startProps.scaleZ ?? 1.0) + delta)
            }
            
            vm.applyGizmoProperties(objectId, properties: newProps)
        }
    }
}

// MARK: - Custom SCNView with scroll wheel support

class GizmoSCNView: SCNView {
    weak var coordinatorRef: Gizmo3DSceneView.Coordinator?
    
    @MainActor
    convenience init(coordinator: Gizmo3DSceneView.Coordinator) {
        self.init(frame: .zero)
        self.coordinatorRef = coordinator
    }
    
    override func scrollWheel(with event: NSEvent) {
        let deltaX = event.scrollingDeltaX
        let deltaY = event.scrollingDeltaY
        let isShiftDown = event.modifierFlags.contains(.shift)
        
        Task { @MainActor in
            guard let coordinator = self.coordinatorRef else { return }
            
            if isShiftDown || abs(deltaX) > abs(deltaY) * 0.5 {
                // Shift+scroll or significant horizontal scroll → pan camera
                coordinator.panCameraRelative(dx: deltaX, dy: -deltaY)
            } else {
                // Normal vertical scroll → zoom
                let sensitivity: CGFloat = 0.1
                coordinator.cameraDistance = max(1.0, min(20.0, coordinator.cameraDistance - deltaY * sensitivity))
                coordinator.updateCameraPosition()
                coordinator.syncCameraToProperties()
            }
        }
    }
}
