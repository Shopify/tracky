//
//  VideoSession.swift
//  Tracky
//
//  Created by Eric Florenzano on 2/3/23.
//

import UIKit
import SceneKit
import ARKit
import AVFoundation
import ARKit
import CoreImage

class VideoSession: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    var fps: UInt
    var outputURL: URL
    var startTime: TimeInterval
    var latestTime: CMTime
    var depth: Bool
    var recordMic: Bool
    var videoResolutionX: UInt
    var videoResolutionY: UInt
    var assetWriter: AVAssetWriter
    var assetWriterPixelBufferInput: AVAssetWriterInputPixelBufferAdaptor
    var ciContext: CIContext? = nil

    var audioQueue: DispatchQueue? = nil
    var audioSession: AVCaptureSession? = nil
    var audioInput: AVAssetWriterInput? = nil
    var audioOutput: AVCaptureAudioDataOutput? = nil

    init(pixelBuffer: CVPixelBuffer, outputURL: URL, startTime: TimeInterval, fps: UInt = 60, depth: Bool, recordMic: Bool = false) {
        // Assign all of the properties that were passed in to the initializer
        self.fps = fps
        self.outputURL = outputURL
        self.startTime = startTime
        self.latestTime = CMTimeMakeWithSeconds(0, preferredTimescale: Int32(fps) * 10)
        self.depth = depth
        self.recordMic = recordMic

        // Get the width and height of the video by analyzing the pixel buffer
        videoResolutionX = UInt(CVPixelBufferGetWidthOfPlane(pixelBuffer, 0))
        videoResolutionY = UInt(CVPixelBufferGetHeightOfPlane(pixelBuffer, 0))

        // If we're writing depth, we need CoreImage to convert to a depth format that
        // the asset writer can handle, so initialize it upfront
        if (depth) {
            ciContext = CIContext()
        }

        // Create an asset writer to write out an mp4 video file
        assetWriter = try! AVAssetWriter(outputURL: outputURL, fileType: AVFileType.mp4)

        // Set the resolution and codec configuration of the mp4 file writer
        let assetWriterVideoInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: videoResolutionX,
            AVVideoHeightKey: videoResolutionY,
        ] as [String : Any])
        assetWriterVideoInput.expectsMediaDataInRealTime = true
        assetWriter.add(assetWriterVideoInput)

        // Set up an encoder for the video frames
        assetWriterPixelBufferInput = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterVideoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: videoResolutionX,
            kCVPixelBufferHeightKey as String: videoResolutionY
        ])

        // If we're recording mic audio, we have a number of additional things to set up,
        // starting by finding an appropriate microphone device
        if recordMic,
           let device = AVCaptureDevice.default(.builtInMicrophone, for: AVMediaType.audio, position: .unspecified) {
            // Set up a background audio queue to offload sample processing
            audioQueue = DispatchQueue(label: "com.shopify.Tracky.AudioQueue")

            // Create an audio capture session
            audioSession = AVCaptureSession()

            // Add the microphone input to the audio capture session
            do {
                let micInput = try AVCaptureDeviceInput(device: device)
                if audioSession?.canAddInput(micInput) == true {
                    audioSession?.addInput(micInput)
                }
            } catch {
                print("ERROR [tryAddAudioInput]: \(error)")
            }

            // Create an audio output and add it to the audio capture session.
            // Right now this output is not connected to anything
            let output = AVCaptureAudioDataOutput()
            audioOutput = output
            if audioSession?.canAddOutput(output) == true {
                audioSession?.addOutput(output)
            }

            // Create an audio input suitable for writing to an mp4 file
            audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: output.recommendedAudioSettingsForAssetWriter(writingTo: .mp4))
            audioInput?.expectsMediaDataInRealTime = true
        }

        super.init()

        if recordMic, let input = audioInput, let output = audioOutput, let queue = audioQueue {
            // Connect the mp4 audio input to the asset writer, so that it will mux with the video
            if assetWriter.canAdd(input) {
                assetWriter.add(input)
            }

            // This connects the output from the audio capture session to ourself, so that we
            // receive the `captureOutput` messages, and can process the audio before adding
            // it to the video stream
            output.setSampleBufferDelegate(self, queue: queue)

            // Start the microphone capture session from the audio queue
            queue.async { [weak self] in
                self?.audioSession?.startRunning()
            }
        }

        // Start writing out the video mp4 starting from time 0.00
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: CMTime.zero)
    }

    // Adds a new video frame to the running session
    func addFrame(timestamp: TimeInterval, image: CVPixelBuffer) {
        // Create a timestamp compatible with CoreMedia by taking the difference between
        // the current timestamp and the first timestamp, using the FPS to ensure proper
        // timescale
        let ts = CMTimeMakeWithSeconds(timestamp - startTime, preferredTimescale: Int32(fps) * 10)

        // Save a copy of this timestamp so that we can assign it to any audio that comes
        // in during this time
        latestTime = ts

        // Make sure the system isn't pushing back and telling us to wait for more data.
        // If it is, we drop this frame to give the system a chance to recover
        if !assetWriterPixelBufferInput.assetWriterInput.isReadyForMoreMediaData {
            print("Not ready for more media data: \(ts)")
            return
        }

        // This will store the final image after any conversion is done
        var finalImage: CVPixelBuffer!

        // If it's a depth image, we need to use CoreImage to convert it to a compatible format
        if depth {
            let ciImage = CIImage(cvPixelBuffer: image)
            let result = CVPixelBufferCreate(nil, Int(videoResolutionX), Int(videoResolutionY), kCVPixelFormatType_32ARGB, kDepthBufferCompat, &finalImage)
            if result != 0 {
                print("Error creating depth CVPixelBuffer, code: \(result)")
                return
            }
            ciContext?.render(ciImage, to: finalImage)
        } else {
            // Otherwise it's not depth, no conversion needed, so our final image is
            // just our input image
            finalImage = image
        }

        // Add the final image at the calculated timestamp to the asset writer
        if !assetWriterPixelBufferInput.append(finalImage, withPresentationTime: ts) {
            print("Could not append \(depth ? "depth" : "rgb") frame \(ts)")
        }
    }

    // Finish writing the video and then call the compltion handler
    func finish(completionHandler handler: (() -> Void)?) {
        assetWriter.finishWriting() {
            handler?()
        }
    }

    // MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Make sure that the `audioInput` has been set up, and grab a reference to the audio session
        guard let input = audioInput, let session = audioSession else { return }

        // We will be processing the audio sample-by-sample which may be computationally
        // expensive, so we send it to a separate audio queue so as not to block the UI
        // thread
        audioQueue?.async { [weak self] in

            // Make sure the session is still active and the input is ready for more data
            guard session.isRunning && input.isReadyForMoreMediaData else { return }

            // Count the number of samples in the incoming sample buffer
            var count: CMItemCount = 0
            CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
            // Get timing info for each sample in the incoming buffer
            var info = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(duration: CMTime.zero, presentationTimeStamp: CMTime.zero, decodeTimeStamp: CMTime.zero), count: count)
            CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: count, arrayToFill: &info, entriesNeededOut: &count)

            // Get the current video timecode, as set from the latest `addFrame` call
            guard let currentTime = self?.latestTime else { return }

            // Assign the current timecode for each sample in the buffer, so that they all align with the video frame
            for i in 0..<count {
                info[i].decodeTimeStamp = currentTime
                info[i].presentationTimeStamp = currentTime
            }

            // Construct a new sound buffer with the adjusted, time-matched timing info
            var soundbuffer:CMSampleBuffer?
            CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sampleBuffer, sampleTimingEntryCount: count, sampleTimingArray: &info, sampleBufferOut: &soundbuffer)
            // Add that new sound buffer to the audio input to be muxed with the mp4
            if let buf = soundbuffer {
                input.append(buf)
            }
        }
    }
}

let kDepthBufferCompat = [
    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
    kCVPixelBufferCGImageCompatibilityKey as String: true
] as CFDictionary
