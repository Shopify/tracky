//
//  ViewController.swift
//  Tracky
//
//  Created by Eric Florenzano on 1/23/23.
//

import UIKit
import SceneKit
import ARKit
import AVFoundation
import ARKit
import ModelIO
import SceneKit.ModelIO

let kAutofocusON = "AF ON"
let kAutofocusOFF = "AF OFF"

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet var recordButton: UIButton!
    @IBOutlet var recordingButton: UIButton!
    @IBOutlet var fpsButton: UIButton!
    @IBOutlet var hideButton: UIButton!
    @IBOutlet var afButton: UIButton!
    @IBOutlet var clearAllButton: UIButton!
    @IBOutlet var micActiveButton: UIButton!
    @IBOutlet var recordTimeLabel: UILabel!
    
    var emptyNode: SCNNode!

    var wantsRecording = false
    var sessionInProgress = false
    var recordStart: TimeInterval = 0
    var recordOrientation = UIDevice.current.orientation
    var isRecording = false {
        didSet {
            DispatchQueue.main.async {
                self.fpsButton.isEnabled = !self.isRecording
            }
        }
    }
    
    var ourEpoch: Int = 0
    var recordingDir: URL? = nil
    
    var fps: UInt = 60
    var micActive: Bool = true
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
        
        guard let emptyUrl = Bundle.main.url(forResource: "empty", withExtension: "usdz") else { fatalError() }
        emptyNode = SCNNode(mdlObject: MDLAsset(url: emptyUrl).object(at: 0))
        emptyNode.enumerateHierarchy { node, _rest in
            if node.name == "TapTarget" {
                node.categoryBitMask = trackedNodeBitmask
                node.isHidden = true
                return
            }
            node.geometry?.materials = (node.geometry?.materials ?? []).map({ mat in
                mat.lightingModel = .constant
                return mat
            })
        }

        // Set the view's delegate
        sceneView.delegate = self

        recordButton.isHidden = false
        recordingButton.isHidden = true
        
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))

        afButton.setTitle(kAutofocusON, for: .normal)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Remove any existing tracked AR stuff
        trackedNodes.forEach { $0.removeFromParentNode() }
        trackedNodes.removeAll()
        //planeAnchors.removeAll(keepingCapacity: true)
        horizontalPlaneNodes.removeAll(keepingCapacity: true)
        verticalPlaneNodes.removeAll(keepingCapacity: true)
        
        rebuildARSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Pause the view's session
        sceneView.session.pause()
    }

    func rebuildARSession() {
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.isAutoFocusEnabled = afButton.title(for: .normal) == kAutofocusON
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
    
    func hideUI() {
        recordButton.isHidden = true
        recordingButton.isHidden = true
        fpsButton.isHidden = true
        hideButton.isHidden = true
        afButton.isHidden = true
        clearAllButton.isHidden = true
        micActiveButton.isHidden = true
        recordTimeLabel.isHidden = true
    }

    func showUI() {
        recordButton.isHidden = isRecording
        recordingButton.isHidden = !isRecording
        fpsButton.isHidden = false
        hideButton.isHidden = false
        afButton.isHidden = false
        clearAllButton.isHidden = false
        micActiveButton.isHidden = false
        recordTimeLabel.isHidden = false
    }

    // MARK: - UITapGestureRecognizer
    
    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        // If the UI is hidden, then tapping unhides it and does nothing else
        if hideButton.isHidden {
            showUI()
            return
        }

        let loc = gesture.location(in: sceneView)

        // First, see if it hits anything in the scene
        if let hitResult = sceneView.hitTest(loc, options: [.categoryBitMask: trackedNodeBitmask, .boundingBoxOnly: true, .ignoreHiddenNodes: false]).first {
            var tmpNode = hitResult.node
            while let tmp = tmpNode.parent, tmp.parent != nil {
                tmpNode = tmp
            }
            if let idx = trackedNodes.firstIndex(of: tmpNode) {
                trackedNodes.remove(at: idx)
                tmpNode.removeFromParentNode()
                clearAllButton.isHidden = trackedNodes.count == 0
                return
            }
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

        let node = emptyNode.clone()
        sceneView.scene.rootNode.addChildNode(node)
        node.simdTransform = result.worldTransform
        trackedNodes.append(node)
        clearAllButton.isHidden = false
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

    @IBAction @objc func handleHideButtonTap() {
        hideUI()
    }

    @IBAction @objc func handleAFButtonTap() {
        let wasOn = afButton.title(for: .normal) == kAutofocusON
        afButton.setTitle(wasOn ? kAutofocusOFF : kAutofocusON, for: .normal)
        rebuildARSession()
    }

    @IBAction @objc func handleFpsButtonTap() {
        if fps > 30 {
            fps = 30
            sceneView.preferredFramesPerSecond = 30
        } else {
            fps = 60
            sceneView.preferredFramesPerSecond = 60
        }
        fpsButton.setTitle("\(fps)fps", for: .normal)
    }

    @IBAction @objc func handleClearAllTap() {
        trackedNodes.forEach { $0.removeFromParentNode() }
        trackedNodes.removeAll()
        clearAllButton.isHidden = true
    }

    @IBAction @objc func handleMicButtonTap() {
        micActive = !micActive
        micActiveButton.setImage(UIImage(systemName: micActive ? "mic.circle.fill" : "mic.slash.circle"), for: .normal)
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

        recordTimeLabel.text = "0:00:00"
        recordTimeLabel.isHidden = false
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
        videoSessionRGB = VideoSession(pixelBuffer: frame.capturedImage, outputURL: outputURL, startTime: time, fps: fps, depth: false, recordMic: micActive)
        videoSessionDepth = VideoSession(pixelBuffer: sceneDepth, outputURL: outputURLDepth, startTime: time, fps: fps, depth: true)
        videoSessionSegmentation = VideoSession(pixelBuffer: estimatedDepth, outputURL: outputURLSegmentation, startTime: time, fps: fps, depth: true)
        projectionMatrix = simd_float4x4(projectionTransform)
        cameraTransforms.removeAll(keepingCapacity: true)
        timestamps.removeAll(keepingCapacity: true)
        lensDatas.removeAll(keepingCapacity: true)
        //planeAnchors.removeAll(keepingCapacity: false)
        recordStart = time
        recordOrientation = UIDevice.current.orientation
        sessionInProgress = false

        isRecording = true
    }
    
    func updateRecording(_ renderer: SCNSceneRenderer, _ time: TimeInterval) {
        guard let frame = sceneView.session.currentFrame,
              let pov = renderer.pointOfView,
              let _ = frame.estimatedDepthData else {
            return
        }
        
        if wantsRecording {
            wantsRecording = false
            startRecording(renderer, frame, time)
        }
        if !isRecording {
            return
        }

        let runTime = time - recordStart

        // Count-up label
        let labelTime = NSInteger(runTime)
        let ms = Int((runTime.truncatingRemainder(dividingBy: 1)) * 100)
        let seconds = labelTime % 60
        let minutes = (labelTime / 60) % 60
        let labelText = String(format: "%02d:%02d.%02d", minutes, seconds, ms)
        DispatchQueue.main.async {
            self.recordTimeLabel.text = labelText
        }

        // Saved data for .bren file
        timestamps.append(Float(runTime))
        cameraTransforms.append(pov.simdTransform)

        let filmHeight = recordOrientation == .portrait ? 36.0 : 24.0
        let sensorHeight = recordOrientation == .portrait ? frame.camera.imageResolution.width : frame.camera.imageResolution.height
        let focalLength = CGFloat(frame.camera.intrinsics[1, 1]) * (filmHeight / sensorHeight)
        lensDatas.append(BrenLensData(focalLength: focalLength, sensorHeight: filmHeight))

        // Capture video frames
        videoSessionRGB?.addFrame(timestamp: time, image: frame.capturedImage)
        if let sceneDepth = frame.sceneDepth?.depthMap {
            videoSessionDepth?.addFrame(timestamp: time, image: sceneDepth)
        }
        if let estimatedDepth = frame.estimatedDepthData {
            videoSessionSegmentation?.addFrame(timestamp: time, image: estimatedDepth)
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
    
    func writeARWorldMap() {
        guard let recordDir = recordingDir else {
            print("ERROR: Cannot save brenfile with nil recordingDir")
            return
        }
        let outputURL = URL(fileURLWithPath: "\(ourEpoch)-environment.arworldmap", relativeTo: recordDir)

        sceneView.session.getCurrentWorldMap { (worldMap, error) in
            guard let worldMap = worldMap else {
                print("Could not get ARWorldMap to save: \(String(describing: error?.localizedDescription))")
                return
            }
            guard let data = try? NSKeyedArchiver.archivedData(withRootObject: worldMap, requiringSecureCoding: true) else {
                print("Could not encode ARWorldMap using NSKeyedArchiver")
                return
            }
            try? data.write(to: outputURL)
            print("Finished writing .arworldmap")
        }
    }

    func writeBrenfile() {
        guard let recordDir = recordingDir else {
            print("ERROR: Cannot save brenfile with nil recordingDir")
            return
        }
        
        var videoX = videoSessionRGB!.videoResolutionX
        var videoY = videoSessionRGB!.videoResolutionY
        if recordOrientation == .portrait {
            let tmp = videoX
            videoX = videoY
            videoY = tmp
        }
        let renderData = BrenRenderData(
            orientation: UInt(recordOrientation.rawValue),
            fps: fps,
            viewResolutionX: viewResolutionX,
            viewResolutionY: viewResolutionY,
            videoResolutionX: videoX,
            videoResolutionY: videoY
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
        recordTimeLabel.isHidden = true
        isRecording = false
        sessionInProgress = false
        videoSessionRGB?.finish {
            self.videoSessionDepth?.finish {
                self.videoSessionSegmentation?.finish {
                    print("Finished writing .mp4s")
                    self.writeARWorldMap()
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
            material.diffuse.contents = UIColor.init(white: CGFloat(1), alpha: CGFloat(1))
            material.fillMode = .lines
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
    
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        guard let _ = anchor as? ARPlaneAnchor, let extentNode = node.childNodes.first else { return }
        var found = false
        if let idx = horizontalPlaneNodes.firstIndex(of: extentNode) {
            horizontalPlaneNodes.remove(at: idx)
            found = true
        }
        if let idx = verticalPlaneNodes.firstIndex(of: extentNode) {
            verticalPlaneNodes.remove(at: idx)
            found = true
        }
        if found {
            node.removeFromParentNode()
        }
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
