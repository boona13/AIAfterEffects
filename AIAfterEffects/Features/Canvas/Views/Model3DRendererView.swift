//
//  Model3DRendererView.swift
//  AIAfterEffects
//
//  Renders a 3D model using RealityKit within the 2D canvas
//

import SwiftUI
import RealityKit
import Combine

// MARK: - 3D Model Renderer View

struct Model3DRendererView: View {
    let sceneObject: SceneObject
    let currentTime: Double
    /// Timing offset from dependency resolver
    var timingOffset: Double = 0
    
    @State private var modelEntity: ModelEntity?
    @State private var loadError: String?
    @State private var isLoading = true
    
    private var modelURL: URL? {
        // Try asset manager first
        if let assetId = sceneObject.properties.modelAssetId {
            return AssetManagerService.shared.modelFileURL(for: assetId)
        }
        // Fall back to direct file path
        if let filePath = sceneObject.properties.modelFilePath {
            return URL(fileURLWithPath: filePath)
        }
        return nil
    }
    
    var body: some View {
        ZStack {
            if isLoading {
                loadingView
            } else if let error = loadError {
                errorView(error)
            } else {
                realityView
            }
        }
        // Size is driven by the object's width/height which matches the canvas aspect ratio
        .frame(
            width: sceneObject.properties.width,
            height: sceneObject.properties.height
        )
        .clipped()
        .onAppear { loadModel() }
    }
    
    // MARK: - RealityKit View
    
    private var realityView: some View {
        Model3DRealityView(
            modelURL: modelURL,
            sceneObject: sceneObject,
            currentTime: currentTime,
            timingOffset: timingOffset
        )
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.6)
            Text("Loading 3D model...")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Error View
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 24))
                .foregroundColor(.red.opacity(0.6))
            Text("3D Model")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
            Text(error)
                .font(.system(size: 9))
                .foregroundColor(.red.opacity(0.5))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Model Loading
    
    private func loadModel() {
        guard let url = modelURL else {
            loadError = "No model file specified"
            isLoading = false
            return
        }
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            loadError = "Model file not found"
            isLoading = false
            return
        }
        
        isLoading = false
    }
}

// MARK: - RealityKit View Wrapper

struct Model3DRealityView: View {
    let modelURL: URL?
    let sceneObject: SceneObject
    let currentTime: Double
    var timingOffset: Double = 0
    
    var body: some View {
        // Use SceneKit-based 3D rendering for macOS compatibility
        // RealityView requires visionOS/iOS 18+ on macOS
        SceneKit3DView(
            modelURL: modelURL,
            sceneObject: sceneObject,
            currentTime: currentTime,
            timingOffset: timingOffset
        )
    }
}

// MARK: - SceneKit 3D View (macOS compatible)

import SceneKit

struct SceneKit3DView: NSViewRepresentable {
    let modelURL: URL?
    let sceneObject: SceneObject
    let currentTime: Double
    var timingOffset: Double = 0
    
    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .clear
        scnView.autoenablesDefaultLighting = true
        scnView.allowsCameraControl = false // AI controls camera
        scnView.antialiasingMode = .multisampling4X
        
        let scene = SCNScene()
        // Transparent background so the 3D model blends with the 2D canvas
        scene.background.contents = NSColor.clear
        scnView.scene = scene
        
        // Add camera - default to a safe distance that shows the whole model
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.automaticallyAdjustsZRange = true
        cameraNode.camera?.fieldOfView = 45
        let camDist = sceneObject.properties.cameraDistance ?? 5.0
        cameraNode.position = SCNVector3(0, 0, CGFloat(camDist))
        cameraNode.name = "mainCamera"
        scene.rootNode.addChildNode(cameraNode)
        
        // Add ambient light
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 800
        ambientLight.light?.color = NSColor.white
        scene.rootNode.addChildNode(ambientLight)
        
        // Add directional light
        let directionalLight = SCNNode()
        directionalLight.light = SCNLight()
        directionalLight.light?.type = .directional
        directionalLight.light?.intensity = 1000
        directionalLight.light?.castsShadow = true
        directionalLight.eulerAngles = SCNVector3(-CGFloat.pi / 4, CGFloat.pi / 4, 0)
        scene.rootNode.addChildNode(directionalLight)
        
        // Add fill light from the other side
        let fillLight = SCNNode()
        fillLight.light = SCNLight()
        fillLight.light?.type = .directional
        fillLight.light?.intensity = 400
        fillLight.eulerAngles = SCNVector3(-CGFloat.pi / 6, -CGFloat.pi / 3, 0)
        scene.rootNode.addChildNode(fillLight)
        
        // Load model
        if let url = modelURL {
            context.coordinator.loadModel(url: url, into: scene, cameraDistance: camDist)
        }
        
        context.coordinator.scnView = scnView
        
        return scnView
    }
    
    func updateNSView(_ scnView: SCNView, context: Context) {
        guard let scene = scnView.scene else { return }
        
        // Disable SceneKit's implicit animations so transforms snap instantly.
        // Without this, SceneKit smoothly interpolates property changes over ~0.25s,
        // which causes the model to "drift" instead of snapping back to its start
        // position when the timeline loops from end → 0.
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        SCNTransaction.disableActions = true
        
        // Update model transform based on animations at currentTime
        if let modelNode = context.coordinator.modelNode {
            let normScale = context.coordinator.normalizationScale
            updateModelTransform(modelNode: modelNode, scene: scene, normalizationScale: normScale)
        }
        
        // Update camera
        if let cameraNode = scene.rootNode.childNode(withName: "mainCamera", recursively: false) {
            updateCamera(cameraNode: cameraNode)
        }
        
        SCNTransaction.commit()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    // MARK: - Transform Updates
    
    private func updateModelTransform(modelNode: SCNNode, scene: SCNScene, normalizationScale: CGFloat) {
        let props = sceneObject.properties
        
        // Base rotation from properties
        let rotX = CGFloat(props.rotationX ?? 0) * .pi / 180
        let rotY = CGFloat(props.rotationY ?? 0) * .pi / 180
        let rotZ = CGFloat(props.rotationZ ?? 0) * .pi / 180
        
        // Start from the base 3D position set by gizmo (default origin).
        // Animations will offset from this below.
        var posX: CGFloat = CGFloat(props.position3DX ?? 0)
        var posY: CGFloat = CGFloat(props.position3DY ?? 0)
        var posZ: CGFloat = CGFloat(props.position3DZ ?? 0)
        
        // Apply 3D animations
        var animRotX: CGFloat = 0
        var animRotY: CGFloat = 0
        var animRotZ: CGFloat = 0
        
        // Accumulated scale factors — animations multiply into these so they compose additively.
        // This replaces the old approach where each scale animation directly set modelNode.scale
        // (which got overwritten by the base scale at the end of this method).
        var scaleFactorX: CGFloat = 1.0
        var scaleFactorY: CGFloat = 1.0
        var scaleFactorZ: CGFloat = 1.0
        
        // Material tint color (driven by object fill color + optional color keyframes).
        var materialTint = props.fillColor
        
        // Find the earliest entrance animation to determine pre-animation state.
        // Scale entrances (scaleUp3D, popIn3D, tornado) start at scale 0, so the model must
        // be invisible (scale 0) before they begin. Position-based entrances (slamDown3D,
        // springBounce3D, etc.) need the model placed at their initial off-screen position,
        // but we also set scale to 0 before any entrance to prevent the model from briefly
        // flashing at origin before jumping to its entrance position.
        //
        // Only the FIRST entrance should hide the model — later entrances must not re-hide.
        let scaleEntranceTypes: Set<AnimationType> = [.scaleUp3D, .popIn3D, .tornado]
        let allEntranceTypes: Set<AnimationType> = [
            .scaleUp3D, .popIn3D, .tornado,
            .slamDown3D, .springBounce3D, .dropAndSettle, .corkscrew, .zigzagDrop, .unwrap
        ]
        
        let earliestEntrance = sceneObject.animations
            .filter { allEntranceTypes.contains($0.type) }
            .min(by: { ($0.startTime + $0.delay) < ($1.startTime + $1.delay) })
        
        // Pre-entrance visibility: if the earliest entrance hasn't started, hide the model.
        // For scale entrances (scaleUp3D etc.), scale=0 is the correct pre-state since the
        // animation itself grows from 0. For position entrances (slamDown3D etc.), we also
        // use scale=0 to prevent flashing at origin. Once the entrance starts, the animation
        // keyframes take over and position/scale the model correctly.
        if let earliest = earliestEntrance {
            let entranceStart = earliest.startTime + earliest.delay
            if currentTime < entranceStart {
                // Safety: only hide if the entrance is within the first 3 seconds.
                // If the LLM set a very late entrance (>3s), let the model appear at its
                // base state rather than being invisible for half the scene.
                if entranceStart <= 3.0 {
                    scaleFactorX = 0; scaleFactorY = 0; scaleFactorZ = 0
                }
            }
        }
        
        for animation in sceneObject.animations {
            let linearProgress = calculateAnimationProgress(animation: animation, currentTime: currentTime)
            
            // Animation hasn't started yet — skip it
            if linearProgress < 0 {
                continue
            }
            
            let easedProgress = EasingHelper.apply(animation.easing, to: linearProgress)
            let normalizedKeyframes = normalizedAdditive3DKeyframesIfNeeded(animation.keyframes, for: animation.type)
            let value = interpolateKeyframes(normalizedKeyframes, at: easedProgress)
            
            switch animation.type {
            case .colorChange, .fillColorChange:
                materialTint = interpolateColorKeyframes(animation.keyframes, at: easedProgress, fallback: materialTint)
            case .strokeColorChange:
                materialTint = interpolateColorKeyframes(animation.keyframes, at: easedProgress, fallback: materialTint)
            case .rotate3DX:
                animRotX += CGFloat(value) * .pi / 180
            case .rotate3DY, .turntable, .revolveSlow:
                animRotY += CGFloat(value) * .pi / 180
            case .rotate3DZ:
                animRotZ += CGFloat(value) * .pi / 180
            case .wobble3D:
                animRotX += CGFloat(value) * .pi / 180
            case .flip3D:
                animRotX += CGFloat(value) * .pi / 180
            case .float3D:
                posY += CGFloat(value) / 100.0 // Scale down for 3D space
            case .orbit3D:
                // Symmetric orbit centered at origin — model moves in a circle of radius 1.0
                // The model is always at distance `radius` from the center
                let angle = CGFloat(value) * .pi / 180
                let radius: CGFloat = 1.0
                posX += sin(angle) * radius
                posZ += cos(angle) * radius
            case .cradle:
                // Pendulum on Y axis (damped swing)
                animRotY += CGFloat(value) * .pi / 180
            case .springBounce3D:
                // Y-axis position bounce (drop from above)
                posY += CGFloat(value) / 100.0
            case .elasticSpin:
                // Spin with elastic overshoot on Y axis
                animRotY += CGFloat(value) * .pi / 180
            case .swing3D:
                // Pendulum on Z axis
                animRotZ += CGFloat(value) * .pi / 180
            case .breathe3D:
                // Scale pulse: value is the multiplier, applied uniformly
                let breatheFactor = CGFloat(value)
                scaleFactorX *= breatheFactor
                scaleFactorY *= breatheFactor
                scaleFactorZ *= breatheFactor
            case .headNod:
                // Nod on X axis
                animRotX += CGFloat(value) * .pi / 180
            case .headShake:
                // Shake on Y axis
                animRotY += CGFloat(value) * .pi / 180
            case .rockAndRoll:
                // Combined X + Z rocking (value drives X, phase-shifted value drives Z)
                let angle = CGFloat(value) * .pi / 180
                animRotX += angle
                // Z gets the same motion but offset by 90° phase — using cos when X uses sin
                animRotZ += angle * 0.7 // Slightly less Z to feel natural
            case .scaleUp3D, .scaleDown3D:
                // Scale animation — value is the scale multiplier
                let scaleFactor = CGFloat(value)
                scaleFactorX *= scaleFactor
                scaleFactorY *= scaleFactor
                scaleFactorZ *= scaleFactor
            case .slamDown3D:
                posY += CGFloat(value) / 100.0
                if abs(value) < 15 && easedProgress > 0.2 && easedProgress < 0.5 {
                    let squashAmount = 1.0 - (1.0 - abs(CGFloat(value)) / 15.0) * 0.25
                    let stretchAmount = 1.0 + (1.0 - abs(CGFloat(value)) / 15.0) * 0.15
                    scaleFactorX *= stretchAmount
                    scaleFactorY *= squashAmount
                    scaleFactorZ *= stretchAmount
                }
            case .tumble:
                // Chaotic multi-axis tumble: X at 1x, Y at 1.3x, Z at 0.7x
                let baseAngle = CGFloat(value) * .pi / 180
                animRotX += baseAngle
                animRotY += baseAngle * 1.3
                animRotZ += baseAngle * 0.7
            case .barrelRoll:
                animRotZ += CGFloat(value) * .pi / 180
            case .corkscrew:
                // Helical rise: spin Y + rise from below to origin
                let progress = CGFloat(value)
                animRotY += progress * 2 * .pi * 2  // 2 full spins
                posY += (progress - 1.0) * 1.5      // starts at -1.5 (below), arrives at 0 (origin)
            case .figureEight:
                // Lissajous figure-8: x = sin(t), z = sin(2t)/2
                let t = CGFloat(value) * 2 * .pi
                posX += sin(t) * 1.2
                posZ += sin(t * 2) * 0.6
                animRotY += CGFloat(value) * .pi * 2 // face direction of motion
            case .boomerang3D:
                // Arc away and back on X-Z plane
                let t = CGFloat(value)
                posX += sin(t * .pi) * 3.0   // arc X
                posZ += -t * 2.0 + t * t * 2.0  // parabolic Z (out and back)
                animRotY += t * .pi          // partial spin during flight
            case .levitate:
                posY += CGFloat(value) / 100.0
            case .magnetPull:
                posZ += CGFloat(value) / 100.0 * 2
            case .magnetPush:
                posZ -= CGFloat(value) / 100.0 * 2
            case .zigzagDrop:
                // Zigzag descent from above to origin (entrance animation)
                let t = CGFloat(value)
                posX += sin(t * 6 * .pi) * 0.8 * (1.0 - t) // decreasing zigzag
                posY += (1.0 - t) * 2.0                      // starts at +2.0 (above), settles to 0 (origin)
                animRotZ += sin(t * 6 * .pi) * 0.15         // subtle tilt with zigzag
            case .rubberBand:
                // X-axis scale stretch/snap
                let factor = CGFloat(value)
                scaleFactorX *= factor
                scaleFactorY *= (2.0 - factor) // inverse on Y
            case .jelly3D:
                // Alternating squash-stretch on X/Y axes
                let phase = CGFloat(value)
                scaleFactorX *= (1.0 + phase * 0.2)  // when phase positive: stretch X
                scaleFactorY *= (1.0 - phase * 0.2)  // when phase positive: squash Y
            case .anticipateSpin:
                animRotY += CGFloat(value) * .pi / 180
            case .popIn3D:
                // Scale with a burst of Y rotation
                let scaleFactor = CGFloat(value)
                scaleFactorX *= scaleFactor
                scaleFactorY *= scaleFactor
                scaleFactorZ *= scaleFactor
                animRotY += CGFloat(easedProgress) * .pi * 0.5  // 90° rotation during pop
            case .glitchJitter3D:
                // Random-like position + rotation jitter from pre-baked keyframes
                let jitterPos = CGFloat(value) / 100.0
                posX += jitterPos
                posY += jitterPos * 0.7
                animRotZ += CGFloat(value) * .pi / 180 * 0.5
            case .heartbeat3D:
                let factor = CGFloat(value)
                scaleFactorX *= factor
                scaleFactorY *= factor
                scaleFactorZ *= factor
            case .tornado:
                // Vortex entrance: spin + rise from below to origin + scale from invisible to full
                let t = CGFloat(value)
                animRotY += t * .pi * 8        // 4 full spins
                posY += (t - 1.0) * 2.0        // starts at -2.0 (below), arrives at 0 (origin)
                let tornadoScale = t            // grow from 0% (invisible) to 100% — seamless with pre-anim state
                scaleFactorX *= tornadoScale
                scaleFactorY *= tornadoScale
                scaleFactorZ *= tornadoScale
            case .unwrap:
                animRotX += CGFloat(value) * .pi / 180
            case .dropAndSettle:
                posY += CGFloat(value) / 100.0
            case .materialFade:
                break // Handled at SwiftUI level via ObjectRendererView opacity
            // 3D Position/Scale keyframe tracks
            case .move3DX:
                posX += CGFloat(value)
            case .move3DY:
                posY += CGFloat(value)
            case .move3DZ:
                posZ += CGFloat(value)
            case .scale3DZ:
                scaleFactorZ *= CGFloat(value)
            default:
                break
            }
        }
        
        // Apply computed position — always written, so it resets when no animations are active
        modelNode.position = SCNVector3(posX, posY, posZ)
        modelNode.eulerAngles = SCNVector3(rotX + animRotX, rotY + animRotY, rotZ + animRotZ)
        
        // Scale: base scale (user scale * normalization) MULTIPLIED by accumulated animation scale factors.
        // This ensures scale animations compose additively — e.g. scaleUp3D (0→1) followed by
        // breathe3D (pulsing 0.9→1.1) correctly stacks: base * scaleUp * breathe.
        // When no scale animations are active, factors are 1.0 so base scale is used.
        let sx = CGFloat(props.scaleX) * normalizationScale * scaleFactorX
        let sy = CGFloat(props.scaleY) * normalizationScale * scaleFactorY
        let sz = CGFloat(props.scaleZ ?? 1.0) * normalizationScale * scaleFactorZ
        modelNode.scale = SCNVector3(sx, sy, sz)
        
        // Apply color/tint after transform updates so 3D color keyframes are visible.
        applyTintColor(materialTint, to: modelNode)
    }
    
    private func updateCamera(cameraNode: SCNNode) {
        let props = sceneObject.properties
        var camDist = CGFloat(props.cameraDistance ?? 5.0)
        var camAngleX = CGFloat(props.cameraAngleX ?? 15)
        var camAngleY = CGFloat(props.cameraAngleY ?? 0)
        // Orbit center = model's position3D (model always stays centered)
        let orbitCenterX = CGFloat(props.position3DX ?? 0)
        let orbitCenterY = CGFloat(props.position3DY ?? 0)
        let orbitCenterZ = CGFloat(props.position3DZ ?? 0)
        var useOrbitPosition = false
        var orbitAngle: CGFloat = 0
        var lateralOffset: CGFloat = 0
        
        // Reset camera FOV to default every frame.
        // Animations like dollyZoom modify FOV — without this reset, the FOV persists
        // after the animation ends and isn't restored when the timeline loops back to 0.
        cameraNode.camera?.fieldOfView = 45
        
        // Spiral zoom state
        var useSpiralZoom = false
        var spiralProgress: CGFloat = 0
        let spiralStartDist: CGFloat = camDist * 2   // start 2x farther
        let spiralEndDist: CGFloat = camDist
        let spiralRevolutions: CGFloat = 2.5         // 2.5 full loops
        
        // Dolly zoom state
        var useDollyZoom = false
        var dollyProgress: CGFloat = 0
        var dutchRoll: CGFloat = 0
        
        // Apply camera animations
        for animation in sceneObject.animations {
            let linearProgress = calculateAnimationProgress(animation: animation, currentTime: currentTime)
            guard linearProgress >= 0 else { continue }
            
            let easedProgress = EasingHelper.apply(animation.easing, to: linearProgress)
            let normalizedKeyframes = normalizedAdditive3DKeyframesIfNeeded(animation.keyframes, for: animation.type)
            let value = interpolateKeyframes(normalizedKeyframes, at: easedProgress)
            
            switch animation.type {
            case .cameraZoom:
                camDist = CGFloat(value)
            case .cameraPan:
                camAngleY += CGFloat(value)
            case .cameraOrbit:
                orbitAngle = CGFloat(value) * .pi / 180
                useOrbitPosition = true
            case .spiralZoom:
                useSpiralZoom = true
                spiralProgress = CGFloat(value)
            case .dollyZoom:
                useDollyZoom = true
                dollyProgress = CGFloat(value)
            case .cameraRise:
                camAngleX = CGFloat(value) // Elevation angle in degrees
            case .cameraDive:
                camAngleX = CGFloat(value) // Elevation angle in degrees
            case .cameraWhipPan:
                camAngleY += CGFloat(value) // Whip pan on Y angle
            case .cameraSlide:
                lateralOffset = CGFloat(value) // Lateral offset in scene units
            case .cameraArc:
                // Semicircle arc — treated like a partial orbit
                orbitAngle = CGFloat(value) * .pi / 180
                useOrbitPosition = true
            case .cameraPedestal:
                camAngleX = CGFloat(value)  // Elevation angle
            case .cameraTruck:
                lateralOffset = CGFloat(value) // Same as slide but typically wider
            case .cameraPushPull:
                camDist = CGFloat(value) // Distance keyframes encode the push-pull
            case .cameraDutchTilt:
                dutchRoll = CGFloat(value) * .pi / 180
            case .cameraHelicopter:
                // Descending spiral from overhead
                let t = CGFloat(value)
                let startHeight: CGFloat = 70   // degrees — nearly overhead
                let endHeight: CGFloat = 20     // degrees — near eye level
                let angle = t * 2 * .pi * 1.5   // 1.5 orbits during descent
                camAngleX = startHeight + (endHeight - startHeight) * t
                orbitAngle = angle
                useOrbitPosition = true
            case .cameraRocket:
                camAngleX = CGFloat(value) // Fast rising elevation
            case .cameraShake:
                // Apply shake offset to both X and Y camera angles
                let shakeVal = CGFloat(value)
                camAngleX += shakeVal
                camAngleY += shakeVal * 0.7 // slightly less on Y for realism
            default:
                break
            }
        }
        
        if useSpiralZoom {
            // Camera spirals inward: interpolate distance and compute orbit angle
            let dist = spiralStartDist + (spiralEndDist - spiralStartDist) * spiralProgress
            let angle = spiralProgress * spiralRevolutions * 2 * .pi
            let radX = camAngleX * .pi / 180
            let heightY = sin(radX) * dist
            cameraNode.position = SCNVector3(
                sin(angle) * cos(radX) * dist,
                heightY,
                cos(angle) * cos(radX) * dist
            )
        } else if useDollyZoom {
            // Hitchcock vertigo: camera moves in while FOV changes
            let startDist = camDist * 2.0
            let endDist = camDist * 0.7
            let dist = startDist + (endDist - startDist) * dollyProgress
            
            // Adjust FOV to keep apparent size roughly constant (vertigo feel)
            // Reference apparent size = atan(1/startDist), we want atan(1/dist) to shift
            let startFOV: CGFloat = 40
            let endFOV: CGFloat = 90
            let fov = startFOV + (endFOV - startFOV) * dollyProgress
            
            if let camera = cameraNode.camera {
                camera.fieldOfView = fov
            }
            
            let radX = camAngleX * .pi / 180
            let radY = camAngleY * .pi / 180
            cameraNode.position = SCNVector3(
                orbitCenterX + sin(radY) * cos(radX) * dist,
                orbitCenterY + sin(radX) * dist,
                orbitCenterZ + cos(radY) * cos(radX) * dist
            )
        } else if useOrbitPosition {
            // Camera orbits around model at fixed height
            let heightY = sin(camAngleX * .pi / 180) * camDist
            cameraNode.position = SCNVector3(
                orbitCenterX + sin(orbitAngle) * camDist,
                orbitCenterY + heightY,
                orbitCenterZ + cos(orbitAngle) * camDist
            )
        } else {
            let radX = camAngleX * .pi / 180
            let radY = camAngleY * .pi / 180
            
            cameraNode.position = SCNVector3(
                orbitCenterX + sin(radY) * cos(radX) * camDist + lateralOffset,
                orbitCenterY + sin(radX) * camDist,
                orbitCenterZ + cos(radY) * cos(radX) * camDist
            )
        }
        cameraNode.look(at: SCNVector3(orbitCenterX, orbitCenterY, orbitCenterZ))
        
        // Apply dutch tilt roll AFTER look(at:) so it adds to the computed orientation
        if dutchRoll != 0 {
            var angles = cameraNode.eulerAngles
            angles.z += CGFloat(dutchRoll)
            cameraNode.eulerAngles = angles
        }
    }
    
    // MARK: - Animation Helpers
    
    /// Animations that are continuous rotations/cycles — should wrap, NOT ping-pong.
    private static let continuousAnimationTypes: Set<AnimationType> = [
        .turntable, .spin, .rotate, .rotate3DX, .rotate3DY, .rotate3DZ,
        .cameraOrbit, .orbit3D, .hueRotate, .tumble, .figureEight
    ]
    
    private func calculateAnimationProgress(animation: AnimationDefinition, currentTime: Double) -> Double {
        let startTime = animation.startTime + animation.delay + timingOffset
        let endTime = startTime + animation.duration
        
        guard currentTime >= startTime else { return -1 }
        
        let isContinuous = Self.continuousAnimationTypes.contains(animation.type)
        let shouldPingPong = !isContinuous && !animation.autoReverse
        
        if animation.repeatCount == -1 {
            let elapsed = currentTime - startTime
            if shouldPingPong {
                // Smooth ping-pong: forward then backward, no snap
                let phase = elapsed.truncatingRemainder(dividingBy: animation.duration * 2)
                if phase <= animation.duration {
                    return min(phase / animation.duration, 1.0)
                } else {
                    return 1.0 - min((phase - animation.duration) / animation.duration, 1.0)
                }
            } else if animation.autoReverse {
                let cycleTime = animation.duration * 2
                let phase = elapsed.truncatingRemainder(dividingBy: cycleTime)
                if phase > animation.duration {
                    return 1.0 - ((phase - animation.duration) / animation.duration)
                }
                return min(phase / animation.duration, 1.0)
            } else {
                // Continuous wrap (turntable, spin, etc.)
                let phase = elapsed.truncatingRemainder(dividingBy: animation.duration)
                return min(phase / animation.duration, 1.0)
            }
        }
        
        if currentTime > endTime {
            if animation.repeatCount > 0 {
                let totalDuration = animation.duration * Double(animation.repeatCount + 1)
                let totalEnd = startTime + totalDuration
                if currentTime > totalEnd { return 1.0 }
                let elapsed = currentTime - startTime
                let cycleIndex = Int(elapsed / animation.duration)
                let phase = elapsed.truncatingRemainder(dividingBy: animation.duration)
                let forwardProgress = min(phase / animation.duration, 1.0)
                if shouldPingPong && cycleIndex % 2 == 1 {
                    return 1.0 - forwardProgress
                }
                return forwardProgress
            }
            return 1.0
        }
        
        return (currentTime - startTime) / animation.duration
    }
    
    private func interpolateKeyframes(_ keyframes: [Keyframe], at progress: Double) -> Double {
        guard !keyframes.isEmpty else { return 0 }
        let sortedKeyframes = keyframes.sorted(by: { $0.time < $1.time })
        guard sortedKeyframes.count > 1 else {
            return sortedKeyframes[0].value.doubleVal
        }
        
        // Find surrounding keyframes
        var prevKeyframe = sortedKeyframes[0]
        var nextKeyframe = sortedKeyframes[sortedKeyframes.count - 1]
        
        for i in 0..<sortedKeyframes.count - 1 {
            if progress >= sortedKeyframes[i].time && progress <= sortedKeyframes[i + 1].time {
                prevKeyframe = sortedKeyframes[i]
                nextKeyframe = sortedKeyframes[i + 1]
                break
            }
        }
        
        if progress <= prevKeyframe.time { return prevKeyframe.value.doubleVal }
        if progress >= nextKeyframe.time { return nextKeyframe.value.doubleVal }
        
        let t = (progress - prevKeyframe.time) / (nextKeyframe.time - prevKeyframe.time)
        return prevKeyframe.value.doubleVal + (nextKeyframe.value.doubleVal - prevKeyframe.value.doubleVal) * t
    }
    
    private func normalizedAdditive3DKeyframesIfNeeded(_ keyframes: [Keyframe], for type: AnimationType) -> [Keyframe] {
        guard additive3DDeltaAnimationTypes.contains(type),
              let firstKeyframe = keyframes.first,
              case .double(let firstValue) = firstKeyframe.value,
              abs(firstValue) > 0.0001 else {
            return keyframes
        }
        
        return keyframes.map { keyframe in
            guard case .double(let value) = keyframe.value else { return keyframe }
            return Keyframe(time: keyframe.time, value: .double(value - firstValue))
        }
    }
    
    private var additive3DDeltaAnimationTypes: Set<AnimationType> {
        [
            .rotate3DX, .rotate3DY, .rotate3DZ,
            .turntable, .revolveSlow, .wobble3D, .flip3D, .orbit3D,
            .float3D, .cradle, .springBounce3D, .elasticSpin, .swing3D,
            .headNod, .headShake, .rockAndRoll, .slamDown3D, .tumble,
            .barrelRoll, .boomerang3D, .levitate, .magnetPull, .magnetPush,
            .zigzagDrop, .anticipateSpin, .glitchJitter3D,
            .cameraPan, .cameraWhipPan, .cameraShake,
            .move3DX, .move3DY, .move3DZ
        ]
    }
    
    private func interpolateColorKeyframes(_ keyframes: [Keyframe], at progress: Double, fallback: CodableColor) -> CodableColor {
        let sorted = keyframes.sorted(by: { $0.time < $1.time })
        guard !sorted.isEmpty else { return fallback }
        
        if sorted.count == 1 {
            if case .color(let c) = sorted[0].value { return c }
            return fallback
        }
        
        var prev = sorted[0]
        var next = sorted[sorted.count - 1]
        
        for i in 0..<sorted.count - 1 {
            if progress >= sorted[i].time && progress <= sorted[i + 1].time {
                prev = sorted[i]
                next = sorted[i + 1]
                break
            }
        }
        
        guard case .color(let prevColor) = prev.value,
              case .color(let nextColor) = next.value else {
            return fallback
        }
        
        if progress <= prev.time { return prevColor }
        if progress >= next.time { return nextColor }
        
        let span = max(next.time - prev.time, 0.0001)
        let t = (progress - prev.time) / span
        
        return CodableColor(
            red: prevColor.red + (nextColor.red - prevColor.red) * t,
            green: prevColor.green + (nextColor.green - prevColor.green) * t,
            blue: prevColor.blue + (nextColor.blue - prevColor.blue) * t,
            alpha: prevColor.alpha + (nextColor.alpha - prevColor.alpha) * t
        )
    }
    
    private func applyTintColor(_ color: CodableColor, to node: SCNNode) {
        let nsColor = NSColor(
            calibratedRed: CGFloat(color.red),
            green: CGFloat(color.green),
            blue: CGFloat(color.blue),
            alpha: CGFloat(max(0, min(1, color.alpha)))
        )
        
        if let geometry = node.geometry {
            for material in geometry.materials {
                // Use multiply so textured models keep their texture details while being tinted.
                material.multiply.contents = nsColor
            }
        }
        
        for child in node.childNodes {
            applyTintColor(color, to: child)
        }
    }
    
    // MARK: - Coordinator
    
    class Coordinator {
        var scnView: SCNView?
        var modelNode: SCNNode?
        /// The scale factor applied during normalization, so user scale is relative to it
        var normalizationScale: CGFloat = 1.0
        
        func loadModel(url: URL, into scene: SCNScene, cameraDistance: Double) {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                do {
                    let loadedScene: SCNScene
                    let ext = url.pathExtension.lowercased()
                    
                    if ext == "usdz" || ext == "usda" || ext == "usdc" || ext == "usd" {
                        loadedScene = try SCNScene(url: url, options: [
                            .checkConsistency: true
                        ])
                    } else if ext == "gltf" || ext == "glb" {
                        loadedScene = try SCNScene(url: url, options: nil)
                    } else {
                        loadedScene = try SCNScene(url: url, options: nil)
                    }
                    
                    DispatchQueue.main.async {
                        // Create a container node
                        let containerNode = SCNNode()
                        containerNode.name = "modelContainer"
                        
                        // Copy all child nodes from loaded scene
                        for child in loadedScene.rootNode.childNodes {
                            containerNode.addChildNode(child.clone())
                        }
                        
                        // Calculate bounding box of the full model
                        let (minBound, maxBound) = containerNode.boundingBox
                        let sizeX = maxBound.x - minBound.x
                        let sizeY = maxBound.y - minBound.y
                        let sizeZ = maxBound.z - minBound.z
                        let maxDimension = max(sizeX, max(sizeY, sizeZ))
                        
                        // Center the model at origin FIRST (using pivot)
                        let centerX = (minBound.x + maxBound.x) / 2
                        let centerY = (minBound.y + maxBound.y) / 2
                        let centerZ = (minBound.z + maxBound.z) / 2
                        containerNode.pivot = SCNMatrix4MakeTranslation(centerX, centerY, centerZ)
                        
                        // Normalize to fit within a 2-unit sphere (model spans -1 to 1)
                        if maxDimension > 0 {
                            let scaleFactor = 2.0 / maxDimension
                            containerNode.scale = SCNVector3(scaleFactor, scaleFactor, scaleFactor)
                            self?.normalizationScale = scaleFactor
                        }
                        
                        scene.rootNode.addChildNode(containerNode)
                        self?.modelNode = containerNode
                        
                        // Auto-position camera to frame the model properly
                        if let cameraNode = scene.rootNode.childNode(withName: "mainCamera", recursively: false) {
                            // Ensure camera is far enough to see the whole normalized model
                            let minCamDist: CGFloat = 4.0
                            let currentDist = CGFloat(cameraDistance)
                            if currentDist < minCamDist {
                                cameraNode.position = SCNVector3(0, 0, minCamDist)
                            }
                            cameraNode.look(at: SCNVector3.zero)
                        }
                        
                        DebugLogger.shared.success(
                            "3D model loaded: size=(\(String(format: "%.1f", sizeX)), \(String(format: "%.1f", sizeY)), \(String(format: "%.1f", sizeZ))), normScale=\(String(format: "%.4f", self?.normalizationScale ?? 0))",
                            category: .app
                        )
                    }
                } catch {
                    DebugLogger.shared.error("Failed to load 3D model: \(error)", category: .app)
                }
            }
        }
    }
}


// MARK: - SCNVector3 Zero Extension

private extension SCNVector3 {
    static let zero = SCNVector3(0, 0, 0)
}

// MARK: - Export Helper

/// Helper to snapshot a SceneKit view for video export
/// Used when ImageRenderer can't capture NSViewRepresentable content
struct Model3DExportHelper {
    static func snapshot(scnView: SCNView, size: CGSize) -> CGImage? {
        let image = scnView.snapshot()
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
