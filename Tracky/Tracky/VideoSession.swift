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
        self.fps = fps
        self.outputURL = outputURL
        self.startTime = startTime
        self.latestTime = CMTimeMakeWithSeconds(0, preferredTimescale: Int32(fps) * 10)
        self.depth = depth
        if (depth) {
            ciContext = CIContext()
        }
        self.recordMic = recordMic
        videoResolutionX = UInt(CVPixelBufferGetWidthOfPlane(pixelBuffer, 0))
        videoResolutionY = UInt(CVPixelBufferGetHeightOfPlane(pixelBuffer, 0))

        assetWriter = try! AVAssetWriter(outputURL: outputURL, fileType: AVFileType.mp4)

        let assetWriterVideoInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: videoResolutionX,
            AVVideoHeightKey: videoResolutionY,
        ] as [String : Any])
        assetWriterVideoInput.expectsMediaDataInRealTime = true
        assetWriter.add(assetWriterVideoInput)

        assetWriterPixelBufferInput = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterVideoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: videoResolutionX,
            kCVPixelBufferHeightKey as String: videoResolutionY
        ])

        if recordMic {
            audioQueue = DispatchQueue(label: "com.shopify.Tracky.AudioQueue")

            let device: AVCaptureDevice = AVCaptureDevice.default(.builtInMicrophone, for: AVMediaType.audio, position: .unspecified)!

            let session = AVCaptureSession()
            //session.sessionPreset = .high
            //session.usesApplicationAudioSession = true
            //session.automaticallyConfiguresApplicationAudioSession = false
            audioSession = session

            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) == true {
                    session.addInput(input)
                }
            } catch {
                print("ERROR [tryAddAudioInput]: \(error)")
            }

            let output = AVCaptureAudioDataOutput()
            audioOutput = output
            if audioSession?.canAddOutput(output) == true {
                audioSession?.addOutput(output)
            }

            audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: output.recommendedAudioSettingsForAssetWriter(writingTo: .mp4))
            audioInput?.expectsMediaDataInRealTime = true
        }

        super.init()

        if recordMic, let input = audioInput, let output = audioOutput, let queue = audioQueue {
            if assetWriter.canAdd(input) {
                assetWriter.add(input)
            }
            output.setSampleBufferDelegate(self, queue: queue)
            queue.async { [weak self] in
                self?.audioSession?.startRunning()
            }
        }

        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: CMTime.zero)
    }

    func addFrame(timestamp: TimeInterval, image: CVPixelBuffer) {
        let ts = CMTimeMakeWithSeconds(timestamp - startTime, preferredTimescale: Int32(fps) * 10)
        latestTime = ts
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
        assetWriter.finishWriting() {
            if let hndl = handler {
                hndl()
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let input = audioInput else { return }
        audioQueue?.async { [weak self] in
            guard let session = self?.audioSession else { return }
            if session.isRunning, input.isReadyForMoreMediaData {

                var count: CMItemCount = 0
                CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
                var info = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(duration: CMTime.zero, presentationTimeStamp: CMTime.zero, decodeTimeStamp: CMTime.zero), count: count)
                CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: count, arrayToFill: &info, entriesNeededOut: &count)

                guard let currentTime = self?.latestTime else { return }

                for i in 0..<count {
                    info[i].decodeTimeStamp = currentTime
                    info[i].presentationTimeStamp = currentTime
                }

                var soundbuffer:CMSampleBuffer?
                CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sampleBuffer, sampleTimingEntryCount: count, sampleTimingArray: &info, sampleBufferOut: &soundbuffer)
                if let buf = soundbuffer {
                    input.append(buf)
                }
            }
        }
    }
}
