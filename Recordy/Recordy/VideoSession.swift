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

class VideoSession {
    var fps: UInt
    var outputURL: URL
    var startTime: TimeInterval
    var depth: Bool
    var videoResolutionX: UInt
    var videoResolutionY: UInt
    var assetWriter: AVAssetWriter
    var assetWriterPixelBufferInput: AVAssetWriterInputPixelBufferAdaptor

    init(pixelBuffer: CVPixelBuffer, outputURL: URL, startTime: TimeInterval, fps: UInt = 60, depth: Bool) {
        self.fps = fps
        self.outputURL = outputURL
        self.startTime = startTime
        self.depth = depth
        videoResolutionX = UInt(CVPixelBufferGetWidthOfPlane(pixelBuffer, 0))
        videoResolutionY = UInt(CVPixelBufferGetHeightOfPlane(pixelBuffer, 0))
        
        if depth {
            let ftype = CVPixelBufferGetPixelFormatType(pixelBuffer)
            let cString: [CChar] = [
                CChar(ftype >> 24 & 0xFF),
                CChar(ftype >> 16 & 0xFF),
                CChar(ftype >> 8 & 0xFF),
                CChar(ftype & 0xFF),
                0
            ]
            print("TYPE: \(String(cString: cString))")
        }
        
        assetWriter = try! AVAssetWriter(outputURL: outputURL, fileType: depth ? AVFileType.mov : AVFileType.mp4)

        let assetWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: [
            AVVideoCodecKey: depth ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: videoResolutionX,
            AVVideoHeightKey: videoResolutionY,
        ] as [String : Any])
        assetWriterInput.expectsMediaDataInRealTime = true
        assetWriter.add(assetWriterInput)

        assetWriterPixelBufferInput = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: depth ? kCVPixelFormatType_DepthFloat32 : kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: videoResolutionX,
            kCVPixelBufferHeightKey as String: videoResolutionY
        ])
        
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: CMTime.zero)
    }

    func addFrame(timestamp: TimeInterval, image: CVPixelBuffer) {
        let ts = CMTimeMakeWithSeconds(timestamp - startTime, preferredTimescale: 600)
        if !assetWriterPixelBufferInput.assetWriterInput.isReadyForMoreMediaData {
            print("Not ready for more media data: \(ts)")
            return
        }
        if !assetWriterPixelBufferInput.append(image, withPresentationTime: ts) {
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
