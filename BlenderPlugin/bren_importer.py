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
import bpy
import math
import mathutils
import json

from bpy.props import StringProperty
from bpy.types import Operator

from bpy_extras.io_utils import ImportHelper
from bpy_extras.io_utils import axis_conversion

CONVERSION_MATRIX = axis_conversion(from_forward='Z', from_up='Y', to_forward='-Y', to_up='Z').to_4x4()
DEG2RAD = math.pi / 180

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
    if 'fps' in render_data:
        context.scene.render.fps = render_data['fps']
    if 'resolution_x' in render_data:
        context.scene.render.resolution_x = render_data['resolution_x']
    if 'resolution_y' in render_data:
        context.scene.render.resolution_y = render_data['resolution_y']

    # Setup scene settings
    context.scene.frame_end = len(camera_timestamps)

    # Create camera
    bpy.ops.object.camera_add(enter_editmode=False)
    cam = context.active_object
    cam.data.display_size = 0.2
    cam.data.sensor_fit = 'VERTICAL'
    cam.data.lens_unit = 'MILLIMETERS'
    cam.name = 'ARCamera'

    # Setup video background
    video_filepath = os.path.join(os.path.dirname(filepath), 'video.mp4')
    background = cam.data.background_images.new()
    background.source = 'MOVIE_CLIP'
    background.clip = bpy.data.movieclips.load(filepath=video_filepath)
    background.frame_method = 'CROP'
    background.rotation = 90 * DEG2RAD
    background.scale = 0.75
    background.show_background_image = True
    cam.data.show_background_images = True

    # Create camera animation
    for i, _timestamp in enumerate(camera_timestamps):
        mat = mathutils.Matrix(camera_transforms[i])
        data = camera_datas[i]
        focal_length, sensor_height = data[1], data[2]

        context.scene.frame_set(i)
        cam.data.lens = focal_length
        cam.data.sensor_height = sensor_height
        cam.data.keyframe_insert('lens', frame=i)
        cam.matrix_world = CONVERSION_MATRIX @ mat
        bpy.ops.anim.keyframe_insert_menu(type='BUILTIN_KSI_LocRot')

    context.scene.frame_set(0)

    # Switch the 3D windows to view through the new camera with the background
    for screen in context.workspace.screens:
        for area in screen.areas:
            for space in area.spaces:
                if space.type == 'VIEW_3D':
                    space.camera = cam
                    space.region_3d.view_perspective = 'CAMERA'

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