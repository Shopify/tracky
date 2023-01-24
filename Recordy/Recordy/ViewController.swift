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

class ViewController: UIViewController, ARSCNViewDelegate {
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet var recordIndicator: UIView!
    var assetWriter: AVAssetWriter!
    var assetWriterPixelBufferInput: AVAssetWriterInputPixelBufferAdaptor!
    var wantsRecording = false
    var isRecording = false
    var recordStart: TimeInterval = 0

    // In-memory recording for now
    var projectionMatrix = matrix_identity_float4x4
    var viewMatrices: [simd_float4x4] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view's delegate
        sceneView.delegate = self
        
        // Show statistics such as fps and timing information
        sceneView.showsStatistics = true

        wantsRecording = true
        recordIndicator.isHidden = true
        
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()

        // Run the view's session
        sceneView.session.run(configuration)
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
            wantsRecording = true
        }
    }

    // MARK: Recording Functions
    
    func startRecording(_ renderer: SCNSceneRenderer, _ frame: ARFrame, _ time: TimeInterval) {
        print("Starting recording")
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
        print("Width: \(width) x Height: \(height)")
        guard let documentsPath = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            print("ERROR: Could not get documents path")
            return
        }
        let outputURL = URL(fileURLWithPath: "recorded_ar_video.mp4", relativeTo: documentsPath)
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
        assetWriterInput.transform = .init(rotationAngle: .pi/2)
        assetWriter.add(assetWriterInput)
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        assetWriterPixelBufferInput = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterInput, sourcePixelBufferAttributes: pixelBufferAttributes)
        assetWriter.startWriting()
        projectionMatrix = simd_float4x4(projectionTransform)
        viewMatrices.removeAll(keepingCapacity: true)
        recordStart = time
        isRecording = true
    }
    
    func updateRecording(_ renderer: SCNSceneRenderer, _ time: TimeInterval) {
        guard let frame = sceneView.session.currentFrame,
            let pov = renderer.pointOfView else {
            return
        }
        let ptime = CMTimeMakeWithSeconds(time, preferredTimescale: 600)
        let hasCapturedImage = sceneView.session.currentFrame?.capturedImage != nil
        if wantsRecording && hasCapturedImage {
            wantsRecording = false
            startRecording(renderer, frame, time)
            assetWriter.startSession(atSourceTime: ptime)
        }
        if isRecording {
            if assetWriterPixelBufferInput.assetWriterInput.isReadyForMoreMediaData {
                assetWriterPixelBufferInput.append(frame.capturedImage, withPresentationTime: ptime)
                viewMatrices.append(simd_inverse(pov.simdTransform))
                // TODO: Record object positions?
            }
        }
    }

    func stopRecording() {
        DispatchQueue.main.async {
            self.recordIndicator.isHidden = true
        }
        isRecording = false
        assetWriter.finishWriting {
            print("Finished writing file")
            print("View matrix count: \(self.viewMatrices.count)")
            // TODO: Write out view matrices
            // Handle finishing of writing here
        }
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
