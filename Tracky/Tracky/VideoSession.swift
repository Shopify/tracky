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
    var videoResolutionX: UInt
    var videoResolutionY: UInt
    var assetWriter: AVAssetWriter
    var assetWriterPixelBufferInput: AVAssetWriterInputPixelBufferAdaptor

    init(pixelBuffer: CVPixelBuffer, startTime: TimeInterval, fps: UInt = 60, outputURL: URL) {
        // Assign all of the properties that were passed in to the initializer
        self.fps = fps
        self.outputURL = outputURL
        self.startTime = startTime

        // Get the width and height of the video by analyzing the pixel buffer
        videoResolutionX = UInt(CVPixelBufferGetWidthOfPlane(pixelBuffer, 0))
        videoResolutionY = UInt(CVPixelBufferGetHeightOfPlane(pixelBuffer, 0))

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
            print("*** Not ready for more media data: \(ts)")
            return
        }

        // Add the final image at the calculated timestamp to the asset writer
        if !assetWriterPixelBufferInput.append(image, withPresentationTime: ts) {
            print("*** Could not append rgb frame \(ts)")
        }
    }

    // Finish writing the video and then call the compltion handler
    func finish(completionHandler handler: (() -> Void)?) {
        assetWriter.finishWriting() {
            handler?()
        }
    }
}
