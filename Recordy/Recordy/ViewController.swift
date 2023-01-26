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
    @IBOutlet var recordIndicator: UIView!
    
    var assetWriter: AVAssetWriter!
    var assetWriterPixelBufferInput: AVAssetWriterInputPixelBufferAdaptor!
    var wantsRecording = false
    var isRecording = false
    var sessionInProgress = false
    var recordStart: TimeInterval = 0
    
    var recordingDir: URL? = nil
    
    var fps: UInt = 60
    var viewResolutionX: UInt = 1
    var viewResolutionY: UInt = 1
    var videoResolutionX: UInt = 1
    var videoResolutionY: UInt = 1
    
    var timestamps: [Float] = []
    var projectionMatrix = matrix_identity_float4x4
    var cameraTransforms: [simd_float4x4] = []
    var lensDatas: [BrenLensData] = []
    var lowestPlane: ARPlaneAnchor? = nil
    
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
        
        recordIndicator.isHidden = true
        
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        configuration.isAutoFocusEnabled = true
        configuration.sceneReconstruction = .meshWithClassification
        configuration.environmentTexturing = .automatic
        configuration.isLightEstimationEnabled = true
        configuration.videoHDRAllowed = false
        
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
        DispatchQueue.main.async {
            self.recordIndicator.isHidden = false
        }
        guard let capturedImage = sceneView.session.currentFrame?.capturedImage else {
            print("ERROR: Could not start recording when ARFrame has no captured image")
            return
        }
        guard let projectionTransform = renderer.pointOfView?.camera?.projectionTransform else {
            print("ERROR: Could not get renderer pov camera")
            return
        }
        let width = CVPixelBufferGetWidthOfPlane(capturedImage, 0)
        let height = CVPixelBufferGetHeightOfPlane(capturedImage, 0)
        videoResolutionX = UInt(width)
        videoResolutionY = UInt(height)
        print("Video Width: \(width) x Height: \(height)")
        guard let documentsPath = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            print("ERROR: Could not get documents path")
            return
        }
        let dirname = dateFormatter.string(from: Date.now)
        let recDir = URL(fileURLWithPath: dirname, isDirectory: true, relativeTo: documentsPath)
        do {
            try FileManager.default.createDirectory(at: recDir, withIntermediateDirectories: true)
        } catch {
            print("Could not create directory \(recDir)")
            return
        }
        recordingDir = recDir
        let outputURL = URL(fileURLWithPath: "video.mp4", relativeTo: recDir)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        assetWriter = try! AVAssetWriter(outputURL: outputURL, fileType: AVFileType.mp4)
        let outputSettings = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ] as [String : Any]
        let assetWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: outputSettings)
        assetWriterInput.expectsMediaDataInRealTime = true
        assetWriter.add(assetWriterInput)
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        assetWriterPixelBufferInput = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterInput, sourcePixelBufferAttributes: pixelBufferAttributes)
        projectionMatrix = simd_float4x4(projectionTransform)
        cameraTransforms.removeAll(keepingCapacity: true)
        timestamps.removeAll(keepingCapacity: true)
        lensDatas.removeAll(keepingCapacity: true)
        lowestPlane = nil
        sessionInProgress = false
        assetWriter.startWriting()
        isRecording = true
    }
    
    func updateRecording(_ renderer: SCNSceneRenderer, _ time: TimeInterval) {
        guard let frame = sceneView.session.currentFrame,
              let pov = renderer.pointOfView,
              let cam = pov.camera else {
            return
        }
        let hasCapturedImage = sceneView.session.currentFrame?.capturedImage != nil
        if wantsRecording && hasCapturedImage {
            wantsRecording = false
            startRecording(renderer, frame, time)
        }
        if isRecording {
            if assetWriterPixelBufferInput.assetWriterInput.isReadyForMoreMediaData {
                let ctime: TimeInterval
                if !sessionInProgress {
                    ctime = 0
                    recordStart = time
                    assetWriter.startSession(atSourceTime: CMTimeMakeWithSeconds(ctime, preferredTimescale: 600))
                    sessionInProgress = true
                } else {
                    ctime = time - recordStart
                }
                assetWriterPixelBufferInput.append(frame.capturedImage, withPresentationTime: CMTimeMakeWithSeconds(ctime, preferredTimescale: 600))
                timestamps.append(Float(ctime))
                cameraTransforms.append(pov.simdTransform)
                lensDatas.append(BrenLensData(
                    fov: cam.fieldOfView,
                    focalLength: cam.focalLength,
                    sensorHeight: cam.sensorHeight,
                    zNear: cam.zNear,
                    zFar: cam.zFar,
                    focusDistance: cam.focusDistance,
                    orientation: UIDevice.current.orientation.rawValue
                ))
            }
        }
    }
    
    func writeBrenfile() {
        guard let recordDir = recordingDir else {
            print("ERROR: Cannot save brenfile with nil recordingDir")
            return
        }
        
        var tfms: [simd_float4x4]
        if let plane = lowestPlane {
            print("Doing plane transformation")
            let tmp = SCNNode()
            tmp.simdTransform = plane.transform
            sceneView.scene.rootNode.addChildNode(tmp) // Necessary?
            tfms = cameraTransforms.map({ tfm in return tmp.simdConvertTransform(tfm, from: nil) })
            tmp.removeFromParentNode() // Necessary?
        } else {
            tfms = cameraTransforms
        }
        
        let renderData = BrenRenderData(
            fps: fps,
            viewResolutionX: viewResolutionX,
            viewResolutionY: viewResolutionY,
            videoResolutionX: videoResolutionX,
            videoResolutionY: videoResolutionY
        )
        let cameraFrames = BrenCameraFrames(timestamps: timestamps, transforms: tfms, datas: lensDatas)
        let data = BrenWrapper(renderData, cameraFrames)
        let jsonEncoder = JSONEncoder()
        guard let jsonData = try? jsonEncoder.encode(data),
              let json = String(data: jsonData, encoding: String.Encoding.utf8) else {
            print("ERROR: Could not encode json data")
            return
        }
        
        let outputURL = URL(fileURLWithPath: "camera.bren", relativeTo: recordDir)
        do {
            try json.write(to: outputURL, atomically: true, encoding: String.Encoding.utf8)
            print("Finished writing .bren")
        } catch {
            // TODO: Print error message
        }
    }
    
    func stopRecording() {
        DispatchQueue.main.async {
            self.recordIndicator.isHidden = true
        }
        isRecording = false
        sessionInProgress = false
        assetWriter.finishWriting {
            print("Finished writing .mp4")
            self.writeBrenfile()
            // TODO: Write out view matrices
            // Handle finishing of writing here
            return
        }
    }
    // MARK: - ARSessionDelegate
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        lowestPlane = frame.anchors
            .filter { anchor in anchor is ARPlaneAnchor }
            .map { anchor in anchor as! ARPlaneAnchor }
            .sorted { a, b in a.transform.columns.3.y < b.transform.columns.3.y }
            .first
    }
    
    // MARK: - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        updateRecording(renderer, time)
    }
    
    /*
     // Override to create and configure nodes for anchors added to the view's session.
     func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
     let node = SCNNode()
     
     return node
     }
     */
    
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
