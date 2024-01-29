//
//  Bren.swift
//  Tracky
//
//  Created by Eric Florenzano on 1/24/23.
//

import Foundation
import simd

// BrenWrapper represents one Brenfile, which is a JSON file with one object
// whose keys map to the fields on this struct
struct BrenWrapper: Codable {
    let camera_frames: BrenCameraFrames // Frame-by-frame camera animation

    init(_ cameraFrames: BrenCameraFrames) {
        camera_frames = cameraFrames
    }
}

struct BrenCameraFrames: Codable {
    let cameraFrames: [CameraFrame]
    
    init(cameraFrames: [CameraFrame]) {
        self.cameraFrames = cameraFrames
    }
}

struct CameraFrame: Codable {
    var blur_score: Float
    var timestamp: Float
    var fx: Float
    var fy: Float
    var cx: Float
    var cy: Float
    var width: UInt
    var height: UInt
    var t_00: Float
    var t_01: Float
    var t_02: Float
    var t_03: Float
    var t_10: Float
    var t_11: Float
    var t_12: Float
    var t_13: Float
    var t_20: Float
    var t_21: Float
    var t_22: Float
    var t_23: Float
    
    init (blur_score: Float, timestamp: Float, fx: Float, fy: Float, cx: Float, cy: Float, width: UInt, height: UInt, t_00: Float, t_01: Float, t_02: Float, t_03: Float, t_10: Float, t_11: Float, t_12: Float, t_13: Float, t_20: Float, t_21: Float, t_22: Float, t_23: Float) {
        self.blur_score = blur_score
        self.timestamp = timestamp
        self.fx = fx
        self.fy = fy
        self.cx = cx
        self.cy = cy
        self.width = width
        self.height = height
        self.t_00 = t_00
        self.t_01 = t_01
        self.t_02 = t_02
        self.t_03 = t_03
        self.t_10 = t_10
        self.t_11 = t_11
        self.t_12 = t_12
        self.t_13 = t_13
        self.t_20 = t_20
        self.t_21 = t_21
        self.t_22 = t_22
        self.t_23 = t_23
    }
}

// create_transform creates a [[Float]] from a simd_float4x4
func create_transform(transform tfm: simd_float4x4) -> [[Float]] {
    return [
        [tfm.columns.0.x, tfm.columns.1.x, tfm.columns.2.x, tfm.columns.3.x],
        [tfm.columns.0.y, tfm.columns.1.y, tfm.columns.2.y, tfm.columns.3.y],
        [tfm.columns.0.z, tfm.columns.1.z, tfm.columns.2.z, tfm.columns.3.z],
        [tfm.columns.0.w, tfm.columns.1.w, tfm.columns.2.w, tfm.columns.3.w]
    ]
}
