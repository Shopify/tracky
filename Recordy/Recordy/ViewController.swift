//
//  ViewController.swift
//  Recordy
//
//  Created by Eric Florenzano on 1/23/23.
//

import UIKit
import SceneKit
import ARKit
import AVFoundation
import ARKit

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet var recordButton: UIButton!
    @IBOutlet var recordingButton: UIButton!
    
    var wantsRecording = false
    var isRecording = false
    var sessionInProgress = false
    var recordStart: TimeInterval = 0
    
    var ourEpoch: Int = 0
    var recordingDir: URL? = nil
    
    var fps: UInt = 60
    var viewResolutionX: UInt = 1
    var viewResolutionY: UInt = 1
    var videoSessionRGB: VideoSession? = nil
    var videoSessionDepth: VideoSession? = nil
    var videoSessionSegmentation: VideoSession? = nil
    
    var timestamps: [Float] = []
    var projectionMatrix = matrix_identity_float4x4
    var cameraTransforms: [simd_float4x4] = []
    var lensDatas: [BrenLensData] = []
    var horizontalPlaneNodes: [SCNNode] = []
    var verticalPlaneNodes: [SCNNode] = []
    let trackedNodeBitmask: Int = 1 << 6
    var trackedNodes: [SCNNode] = []
    
    let dateFormatter : DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view's delegate
        sceneView.delegate = self
        
        // Show statistics such as fps and timing information
        sceneView.showsStatistics = true
        sceneView.debugOptions = [.showBoundingBoxes]

        recordButton.isHidden = false
        recordingButton.isHidden = true
        
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Remove any existing tracked AR stuff
        trackedNodes.forEach { $0.removeFromParentNode() }
        trackedNodes.removeAll(keepingCapacity: true)
        //planeAnchors.removeAll(keepingCapacity: true)
        horizontalPlaneNodes.removeAll(keepingCapacity: true)
        verticalPlaneNodes.removeAll(keepingCapacity: true)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.isAutoFocusEnabled = true
        configuration.sceneReconstruction = .meshWithClassification
        configuration.environmentTexturing = .automatic
        configuration.isLightEstimationEnabled = true
        configuration.videoHDRAllowed = false
        configuration.frameSemantics.insert(.sceneDepth)
        configuration.frameSemantics.insert(.personSegmentationWithDepth)
        
        // Run the view's session
        sceneView.session.run(configuration)
        sceneView.session.delegate = self
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    // MARK: - UITapGestureRecognizer
    
    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        let loc = gesture.location(in: sceneView)
        
        // First, see if it hits anything in the scene
        if let hitResult = sceneView.hitTest(loc, options: [.categoryBitMask: trackedNodeBitmask]).first,
           let idx = trackedNodes.firstIndex(of: hitResult.node) {
            trackedNodes.remove(at: idx)
            hitResult.node.removeFromParentNode()
            return
        }
        
        // Otherwise, raycast out into the real world and place a new tracked node there
        guard let query = sceneView.raycastQuery(from: loc, allowing: .estimatedPlane, alignment: .any) else {
            // In a production app we should provide feedback to the user here
            print("Couldn't create a query!")
            return
        }
        guard let result = sceneView.session.raycast(query).first else {
            print("Couldn't match the raycast with a plane.")
            return
        }

        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.locksAmbientWithDiffuse = true
        mat.diffuse.contents = UIColor.gray
        let geom = SCNBox(width: 0.1, height: 0.1, length: 0.1, chamferRadius: 0)
        geom.materials = geom.materials.map({ _ in return  mat })
        let node = SCNNode(geometry: geom)
        node.categoryBitMask = trackedNodeBitmask
        sceneView.scene.rootNode.addChildNode(node)
        node.simdTransform = result.worldTransform
        trackedNodes.append(node)
    }
    
    // Button handler
    
    @IBAction @objc func handleMainButtonTap() {
        recordButton.isHidden = !isRecording
        recordingButton.isHidden = isRecording
        if isRecording {
            stopRecording()
        } else {
            setWantsRecording()
        }
    }
    
    // MARK: Recording Functions
    
    func setWantsRecording() {
        // Note: these calls exist here because of and also imply that
        //       this method will only be called from the main thread.
        let siz = view.frame.size
        let scl = UIScreen.main.scale
        fps = UInt(sceneView.preferredFramesPerSecond)
        if fps == 0 {
            fps = 60 // idk
        }
        viewResolutionX = UInt(siz.width * scl)
        viewResolutionY = UInt(siz.height * scl)
        
        wantsRecording = true
    }
    
    func startRecording(_ renderer: SCNSceneRenderer, _ frame: ARFrame, _ time: TimeInterval) {
        guard let projectionTransform = renderer.pointOfView?.camera?.projectionTransform else {
            print("ERROR: Could not get renderer pov camera")
            return
        }
        guard let sceneDepth = frame.sceneDepth?.depthMap else {
            print("ERROR: Could not start recording when ARFrame has no AR depth data")
            return
        }
        guard let estimatedDepth = frame.estimatedDepthData else {
            print("ERROR: Could not start recording when ARFrame has no estimated depth data")
            return
        }
        guard let documentsPath = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            print("ERROR: Could not get documents path")
            return
        }
        let dirname = dateFormatter.string(from: Date.now)
        ourEpoch = Int(Date.now.timeIntervalSince1970) - 1676000000
        let recDir = URL(fileURLWithPath: "\(dirname) \(ourEpoch)", isDirectory: true, relativeTo: documentsPath)
        do {
            try FileManager.default.createDirectory(at: recDir, withIntermediateDirectories: true)
        } catch {
            print("Could not create directory \(recDir)")
            return
        }
        recordingDir = recDir
        let outputURL = URL(fileURLWithPath: "\(ourEpoch)-video.mp4", relativeTo: recDir)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        let outputURLDepth = URL(fileURLWithPath: "\(ourEpoch)-depth.mp4", relativeTo: recDir)
        if FileManager.default.fileExists(atPath: outputURLDepth.path) {
            try? FileManager.default.removeItem(at: outputURLDepth)
        }
        let outputURLSegmentation = URL(fileURLWithPath: "\(ourEpoch)-segmentation.mp4", relativeTo: recDir)
        if FileManager.default.fileExists(atPath: outputURLSegmentation.path) {
            try? FileManager.default.removeItem(at: outputURLSegmentation)
        }
        videoSessionRGB = VideoSession(pixelBuffer: frame.capturedImage, outputURL: outputURL, startTime: time, fps: fps, depth: false)
        videoSessionDepth = VideoSession(pixelBuffer: sceneDepth, outputURL: outputURLDepth, startTime: time, fps: fps, depth: true)
        videoSessionSegmentation = VideoSession(pixelBuffer: estimatedDepth, outputURL: outputURLSegmentation, startTime: time, fps: fps, depth: true)
        projectionMatrix = simd_float4x4(projectionTransform)
        cameraTransforms.removeAll(keepingCapacity: true)
        timestamps.removeAll(keepingCapacity: true)
        lensDatas.removeAll(keepingCapacity: true)
        //planeAnchors.removeAll(keepingCapacity: false)
        recordStart = time
        sessionInProgress = false

        isRecording = true
    }
    
    func updateRecording(_ renderer: SCNSceneRenderer, _ time: TimeInterval) {
        guard let frame = sceneView.session.currentFrame,
              let pov = renderer.pointOfView,
              let cam = pov.camera,
              let _ = frame.estimatedDepthData else {
            return
        }
        
        if wantsRecording {
            wantsRecording = false
            startRecording(renderer, frame, time)
        }
        if isRecording {
            timestamps.append(Float(time - recordStart))
            cameraTransforms.append(pov.simdTransform)
            let focalLengthKey = kCGImagePropertyExifFocalLenIn35mmFilm as String
            let focalLength = frame.exifData[focalLengthKey] as! NSNumber
            lensDatas.append(BrenLensData(
                fov: cam.fieldOfView, // TODO: Remove me?
                focalLength: CGFloat(truncating: focalLength),
                sensorHeight: 35,
                zNear: cam.zNear, // TODO: Remove me?
                zFar: cam.zFar, // TODO: Remove me?
                focusDistance: cam.focusDistance, // TODO: Remove me?
                orientation: UIDevice.current.orientation.rawValue
            ))
            videoSessionRGB?.addFrame(timestamp: time, image: frame.capturedImage)
            if let sceneDepth = frame.sceneDepth?.depthMap {
                videoSessionDepth?.addFrame(timestamp: time, image: sceneDepth)
            }
            if let estimatedDepth = frame.estimatedDepthData {
                videoSessionSegmentation?.addFrame(timestamp: time, image: estimatedDepth)
            }
        }
    }
    
    private func gatherBrenPlanes() -> [BrenPlane] {
        var planes: [BrenPlane] = []
        for extentNode in horizontalPlaneNodes {
            planes.append(BrenPlane(
                transform: extentNode.simdWorldTransform,
                alignment: "horizontal"
            ))
        }
        for extentNode in verticalPlaneNodes {
            planes.append(BrenPlane(
                transform: extentNode.simdWorldTransform,
                alignment: "vertical"
            ))
        }
        return planes
    }
    
    func writeBrenfile() {
        guard let recordDir = recordingDir else {
            print("ERROR: Cannot save brenfile with nil recordingDir")
            return
        }
        
        let renderData = BrenRenderData(
            fps: fps,
            viewResolutionX: viewResolutionX,
            viewResolutionY: viewResolutionY,
            videoResolutionX: videoSessionRGB!.videoResolutionX,
            videoResolutionY: videoSessionRGB!.videoResolutionY
        )
        let cameraFrames = BrenCameraFrames(
            timestamps: timestamps,
            transforms: cameraTransforms,
            datas: lensDatas
        )
        let planes = gatherBrenPlanes()
        let trackedTransforms = trackedNodes.map { $0.simdTransform }
        let data = BrenWrapper(renderData, cameraFrames, planes, trackedTransforms)
        let jsonEncoder = JSONEncoder()
        guard let jsonData = try? jsonEncoder.encode(data),
              let json = String(data: jsonData, encoding: String.Encoding.utf8) else {
            print("ERROR: Could not encode json data")
            return
        }
        
        let outputURL = URL(fileURLWithPath: "\(ourEpoch)-camera.bren", relativeTo: recordDir)
        do {
            try json.write(to: outputURL, atomically: true, encoding: String.Encoding.utf8)
            print("Finished writing .bren")
        } catch {
            // TODO: Print error message
        }
    }
    
    func stopRecording() {
        isRecording = false
        sessionInProgress = false
        videoSessionRGB?.finish {
            self.videoSessionDepth?.finish {
                self.videoSessionSegmentation?.finish {
                    print("Finished writing .mp4s")
                    self.writeBrenfile()
                    self.videoSessionRGB = nil
                }
            }
        }
    }
    // MARK: - ARSessionDelegate
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
    }
    
    // MARK: - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        updateRecording(renderer, time)
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        
        let extentPlane: SCNPlane = SCNPlane(width: 1, height: 1)
        extentPlane.materials = extentPlane.materials.map({ _m in
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.locksAmbientWithDiffuse = true
            material.diffuse.contents = UIColor.init(white: CGFloat(1), alpha: CGFloat(0.1))
            return material
        })
        let extentNode = SCNNode(geometry: extentPlane)
        extentNode.simdPosition = planeAnchor.center
        extentNode.eulerAngles.x = -.pi / 2
        extentNode.eulerAngles.y = planeAnchor.planeExtent.rotationOnYAxis
        extentNode.simdScale.x = planeAnchor.planeExtent.width
        extentNode.simdScale.y = planeAnchor.planeExtent.height
        
        // Add the visualization to the ARKit-managed node so that it tracks
        // changes in the plane anchor as plane estimation continues.
        node.addChildNode(extentNode)

        if planeAnchor.alignment == .vertical {
            verticalPlaneNodes.append(extentNode)
        } else {
            horizontalPlaneNodes.append(extentNode)
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor,
            let extentNode = node.childNodes.first
            else { return }
        
        extentNode.simdPosition = planeAnchor.center
        extentNode.eulerAngles.y = planeAnchor.planeExtent.rotationOnYAxis
        extentNode.simdScale.x = planeAnchor.planeExtent.width
        extentNode.simdScale.y = planeAnchor.planeExtent.height
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
        
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
        
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        
    }
}
