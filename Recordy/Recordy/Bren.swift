//
//  Bren.swift
//  Recordy
//
//  Created by Eric Florenzano on 1/24/23.
//

import Foundation
import simd

struct BrenRenderData: Codable {
    let fps: UInt
    let resolution_x: UInt
    let resolution_y: UInt
    
    init(fps: UInt, resolutionX: UInt, resolutionY: UInt) {
        self.fps = fps
        self.resolution_x = resolutionX
        self.resolution_y = resolutionY
    }
}

struct BrenCameraFrames: Codable {
    let timestamps: [Float]
    let transforms: [[[Float]]]
    let datas: [[Float]]
    
    init(timestamps: [Float], transforms: [simd_float4x4], datas: [BrenLensData]) {
        self.timestamps = timestamps
        self.transforms = transforms.map(create_transform)
        self.datas = datas.map({ dat in dat.data })
    }
}

struct BrenWrapper: Codable {
    let render_data: BrenRenderData
    let camera_frames: BrenCameraFrames
    
    init(_ renderData: BrenRenderData, _ cameraFrames: BrenCameraFrames) {
        render_data = renderData
        camera_frames = cameraFrames
    }
}

// Utility

func create_transform(transform tfm: simd_float4x4) -> [[Float]] {
    return [
        [tfm.columns.0.x, tfm.columns.1.x, tfm.columns.2.x, tfm.columns.3.x],
        [tfm.columns.0.y, tfm.columns.1.y, tfm.columns.2.y, tfm.columns.3.y],
        [tfm.columns.0.z, tfm.columns.1.z, tfm.columns.2.z, tfm.columns.3.z],
        [tfm.columns.0.w, tfm.columns.1.w, tfm.columns.2.w, tfm.columns.3.w]
    ]
}

struct BrenLensData: Codable {
    let data: [Float]
    
    var fov: Float { get { return data[0] } }
    var focalLength: Float { get { return data[1] } }
    var sensorHeight: Float { get { return data[2] } }
    var zNear: Float { get { return data[3] } }
    var zFar: Float { get { return data[4] } }
    var focusDistance: Float { get { return data[5] } }
    
    init(fov: CGFloat,
         focalLength: CGFloat,
         sensorHeight: CGFloat,
         zNear: CGFloat,
         zFar: CGFloat,
         focusDistance: CGFloat) {
        data = [
            Float(fov),
            Float(focalLength),
            Float(sensorHeight),
            Float(zNear),
            Float(zFar),
            Float(focusDistance),
        ]
    }
}
