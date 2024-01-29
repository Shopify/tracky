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
    @IBOutlet var recordTimeLabel: UILabel!

    var fps: UInt = 60
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

    // Helpers to help encode the data from an ARKit frames into video and .json files
    var videoSessionRGB: VideoSession? = nil
    var dataSession: DataSession? = nil

    // SceneKit variables that we're tracking, like horizontal planes, or tracked nodes
    var projectionMatrix = matrix_identity_float4x4
    var horizontalPlaneNodes: [SCNNode] = []
    var verticalPlaneNodes: [SCNNode] = []

    var picking: String? = nil

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

        // Set the view's delegate
        sceneView.delegate = self

        // When the app starts, it's not recording
        recordButton.isHidden = false
        recordingButton.isHidden = true

        // Add a handler for non-UI taps (we'll raycast into the scene)
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))

        // Set the default title on the auto-focus button
        afButton.setTitle(kAutofocusON, for: .normal)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Remove any existing tracked AR stuff
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
        //recordTimeLabel.isHidden = false
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
        clearAllButton.isHidden = true
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

        recordTimeLabel.isHidden = false
        runTime = 0

        wantsRecording = true
    }

    // Starts the actual recording processes (not on UI thread)
    func startRecording(_ renderer: SCNSceneRenderer, _ frame: ARFrame, _ time: TimeInterval) {
        guard let projectionTransform = renderer.pointOfView?.camera?.projectionTransform else {
            print("*** ERROR: Could not get renderer pov camera")
            return
        }
        guard let documentsPath = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            print("*** ERROR: Could not get documents path")
            return
        }
        let dirname = dateFormatter.string(from: Date.now)
        ourEpoch = Int(Date.now.timeIntervalSince1970) - 1676000000
        let recDir = URL(fileURLWithPath: "\(dirname)_\(ourEpoch)", isDirectory: true, relativeTo: documentsPath)
        do {
            try FileManager.default.createDirectory(at: recDir, withIntermediateDirectories: true)
        } catch {
            print("*** Could not create directory \(recDir)")
            return
        }
        recordingDir = recDir

        // Create the keyframes directory
        let keyframesDir = recDir.appendingPathComponent("keyframes", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: keyframesDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("*** Could not create directory \(keyframesDir)")
            return
        }

        // Create the images directory
        let imagesDir = keyframesDir.appendingPathComponent("images", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("*** Could not create directory \(imagesDir)")
            return
        }
        
        let dat = DataSession(startTime: time,
                              fps: fps,
                              outputURL: URL(fileURLWithPath: "\(ourEpoch)-camera.json", relativeTo: recDir))
        dataSession = dat

        videoSessionRGB = VideoSession(pixelBuffer: frame.capturedImage,
                                       startTime: time,
                                       fps: dat.fps,
                                       videoURL: URL(fileURLWithPath: "\(ourEpoch)-video.mp4", relativeTo: recDir),
                                       imagesURL: imagesDir)

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

        dataSession.addFrame(
            time: time,
            cameraTransform: pov.simdTransform,
            intrinsics: frame.camera.intrinsics,
            videoResolutionX: videoSessionRGB?.videoResolutionX ?? 0,
            videoResolutionY: videoSessionRGB?.videoResolutionY ?? 0
        )

        // Capture video frames
        videoSessionRGB?.addFrame(timestamp: time, image: frame.capturedImage)

        runTime = dataSession.runTime
    }

    // Grabs the ARWorldMap from the ARKit session and writes it to the recording directory
    func writeARWorldMap() {
        guard let recordDir = recordingDir else {
            print("*** ERROR: Cannot save brenfile with nil recordingDir")
            return
        }
        let outputURL = URL(fileURLWithPath: "\(ourEpoch)-environment.arworldmap", relativeTo: recordDir)

        sceneView.session.getCurrentWorldMap { (worldMap, error) in
            guard let worldMap = worldMap else {
                print("*** Could not get ARWorldMap to save: \(String(describing: error?.localizedDescription))")
                return
            }
            guard let data = try? NSKeyedArchiver.archivedData(withRootObject: worldMap, requiringSecureCoding: true) else {
                print("*** Could not encode ARWorldMap using NSKeyedArchiver")
                return
            }
            try? data.write(to: outputURL)
            print("*** Finished writing .arworldmap")
        }
    }

    // Gathers all the available information and writes out the .json file with all the tracked transforms
    func writeBrenfile() {
        guard let dataSession = dataSession,
              let videoSessionRGB = videoSessionRGB else {
            return
        }
        
        if !dataSession.write(videoSessionRGB: videoSessionRGB) {
            print("*** Could not write .json file")
        }
    }

    // Stops the recording process and writes out all the relevant files
    func stopRecording() {
        recordTimeLabel.isHidden = true
        isRecording = false
        videoSessionRGB?.finish {
            print("*** Finished writing .mp4")
            self.writeARWorldMap()
            self.writeBrenfile()
            self.videoSessionRGB = nil
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
