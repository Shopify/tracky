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

// Helper class for capturing an ARKit video stream to disk
class VideoSession: NSObject {
    var fps: UInt
    var outputURL: URL
    var startTime: TimeInterval
    var depth: Bool
    var videoResolutionX: UInt
    var videoResolutionY: UInt
    var assetWriter: AVAssetWriter
    var assetWriterPixelBufferInput: AVAssetWriterInputPixelBufferAdaptor
    var ciContext: CIContext? = nil

    init(pixelBuffer: CVPixelBuffer, startTime: TimeInterval, fps: UInt = 60, depth: Bool, outputURL: URL) {
        // Assign all of the properties that were passed in to the initializer
        self.fps = fps
        self.outputURL = outputURL
        self.startTime = startTime
        self.depth = depth

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

        super.init()

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
}

let kDepthBufferCompat = [
    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
    kCVPixelBufferCGImageCompatibilityKey as String: true
] as CFDictionary
