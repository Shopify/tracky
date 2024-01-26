//
//  DataSession.swift
//  Tracky
//
//  Created by Eric Florenzano on 2/28/23.
//

import Foundation
import UIKit
import simd

// Helper class for writing an ARKit frame stream into a .bren file with tracked transforms
class DataSession {
    let fps: UInt
    let viewResolutionX: UInt
    let viewResolutionY: UInt
    let startTime: TimeInterval
    let outputURL: URL
    let orientation = UIDevice.current.orientation

    var runTime: TimeInterval = 0
    var timestamps: [Float] = []
    var cameraTransforms: [simd_float4x4] = []
    var lensDatas: [BrenLensData] = []

    // Capture the start time and view resolution, as well as the eventual output url
    init(startTime: TimeInterval, fps: UInt, viewResolutionX: UInt, viewResolutionY: UInt, outputURL: URL) {
        self.fps = fps
        self.viewResolutionX = viewResolutionX
        self.viewResolutionY = viewResolutionY
        self.startTime = startTime
        self.outputURL = outputURL
    }

    // Add a new ARKit data frame
    func addFrame(time: TimeInterval, cameraTransform: simd_float4x4, resolution: CGSize, intrinsics: simd_float3x3) {
        runTime = time - startTime

        // Saved data for .bren file
        timestamps.append(Float(runTime))
        cameraTransforms.append(cameraTransform)

        let filmHeight: CGFloat = orientation == .portrait ? 36.0 : 24.0
        let sensorHeight: CGFloat = orientation == .portrait ? resolution.width : resolution.height
        let focalLength = CGFloat(intrinsics[1, 1]) * (filmHeight / sensorHeight)
        lensDatas.append(BrenLensData(focalLength: focalLength, sensorHeight: filmHeight))
    }

    // Write all the recorded data as a .bren file at the configured output URL
    func write(videoSessionRGB: VideoSession) -> Bool {
        var videoX = videoSessionRGB.videoResolutionX
        var videoY = videoSessionRGB.videoResolutionY
        if orientation == .portrait {
            let tmp = videoX
            videoX = videoY
            videoY = tmp
        }
        let renderData = BrenRenderData(
            orientation: UInt(orientation.rawValue),
            fps: fps,
            viewResolutionX: viewResolutionX,
            viewResolutionY: viewResolutionY,
            videoResolutionX: videoX,
            videoResolutionY: videoY
        )
        let cameraFrames = BrenCameraFrames(
            timestamps: timestamps,
            transforms: cameraTransforms,
            datas: lensDatas
        )
        let data = BrenWrapper(renderData, cameraFrames)

        // Turns out .bren is just JSON :D
        let jsonEncoder = JSONEncoder()
        guard let jsonData = try? jsonEncoder.encode(data),
              let json = String(data: jsonData, encoding: String.Encoding.utf8) else {
            print("ERROR: Could not encode .bren json data")
            return false
        }

        do {
            try json.write(to: outputURL, atomically: true, encoding: String.Encoding.utf8)
            print("Finished writing .bren")
            return true
        } catch {
            return false
        }
    }
}
