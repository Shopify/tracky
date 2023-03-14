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

let kTrackedNodeBitmask: Int = 1 << 6
let kModelNodeBitmask: Int = 1 << 7

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate, UIDocumentPickerDelegate {
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet var recordButton: UIButton!
    @IBOutlet var recordingButton: UIButton!
    @IBOutlet var fpsButton: UIButton!
    @IBOutlet var hideButton: UIButton!
    @IBOutlet var afButton: UIButton!
    @IBOutlet var clearAllButton: UIButton!
    @IBOutlet var micActiveButton: UIButton!
    @IBOutlet var recordTimeLabel: UILabel!
    @IBOutlet var modelButton: UIButton!

    var modelNode: SCNNode? = nil
    var modelRotation: SCNVector3? = nil

    var emptyNode: SCNNode!

    var fps: UInt = 60
    var viewResolutionX: UInt = 0
    var viewResolutionY: UInt = 0
    var wantsRecording = false
    var isRecording = false {
        didSet {
            DispatchQueue.main.async {
                self.fpsButton.isEnabled = !self.isRecording
            }
        }
    }

    // A unique timestamp that helps end users identify all the files that tie together a session
    var ourEpoch: Int = 0
    // The directory where all the files will be saved
    var recordingDir: URL? = nil

    // A boolean indicating whether or not to record microphone audio when recording an AR session
    var micActive: Bool = true

    // Helpers to help encode the data from an ARKit frames into video and .bren files
    var videoSessionRGB: VideoSession? = nil
    var videoSessionDepth: VideoSession? = nil
    var videoSessionSegmentation: VideoSession? = nil
    var dataSession: DataSession? = nil

    // SceneKit variables that we're tracking, like horizontal planes, or tracked nodes
    var projectionMatrix = matrix_identity_float4x4
    var horizontalPlaneNodes: [SCNNode] = []
    var verticalPlaneNodes: [SCNNode] = []
    var trackedNodes: [SCNNode] = []

    // The running time in seconds of a recording session (dispatches an update to the UI label)
    var runTime: TimeInterval = 0 {
        didSet {
            let labelTime = NSInteger(runTime)
            let ms = Int((runTime.truncatingRemainder(dividingBy: 1)) * 100)
            let seconds = labelTime % 60
            let minutes = (labelTime / 60) % 60
            let labelText = String(format: "%02d:%02d.%02d", minutes, seconds, ms)
            DispatchQueue.main.async {
                self.recordTimeLabel.text = labelText
            }
        }
    }

    // We use this formatter to get a directory name from the current time
    let dateFormatter : DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yyyy_HH-mm-ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        // Load the "empty" node
        guard let emptyUrl = Bundle.main.url(forResource: "empty", withExtension: "usdz") else { fatalError() }
        emptyNode = SCNNode(mdlObject: MDLAsset(url: emptyUrl).object(at: 0))
        emptyNode.enumerateHierarchy { node, _rest in
            // The tap target is bigger than the display, so we hide it but we assign it the appropriate
            // bitmask that we can hit test against it later
            if node.name == "TapTarget" {
                node.categoryBitMask = kTrackedNodeBitmask
                node.isHidden = true
                return
            }
            // We don't want the "empty" model to have complex lighting, so we make sure all its materials
            // have a lighting model of .constant
            node.geometry?.materials = (node.geometry?.materials ?? []).map({ mat in
                mat.lightingModel = .constant
                return mat
            })
        }

        // Set the view's delegate
        sceneView.delegate = self

        // When the app starts, it's not recording
        recordButton.isHidden = false
        recordingButton.isHidden = true

        // Add a handler for non-UI taps (we'll raycast into the scene)
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))

        view.addGestureRecognizer(UIRotationGestureRecognizer(target: self, action: #selector(handleRotate)))

        // Set the default title on the auto-focus button
        afButton.setTitle(kAutofocusON, for: .normal)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Remove any existing tracked AR stuff
        trackedNodes.forEach { $0.removeFromParentNode() }
        trackedNodes.removeAll()
        horizontalPlaneNodes.removeAll(keepingCapacity: true)
        verticalPlaneNodes.removeAll(keepingCapacity: true)

        // Kick off the AR session (or rebuild it if it hasn't been started)
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

    // Hides all visible UI elements and only leaves the SceneKit view active
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

    // Shows all possible appropriate UI elements
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

    // MARK: - Button handlers

    // Toggles between recording and saving states
    @IBAction @objc func handleMainButtonTap() {
        recordButton.isHidden = !isRecording
        recordingButton.isHidden = isRecording
        if isRecording {
            stopRecording()
        } else {
            setWantsRecording()
        }
    }

    // Hides the UI
    @IBAction @objc func handleHideButtonTap() {
        hideUI()
    }

    // Toggles between autofocus on and off, and then cleanly transitions the AR session
    @IBAction @objc func handleAFButtonTap() {
        let wasOn = afButton.title(for: .normal) == kAutofocusON
        afButton.setTitle(wasOn ? kAutofocusOFF : kAutofocusON, for: .normal)
        rebuildARSession()
    }

    // Toggles between 30 and 60fps target (60fps target may not always be achievable at runtime)
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

    // Clears all tracked nodes
    @IBAction @objc func handleClearAllTap() {
        trackedNodes.forEach { $0.removeFromParentNode() }
        trackedNodes.removeAll()
        modelNode?.removeFromParentNode()
        modelNode = nil
        clearAllButton.isHidden = true
    }

    // Toggles between whether the microphone will be active or disabled during recording
    @IBAction @objc func handleMicButtonTap() {
        micActive = !micActive
        micActiveButton.setImage(UIImage(systemName: micActive ? "mic.circle.fill" : "mic.slash.circle"), for: .normal)
    }

    // Chooses a model to place in the scene
    @IBAction @objc func handleModelButtonTap() {
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.usdz])
        documentPicker.delegate = self
        documentPicker.modalPresentationStyle = .overFullScreen
        documentPicker.allowsMultipleSelection = false
        present(documentPicker, animated: true)
    }

    // MARK: - UIDocumentPickerDelegate Functions

    @objc(documentPicker:didPickDocumentAtURL:) func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        dismiss(animated: true)

        guard url.startAccessingSecurityScopedResource() else {
            return
        }

        defer {
            url.stopAccessingSecurityScopedResource()
        }

        let mdlAsset = MDLAsset(url: url)
        let scene = SCNScene(mdlAsset: mdlAsset)

        scene.rootNode.enumerateHierarchy { node, _rest in
            node.categoryBitMask = kModelNodeBitmask
        }

        modelButton.isEnabled = false
        modelNode = scene.rootNode
    }

    @objc func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        // Do we need to do anything here?
    }

    // MARK: - Recording Functions

    // Initiate the recording process, starting by capturing data from things that can only be
    // captured from the main thread, and then setting the `wantsRecording` boolean to true
    // in order to greenlight the next stage of the recording process
    func setWantsRecording() {
        fps = UInt(sceneView.preferredFramesPerSecond)
        if fps == 0 {
            fps = 60 // idk
        }
        let scl = UIScreen.main.scale
        viewResolutionX = UInt(view.frame.size.width * scl)
        viewResolutionY = UInt(view.frame.size.height * scl)

        recordTimeLabel.isHidden = false
        runTime = 0

        wantsRecording = true
    }

    // Starts the actual recording processes (not on UI thread)
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
        let recDir = URL(fileURLWithPath: "\(dirname)_\(ourEpoch)", isDirectory: true, relativeTo: documentsPath)
        do {
            try FileManager.default.createDirectory(at: recDir, withIntermediateDirectories: true)
        } catch {
            print("Could not create directory \(recDir)")
            return
        }
        recordingDir = recDir

        let dat = DataSession(startTime: time,
                              fps: fps,
                              viewResolutionX: viewResolutionX,
                              viewResolutionY: viewResolutionY,
                              outputURL: URL(fileURLWithPath: "\(ourEpoch)-camera.bren", relativeTo: recDir))
        dataSession = dat

        videoSessionRGB = VideoSession(pixelBuffer: frame.capturedImage,
                                       startTime: time,
                                       fps: dat.fps,
                                       depth: false,
                                       recordMic: micActive,
                                       outputURL: URL(fileURLWithPath: "\(ourEpoch)-video.mp4", relativeTo: recDir))
        videoSessionDepth = VideoSession(pixelBuffer: sceneDepth,
                                         startTime: time,
                                         fps: dat.fps,
                                         depth: true,
                                         recordMic: false,
                                         outputURL: URL(fileURLWithPath: "\(ourEpoch)-depth.mp4", relativeTo: recDir))
        videoSessionSegmentation = VideoSession(pixelBuffer: estimatedDepth,
                                                startTime: time,
                                                fps: dat.fps,
                                                depth: true,
                                                recordMic: false,
                                                outputURL: URL(fileURLWithPath: "\(ourEpoch)-segmentation.mp4", relativeTo: recDir))

        projectionMatrix = simd_float4x4(projectionTransform)
        isRecording = true
    }

    // Captures an AR frame into the recording session
    func updateRecording(_ renderer: SCNSceneRenderer, _ time: TimeInterval) {
        guard let frame = sceneView.session.currentFrame else { return }
        
        if wantsRecording {
            wantsRecording = false
            startRecording(renderer, frame, time)
        }
        if !isRecording {
            return
        }

        guard let dataSession = dataSession,
              let pov = renderer.pointOfView else { return }

        dataSession.addFrame(time: time, cameraTransform: pov.simdTransform, resolution: frame.camera.imageResolution, intrinsics: frame.camera.intrinsics)

        // Capture video frames
        videoSessionRGB?.addFrame(timestamp: time, image: frame.capturedImage)
        if let sceneDepth = frame.sceneDepth?.depthMap {
            videoSessionDepth?.addFrame(timestamp: time, image: sceneDepth)
        }
        if let estimatedDepth = frame.estimatedDepthData {
            videoSessionSegmentation?.addFrame(timestamp: time, image: estimatedDepth)
        }

        runTime = dataSession.runTime
    }

    // Grabs the ARWorldMap from the ARKit session and writes it to the recording directory
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

    // Gathers all the available information and writes out the .bren file with all the tracked transforms
    func writeBrenfile() {
        guard let dataSession = dataSession,
              let videoSessionRGB = videoSessionRGB else {
            return
        }
        
        var planes: [BrenPlane] = []
        for extentNode in horizontalPlaneNodes {
            planes.append(BrenPlane(transform: extentNode.simdWorldTransform, alignment: "horizontal"))
        }
        for extentNode in verticalPlaneNodes {
            planes.append(BrenPlane(transform: extentNode.simdWorldTransform, alignment: "vertical"))
        }
        let trackedTransforms = trackedNodes.map { $0.simdTransform }

        if !dataSession.write(videoSessionRGB: videoSessionRGB, planes: planes, trackedTransforms: trackedTransforms) {
            print("Could not write .bren file")
        }
    }

    // Stops the recording process and writes out all the relevant files
    func stopRecording() {
        recordTimeLabel.isHidden = true
        isRecording = false
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

    // MARK: - UITapGestureRecognizer

    // Handle non-UI taps
    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        // If the UI is hidden, then tapping unhides it and does nothing else
        if hideButton.isHidden {
            showUI()
            return
        }

        let loc = gesture.location(in: sceneView)

        // First, see if it hits any tracked empties
        if let hitResult = sceneView.hitTest(loc, options: [.categoryBitMask: kTrackedNodeBitmask, .boundingBoxOnly: true, .ignoreHiddenNodes: false]).first {
            var tmpNode = hitResult.node
            while let tmp = tmpNode.parent, tmp.parent != nil {
                tmpNode = tmp
            }
            if let idx = trackedNodes.firstIndex(of: tmpNode) {
                trackedNodes.remove(at: idx)
                tmpNode.removeFromParentNode()
                clearAllButton.isHidden = trackedNodes.count == 0 && modelNode == nil
                return
            }
        }

        // Next, see if it hits the model node
        if let _ = sceneView.hitTest(loc, options: [.categoryBitMask: kModelNodeBitmask, .boundingBoxOnly: false, .ignoreHiddenNodes: true]).first {
            modelNode?.removeFromParentNode()
            modelNode = nil
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

        // If we have a model node and the button is disabled, that's because we're ready
        // to place the current model node
        if let node = modelNode, !modelButton.isEnabled {
            node.removeFromParentNode()
            sceneView.scene.rootNode.addChildNode(node)
            node.simdTransform = result.worldTransform
            modelButton.isEnabled = true
            clearAllButton.isHidden = false
            return
        }

        let node = emptyNode.clone()
        sceneView.scene.rootNode.addChildNode(node)
        node.simdTransform = result.worldTransform
        trackedNodes.append(node)
        clearAllButton.isHidden = false
    }

    // MARK: - UIRotationGestureRecognizer

    @objc func handleRotate(_ gesture: UIRotationGestureRecognizer) {
        guard let node = modelNode else { return }
        switch gesture.state {
        case .began:
            modelRotation = node.eulerAngles
        case .changed:
            guard var modelRotationOrig = modelRotation else { return }
            modelRotationOrig.y -= Float(gesture.rotation)
            node.eulerAngles = modelRotationOrig
        default:
            modelRotation = nil
        }
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
    }
    
    // MARK: - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        updateRecording(renderer, time)
    }

    // Whenever a new ARKit tracked plane is detected, add it to the scene
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

    // Whenever a ARKit tracked plane is updated, update its SceneKit node to match
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor,
            let extentNode = node.childNodes.first
            else { return }
        
        extentNode.simdPosition = planeAnchor.center
        extentNode.eulerAngles.y = planeAnchor.planeExtent.rotationOnYAxis
        extentNode.simdScale.x = planeAnchor.planeExtent.width
        extentNode.simdScale.y = planeAnchor.planeExtent.height
    }

    // Whenever ARKit loses track of a plane, remove it from SceneKit and our tracking as well
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
