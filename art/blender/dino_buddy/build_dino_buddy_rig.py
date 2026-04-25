import bpy
import math
import os


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BLEND_PATH = os.path.join(SCRIPT_DIR, "dino_buddy_rigged.blend")
EXPORT_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, "..", "..", "exports", "dino_buddy"))
GLB_PATH = os.path.join(EXPORT_DIR, "dino_buddy_rigged.glb")


PRIMARY_COLOR = (0.309804, 0.878431, 0.509804, 1.0)
ACCENT_COLOR = (0.686275, 1.0, 0.772549, 1.0)
EYE_WHITE_COLOR = (0.96, 0.98, 1.0, 1.0)
PUPIL_COLOR = (0.08, 0.09, 0.12, 1.0)
TOOTH_COLOR = (0.965, 0.95, 0.91, 1.0)


def clean_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablock_collection in (
        bpy.data.meshes,
        bpy.data.armatures,
        bpy.data.materials,
        bpy.data.actions,
        bpy.data.cameras,
        bpy.data.lights,
    ):
        for datablock in list(datablock_collection):
            if datablock.users == 0:
                datablock_collection.remove(datablock)


def set_scene_defaults():
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.render.fps = 24
    scene.frame_start = 1
    scene.frame_end = 24
    os.makedirs(EXPORT_DIR, exist_ok=True)


def make_material(name, color, emission_strength=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    principled = mat.node_tree.nodes["Principled BSDF"]
    principled.inputs["Base Color"].default_value = color
    principled.inputs["Roughness"].default_value = 0.55
    principled.inputs["Metallic"].default_value = 0.08
    if emission_strength > 0.0:
        principled.inputs["Emission Color"].default_value = color
        principled.inputs["Emission Strength"].default_value = emission_strength
    return mat


def apply_material(obj, material):
    if obj.data.materials:
        obj.data.materials[0] = material
    else:
        obj.data.materials.append(material)


def deselect_all():
    bpy.ops.object.select_all(action="DESELECT")


def select_objects(objects, active):
    deselect_all()
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = active


def create_armature():
    bpy.ops.object.armature_add(enter_editmode=True, location=(0.0, 0.0, 0.0))
    arm_obj = bpy.context.object
    arm_obj.name = "DinoBuddyRig"
    arm_obj.data.name = "DinoBuddyRigData"

    edit_bones = arm_obj.data.edit_bones
    root = edit_bones[0]
    root.name = "Root"
    root.head = (0.0, 0.0, 0.0)
    root.tail = (0.0, 0.0, 0.35)

    def add_bone(name, head, tail, parent=None):
        bone = edit_bones.new(name)
        bone.head = head
        bone.tail = tail
        if parent is not None:
            bone.parent = parent
        return bone

    hips = add_bone("Hips", (0.0, 0.0, 0.38), (0.0, -0.02, 1.02), root)
    chest = add_bone("Chest", (0.0, -0.04, 1.02), (0.0, -0.10, 1.50), hips)
    neck = add_bone("Neck", (0.0, -0.22, 1.36), (0.0, -0.56, 1.68), chest)
    head = add_bone("Head", (0.0, -0.56, 1.68), (0.0, -1.06, 1.78), neck)
    add_bone("Jaw", (0.0, -0.84, 1.55), (0.0, -1.14, 1.40), head)

    tail_base = add_bone("TailBase", (0.0, 0.22, 1.00), (0.0, 0.72, 0.93), hips)
    tail_mid = add_bone("TailMid", (0.0, 0.72, 0.93), (0.0, 1.18, 0.82), tail_base)
    add_bone("TailTip", (0.0, 1.18, 0.82), (0.0, 1.58, 0.72), tail_mid)

    def add_arm(side_prefix, x_sign):
        shoulder = add_bone(
            f"{side_prefix}_Upper",
            (0.34 * x_sign, -0.20, 1.17),
            (0.46 * x_sign, -0.36, 0.98),
            chest,
        )
        forearm = add_bone(
            f"{side_prefix}_Lower",
            shoulder.tail,
            (0.56 * x_sign, -0.48, 0.84),
            shoulder,
        )
        add_bone(
            f"{side_prefix}_Foot",
            forearm.tail,
            (0.64 * x_sign, -0.58, 0.80),
            forearm,
        )

    def add_leg(side_prefix, x_sign):
        upper = add_bone(
            f"{side_prefix}_Upper",
            (0.28 * x_sign, 0.04, 0.92),
            (0.28 * x_sign, 0.10, 0.46),
            hips,
        )
        lower = add_bone(
            f"{side_prefix}_Lower",
            upper.tail,
            (0.28 * x_sign, 0.02, 0.12),
            upper,
        )
        add_bone(
            f"{side_prefix}_Foot",
            lower.tail,
            (0.28 * x_sign, -0.20, 0.03),
            lower,
        )

    add_arm("FrontLegL", -1.0)
    add_arm("FrontLegR", 1.0)
    add_leg("BackLegL", -1.0)
    add_leg("BackLegR", 1.0)

    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj


def add_box(name, location, scale, material, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    apply_material(obj, material)
    return obj


def add_uv_sphere(name, location, radius, material, segments=24, rings=14):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=location, segments=segments, ring_count=rings)
    obj = bpy.context.object
    obj.name = name
    apply_material(obj, material)
    bpy.ops.object.shade_smooth()
    return obj


def add_scaled_sphere(name, location, scale, material, rotation=(0.0, 0.0, 0.0)):
    obj = add_uv_sphere(name, location, 1.0, material)
    obj.rotation_euler = rotation
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return obj


def add_cone(name, location, radius, depth, material, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cone_add(
        vertices=12,
        radius1=radius,
        radius2=0.0,
        depth=depth,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    apply_material(obj, material)
    bpy.ops.object.shade_smooth()
    return obj


def parent_to_bone(obj, armature, bone_name):
    obj.parent = armature
    obj.parent_type = "BONE"
    obj.parent_bone = bone_name
    bone_world_matrix = armature.matrix_world @ armature.pose.bones[bone_name].matrix
    obj.matrix_parent_inverse = bone_world_matrix.inverted()


def join_meshes(objects, name):
    select_objects(objects, objects[0])
    bpy.ops.object.join()
    joined = bpy.context.object
    joined.name = name
    return joined


def finish_mesh(obj, voxel_size, subsurf_levels=1, smooth_iterations=6):
    select_objects([obj], obj)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    remesh = obj.modifiers.new("OrganicRemesh", "REMESH")
    remesh.mode = "VOXEL"
    remesh.voxel_size = voxel_size
    remesh.adaptivity = 0.0
    if hasattr(remesh, "use_smooth_shade"):
        remesh.use_smooth_shade = True
    bpy.ops.object.modifier_apply(modifier=remesh.name)

    smooth = obj.modifiers.new("OrganicSmooth", "SMOOTH")
    smooth.factor = 1.25
    smooth.iterations = smooth_iterations
    bpy.ops.object.modifier_apply(modifier=smooth.name)

    subsurf = obj.modifiers.new("OrganicSubsurf", "SUBSURF")
    subsurf.levels = subsurf_levels
    subsurf.render_levels = subsurf_levels
    bpy.ops.object.modifier_apply(modifier=subsurf.name)

    bpy.ops.object.shade_smooth()


def bind_mesh_to_armature(obj, armature):
    select_objects([obj, armature], armature)
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")


def build_body_mesh(armature, primary_mat):
    parts = [
        add_scaled_sphere("BodyHip", (0.0, 0.16, 0.90), (0.50, 0.66, 0.54), primary_mat),
        add_scaled_sphere("BodyBelly", (0.0, -0.04, 0.95), (0.64, 0.84, 0.74), primary_mat),
        add_scaled_sphere("BodyChest", (0.0, -0.20, 1.22), (0.48, 0.54, 0.50), primary_mat),
        add_scaled_sphere("NeckBase", (0.0, -0.28, 1.34), (0.22, 0.24, 0.24), primary_mat),
        add_scaled_sphere("NeckMid", (0.0, -0.45, 1.48), (0.20, 0.24, 0.24), primary_mat),
        add_scaled_sphere("HeadBack", (0.0, -0.72, 1.69), (0.34, 0.38, 0.31), primary_mat),
        add_scaled_sphere("HeadMid", (0.0, -0.92, 1.64), (0.25, 0.30, 0.22), primary_mat),
        add_scaled_sphere("SnoutTip", (0.0, -1.15, 1.57), (0.18, 0.24, 0.14), primary_mat),
        add_scaled_sphere("TailBaseVolume", (0.0, 0.50, 0.95), (0.18, 0.30, 0.18), primary_mat),
        add_scaled_sphere("TailMidVolume", (0.0, 0.92, 0.84), (0.12, 0.24, 0.12), primary_mat),
        add_scaled_sphere("TailTipVolume", (0.0, 1.30, 0.74), (0.08, 0.18, 0.08), primary_mat),
    ]

    for x_sign in (-1.0, 1.0):
        parts.extend(
            [
                add_scaled_sphere(f"Shoulder_{x_sign}", (0.34 * x_sign, -0.20, 1.17), (0.12, 0.12, 0.12), primary_mat),
                add_scaled_sphere(f"ArmUpper_{x_sign}", (0.43 * x_sign, -0.33, 1.00), (0.09, 0.09, 0.19), primary_mat),
                add_scaled_sphere(f"ArmLower_{x_sign}", (0.52 * x_sign, -0.46, 0.86), (0.075, 0.075, 0.15), primary_mat),
                add_scaled_sphere(f"ArmHand_{x_sign}", (0.60 * x_sign, -0.56, 0.80), (0.055, 0.070, 0.10), primary_mat),
                add_scaled_sphere(f"Thigh_{x_sign}", (0.28 * x_sign, 0.05, 0.74), (0.18, 0.18, 0.36), primary_mat),
                add_scaled_sphere(f"Shin_{x_sign}", (0.28 * x_sign, 0.06, 0.33), (0.12, 0.12, 0.28), primary_mat),
                add_scaled_sphere(f"Foot_{x_sign}", (0.28 * x_sign, -0.08, 0.08), (0.14, 0.22, 0.08), primary_mat),
            ]
        )

    body = join_meshes(parts, "DinoBuddyBody")
    finish_mesh(body, voxel_size=0.06, subsurf_levels=1, smooth_iterations=10)
    apply_material(body, primary_mat)
    bind_mesh_to_armature(body, armature)
    return body


def build_belly_patch(armature, accent_mat):
    patch = add_scaled_sphere("BellyPatch", (0.0, -0.18, 0.92), (0.36, 0.42, 0.46), accent_mat)
    chest_patch = add_scaled_sphere("ChestPatch", (0.0, -0.27, 1.18), (0.23, 0.20, 0.25), accent_mat)
    patch = join_meshes([patch, chest_patch], "DinoBuddyBelly")
    finish_mesh(patch, voxel_size=0.05, subsurf_levels=1, smooth_iterations=6)
    apply_material(patch, accent_mat)
    bind_mesh_to_armature(patch, armature)
    return patch


def build_jaw_mesh(armature, primary_mat):
    parts = [
        add_scaled_sphere("JawBack", (0.0, -0.83, 1.48), (0.22, 0.16, 0.07), primary_mat),
        add_scaled_sphere("JawMid", (0.0, -0.99, 1.43), (0.18, 0.20, 0.06), primary_mat),
        add_scaled_sphere("JawTip", (0.0, -1.15, 1.42), (0.11, 0.12, 0.045), primary_mat),
    ]
    jaw = join_meshes(parts, "DinoBuddyJaw")
    finish_mesh(jaw, voxel_size=0.035, subsurf_levels=1, smooth_iterations=6)
    apply_material(jaw, primary_mat)
    parent_to_bone(jaw, armature, "Jaw")
    return jaw


def build_eyes(armature, eye_white_mat, pupil_mat):
    created = []
    for x_sign in (-1.0, 1.0):
        eye = add_scaled_sphere(f"EyeWhite_{x_sign}", (0.18 * x_sign, -0.96, 1.70), (0.13, 0.12, 0.13), eye_white_mat)
        pupil = add_scaled_sphere(f"Pupil_{x_sign}", (0.215 * x_sign, -1.06, 1.69), (0.05, 0.022, 0.05), pupil_mat)
        created.extend([eye, pupil])

    for obj in created:
        parent_to_bone(obj, armature, "Head")

    return created


def build_teeth(armature, tooth_mat):
    created = []
    upper_positions = [
        (0.0, -1.05, 1.49),
        (-0.08, -0.98, 1.50),
        (0.08, -0.98, 1.50),
        (-0.14, -0.91, 1.50),
        (0.14, -0.91, 1.50),
    ]
    lower_positions = [
        (0.0, -1.04, 1.38),
        (-0.09, -0.96, 1.39),
        (0.09, -0.96, 1.39),
        (-0.14, -0.88, 1.40),
        (0.14, -0.88, 1.40),
    ]

    for index, position in enumerate(upper_positions):
        tooth = add_cone(
            f"UpperTooth_{index}",
            position,
            radius=0.017 if index < 3 else 0.013,
            depth=0.11 if index < 3 else 0.09,
            material=tooth_mat,
            rotation=(math.radians(180.0), 0.0, 0.0),
        )
        parent_to_bone(tooth, armature, "Head")
        created.append(tooth)

    for index, position in enumerate(lower_positions):
        tooth = add_cone(
            f"LowerTooth_{index}",
            position,
            radius=0.015 if index < 3 else 0.012,
            depth=0.10 if index < 3 else 0.08,
            material=tooth_mat,
            rotation=(0.0, 0.0, 0.0),
        )
        parent_to_bone(tooth, armature, "Jaw")
        created.append(tooth)

    return created


def build_mesh_rig(armature, primary_mat, accent_mat, eye_white_mat, pupil_mat, tooth_mat):
    created = []

    def add_piece(name, bone_name, location, scale, material, rotation=(0.0, 0.0, 0.0)):
        piece = add_scaled_sphere(name, location, scale, material, rotation=rotation)
        parent_to_bone(piece, armature, bone_name)
        created.append(piece)
        return piece

    add_piece("Torso", "Hips", (0.0, 0.10, 0.96), (0.50, 0.70, 0.58), primary_mat)
    add_piece("Chest", "Chest", (0.0, -0.12, 1.24), (0.42, 0.46, 0.44), primary_mat)
    add_piece("BellyPatch", "Hips", (0.0, -0.15, 0.92), (0.33, 0.40, 0.43), accent_mat)
    add_piece("ChestPatch", "Chest", (0.0, -0.26, 1.16), (0.20, 0.20, 0.23), accent_mat)
    add_piece("NeckBase", "Chest", (0.0, -0.30, 1.38), (0.18, 0.18, 0.22), primary_mat)

    add_piece("Head", "Head", (0.0, -0.76, 1.69), (0.34, 0.40, 0.31), primary_mat)
    add_piece("Snout", "Head", (0.0, -1.06, 1.58), (0.18, 0.24, 0.14), primary_mat)
    add_piece("SnoutPatch", "Head", (0.0, -1.00, 1.57), (0.15, 0.18, 0.10), accent_mat)
    add_piece("CheekL", "Head", (-0.20, -0.88, 1.62), (0.10, 0.10, 0.10), primary_mat)
    add_piece("CheekR", "Head", (0.20, -0.88, 1.62), (0.10, 0.10, 0.10), primary_mat)

    add_piece("Jaw", "Jaw", (0.0, -1.00, 1.41), (0.17, 0.19, 0.06), primary_mat)
    add_piece("TailBaseVolume", "TailBase", (0.0, 0.56, 0.95), (0.18, 0.28, 0.18), primary_mat, rotation=(-0.25, 0.0, 0.0))
    add_piece("TailMidVolume", "TailMid", (0.0, 0.97, 0.83), (0.12, 0.24, 0.12), primary_mat, rotation=(-0.35, 0.0, 0.0))
    add_piece("TailTipVolume", "TailTip", (0.0, 1.34, 0.73), (0.08, 0.18, 0.08), accent_mat, rotation=(-0.45, 0.0, 0.0))

    for x_sign in (-1.0, 1.0):
        z_twist = 0.14 * x_sign
        add_piece(f"ArmUpper_{x_sign}", f"FrontLeg{'L' if x_sign < 0 else 'R'}_Upper", (0.44 * x_sign, -0.33, 1.02), (0.08, 0.08, 0.18), primary_mat, rotation=(0.45, 0.0, z_twist))
        add_piece(f"ArmLower_{x_sign}", f"FrontLeg{'L' if x_sign < 0 else 'R'}_Lower", (0.54 * x_sign, -0.47, 0.87), (0.06, 0.06, 0.14), primary_mat, rotation=(0.55, 0.0, z_twist))
        add_piece(f"ArmHand_{x_sign}", f"FrontLeg{'L' if x_sign < 0 else 'R'}_Foot", (0.62 * x_sign, -0.58, 0.80), (0.05, 0.07, 0.10), accent_mat, rotation=(0.78, 0.0, z_twist))

        add_piece(f"Haunch_{x_sign}", "Hips", (0.26 * x_sign, 0.10, 0.76), (0.17, 0.18, 0.28), primary_mat)
        add_piece(f"LegUpper_{x_sign}", f"BackLeg{'L' if x_sign < 0 else 'R'}_Upper", (0.28 * x_sign, 0.05, 0.68), (0.16, 0.16, 0.34), primary_mat)
        add_piece(f"LegLower_{x_sign}", f"BackLeg{'L' if x_sign < 0 else 'R'}_Lower", (0.28 * x_sign, 0.04, 0.30), (0.11, 0.11, 0.28), primary_mat)
        add_piece(f"Foot_{x_sign}", f"BackLeg{'L' if x_sign < 0 else 'R'}_Foot", (0.28 * x_sign, -0.06, 0.07), (0.14, 0.22, 0.08), accent_mat)

        eye = add_scaled_sphere(f"EyeWhite_{x_sign}", (0.18 * x_sign, -0.98, 1.69), (0.12, 0.12, 0.12), eye_white_mat)
        pupil = add_scaled_sphere(f"Pupil_{x_sign}", (0.215 * x_sign, -1.08, 1.68), (0.045, 0.020, 0.045), pupil_mat)
        parent_to_bone(eye, armature, "Head")
        parent_to_bone(pupil, armature, "Head")
        created.extend([eye, pupil])

    upper_positions = [
        (0.0, -1.04, 1.49),
        (-0.08, -0.97, 1.50),
        (0.08, -0.97, 1.50),
        (-0.14, -0.91, 1.50),
        (0.14, -0.91, 1.50),
    ]
    lower_positions = [
        (0.0, -1.03, 1.38),
        (-0.09, -0.96, 1.39),
        (0.09, -0.96, 1.39),
        (-0.14, -0.89, 1.40),
        (0.14, -0.89, 1.40),
    ]

    for index, position in enumerate(upper_positions):
        tooth = add_cone(
            f"UpperTooth_{index}",
            position,
            radius=0.015 if index < 3 else 0.012,
            depth=0.10 if index < 3 else 0.08,
            material=tooth_mat,
            rotation=(math.radians(180.0), 0.0, 0.0),
        )
        parent_to_bone(tooth, armature, "Head")
        created.append(tooth)

    for index, position in enumerate(lower_positions):
        tooth = add_cone(
            f"LowerTooth_{index}",
            position,
            radius=0.013 if index < 3 else 0.011,
            depth=0.09 if index < 3 else 0.07,
            material=tooth_mat,
            rotation=(0.0, 0.0, 0.0),
        )
        parent_to_bone(tooth, armature, "Jaw")
        created.append(tooth)

    return created


def make_light_camera():
    bpy.ops.object.light_add(type="SUN", location=(4.0, -2.0, 6.0))
    sun = bpy.context.object
    sun.rotation_euler = (math.radians(48.0), 0.0, math.radians(25.0))
    sun.data.energy = 2.2

    bpy.ops.object.camera_add(location=(4.4, -5.8, 3.7), rotation=(math.radians(73.0), 0.0, math.radians(28.0)))
    cam = bpy.context.object
    cam.data.lens = 50
    bpy.context.scene.camera = cam


def reset_pose(armature):
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="POSE")
    for pbone in armature.pose.bones:
        pbone.location = (0.0, 0.0, 0.0)
        pbone.rotation_mode = "XYZ"
        pbone.rotation_euler = (0.0, 0.0, 0.0)
        pbone.scale = (1.0, 1.0, 1.0)
    bpy.ops.object.mode_set(mode="OBJECT")


def key_pose(armature, frame, rotations):
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="POSE")
    bpy.context.scene.frame_set(frame)
    for bone_name, values in rotations.items():
        pbone = armature.pose.bones[bone_name]
        pbone.rotation_mode = "XYZ"
        pbone.rotation_euler = values
        pbone.keyframe_insert(data_path="rotation_euler", frame=frame)
    bpy.ops.object.mode_set(mode="OBJECT")


def create_action(armature, name, start_frame, end_frame, keyframes, loop=False):
    reset_pose(armature)
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    armature.animation_data_create()
    armature.animation_data.action = action
    for frame, rotations in keyframes:
        key_pose(armature, frame, rotations)
    _ = loop
    return action


def build_actions(armature):
    create_action(
        armature,
        "Idle",
        1,
        24,
        [
            (1, {"TailBase": (0.0, 0.0, 0.10), "TailMid": (0.0, 0.0, 0.14), "Head": (0.04, 0.0, 0.03), "Chest": (0.02, 0.0, 0.0)}),
            (12, {"TailBase": (0.0, 0.0, -0.10), "TailMid": (0.0, 0.0, -0.16), "Head": (-0.03, 0.0, -0.03), "Chest": (-0.02, 0.0, 0.0)}),
            (24, {"TailBase": (0.0, 0.0, 0.10), "TailMid": (0.0, 0.0, 0.14), "Head": (0.04, 0.0, 0.03), "Chest": (0.02, 0.0, 0.0)}),
        ],
        loop=True,
    )

    create_action(
        armature,
        "Walk",
        1,
        24,
        [
            (1, {
                "FrontLegL_Upper": (0.10, 0.0, 0.0),
                "FrontLegR_Upper": (-0.05, 0.0, 0.0),
                "BackLegL_Upper": (-0.58, 0.0, 0.0),
                "BackLegR_Upper": (0.72, 0.0, 0.0),
                "BackLegL_Lower": (0.16, 0.0, 0.0),
                "BackLegR_Lower": (-0.22, 0.0, 0.0),
                "TailBase": (0.0, 0.0, 0.12),
                "Head": (0.03, 0.0, 0.0),
            }),
            (12, {
                "FrontLegL_Upper": (-0.05, 0.0, 0.0),
                "FrontLegR_Upper": (0.10, 0.0, 0.0),
                "BackLegL_Upper": (0.72, 0.0, 0.0),
                "BackLegR_Upper": (-0.58, 0.0, 0.0),
                "BackLegL_Lower": (-0.22, 0.0, 0.0),
                "BackLegR_Lower": (0.16, 0.0, 0.0),
                "TailBase": (0.0, 0.0, -0.12),
                "Head": (-0.03, 0.0, 0.0),
            }),
            (24, {
                "FrontLegL_Upper": (0.10, 0.0, 0.0),
                "FrontLegR_Upper": (-0.05, 0.0, 0.0),
                "BackLegL_Upper": (-0.58, 0.0, 0.0),
                "BackLegR_Upper": (0.72, 0.0, 0.0),
                "BackLegL_Lower": (0.16, 0.0, 0.0),
                "BackLegR_Lower": (-0.22, 0.0, 0.0),
                "TailBase": (0.0, 0.0, 0.12),
                "Head": (0.03, 0.0, 0.0),
            }),
        ],
        loop=True,
    )

    create_action(
        armature,
        "BattleIdle",
        1,
        20,
        [
            (1, {"Chest": (0.04, 0.0, 0.0), "TailBase": (0.0, 0.0, 0.08), "Head": (0.05, 0.0, 0.02), "Jaw": (0.04, 0.0, 0.0)}),
            (10, {"Chest": (-0.03, 0.0, 0.0), "TailBase": (0.0, 0.0, -0.08), "Head": (-0.05, 0.0, -0.03), "Jaw": (0.0, 0.0, 0.0)}),
            (20, {"Chest": (0.04, 0.0, 0.0), "TailBase": (0.0, 0.0, 0.08), "Head": (0.05, 0.0, 0.02), "Jaw": (0.04, 0.0, 0.0)}),
        ],
        loop=True,
    )

    create_action(
        armature,
        "Attack",
        1,
        16,
        [
            (1, {"Chest": (0.0, 0.0, 0.0), "Head": (0.0, 0.0, 0.0), "TailBase": (0.0, 0.0, 0.0), "Jaw": (0.0, 0.0, 0.0)}),
            (6, {"Chest": (-0.28, 0.0, 0.0), "Head": (0.40, 0.0, 0.0), "TailBase": (0.0, 0.0, 0.20), "Jaw": (0.32, 0.0, 0.0)}),
            (10, {"Chest": (0.22, 0.0, 0.0), "Head": (-0.18, 0.0, 0.0), "TailBase": (0.0, 0.0, -0.22), "Jaw": (0.08, 0.0, 0.0)}),
            (16, {"Chest": (0.0, 0.0, 0.0), "Head": (0.0, 0.0, 0.0), "TailBase": (0.0, 0.0, 0.0), "Jaw": (0.0, 0.0, 0.0)}),
        ],
        loop=False,
    )

    create_action(
        armature,
        "HappyChirp",
        1,
        18,
        [
            (1, {"Head": (0.0, 0.0, 0.0), "Jaw": (0.0, 0.0, 0.0)}),
            (5, {"Head": (0.18, 0.0, 0.12), "Jaw": (0.30, 0.0, 0.0)}),
            (10, {"Head": (-0.14, 0.0, -0.12), "Jaw": (0.16, 0.0, 0.0)}),
            (18, {"Head": (0.0, 0.0, 0.0), "Jaw": (0.0, 0.0, 0.0)}),
        ],
        loop=False,
    )

    create_action(
        armature,
        "Victory",
        1,
        24,
        [
            (1, {"Chest": (0.0, 0.0, 0.0), "Head": (0.0, 0.0, 0.0), "Jaw": (0.0, 0.0, 0.0)}),
            (8, {"Chest": (-0.18, 0.0, 0.0), "Head": (0.30, 0.0, 0.14), "TailBase": (0.0, 0.0, 0.12), "Jaw": (0.12, 0.0, 0.0)}),
            (16, {"Chest": (-0.12, 0.0, 0.0), "Head": (0.18, 0.0, -0.14), "TailBase": (0.0, 0.0, -0.12), "Jaw": (0.04, 0.0, 0.0)}),
            (24, {"Chest": (0.0, 0.0, 0.0), "Head": (0.0, 0.0, 0.0), "TailBase": (0.0, 0.0, 0.0), "Jaw": (0.0, 0.0, 0.0)}),
        ],
        loop=False,
    )


def save_and_export(armature):
    reset_pose(armature)
    bpy.context.scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)

    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    for obj in bpy.data.objects:
        if obj.parent == armature:
            obj.select_set(True)

    try:
        bpy.ops.export_scene.gltf(
            filepath=GLB_PATH,
            export_format="GLB",
            use_selection=True,
            export_yup=True,
            export_animations=True,
            export_animation_mode="ACTIONS",
            export_nla_strips=False,
            export_apply=True,
        )
    except TypeError:
        bpy.ops.export_scene.gltf(
            filepath=GLB_PATH,
            export_format="GLB",
            use_selection=True,
            export_yup=True,
            export_animations=True,
            export_nla_strips=False,
            export_apply=True,
        )


def main():
    clean_scene()
    set_scene_defaults()

    primary_mat = make_material("DinoPrimary", PRIMARY_COLOR)
    accent_mat = make_material("DinoAccent", ACCENT_COLOR, emission_strength=0.25)
    eye_white_mat = make_material("DinoEyeWhite", EYE_WHITE_COLOR)
    pupil_mat = make_material("DinoPupil", PUPIL_COLOR)
    tooth_mat = make_material("DinoTooth", TOOTH_COLOR)

    armature = create_armature()
    build_mesh_rig(armature, primary_mat, accent_mat, eye_white_mat, pupil_mat, tooth_mat)
    make_light_camera()
    build_actions(armature)
    save_and_export(armature)

    print(f"Saved blend: {BLEND_PATH}")
    print(f"Exported glb: {GLB_PATH}")


if __name__ == "__main__":
    main()
