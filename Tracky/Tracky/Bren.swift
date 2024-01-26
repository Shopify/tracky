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
    // These are only marked as mutable so that Swift serializes them
    var version_major: Int = 1
    var version_minor: Int = 2
    let render_data: BrenRenderData // Info about the rendering setup
    let camera_frames: BrenCameraFrames // Frame-by-frame camera animation

    init(_ renderData: BrenRenderData, _ cameraFrames: BrenCameraFrames) {
        render_data = renderData
        camera_frames = cameraFrames
    }
}

// BrenRenderData contains systemic information about rendering,
// such as resolutions and frames per second, captured at the start
// of the recording session
struct BrenRenderData: Codable {
    let orientation: UInt // The orientation of the phone
    let fps: UInt // The desired rendering cadence
    let view_resolution_x: UInt // The X resolution of the AR view on iOS
    let view_resolution_y: UInt // The Y resolution of the AR view on iOS
    let video_resolution_x: UInt // The X resolution of the background AR video asset
    let video_resolution_y: UInt // The Y resolution of the background AR video asset
    
    init(orientation: UInt, fps: UInt, viewResolutionX: UInt, viewResolutionY: UInt, videoResolutionX: UInt, videoResolutionY: UInt) {
        self.orientation = orientation
        self.fps = fps
        self.view_resolution_x = viewResolutionX
        self.view_resolution_y = viewResolutionY
        self.video_resolution_x = videoResolutionX
        self.video_resolution_y = videoResolutionY
    }
}

// BrenCameraFrames is a structure-of-arrays containing the camera animation and parameters
struct BrenCameraFrames: Codable {
    let timestamps: [Float] // A list of timestamps that were recorded
    let transforms: [[[Float]]] // The 4x4 camera transform matrix at each of those timestamps
    let datas: [[Float]] // The camera lens configuration at each of those timestamps
    
    init(timestamps: [Float], transforms: [simd_float4x4], datas: [BrenLensData]) {
        self.timestamps = timestamps
        self.transforms = transforms.map(create_transform)
        self.datas = datas.map({ dat in dat.data })
    }
}

// BrenLensData is a configuration of the camera's sensor at a point in time
struct BrenLensData: Codable {
    var data: [Float] // [focalLength, sensorHeight]

    var focalLength: Float { get { return data[0] } set(value) { data[0] = value } }
    var sensorHeight: Float { get { return data[1] } set(value) { data[1] = value } }

    init(focalLength: CGFloat, sensorHeight: CGFloat) {
        data = [Float(focalLength), Float(sensorHeight)]
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
