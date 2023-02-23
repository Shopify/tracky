bl_info = {
    'name': 'Import: Tracky tracking shot (.bren)',
    'description': 'Import AR tracking data recorded by the Tracky tracking app.',
    'author': 'Shopify',
    'version': (1, 0, 0),
    'blender': (2, 80, 0),
    'location': 'File > Import > Tracky Tracking Data (.bren)',
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

UNITY2BLENDER = axis_conversion(from_forward='Z', from_up='Y', to_forward='-Y', to_up='Z').to_4x4()

IDENTITY_MATRIX = mathutils.Matrix.Identity(4)

ORIENTATION_PORTRAIT = 1
ORIENTATION_UPSIDE_DOWN = 2
ORIENTATION_LANDSCAPE_LEFT = 3
ORIENTATION_LANDSCAPE_RIGHT = 4

RAD_PORTRAIT = math.radians(0)
RAD_LANDSCAPE_LEFT = math.radians(0)
RAD_LANDSCAPE_RIGHT = math.radians(180)

ROTATE_PORTRAIT = mathutils.Matrix.Rotation(RAD_PORTRAIT, 4, 'Z')
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
    planes = data.get('planes') or []
    tracked_transforms = data.get('tracked_transforms') or []

    resolution_x = render_data['video_resolution_x']
    resolution_y = render_data['video_resolution_y']

    if len(camera_datas) == 0:
        return

    camera_rotation = IDENTITY_MATRIX
    video_orientation = render_data['orientation']
    if video_orientation == ORIENTATION_PORTRAIT:
        camera_rotation = ROTATE_PORTRAIT
    elif video_orientation == ORIENTATION_LANDSCAPE_LEFT:
        camera_rotation = ROTATE_LANDSCAPE_LEFT
    elif video_orientation == ROTATE_LANDSCAPE_RIGHT:
        camera_rotation = ROTATE_LANDSCAPE_RIGHT

    # Setup render settings
    fps = render_data.get('fps', 60)
    context.scene.render.fps = fps
    context.scene.render.resolution_x = resolution_x
    context.scene.render.resolution_y = resolution_y

    # Setup scene settings
    if len(camera_timestamps) > 0:
        context.scene.frame_end = max(int(math.ceil(camera_timestamps[-1] * fps)), 1)

    bpy.ops.object.add()
    bren_root = context.object
    bren_root.name = 'Imported Tracking Data'

    # Create camera
    bpy.ops.object.camera_add(enter_editmode=False)
    cam = context.active_object
    cam.data.sensor_fit = 'VERTICAL'
    cam.data.lens_unit = 'MILLIMETERS'
    cam.name = 'ARCamera'
    cam.parent = bren_root

    # Setup video background
    video_filepath = filepath.replace('-camera.bren', '-video.mp4')
    background = cam.data.background_images.new()
    background.source = 'MOVIE_CLIP'
    background.alpha = 1
    background.clip = bpy.data.movieclips.load(filepath=video_filepath)
    background.frame_method = 'STRETCH'
    background.show_background_image = True
    if video_orientation == ORIENTATION_PORTRAIT:
        background.frame_method = 'CROP'
        background.rotation = math.radians(90)
        background.scale = resolution_x / resolution_y
    elif video_orientation == ORIENTATION_LANDSCAPE_RIGHT:
        background.rotation = RAD_LANDSCAPE_RIGHT
    cam.data.show_background_images = True

    # Switch the 3D windows to view through the new camera with the background
    for screen in context.workspace.screens:
        for area in screen.areas:
            for space in area.spaces:
                if space.type == 'VIEW_3D':
                    space.camera = cam
                    # TODO: Add the following back as an import option
                    #space.region_3d.view_perspective = 'CAMERA'

    # Create camera animation
    for idx, timestamp in enumerate(camera_timestamps):
        try:
            mat = mathutils.Matrix(camera_transforms[idx])
            data = camera_datas[idx]
        except IndexError:
            continue
        focal_length, sensor_height = data[0], data[1]

        frameidx = max(int(math.ceil(timestamp * fps)), 1)

        context.scene.frame_set(frameidx)

        cam.data.lens = focal_length
        cam.data.sensor_height = sensor_height
        assert cam.data.keyframe_insert('lens', frame=frameidx), 'Could not insert lens keyframe'

        cam.matrix_world = UNITY2BLENDER @ (mat @ camera_rotation)

        # Note that we only save the loc and rot keyframes, but it does apply the scale to the camera
        bpy.ops.anim.keyframe_insert_menu(type='BUILTIN_KSI_LocRot')

    # Rewind back to the first frame
    context.scene.frame_set(1)

    # Add planes
    for plane_index, plane in enumerate(planes):
        bpy.ops.mesh.primitive_plane_add(size=1.0, calc_uvs=True, enter_editmode=False, align='WORLD')
        plane_obj = context.object
        plane_obj.parent = bren_root
        plane_obj.name = '%s Plane [%d]' % (plane['alignment'].capitalize(), plane_index + 1)
        plane_obj.display_type = 'WIRE'
        plane_obj.hide_render = True
        plane_obj.matrix_world = (UNITY2BLENDER @ mathutils.Matrix(plane['transform']))
    
    # Add tracked empty transforms
    for track_index, tfm in enumerate(tracked_transforms):
        bpy.ops.object.add()
        tracked_obj = context.object
        tracked_obj.parent = bren_root
        tracked_obj.name = 'Empty [%d]' % (track_index + 1,)
        tracked_obj.empty_display_size = 0.2
        tracked_obj.matrix_world = UNITY2BLENDER @ mathutils.Matrix(tfm)

    # Select the camera object again so that the user can adjust any keyframes as needed
    context.object.select_set(False)
    cam.select_set(True)

    return {'FINISHED'}
    

class ImportBrenfile(Operator, ImportHelper):
    """Import Brenfiles recorded by Tracky."""

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
    self.layout.operator(ImportBrenfile.bl_idname, text="Tracky Tracking Data (.bren)")

def register():
    bpy.utils.register_class(ImportBrenfile)
    bpy.types.TOPBAR_MT_file_import.append(menu_func_import)

def unregister():
    bpy.utils.unregister_class(ImportBrenfile)
    bpy.types.TOPBAR_MT_file_import.remove(menu_func_import)

if __name__ == "__main__":
    register()