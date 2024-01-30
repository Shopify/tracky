//
//  DataSession.swift
//  Tracky
//
//  Created by Eric Florenzano on 2/28/23.
//

import Foundation
import UIKit
import simd

// Helper class for writing an ARKit frame stream into a .json file with tracked transforms
class DataSession {
    let fps: UInt
    let startTime: TimeInterval
    let camerasURL: URL
    let orientation = UIDevice.current.orientation

    var runTime: TimeInterval = 0
    var cameraFrames: [CameraFrame] = []

    // Capture the start time and view resolution, as well as the eventual output url
    init(startTime: TimeInterval, fps: UInt, camerasURL: URL) {
        self.fps = fps
        self.startTime = startTime
        self.camerasURL = camerasURL
    }

    // Add a new ARKit data frame
    func addFrame(time: TimeInterval, cameraTransform: simd_float4x4, intrinsics: simd_float3x3, videoResolutionX: UInt, videoResolutionY: UInt) {
        runTime = time - startTime
        
        let fx: Float = intrinsics[0, 0];
        let fy: Float = intrinsics[1, 1];
        let cx: Float = intrinsics[2, 0];
        let cy: Float = intrinsics[2, 1];
        
        // t_ij
        // i is the row
        // j is the column
        //
        // [ t_00 t_01 t_02 t_03 ]
        // [ t_10 t_11 t_12 t_13 ]
        // [ t_20 t_21 t_22 t_23 ]
        // [ t_30 t_31 t_32 t_33 ]
        //
        // Last row should be [0, 0, 0, 1]
        let t_00: Float = cameraTransform[0, 0]
        let t_01: Float = cameraTransform[1, 0]
        let t_02: Float = cameraTransform[2, 0]
        let t_03: Float = cameraTransform[3, 0]
        let t_10: Float = cameraTransform[0, 1]
        let t_11: Float = cameraTransform[1, 1]
        let t_12: Float = cameraTransform[2, 1]
        let t_13: Float = cameraTransform[3, 1]
        let t_20: Float = cameraTransform[0, 2]
        let t_21: Float = cameraTransform[1, 2]
        let t_22: Float = cameraTransform[2, 2]
        let t_23: Float = cameraTransform[3, 2]
        
        cameraFrames.append(CameraFrame(blur_score: 100.0, timestamp: Float(runTime), fx: fx, fy: fy, cx: cx, cy: cy, width: videoResolutionX, height: videoResolutionY, t_00: t_00, t_01: t_01, t_02: t_02, t_03: t_03, t_10: t_10, t_11: t_11, t_12: t_12, t_13: t_13, t_20: t_20, t_21: t_21, t_22: t_22, t_23: t_23));
    }

    func write(videoSessionRGB: VideoSession) -> Bool {
        let jsonEncoder = JSONEncoder()

        for (index, cameraFrame) in cameraFrames.enumerated() {
            if index % 15 == 0 {
                guard let jsonData = try? jsonEncoder.encode(cameraFrame) else {
                    print("*** ERROR: Could not encode CameraFrame at index \(index)")
                    continue
                }

                let filename = camerasURL.appendingPathComponent("\(index).json")
                do {
                    try jsonData.write(to: filename)
                } catch {
                    print("*** ERROR: Could not write CameraFrame at index \(index) to file: \(error)")
                    return false
                }
            }
        }

        print("*** Finished writing CameraFrames")
        return true
    }
}
