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

from bpy.props import StringProperty, BoolProperty
from bpy.types import Operator, Panel

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


def import_brenfile(context, filepath, create_nodes=True, switch_to_cam=False):
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

    camera_rotation = IDENTITY_MATRIX
    video_orientation = render_data['orientation']
    if video_orientation == ORIENTATION_PORTRAIT:
        camera_rotation = ROTATE_PORTRAIT
    elif video_orientation == ORIENTATION_LANDSCAPE_LEFT:
        camera_rotation = ROTATE_LANDSCAPE_LEFT
    elif video_orientation == ROTATE_LANDSCAPE_RIGHT:
        camera_rotation = ROTATE_LANDSCAPE_RIGHT

    # Render settings that we want to switch all the time
    context.scene.render.film_transparent = True

    if create_nodes:
        create_node_graph(context, filepath, video_orientation)

        # Disable any filmic or custom color management and switch to standard
        context.scene.view_settings.view_transform = 'Standard'

        # Set defaults for the video encoding outputs
        context.scene.render.filepath = filepath.replace('-camera.bren', '-blender-render.mp4')
        context.scene.render.image_settings.file_format = 'FFMPEG'
        context.scene.render.ffmpeg.constant_rate_factor = 'HIGH'
        context.scene.render.ffmpeg.format = 'MPEG4'

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
                    if switch_to_cam:
                        space.region_3d.view_perspective = 'CAMERA'

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

        # Make sure cycles visibility is also disabled, first using the older method of `cycles_visibility``
        visibility = getattr(plane_obj, 'cycles_visibility', None)
        if visibility is not None:
            visibility.camera = False
            visibility.diffuse = False
            visibility.glossy = False
            visibility.transmission = False
            visibility.scatter = False

        # Then using the newer method of `visible_*`
        plane_obj.visible_camera = False
        plane_obj.visible_diffuse = False
        plane_obj.visible_glossy = False
        plane_obj.visible_shadow = False
        plane_obj.visible_transmission = False
        plane_obj.visible_volume_scatter = False
    
    # Add tracked empty transforms
    for track_index, tfm in enumerate(tracked_transforms):
        bpy.ops.object.add()
        tracked_obj = context.object
        tracked_obj.parent = bren_root
        tracked_obj.name = 'Empty [%d]' % (track_index + 1,)
        tracked_obj.empty_display_size = 0.2
        tracked_obj.matrix_world = UNITY2BLENDER @ mathutils.Matrix(tfm)

    # Select the camera object again so that the user can adjust any keyframes as needed
    for obj in bpy.data.objects:
        obj.select_set(False)
    cam.select_set(True)

    return {'FINISHED'}


def create_node_graph(context, filepath, orientation):
    scene = context.scene
    scene.use_nodes = True

    node_tree = scene.node_tree
    nodes = node_tree.nodes

    # Remove existing nodes, we'll be recreating everything we need
    for node in list(nodes):
        nodes.remove(node)

    for obj in bpy.data.objects:
        obj.select_set(False)

    # Create video node and load its movie clip
    video_filepath = filepath.replace('-camera.bren', '-video.mp4')
    video_node = nodes.new('CompositorNodeMovieClip')
    video_node.clip = bpy.data.movieclips.load(filepath=video_filepath)
    video_node.location.x = -970.6415405273438
    video_node.location.y = 701.6468505859375

    # Create rotate node
    rotate_node = nodes.new('CompositorNodeRotate')
    rotate_node.filter_type = 'BILINEAR'
    if orientation == ORIENTATION_PORTRAIT:
        rotate_node.inputs['Degr'].default_value = math.radians(-90)
    elif orientation == ORIENTATION_LANDSCAPE_RIGHT:
        rotate_node.inputs['Degr'].default_value = math.radians(180)
    rotate_node.location.x = -764.8800659179688
    rotate_node.location.y = 677.620361328125

    # Connect the output of the video clip into the rotate node
    node_tree.links.new(
        video_node.outputs['Image'],
        rotate_node.inputs['Image']
    )

    # Create first scale node
    scale_node_1 = nodes.new('CompositorNodeScale')
    scale_node_1.space = 'SCENE_SIZE'
    scale_node_1.location.x = -554.6401977539062
    scale_node_1.location.y = 616.1422119140625

    # Connect the output of the rotate node into the scale node
    node_tree.links.new(
        rotate_node.outputs['Image'],
        scale_node_1.inputs['Image']
    )

    # Create a mix node
    mix_node_1 = nodes.new('CompositorNodeMixRGB')
    mix_node_1.location.x = 722.7017822265625
    mix_node_1.location.y = 130.2596435546875

    # Connect the output of the first scale node into the first image input of
    # the mix node
    node_tree.links.new(
        scale_node_1.outputs['Image'],
        mix_node_1.inputs[1]
    )

    # Create a composite node
    composite_node = nodes.new('CompositorNodeComposite')
    composite_node.use_alpha = False
    composite_node.location.x = 1001.59716796875
    composite_node.location.y = 216.81689453125

    # Connect the output of the mix node to the composite node
    node_tree.links.new(
        mix_node_1.outputs['Image'],
        composite_node.inputs['Image']
    )

    # Create a viewer node and set it to use alpha
    viewer_node = nodes.new('CompositorNodeViewer')
    viewer_node.use_alpha = True
    viewer_node.location.x = 1006.509765625
    viewer_node.location.y = 32.799072265625

    # Connect the output of the mix node to the viewer node
    node_tree.links.new(
        mix_node_1.outputs['Image'],
        viewer_node.inputs['Image']
    )

    # Create an RLayers node
    rlayers_node = nodes.new('CompositorNodeRLayers')
    rlayers_node.location.x = -1076.2921142578125
    rlayers_node.location.y = 261.254150390625

    # Create a multiply node
    multiply_node = nodes.new('CompositorNodeMixRGB')
    multiply_node.blend_type = 'MULTIPLY'
    multiply_node.inputs['Fac'].default_value = 1
    multiply_node.location.x = 501.7509765625
    multiply_node.location.y = -67.72088623046875

    # Connect the output of the multiply node to the mix node
    node_tree.links.new(
        multiply_node.outputs['Image'],
        mix_node_1.inputs[0]
    )

    # Connect the image output of the RLayers node to the mix node
    node_tree.links.new(
        rlayers_node.outputs['Image'],
        mix_node_1.inputs[2]
    )

    # Connect the alpha output of the RLayers node to the multiply node
    node_tree.links.new(
        rlayers_node.outputs['Alpha'],
        multiply_node.inputs[2]
    )

    # Create segmentation node and load its movie clip
    segmentation_filepath = filepath.replace('-camera.bren', '-segmentation.mp4')
    segmentation_node = nodes.new('CompositorNodeMovieClip')
    segmentation_node.clip = bpy.data.movieclips.load(filepath=segmentation_filepath)
    segmentation_node.location.x = -976.0883178710938
    segmentation_node.location.y = -304.98193359375

    # Create a frame node
    frame_node = nodes.new('NodeFrame')
    frame_node.label = 'ADJUST THESE FOR THE SEGMENTATION MASK'
    frame_node.location.x = -314.157958984375
    frame_node.location.y = -256.0308837890625

    # Create second scale node
    scale_node_2 = nodes.new('CompositorNodeScale')
    scale_node_2.parent = frame_node
    scale_node_2.frame_method = 'STRETCH'
    scale_node_2.location.x = -426.41912841796875
    scale_node_2.location.y = -62.532958984375

    # Connect the output of the segmentation clip into the scale node
    node_tree.links.new(
        segmentation_node.outputs['Image'],
        scale_node_2.inputs['Image']
    )

    # Create an exposure node
    exposure_node = nodes.new('CompositorNodeExposure')
    exposure_node.parent = frame_node
    exposure_node.inputs['Exposure'].default_value = 3
    exposure_node.location.x = -233.28424072265625
    exposure_node.location.y = -102.9228515625

    # Connect the output of the scale node into the exposure node
    node_tree.links.new(
        scale_node_2.outputs['Image'],
        exposure_node.inputs['Image']
    )

    # Create an invert node
    invert_node = nodes.new('CompositorNodeInvert')
    invert_node.parent = frame_node
    invert_node.invert_rgb = True
    invert_node.invert_alpha = False
    invert_node.inputs['Fac'].default_value = 1
    invert_node.hide = True
    invert_node.location.x = -48.83795166015625
    invert_node.location.y = -120.58245849609375

    # Connect the output of the exposure node into the invert node
    node_tree.links.new(
        exposure_node.outputs['Image'],
        invert_node.inputs['Color']
    )

    # Create the first blur node
    blur_node_1 = nodes.new('CompositorNodeBlur')
    blur_node_1.parent = frame_node
    blur_node_1.filter_type = 'MITCH'
    blur_node_1.size_x = 20
    blur_node_1.size_y = 20
    blur_node_1.inputs['Size'].default_value = 1
    blur_node_1.location.x = 178.44140625
    blur_node_1.location.y = -45.1683349609375

    # Connect the output of the invert node into the blur node
    node_tree.links.new(
        invert_node.outputs['Color'],
        blur_node_1.inputs['Image']
    )

    # Create the dialate/erode filter node
    de_node = nodes.new('CompositorNodeDilateErode')
    de_node.parent = frame_node
    de_node.mode = 'THRESHOLD'
    de_node.distance = 3
    de_node.edge = 3
    de_node.location.x = 377.0482177734375
    de_node.location.y = -50.9749755859375

    # Connect the output of the first blur node into the dilate/erode node
    node_tree.links.new(
        blur_node_1.outputs['Image'],
        de_node.inputs['Mask']
    )

    # Create the second blur node
    blur_node_2 = nodes.new('CompositorNodeBlur')
    blur_node_2.parent = frame_node
    blur_node_2.filter_type = 'MITCH'
    blur_node_2.size_x = 10
    blur_node_2.size_y = 10
    blur_node_2.inputs['Size'].default_value = 1
    blur_node_2.location.x = 555.4044189453125
    blur_node_2.location.y = -27.837646484375

    # Connect the output of the dilate/erode filter node into the second blur node
    node_tree.links.new(
        de_node.outputs['Mask'],
        blur_node_2.inputs['Image']
    )

    # Connect the output of the second blur node into the multiply node
    node_tree.links.new(
        blur_node_2.outputs['Image'],
        multiply_node.inputs[1]
    )

    for obj in bpy.data.objects:
        obj.select_set(False)



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
        return import_brenfile(context,
                               self.filepath,
                               create_nodes=context.scene.create_nodes,
                               switch_to_cam=context.scene.switch_to_cam)

    def draw(self, context):
        pass


class ImportBrenfileSettings(Panel):
    bl_space_type = 'FILE_BROWSER'
    bl_region_type = 'TOOL_PROPS'
    bl_label = "Brenfile Import Settings"

    @classmethod
    def poll(cls, context):
        operator = context.space_data.active_operator
        return operator.bl_idname == bpy.ops.shopify.brenfile.idname()

    def draw(self, context):
        layout = self.layout
        layout.use_property_split = False
        layout.use_property_decorate = False  # No animation.

        layout.prop(context.scene, 'create_nodes')
        layout.prop(context.scene, 'switch_to_cam')


def menu_func_import(self, context):
    self.layout.operator(ImportBrenfile.bl_idname, text="Tracky Tracking Data (.bren)")

def register():
    bpy.types.Scene.create_nodes = BoolProperty(
        name="Setup Render Nodes",
        description="Sets up render nodes for hand and person occlusion",
        default=True,
    )
    bpy.types.Scene.switch_to_cam = BoolProperty(
        name="Make Imported Camera Active",
        description="Makes the newly-imported AR camera active in the current 3D viewport",
        default=False,
    )
    bpy.utils.register_class(ImportBrenfile)
    bpy.utils.register_class(ImportBrenfileSettings)
    bpy.types.TOPBAR_MT_file_import.append(menu_func_import)

def unregister():
    bpy.utils.unregister_class(ImportBrenfile)
    bpy.utils.unregister_class(ImportBrenfileSettings)
    bpy.types.TOPBAR_MT_file_import.remove(menu_func_import)
    del bpy.types.Scene.create_nodes
    del bpy.types.Scene.switch_to_cam

if __name__ == "__main__":
    register()