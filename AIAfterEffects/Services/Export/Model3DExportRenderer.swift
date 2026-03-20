//
//  Model3DExportRenderer.swift
//  AIAfterEffects
//
//  Offscreen SceneKit renderer for capturing 3D models during video export.
//  ImageRenderer cannot capture NSViewRepresentable content, so this uses
//  SCNRenderer to render 3D scenes to CGImage for each frame.
//

import SceneKit
import AppKit
import Foundation

// MARK: - Model 3D Export Renderer

/// Manages offscreen SceneKit rendering for video export.
/// Each instance handles one 3D model object and can render frames at any time.
final class Model3DExportRenderer {
    
    private let scene: SCNScene
    private let renderer: SCNRenderer
    private var modelNode: SCNNode?
    private var normalizationScale: CGFloat = 1.0
    private let renderSize: CGSize
    private let logger = DebugLogger.shared
    
    // MARK: - Initialization
    
    /// Create an export renderer for a specific 3D model object.
    /// - Parameters:
    ///   - sceneObject: The SceneObject containing model3D properties
    ///   - modelURL: Pre-resolved URL to the 3D model file
    ///   - renderSize: The canvas size to render at (3D scene always fills full canvas)
    init(sceneObject: SceneObject, modelURL: URL, renderSize: CGSize) {
        self.renderSize = renderSize
        self.scene = SCNScene()
        scene.background.contents = NSColor.clear
        
        // Create Metal-backed SCNRenderer for offscreen rendering
        let device = MTLCreateSystemDefaultDevice()
        self.renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.autoenablesDefaultLighting = true
        
        // Setup camera
        let camDist = sceneObject.properties.cameraDistance ?? 5.0
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.automaticallyAdjustsZRange = true
        cameraNode.camera?.fieldOfView = 45
        cameraNode.position = SCNVector3(0, 0, CGFloat(camDist))
        cameraNode.name = "mainCamera"
        scene.rootNode.addChildNode(cameraNode)
        
        // CRITICAL: SCNRenderer requires explicit pointOfView (unlike SCNView which auto-picks)
        renderer.pointOfView = cameraNode
        
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
        
        // Load the model synchronously for export
        loadModel(url: modelURL, cameraDistance: camDist, objectName: sceneObject.name)
    }
    
    // MARK: - Model Loading
    
    private func loadModel(url: URL, cameraDistance: Double, objectName: String) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            logger.warning("Model3DExportRenderer: Model file not found for object '\(objectName)'", category: .app)
            return
        }
        
        do {
            let loadedScene = try SCNScene(url: url, options: [
                .checkConsistency: true
            ])
            
            // Create a container node
            let containerNode = SCNNode()
            containerNode.name = "modelContainer"
            
            // Copy all child nodes from loaded scene
            for child in loadedScene.rootNode.childNodes {
                containerNode.addChildNode(child.clone())
            }
            
            // Calculate bounding box and normalize
            let (minBound, maxBound) = containerNode.boundingBox
            let sizeX = maxBound.x - minBound.x
            let sizeY = maxBound.y - minBound.y
            let sizeZ = maxBound.z - minBound.z
            let maxDimension = max(sizeX, max(sizeY, sizeZ))
            
            // Center the model at origin using pivot
            let centerX = (minBound.x + maxBound.x) / 2
            let centerY = (minBound.y + maxBound.y) / 2
            let centerZ = (minBound.z + maxBound.z) / 2
            containerNode.pivot = SCNMatrix4MakeTranslation(centerX, centerY, centerZ)
            
            // Normalize to fit within a 2-unit sphere
            if maxDimension > 0 {
                let scaleFactor = 2.0 / maxDimension
                containerNode.scale = SCNVector3(scaleFactor, scaleFactor, scaleFactor)
                normalizationScale = scaleFactor
            }
            
            scene.rootNode.addChildNode(containerNode)
            modelNode = containerNode
            
            // Auto-position camera
            if let cameraNode = scene.rootNode.childNode(withName: "mainCamera", recursively: false) {
                let minCamDist: CGFloat = 4.0
                let currentDist = CGFloat(cameraDistance)
                if currentDist < minCamDist {
                    cameraNode.position = SCNVector3(0, 0, minCamDist)
                }
                cameraNode.look(at: SCNVector3(0, 0, 0))
            }
            
            logger.debug(
                "Model3DExportRenderer: Loaded model '\(objectName)' size=(\(String(format: "%.1f", sizeX)), \(String(format: "%.1f", sizeY)), \(String(format: "%.1f", sizeZ))), normScale=\(String(format: "%.4f", normalizationScale))",
                category: .app
            )
        } catch {
            logger.error("Model3DExportRenderer: Failed to load model: \(error)", category: .app)
        }
    }
    
    // MARK: - Frame Rendering
    
    /// Render a single frame at the given time for the given scene object state.
    /// - Parameters:
    ///   - sceneObject: Current state of the scene object (with animations)
    ///   - currentTime: The current playback time
    /// - Returns: NSImage of the rendered 3D scene, or nil on failure
    func renderFrame(sceneObject: SceneObject, at currentTime: Double) -> NSImage? {
        guard let modelNode = modelNode else { return nil }
        
        // Update model transform (position, rotation, scale from animations)
        updateModelTransform(modelNode: modelNode, sceneObject: sceneObject, currentTime: currentTime)
        
        // Update camera and keep pointOfView in sync
        if let cameraNode = scene.rootNode.childNode(withName: "mainCamera", recursively: false) {
            updateCamera(cameraNode: cameraNode, sceneObject: sceneObject, currentTime: currentTime)
            renderer.pointOfView = cameraNode
        }
        
        // Render the scene to an image
        let image = renderer.snapshot(
            atTime: 0, // We manually set all transforms, so SCNRenderer time doesn't matter
            with: renderSize,
            antialiasingMode: .multisampling4X
        )
        
        return image
    }
    
    // MARK: - Transform Updates (mirrored from SceneKit3DView)
    
    private func updateModelTransform(modelNode: SCNNode, sceneObject: SceneObject, currentTime: Double) {
        let props = sceneObject.properties
        
        let rotX = CGFloat(props.rotationX ?? 0) * .pi / 180
        let rotY = CGFloat(props.rotationY ?? 0) * .pi / 180
        let rotZ = CGFloat(props.rotationZ ?? 0) * .pi / 180
        
        // ALWAYS reset position to origin — ensures clean state at any time
        var posX: CGFloat = 0
        var posY: CGFloat = 0
        var posZ: CGFloat = 0
        
        var animRotX: CGFloat = 0
        var animRotY: CGFloat = 0
        var animRotZ: CGFloat = 0
        
        // Accumulated scale factors — animations multiply into these so they compose additively.
        var scaleFactorX: CGFloat = 1.0
        var scaleFactorY: CGFloat = 1.0
        var scaleFactorZ: CGFloat = 1.0
        
        // Find the earliest scale-based entrance animation to determine pre-animation state.
        // Only the FIRST entrance should set scale to 0 — later entrances must not re-hide the model.
        let scaleEntranceTypes: Set<AnimationType> = [.scaleUp3D, .popIn3D, .tornado]
        let earliestScaleEntrance = sceneObject.animations
            .filter { scaleEntranceTypes.contains($0.type) }
            .min(by: { ($0.startTime + $0.delay) < ($1.startTime + $1.delay) })
        
        for animation in sceneObject.animations {
            let linearProgress = calculateAnimationProgress(animation: animation, currentTime: currentTime)
            
            // For the EARLIEST scale entrance that hasn't started yet, keep model invisible.
            if linearProgress < 0 {
                if let earliest = earliestScaleEntrance, animation.id == earliest.id {
                    scaleFactorX = 0; scaleFactorY = 0; scaleFactorZ = 0
                }
                continue
            }
            
            let easedProgress = EasingHelper.apply(animation.easing, to: linearProgress)
            let normalizedKeyframes = normalizedAdditive3DKeyframesIfNeeded(animation.keyframes, for: animation.type)
            let value = interpolateKeyframes(normalizedKeyframes, at: easedProgress)
            
            switch animation.type {
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
                posY += CGFloat(value) / 100.0
            case .orbit3D:
                // Symmetric orbit centered at origin — model moves in a circle of radius 1.0
                let angle = CGFloat(value) * .pi / 180
                let radius: CGFloat = 1.0
                posX += sin(angle) * radius
                posZ += cos(angle) * radius
            case .cradle:
                animRotY += CGFloat(value) * .pi / 180
            case .springBounce3D:
                posY += CGFloat(value) / 100.0
            case .elasticSpin:
                animRotY += CGFloat(value) * .pi / 180
            case .swing3D:
                animRotZ += CGFloat(value) * .pi / 180
            case .breathe3D:
                let breatheFactor = CGFloat(value)
                scaleFactorX *= breatheFactor
                scaleFactorY *= breatheFactor
                scaleFactorZ *= breatheFactor
            case .headNod:
                animRotX += CGFloat(value) * .pi / 180
            case .headShake:
                animRotY += CGFloat(value) * .pi / 180
            case .rockAndRoll:
                let angle = CGFloat(value) * .pi / 180
                animRotX += angle
                animRotZ += angle * 0.7
            case .scaleUp3D, .scaleDown3D:
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
                let baseAngle = CGFloat(value) * .pi / 180
                animRotX += baseAngle
                animRotY += baseAngle * 1.3
                animRotZ += baseAngle * 0.7
            case .barrelRoll:
                animRotZ += CGFloat(value) * .pi / 180
            case .corkscrew:
                // Helical rise: spin Y + rise from below to origin
                let progress = CGFloat(value)
                animRotY += progress * 2 * .pi * 2
                posY += (progress - 1.0) * 1.5      // starts at -1.5 (below), arrives at 0 (origin)
            case .figureEight:
                let t = CGFloat(value) * 2 * .pi
                posX += sin(t) * 1.2
                posZ += sin(t * 2) * 0.6
                animRotY += CGFloat(value) * .pi * 2
            case .boomerang3D:
                let t = CGFloat(value)
                posX += sin(t * .pi) * 3.0
                posZ += -t * 2.0 + t * t * 2.0
                animRotY += t * .pi
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
                animRotZ += sin(t * 6 * .pi) * 0.15
            case .rubberBand:
                let factor = CGFloat(value)
                scaleFactorX *= factor
                scaleFactorY *= (2.0 - factor)
            case .jelly3D:
                let phase = CGFloat(value)
                scaleFactorX *= (1.0 + phase * 0.2)
                scaleFactorY *= (1.0 - phase * 0.2)
            case .anticipateSpin:
                animRotY += CGFloat(value) * .pi / 180
            case .popIn3D:
                let scaleFactor = CGFloat(value)
                scaleFactorX *= scaleFactor
                scaleFactorY *= scaleFactor
                scaleFactorZ *= scaleFactor
                animRotY += CGFloat(easedProgress) * .pi * 0.5
            case .glitchJitter3D:
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
                let tornadoScale = t            // grow from 0% (invisible) to 100%
                scaleFactorX *= tornadoScale
                scaleFactorY *= tornadoScale
                scaleFactorZ *= tornadoScale
            case .unwrap:
                animRotX += CGFloat(value) * .pi / 180
            case .dropAndSettle:
                posY += CGFloat(value) / 100.0
            case .materialFade:
                break
            default:
                break
            }
        }
        
        modelNode.position = SCNVector3(posX, posY, posZ)
        modelNode.eulerAngles = SCNVector3(rotX + animRotX, rotY + animRotY, rotZ + animRotZ)
        
        // Scale: base scale * accumulated animation factors (additive composition)
        let sx = CGFloat(props.scaleX) * normalizationScale * scaleFactorX
        let sy = CGFloat(props.scaleY) * normalizationScale * scaleFactorY
        let sz = CGFloat(props.scaleZ ?? 1.0) * normalizationScale * scaleFactorZ
        modelNode.scale = SCNVector3(sx, sy, sz)
    }
    
    private func updateCamera(cameraNode: SCNNode, sceneObject: SceneObject, currentTime: Double) {
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
        
        // Spiral zoom state
        var useSpiralZoom = false
        var spiralProgress: CGFloat = 0
        let spiralStartDist: CGFloat = camDist * 2
        let spiralEndDist: CGFloat = camDist
        let spiralRevolutions: CGFloat = 2.5
        
        // Dolly zoom state
        var useDollyZoom = false
        var dollyProgress: CGFloat = 0
        var dutchRoll: CGFloat = 0
        
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
                camAngleX = CGFloat(value)
            case .cameraDive:
                camAngleX = CGFloat(value)
            case .cameraWhipPan:
                camAngleY += CGFloat(value)
            case .cameraSlide:
                lateralOffset = CGFloat(value)
            case .cameraArc:
                orbitAngle = CGFloat(value) * .pi / 180
                useOrbitPosition = true
            case .cameraPedestal:
                camAngleX = CGFloat(value)
            case .cameraTruck:
                lateralOffset = CGFloat(value)
            case .cameraPushPull:
                camDist = CGFloat(value)
            case .cameraDutchTilt:
                dutchRoll = CGFloat(value) * .pi / 180
            case .cameraHelicopter:
                let t = CGFloat(value)
                let startHeight: CGFloat = 70
                let endHeight: CGFloat = 20
                let angle = t * 2 * .pi * 1.5
                camAngleX = startHeight + (endHeight - startHeight) * t
                orbitAngle = angle
                useOrbitPosition = true
            case .cameraRocket:
                camAngleX = CGFloat(value)
            case .cameraShake:
                let shakeVal = CGFloat(value)
                camAngleX += shakeVal
                camAngleY += shakeVal * 0.7
            default:
                break
            }
        }
        
        if useSpiralZoom {
            let dist = spiralStartDist + (spiralEndDist - spiralStartDist) * spiralProgress
            let angle = spiralProgress * spiralRevolutions * 2 * .pi
            let radX = camAngleX * .pi / 180
            let heightY = sin(radX) * dist
            cameraNode.position = SCNVector3(
                orbitCenterX + sin(angle) * cos(radX) * dist,
                orbitCenterY + heightY,
                orbitCenterZ + cos(angle) * cos(radX) * dist
            )
        } else if useDollyZoom {
            let startDist = camDist * 2.0
            let endDist = camDist * 0.7
            let dist = startDist + (endDist - startDist) * dollyProgress
            
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
    
    // MARK: - Animation Helpers (mirrored from SceneKit3DView)
    
    private static let continuousAnimationTypes: Set<AnimationType> = [
        .turntable, .spin, .rotate, .rotate3DX, .rotate3DY, .rotate3DZ,
        .cameraOrbit, .orbit3D, .hueRotate, .tumble, .figureEight
    ]
    
    private func calculateAnimationProgress(animation: AnimationDefinition, currentTime: Double) -> Double {
        let startTime = animation.startTime + animation.delay
        let endTime = startTime + animation.duration
        
        guard currentTime >= startTime else { return -1 }
        
        let isContinuous = Self.continuousAnimationTypes.contains(animation.type)
        let shouldPingPong = !isContinuous && !animation.autoReverse
        
        if animation.repeatCount == -1 {
            let elapsed = currentTime - startTime
            if shouldPingPong {
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
        guard keyframes.count > 1 else {
            return keyframes[0].value.doubleVal
        }
        
        var prevKeyframe = keyframes[0]
        var nextKeyframe = keyframes[keyframes.count - 1]
        
        for i in 0..<keyframes.count - 1 {
            if progress >= keyframes[i].time && progress <= keyframes[i + 1].time {
                prevKeyframe = keyframes[i]
                nextKeyframe = keyframes[i + 1]
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
}


// MARK: - Model 3D Export Manager

/// Manages all offscreen 3D renderers for a video export session.
/// Creates one renderer per model3D object and caches them for the duration of export.
final class Model3DExportManager {
    
    private var renderers: [UUID: Model3DExportRenderer] = [:]
    private let logger = DebugLogger.shared
    
    /// Initialize renderers for all model3D objects in the scene.
    /// Must be called from @MainActor context to resolve model file URLs.
    @MainActor
    func prepare(sceneState: SceneState) {
        renderers.removeAll()
        
        let model3DObjects = sceneState.objects.filter { $0.type == .model3D }
        
        for obj in model3DObjects {
            // Render at the object's actual dimensions so the snapshot matches
            // the SwiftUI frame it will be displayed in — prevents stretching
            // when models are smaller than the full canvas (e.g. grid layouts).
            let objSize = CGSize(
                width: obj.properties.width,
                height: obj.properties.height
            )
            
            // Resolve model URL on MainActor (AssetManagerService is @MainActor)
            var modelURL: URL?
            if let assetId = obj.properties.modelAssetId {
                modelURL = AssetManagerService.shared.modelFileURL(for: assetId)
            } else if let filePath = obj.properties.modelFilePath {
                modelURL = URL(fileURLWithPath: filePath)
            }
            
            guard let url = modelURL else {
                logger.warning("Model3DExportManager: No model URL for object '\(obj.name)'", category: .app)
                continue
            }
            
            let renderer = Model3DExportRenderer(sceneObject: obj, modelURL: url, renderSize: objSize)
            renderers[obj.id] = renderer
        }
        
        if !model3DObjects.isEmpty {
            logger.info("Model3DExportManager: Prepared \(model3DObjects.count) offscreen 3D renderer(s)", category: .app)
        }
    }
    
    /// Render all 3D model snapshots for a given time.
    /// - Parameters:
    ///   - sceneState: Current scene state
    ///   - currentTime: The playback time to render at
    /// - Returns: Dictionary mapping object UUID to rendered NSImage
    func renderAll(sceneState: SceneState, at currentTime: Double) -> [UUID: NSImage] {
        var snapshots: [UUID: NSImage] = [:]
        
        for obj in sceneState.objects where obj.type == .model3D {
            if let renderer = renderers[obj.id],
               let image = renderer.renderFrame(sceneObject: obj, at: currentTime) {
                snapshots[obj.id] = image
            }
        }
        
        return snapshots
    }
    
    /// Whether there are any 3D models that need offscreen rendering.
    var hasModels: Bool {
        !renderers.isEmpty
    }
    
    /// Clean up all renderers.
    func cleanup() {
        renderers.removeAll()
    }
}
