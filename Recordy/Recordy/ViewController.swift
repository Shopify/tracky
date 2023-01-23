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
    var assetWriter: AVAssetWriter!
    var assetWriterPixelBufferInput: AVAssetWriterInputPixelBufferAdaptor!
    var wantsRecording = false
    var isRecording = false
    var recordStart: TimeInterval = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view's delegate
        sceneView.delegate = self
        
        // Show statistics such as fps and timing information
        sceneView.showsStatistics = true

        // Start the AVAssetWriter
        startRecording()
        
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
        print("Stopping recording")
        stopRecording()
    }

    // MARK: Recording Functions
    
    func startRecording() {
        print("Starting recording")
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
            AVVideoWidthKey: 1920,
            AVVideoHeightKey: 1080
        ] as [String : Any]
        let assetWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: outputSettings)
        assetWriterInput.expectsMediaDataInRealTime = true
        assetWriter.add(assetWriterInput)
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 1920,
            kCVPixelBufferHeightKey as String: 1080
        ]
        assetWriterPixelBufferInput = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterInput, sourcePixelBufferAttributes: pixelBufferAttributes)
        assetWriter.startWriting()
        wantsRecording = true
    }
    
    func updateRecording(_ time: TimeInterval) {
        let ptime = CMTimeMakeWithSeconds(time, preferredTimescale: 600)
        if wantsRecording {
            wantsRecording = false
            isRecording = true
            recordStart = time
            assetWriter.startSession(atSourceTime: ptime)
        }
        if isRecording {
            if assetWriterPixelBufferInput.assetWriterInput.isReadyForMoreMediaData,
               let pixelBuffer = sceneView.session.currentFrame?.capturedImage {
                assetWriterPixelBufferInput.append(pixelBuffer, withPresentationTime: ptime)
            }
        }
    }

    func stopRecording() {
        isRecording = false
        assetWriter.finishWriting {
            print("Finished writing file")
            // Handle finishing of writing here
        }
    }
    
    // MARK: - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        updateRecording(time)
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
