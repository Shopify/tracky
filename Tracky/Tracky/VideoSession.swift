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
    var videoURL: URL
    var imagesURL: URL
    var startTime: TimeInterval
    var videoResolutionX: UInt
    var videoResolutionY: UInt
    var assetWriter: AVAssetWriter
    var assetWriterPixelBufferInput: AVAssetWriterInputPixelBufferAdaptor
    var numFrames: UInt

    init(pixelBuffer: CVPixelBuffer, startTime: TimeInterval, fps: UInt = 60, videoURL: URL, imagesURL: URL) {
        // Assign all of the properties that were passed in to the initializer
        self.fps = fps
        self.videoURL = videoURL
        self.imagesURL = imagesURL
        self.startTime = startTime
        self.numFrames = 0

        // Get the width and height of the video by analyzing the pixel buffer
        videoResolutionX = UInt(CVPixelBufferGetWidthOfPlane(pixelBuffer, 0))
        videoResolutionY = UInt(CVPixelBufferGetHeightOfPlane(pixelBuffer, 0))

        // Create an asset writer to write out an mp4 video file
        assetWriter = try! AVAssetWriter(outputURL: videoURL, fileType: AVFileType.mp4)

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
            return
        }
        
        numFrames += 1;
    }

    // Finish writing the video and then call the compltion handler
    func finish(completionHandler handler: (() -> Void)?) {
        assetWriter.finishWriting() {
            print("*** numFrames processed: \(self.numFrames)")
            
            self.convertVideoToFrames();
            
            handler?()
        }
    }

    func convertVideoToFrames() {
        let asset = AVAsset(url: videoURL)
        guard let assetReader = try? AVAssetReader(asset: asset) else {
            print("*** Could not initialize asset reader")
            return
        }

        guard let track = asset.tracks(withMediaType: .video).first else { return }
        let outputSettings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB]
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)

        assetReader.add(readerOutput)
        assetReader.startReading()

        var frameCount = 0
        while let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            autoreleasepool {
                if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    // Here you can create a UIImage or an SKTexture from the CIImage
                    var ciImage: CIImage? = CIImage(cvPixelBuffer: imageBuffer)
                    var image: UIImage? = UIImage(ciImage: ciImage!)

                    // Save image to disk
                    if let data = image!.jpegData(compressionQuality: 1.0) {
                        let filename = imagesURL.appendingPathComponent("\(frameCount).jpg")
                        try? data.write(to: filename)
                    }

                    ciImage = nil
                    image = nil
                    
                    frameCount += 1
                }
                CMSampleBufferInvalidate(sampleBuffer)
            }
        }
        
        print("*** numFrames saved to disk: \(frameCount)")
    }

    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
}
