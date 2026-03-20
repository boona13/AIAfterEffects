//
//  SceneKitGizmoNodes.swift
//  AIAfterEffects
//
//  Builds SceneKit gizmo geometry for 3D transform manipulation:
//  translation arrows, rotation rings, and scale cubes — Blender-style.
//

import SceneKit

// MARK: - Gizmo Constants

enum GizmoConstants {
    static let axisLength: CGFloat = 1.5
    static let shaftRadius: CGFloat = 0.02
    static let coneRadius: CGFloat = 0.06
    static let coneHeight: CGFloat = 0.18
    static let handleCubeSize: CGFloat = 0.08
    static let ringRadius: CGFloat = 1.2
    static let ringPipeRadius: CGFloat = 0.025
    static let planeHandleSize: CGFloat = 0.3
    static let planeHandleOffset: CGFloat = 0.5
    static let centerSphereRadius: CGFloat = 0.08
    /// Render order high enough to draw on top of any model geometry
    static let alwaysOnTopRenderOrder = 100
    
    // Hit-test names
    static let xAxisName = "gizmo_axis_x"
    static let yAxisName = "gizmo_axis_y"
    static let zAxisName = "gizmo_axis_z"
    static let xyPlaneName = "gizmo_plane_xy"
    static let xzPlaneName = "gizmo_plane_xz"
    static let yzPlaneName = "gizmo_plane_yz"
    static let centerName = "gizmo_center"
    static let ringXName = "gizmo_ring_x"
    static let ringYName = "gizmo_ring_y"
    static let ringZName = "gizmo_ring_z"
    static let trackballName = "gizmo_trackball"
    static let scaleXName = "gizmo_scale_x"
    static let scaleYName = "gizmo_scale_y"
    static let scaleZName = "gizmo_scale_z"
    
    // Colors
    static let xColor = NSColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1.0) // Red
    static let yColor = NSColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1.0) // Green
    static let zColor = NSColor(red: 0.3, green: 0.4, blue: 0.9, alpha: 1.0) // Blue
    static let highlightColor = NSColor(red: 1.0, green: 0.9, blue: 0.3, alpha: 1.0) // Yellow highlight
    static let centerColor = NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 0.8)
    static let planeAlpha: CGFloat = 0.25
}

// MARK: - Gizmo Node Factory

class GizmoNodeFactory {
    
    // MARK: - Translation Gizmo (Move)
    
    /// Makes all geometry in a node tree render on top of scene content (ignoring depth buffer).
    /// This ensures gizmo handles are never hidden inside or behind the 3D model.
    static func makeAlwaysOnTop(_ node: SCNNode) {
        node.renderingOrder = GizmoConstants.alwaysOnTopRenderOrder
        node.enumerateChildNodes { child, _ in
            child.renderingOrder = GizmoConstants.alwaysOnTopRenderOrder
            if let mat = child.geometry?.firstMaterial {
                mat.readsFromDepthBuffer = false
                mat.writesToDepthBuffer = false
            }
        }
    }
    
    /// Creates a full translation gizmo with 3 axis arrows, 3 plane handles, and a center sphere
    static func makeTranslationGizmo() -> SCNNode {
        let root = SCNNode()
        root.name = "gizmo_translation"
        
        // Axis arrows
        root.addChildNode(makeAxisArrow(
            axis: .x,
            color: GizmoConstants.xColor,
            name: GizmoConstants.xAxisName
        ))
        root.addChildNode(makeAxisArrow(
            axis: .y,
            color: GizmoConstants.yColor,
            name: GizmoConstants.yAxisName
        ))
        root.addChildNode(makeAxisArrow(
            axis: .z,
            color: GizmoConstants.zColor,
            name: GizmoConstants.zAxisName
        ))
        
        // Plane handles
        root.addChildNode(makePlaneHandle(
            plane: .xy,
            color1: GizmoConstants.xColor,
            color2: GizmoConstants.yColor,
            name: GizmoConstants.xyPlaneName
        ))
        root.addChildNode(makePlaneHandle(
            plane: .xz,
            color1: GizmoConstants.xColor,
            color2: GizmoConstants.zColor,
            name: GizmoConstants.xzPlaneName
        ))
        root.addChildNode(makePlaneHandle(
            plane: .yz,
            color1: GizmoConstants.yColor,
            color2: GizmoConstants.zColor,
            name: GizmoConstants.yzPlaneName
        ))
        
        // Center sphere — always-on-top ghost so it's never hidden inside the model
        let center = makeCenterHandle(
            geometry: SCNSphere(radius: GizmoConstants.centerSphereRadius * 2),
            color: GizmoConstants.centerColor,
            name: GizmoConstants.centerName
        )
        root.addChildNode(center)
        
        makeAlwaysOnTop(root)
        return root
    }
    
    // MARK: - Rotation Gizmo
    
    /// Creates a rotation gizmo with 3 colored torus rings and a trackball sphere
    static func makeRotationGizmo() -> SCNNode {
        let root = SCNNode()
        root.name = "gizmo_rotation"
        
        // X ring (Red) — rotates around X axis, so torus is in YZ plane
        let ringX = makeRing(color: GizmoConstants.xColor, name: GizmoConstants.ringXName)
        ringX.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2) // Rotate to YZ plane
        root.addChildNode(ringX)
        
        // Y ring (Green) — rotates around Y axis, torus default is in XZ plane
        let ringY = makeRing(color: GizmoConstants.yColor, name: GizmoConstants.ringYName)
        // Default torus is already in XZ plane
        root.addChildNode(ringY)
        
        // Z ring (Blue) — rotates around Z axis, so torus is in XY plane
        let ringZ = makeRing(color: GizmoConstants.zColor, name: GizmoConstants.ringZName)
        ringZ.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0) // Rotate to XY plane
        root.addChildNode(ringZ)
        
        // Trackball sphere (transparent, for free rotation)
        let trackball = SCNNode(geometry: SCNSphere(radius: GizmoConstants.ringRadius * 0.95))
        trackball.geometry?.firstMaterial?.diffuse.contents = NSColor.white.withAlphaComponent(0.05)
        trackball.geometry?.firstMaterial?.isDoubleSided = true
        trackball.geometry?.firstMaterial?.transparency = 0.95
        trackball.name = GizmoConstants.trackballName
        root.addChildNode(trackball)
        
        makeAlwaysOnTop(root)
        return root
    }
    
    // MARK: - Scale Gizmo
    
    /// Creates a scale gizmo with 3 axis lines + cube endpoints and a center cube
    static func makeScaleGizmo() -> SCNNode {
        let root = SCNNode()
        root.name = "gizmo_scale"
        
        root.addChildNode(makeScaleAxis(
            axis: .x,
            color: GizmoConstants.xColor,
            name: GizmoConstants.scaleXName
        ))
        root.addChildNode(makeScaleAxis(
            axis: .y,
            color: GizmoConstants.yColor,
            name: GizmoConstants.scaleYName
        ))
        root.addChildNode(makeScaleAxis(
            axis: .z,
            color: GizmoConstants.zColor,
            name: GizmoConstants.scaleZName
        ))
        
        // Center cube for uniform scale — always-on-top ghost
        let cubeSize = GizmoConstants.handleCubeSize * 2.5
        let centerBox = SCNBox(width: cubeSize, height: cubeSize, length: cubeSize, chamferRadius: cubeSize * 0.15)
        let center = makeCenterHandle(
            geometry: centerBox,
            color: GizmoConstants.centerColor,
            name: GizmoConstants.centerName
        )
        root.addChildNode(center)
        
        makeAlwaysOnTop(root)
        return root
    }
    
    // MARK: - Axis Arrow (Translation)
    
    private enum Axis3D {
        case x, y, z
    }
    
    private static func makeAxisArrow(axis: Axis3D, color: NSColor, name: String) -> SCNNode {
        let group = SCNNode()
        group.name = name
        
        // Shaft (cylinder)
        let shaft = SCNCylinder(radius: GizmoConstants.shaftRadius, height: GizmoConstants.axisLength)
        shaft.firstMaterial?.diffuse.contents = color
        shaft.firstMaterial?.lightingModel = .constant
        let shaftNode = SCNNode(geometry: shaft)
        shaftNode.name = name
        shaftNode.position = SCNVector3(0, GizmoConstants.axisLength / 2, 0)
        group.addChildNode(shaftNode)
        
        // Cone tip
        let cone = SCNCone(topRadius: 0, bottomRadius: GizmoConstants.coneRadius, height: GizmoConstants.coneHeight)
        cone.firstMaterial?.diffuse.contents = color
        cone.firstMaterial?.lightingModel = .constant
        let coneNode = SCNNode(geometry: cone)
        coneNode.name = name
        coneNode.position = SCNVector3(0, GizmoConstants.axisLength + GizmoConstants.coneHeight / 2, 0)
        group.addChildNode(coneNode)
        
        // Invisible larger hit-test geometry for easier clicking
        let hitCylinder = SCNCylinder(radius: GizmoConstants.shaftRadius * 4, height: GizmoConstants.axisLength + GizmoConstants.coneHeight)
        hitCylinder.firstMaterial?.transparency = 0.001
        let hitNode = SCNNode(geometry: hitCylinder)
        hitNode.name = name
        hitNode.position = SCNVector3(0, (GizmoConstants.axisLength + GizmoConstants.coneHeight) / 2, 0)
        group.addChildNode(hitNode)
        
        // Orient along the correct axis
        switch axis {
        case .x:
            group.eulerAngles = SCNVector3(0, 0, -CGFloat.pi / 2) // Point along +X
        case .y:
            break // Default cylinder is along Y
        case .z:
            group.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0) // Point along +Z
        }
        
        return group
    }
    
    // MARK: - Plane Handle (Translation)
    
    private enum Plane3D {
        case xy, xz, yz
    }
    
    private static func makePlaneHandle(plane: Plane3D, color1: NSColor, color2: NSColor, name: String) -> SCNNode {
        let size = GizmoConstants.planeHandleSize
        let offset = GizmoConstants.planeHandleOffset
        
        // Create a small square plane
        let planeGeo = SCNPlane(width: size, height: size)
        let blended = blendColors(color1, color2)
        planeGeo.firstMaterial?.diffuse.contents = blended.withAlphaComponent(GizmoConstants.planeAlpha)
        planeGeo.firstMaterial?.isDoubleSided = true
        planeGeo.firstMaterial?.lightingModel = .constant
        
        let node = SCNNode(geometry: planeGeo)
        node.name = name
        
        // Border lines
        let border = SCNBox(width: size, height: size, length: 0.002, chamferRadius: 0)
        border.firstMaterial?.diffuse.contents = blended.withAlphaComponent(0.6)
        border.firstMaterial?.lightingModel = .constant
        let borderNode = SCNNode(geometry: border)
        borderNode.name = name
        node.addChildNode(borderNode)
        
        switch plane {
        case .xy:
            node.position = SCNVector3(offset, offset, 0)
        case .xz:
            node.eulerAngles = SCNVector3(-CGFloat.pi / 2, 0, 0)
            node.position = SCNVector3(offset, 0, offset)
        case .yz:
            node.eulerAngles = SCNVector3(0, CGFloat.pi / 2, 0)
            node.position = SCNVector3(0, offset, offset)
        }
        
        return node
    }
    
    // MARK: - Ring (Rotation)
    
    private static func makeRing(color: NSColor, name: String) -> SCNNode {
        let torus = SCNTorus(ringRadius: GizmoConstants.ringRadius, pipeRadius: GizmoConstants.ringPipeRadius)
        torus.firstMaterial?.diffuse.contents = color
        torus.firstMaterial?.lightingModel = .constant
        
        let node = SCNNode(geometry: torus)
        node.name = name
        
        // Invisible larger hit-test geometry
        let hitTorus = SCNTorus(ringRadius: GizmoConstants.ringRadius, pipeRadius: GizmoConstants.ringPipeRadius * 4)
        hitTorus.firstMaterial?.transparency = 0.001
        let hitNode = SCNNode(geometry: hitTorus)
        hitNode.name = name
        node.addChildNode(hitNode)
        
        return node
    }
    
    // MARK: - Scale Axis
    
    private static func makeScaleAxis(axis: Axis3D, color: NSColor, name: String) -> SCNNode {
        let group = SCNNode()
        group.name = name
        
        // Shaft line
        let shaft = SCNCylinder(radius: GizmoConstants.shaftRadius, height: GizmoConstants.axisLength)
        shaft.firstMaterial?.diffuse.contents = color
        shaft.firstMaterial?.lightingModel = .constant
        let shaftNode = SCNNode(geometry: shaft)
        shaftNode.name = name
        shaftNode.position = SCNVector3(0, GizmoConstants.axisLength / 2, 0)
        group.addChildNode(shaftNode)
        
        // Cube endpoint
        let cube = SCNBox(width: GizmoConstants.handleCubeSize,
                          height: GizmoConstants.handleCubeSize,
                          length: GizmoConstants.handleCubeSize,
                          chamferRadius: 0.005)
        cube.firstMaterial?.diffuse.contents = color
        cube.firstMaterial?.lightingModel = .constant
        let cubeNode = SCNNode(geometry: cube)
        cubeNode.name = name
        cubeNode.position = SCNVector3(0, GizmoConstants.axisLength + GizmoConstants.handleCubeSize / 2, 0)
        group.addChildNode(cubeNode)
        
        // Invisible hit geometry
        let hitCylinder = SCNCylinder(radius: GizmoConstants.shaftRadius * 4, height: GizmoConstants.axisLength + GizmoConstants.handleCubeSize)
        hitCylinder.firstMaterial?.transparency = 0.001
        let hitNode = SCNNode(geometry: hitCylinder)
        hitNode.name = name
        hitNode.position = SCNVector3(0, (GizmoConstants.axisLength + GizmoConstants.handleCubeSize) / 2, 0)
        group.addChildNode(hitNode)
        
        // Orient
        switch axis {
        case .x:
            group.eulerAngles = SCNVector3(0, 0, -CGFloat.pi / 2)
        case .y:
            break
        case .z:
            group.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        }
        
        return group
    }
    
    // MARK: - Grid Floor
    
    /// Creates a grid floor plane for spatial reference in 3D edit mode
    static func makeGridFloor(size: CGFloat = 10, divisions: Int = 20) -> SCNNode {
        let root = SCNNode()
        root.name = "grid_floor"
        
        let step = size / CGFloat(divisions)
        let half = size / 2
        
        // Create grid lines using thin boxes
        let lineThickness: CGFloat = 0.005
        let gridColor = NSColor.gray.withAlphaComponent(0.3)
        let centerLineColor = NSColor.gray.withAlphaComponent(0.5)
        
        for i in 0...divisions {
            let pos = -half + CGFloat(i) * step
            let isCenter = i == divisions / 2
            let color = isCenter ? centerLineColor : gridColor
            
            // Line along X
            let xLine = SCNBox(width: size, height: lineThickness, length: lineThickness, chamferRadius: 0)
            xLine.firstMaterial?.diffuse.contents = color
            xLine.firstMaterial?.lightingModel = .constant
            let xNode = SCNNode(geometry: xLine)
            xNode.position = SCNVector3(0, 0, pos)
            root.addChildNode(xNode)
            
            // Line along Z
            let zLine = SCNBox(width: lineThickness, height: lineThickness, length: size, chamferRadius: 0)
            zLine.firstMaterial?.diffuse.contents = color
            zLine.firstMaterial?.lightingModel = .constant
            let zNode = SCNNode(geometry: zLine)
            zNode.position = SCNVector3(pos, 0, 0)
            root.addChildNode(zNode)
        }
        
        return root
    }
    
    // MARK: - Axis Indicator Widget
    
    /// Small axis indicator (RGB lines) for the corner of the viewport
    static func makeAxisIndicator(length: CGFloat = 0.5) -> SCNNode {
        let root = SCNNode()
        root.name = "axis_indicator"
        
        let radius: CGFloat = 0.015
        
        // X axis (red)
        let xCyl = SCNCylinder(radius: radius, height: length)
        xCyl.firstMaterial?.diffuse.contents = GizmoConstants.xColor
        xCyl.firstMaterial?.lightingModel = .constant
        let xNode = SCNNode(geometry: xCyl)
        xNode.position = SCNVector3(length / 2, 0, 0)
        xNode.eulerAngles = SCNVector3(0, 0, -CGFloat.pi / 2)
        root.addChildNode(xNode)
        
        // Y axis (green)
        let yCyl = SCNCylinder(radius: radius, height: length)
        yCyl.firstMaterial?.diffuse.contents = GizmoConstants.yColor
        yCyl.firstMaterial?.lightingModel = .constant
        let yNode = SCNNode(geometry: yCyl)
        yNode.position = SCNVector3(0, length / 2, 0)
        root.addChildNode(yNode)
        
        // Z axis (blue)
        let zCyl = SCNCylinder(radius: radius, height: length)
        zCyl.firstMaterial?.diffuse.contents = GizmoConstants.zColor
        zCyl.firstMaterial?.lightingModel = .constant
        let zNode = SCNNode(geometry: zCyl)
        zNode.position = SCNVector3(0, 0, length / 2)
        zNode.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        root.addChildNode(zNode)
        
        return root
    }
    
    // MARK: - Highlight
    
    /// Highlight a specific gizmo node by changing its material color
    static func highlightNode(named name: String, in gizmoRoot: SCNNode) {
        resetHighlights(in: gizmoRoot)
        gizmoRoot.enumerateChildNodes { node, _ in
            if node.name == name {
                node.geometry?.firstMaterial?.emission.contents = GizmoConstants.highlightColor
                node.geometry?.firstMaterial?.emission.intensity = 0.5
            }
        }
    }
    
    /// Reset all gizmo highlights
    static func resetHighlights(in gizmoRoot: SCNNode) {
        gizmoRoot.enumerateChildNodes { node, _ in
            if let name = node.name, name.hasPrefix("gizmo_") {
                node.geometry?.firstMaterial?.emission.contents = NSColor.black
                node.geometry?.firstMaterial?.emission.intensity = 0
            }
        }
    }
    
    // MARK: - Center Handle (always-on-top ghost)
    
    /// Creates a center handle that renders on top of all scene geometry.
    /// Uses a semi-transparent fill + wireframe outline so it's always visible
    /// even when the 3D model completely surrounds the origin.
    private static func makeCenterHandle(geometry: SCNGeometry, color: NSColor, name: String) -> SCNNode {
        let node = SCNNode()
        node.name = name
        node.renderingOrder = GizmoConstants.alwaysOnTopRenderOrder
        
        // Solid fill — semi-transparent, depth-test disabled so it draws over everything
        let fillNode = SCNNode(geometry: geometry.copy() as? SCNGeometry ?? geometry)
        fillNode.name = name
        let fillMat = SCNMaterial()
        fillMat.diffuse.contents = color
        fillMat.transparency = 0.45
        fillMat.lightingModel = .constant
        fillMat.readsFromDepthBuffer = false   // Ignore depth → always visible
        fillMat.writesToDepthBuffer = false
        fillMat.isDoubleSided = true
        fillNode.geometry?.firstMaterial = fillMat
        fillNode.renderingOrder = GizmoConstants.alwaysOnTopRenderOrder
        node.addChildNode(fillNode)
        
        // Wireframe outline — fully opaque edge ring for readability
        let outlineNode = SCNNode(geometry: geometry.copy() as? SCNGeometry ?? geometry)
        outlineNode.name = name
        let outlineMat = SCNMaterial()
        outlineMat.diffuse.contents = NSColor.white
        outlineMat.lightingModel = .constant
        outlineMat.fillMode = .lines
        outlineMat.readsFromDepthBuffer = false
        outlineMat.writesToDepthBuffer = false
        outlineMat.isDoubleSided = true
        outlineNode.geometry?.firstMaterial = outlineMat
        outlineNode.renderingOrder = GizmoConstants.alwaysOnTopRenderOrder + 1
        node.addChildNode(outlineNode)
        
        // Invisible larger hit-test sphere — makes clicking much easier
        let hitSize: CGFloat = 0.25
        let hitGeo = SCNSphere(radius: hitSize)
        hitGeo.firstMaterial?.transparency = 0.001
        hitGeo.firstMaterial?.readsFromDepthBuffer = false
        let hitNode = SCNNode(geometry: hitGeo)
        hitNode.name = name
        hitNode.renderingOrder = GizmoConstants.alwaysOnTopRenderOrder
        node.addChildNode(hitNode)
        
        return node
    }
    
    // MARK: - Helpers
    
    private static func blendColors(_ c1: NSColor, _ c2: NSColor) -> NSColor {
        guard let c1RGB = c1.usingColorSpace(.sRGB),
              let c2RGB = c2.usingColorSpace(.sRGB) else { return c1 }
        return NSColor(
            red: (c1RGB.redComponent + c2RGB.redComponent) / 2,
            green: (c1RGB.greenComponent + c2RGB.greenComponent) / 2,
            blue: (c1RGB.blueComponent + c2RGB.blueComponent) / 2,
            alpha: 1.0
        )
    }
    
    /// Identify a GizmoHandle3D from a hit-test node name
    static func handle3D(from nodeName: String?) -> GizmoHandle3D? {
        guard let name = nodeName else { return nil }
        switch name {
        case GizmoConstants.xAxisName: return .axisX
        case GizmoConstants.yAxisName: return .axisY
        case GizmoConstants.zAxisName: return .axisZ
        case GizmoConstants.xyPlaneName: return .planeXY
        case GizmoConstants.xzPlaneName: return .planeXZ
        case GizmoConstants.yzPlaneName: return .planeYZ
        case GizmoConstants.centerName: return .center
        case GizmoConstants.ringXName: return .ringX
        case GizmoConstants.ringYName: return .ringY
        case GizmoConstants.ringZName: return .ringZ
        case GizmoConstants.trackballName: return .trackball
        case GizmoConstants.scaleXName: return .scaleX
        case GizmoConstants.scaleYName: return .scaleY
        case GizmoConstants.scaleZName: return .scaleZ
        default: return nil
        }
    }
}
