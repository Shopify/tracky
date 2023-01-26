bl_info = {
    'name': 'Import: Recordy tracking shot (.bren)',
    'description': 'Import AR tracking data recorded by the Recordy tracking app.',
    'author': 'Shopify',
    'version': (1, 0, 0),
    'blender': (2, 80, 0),
    'location': 'File > Import > Recordy Tracking Data (.bren)',
    'warning': '',
    'category': 'Import-Export',
}

import os
import math
import json

import bpy
import mathutils

from bpy.props import StringProperty
from bpy.types import Operator

from bpy_extras.io_utils import ImportHelper
from bpy_extras.io_utils import axis_conversion

UNITY2BLENDER = mathutils.Matrix.Scale(10, 4) @ axis_conversion(from_forward='Z', from_up='Y', to_forward='-Y', to_up='Z').to_4x4()
FRAME_OFFSET = 20

IDENTITY_MATRIX = mathutils.Matrix.Identity(4)

RAD_PORTRAIT = math.radians(-90)
RAD_PORTRAIT_UPSIDE_DOWN = math.radians(90)
RAD_LANDSCAPE_LEFT = math.radians(0)
RAD_LANDSCAPE_RIGHT = math.radians(180)

ROTATE_PORTRAIT = mathutils.Matrix.Rotation(RAD_PORTRAIT, 4, 'Z')
ROTATE_PORTRAIT_UPSIDE_DOWN = mathutils.Matrix.Rotation(RAD_PORTRAIT_UPSIDE_DOWN, 4, 'Z')
ROTATE_LANDSCAPE_LEFT = mathutils.Matrix.Rotation(RAD_LANDSCAPE_LEFT, 4, 'Z')
ROTATE_LANDSCAPE_RIGHT = mathutils.Matrix.Rotation(RAD_LANDSCAPE_RIGHT, 4, 'Z')


def import_brenfile(context, filepath):
    # Parse json data
    with open(filepath, 'r') as f:
        data = json.load(f)

    # Pull out relevant properties
    render_data = data.get('render_data') or {}
    camera_frames = data.get('camera_frames') or []
    camera_timestamps = camera_frames.get('timestamps') or []
    camera_transforms = camera_frames.get('transforms') or []
    camera_datas = camera_frames.get('datas') or []

    # Setup render settings
    fps = 60
    if 'fps' in render_data:
        fps = render_data['fps']
        context.scene.render.fps = fps
    if 'video_resolution_x' in render_data:
        context.scene.render.resolution_x = render_data['video_resolution_x']
    if 'video_resolution_y' in render_data:
        context.scene.render.resolution_y = render_data['video_resolution_y']

    # Setup scene settings
    context.scene.frame_end = len(camera_timestamps) + FRAME_OFFSET

    # Create camera
    bpy.ops.object.camera_add(enter_editmode=False)
    cam = context.active_object
    cam.data.sensor_fit = 'VERTICAL'
    cam.data.lens_unit = 'MILLIMETERS'
    cam.name = 'ARCamera'

    # Setup video background
    video_filepath = os.path.join(os.path.dirname(filepath), 'video.mp4')
    background = cam.data.background_images.new()
    background.source = 'MOVIE_CLIP'
    background.clip = bpy.data.movieclips.load(filepath=video_filepath)
    background.frame_method = 'STRETCH'
    background.show_background_image = True
    cam.data.show_background_images = True

    # Switch the 3D windows to view through the new camera with the background
    for screen in context.workspace.screens:
        for area in screen.areas:
            for space in area.spaces:
                if space.type == 'VIEW_3D':
                    space.camera = cam
                    space.region_3d.view_perspective = 'CAMERA'

    # Create camera animation
    rot = IDENTITY_MATRIX
    for _i, timestamp in enumerate(camera_timestamps):
        i = int(math.floor(timestamp * fps))
        mat = mathutils.Matrix(camera_transforms[i])
        data = camera_datas[i]
        focal_length, sensor_height, orientation = data[1], data[2], data[6]
        frameidx = i + FRAME_OFFSET

        context.scene.frame_set(frameidx)

        cam.data.lens = focal_length
        cam.data.sensor_height = sensor_height
        assert cam.data.keyframe_insert('lens', frame=frameidx), 'Could not insert lens keyframe'
        assert cam.data.keyframe_insert('sensor_height', frame=frameidx), 'Could not insert sensor_height keyframe'

        if orientation == 1:
            rot = ROTATE_PORTRAIT
        elif orientation == 2:
            rot = ROTATE_PORTRAIT_UPSIDE_DOWN
        elif orientation == 3:
            rot = ROTATE_LANDSCAPE_LEFT
        elif orientation == 4:
            rot = ROTATE_LANDSCAPE_RIGHT
        cam.matrix_world = UNITY2BLENDER @ (mat @ rot)

        # Note that we only save the loc and rot keyframes, but it does apply the scale to the camera
        bpy.ops.anim.keyframe_insert_menu(type='BUILTIN_KSI_LocRot')

    # Rewind back to the first frame
    context.scene.frame_set(0)

    return {'FINISHED'}
    

class ImportBrenfile(Operator, ImportHelper):
    """Import Brenfiles recorded by Recordy."""

    bl_idname = "shopify.brenfile"  # important since its how bpy.ops.import_test.some_data is constructed
    bl_label = "Brenfile (.bren)"

    # ImportHelper mixin class uses this
    filename_ext = ".bren"

    filter_glob: StringProperty(
        default="*.bren",
        options={'HIDDEN'},
        maxlen=255,  # Max internal buffer length, longer would be clamped.
    )

    def execute(self, context):
        return import_brenfile(context, self.filepath)

def menu_func_import(self, context):
    self.layout.operator(ImportBrenfile.bl_idname, text="Recordy Tracking Data (.bren)")

def register():
    bpy.utils.register_class(ImportBrenfile)
    bpy.types.TOPBAR_MT_file_import.append(menu_func_import)

def unregister():
    bpy.utils.unregister_class(ImportBrenfile)
    bpy.types.TOPBAR_MT_file_import.remove(menu_func_import)

if __name__ == "__main__":
    register()