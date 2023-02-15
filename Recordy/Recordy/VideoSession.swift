//
//  VideoSession.swift
//  Recordy
//
//  Created by Eric Florenzano on 2/3/23.
//

import UIKit
import SceneKit
import ARKit
import AVFoundation
import ARKit
import CoreImage

class VideoSession {
    var fps: UInt
    var outputURL: URL
    var startTime: TimeInterval
    var depth: Bool
    var videoResolutionX: UInt
    var videoResolutionY: UInt
    var assetWriter: AVAssetWriter
    var assetWriterPixelBufferInput: AVAssetWriterInputPixelBufferAdaptor
    var ciContext: CIContext? = nil

    init(pixelBuffer: CVPixelBuffer, outputURL: URL, startTime: TimeInterval, fps: UInt = 60, depth: Bool) {
        self.fps = fps
        self.outputURL = outputURL
        self.startTime = startTime
        self.depth = depth
        if (depth) {
            ciContext = CIContext()
        }
        videoResolutionX = UInt(CVPixelBufferGetWidthOfPlane(pixelBuffer, 0))
        videoResolutionY = UInt(CVPixelBufferGetHeightOfPlane(pixelBuffer, 0))

        assetWriter = try! AVAssetWriter(outputURL: outputURL, fileType: AVFileType.mp4)

        let assetWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: videoResolutionX,
            AVVideoHeightKey: videoResolutionY,
        ] as [String : Any])
        assetWriterInput.expectsMediaDataInRealTime = true
        assetWriter.add(assetWriterInput)

        assetWriterPixelBufferInput = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: videoResolutionX,
            kCVPixelBufferHeightKey as String: videoResolutionY
        ])
        
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: CMTime.zero)
    }

    func addFrame(timestamp: TimeInterval, image: CVPixelBuffer) {
        let ts = CMTimeMakeWithSeconds(timestamp - startTime, preferredTimescale: Int32(fps) * 10)
        if !assetWriterPixelBufferInput.assetWriterInput.isReadyForMoreMediaData {
            print("Not ready for more media data: \(ts)")
            return
        }
        var convertedImage: CVPixelBuffer!
        if depth {
            let ciImage = CIImage(cvPixelBuffer: image)
            let result = CVPixelBufferCreate(nil, Int(videoResolutionX), Int(videoResolutionY), kCVPixelFormatType_32ARGB, [
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                kCVPixelBufferCGImageCompatibilityKey as String: true
            ] as CFDictionary, &convertedImage)
            if result != 0 {
                print("Error creating depth CVPixelBuffer, code: \(result)")
                return
            }
            ciContext?.render(ciImage, to: convertedImage)
        } else {
            convertedImage = image
        }
        if !assetWriterPixelBufferInput.append(convertedImage, withPresentationTime: ts) {
            print("Could not append \(depth ? "depth" : "rgb") frame \(ts)")
        }
    }
    
    func finish(completionHandler handler: (() -> Void)?) {
        if let handle = handler {
            assetWriter.finishWriting(completionHandler: handle)
        } else {
            assetWriter.finishWriting() {
                // Nothing
            }
        }
    }
}
