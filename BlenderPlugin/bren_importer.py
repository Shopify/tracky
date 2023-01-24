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

import bpy
import math
import mathutils
import json

from bpy.props import StringProperty
from bpy.types import Operator

from bpy_extras.io_utils import ImportHelper
from bpy_extras.io_utils import axis_conversion

CONVERSION_MATRIX = axis_conversion(from_forward='Z', from_up='Y', to_forward='-Y', to_up='Z').to_4x4()


def import_brenfile(context, filepath):
    # Parse json data
    with open(filepath, 'r') as f:
        data = json.load(f)

    # Pull out relevant properties
    render_data = data.get('render_data') or {}
    camera_frames = data.get('camera_frames') or []

    # Setup render settings
    if 'fps' in render_data:
        context.scene.render.fps = render_data['fps']
    if 'resolution_x' in render_data:
        context.scene.render.resolution_x = render_data['resolution_x']
    if 'resolution_Y' in render_data:
        context.scene.render.resolution_y = render_data['resolution_y']

    # Setup scene settings
    context.scene.frame_end = len(camera_frames)

    # Create camera
    bpy.ops.object.camera_add(enter_editmode=False)
    cam = context.active_object
    cam.data.display_size = 0.2
    cam.name = "ARCamera"

    # Create camera animation
    for i, frame in enumerate(camera_frames):
        context.scene.frame_set(i)
        cam.data.keyframe_insert('lens', frame=i)
        cam.matrix_world = CONVERSION_MATRIX @ mathutils.Matrix(frame)
        bpy.ops.anim.keyframe_insert_menu(type='BUILTIN_KSI_LocRot')

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