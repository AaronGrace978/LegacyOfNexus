"""Rig the high-poly Dino Buddy sculpt onto the shared Dino Buddy armature.

This script:
  1. Cleans the Blender scene.
  2. Imports `art/exports/dino_buddy/dino_buddy_sculpt.glb` (a raw, un-rigged,
     ~285k-triangle hero sculpt delivered for Dino Buddy).
  3. Decimates it to a game-friendly triangle budget.
  4. Normalizes its placement so it lines up with the shared armature
     (feet on the ground plane, centered on X, facing -Y as the existing rig expects).
  5. Reuses `build_dino_buddy_rig.create_armature()` + `build_actions()` so the
     sculpt-rigged dino shares its bones and animation names (Idle / Walk /
     BattleIdle / Attack / HappyChirp / Victory) with the primitive rig.
  6. Binds the sculpt to the armature with automatic weights.
  7. Exports `art/exports/dino_buddy/dino_buddy_sculpt_rigged.glb`.

Because the engine side (`scripts/player/dino_buddy.gd`) already resolves
`Idle`, `Walk`, `HappyChirp`, etc., the exported GLB is a drop-in replacement
for the Quaternius model whenever the visual scene is swapped to point at it.

Rebuild:

    & "G:\\Legacy of Nexus\\Blender\\blender.exe" --background --python \
      "G:\\Legacy of Nexus\\art\\blender\\dino_buddy\\build_dino_buddy_sculpt_rig.py"
"""

from __future__ import annotations

import os
import sys

import bpy


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import build_dino_buddy_rig as base  # noqa: E402  (intentional late import after sys.path tweak)


EXPORT_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, "..", "..", "exports", "dino_buddy"))
SOURCE_GLB = os.path.join(EXPORT_DIR, "dino_buddy_sculpt.glb")
BLEND_PATH = os.path.join(SCRIPT_DIR, "dino_buddy_sculpt_rigged.blend")
GLB_PATH = os.path.join(EXPORT_DIR, "dino_buddy_sculpt_rigged.glb")

# Game-friendly triangle budget. The primitive rig lands around ~4k tris; the
# Quaternius Dino is ~10k. Matching the latter keeps the sculpt visually richer
# than primitives without blowing the character-budget ballpark.
TARGET_TRIANGLE_COUNT = 12_000

# Flip the sculpt 180 degrees around Z if it imports facing the wrong way.
# The rig expects the dino's snout to point toward -Y. If after running this
# script the snout ends up on the tail side of the armature, flip this flag
# and rerun.
SCULPT_FACES_POSITIVE_Y = False

# Padding added around the armature's deform-bone bbox when fitting the sculpt,
# so the mesh silhouette completely envelopes the bones (required for
# bone-heat weighting to have anything to latch onto).
ARMATURE_FIT_PADDING = 0.10

# Per-vertex color ramp: feature-film chibi rex boards (saturated forest green,
# warm cream belly / throat). Values are linear sRGB 0-1.
BACK_COLOR = (0.07, 0.50, 0.20, 1.0)         # deep saturated green along the spine
BODY_COLOR = (0.20, 0.78, 0.38, 1.0)         # bright hero green on flanks / limbs
BELLY_COLOR = (0.96, 0.93, 0.72, 1.0)        # warm cream underbelly
THROAT_HIGHLIGHT = (0.99, 0.97, 0.86, 1.0)   # light cream under the jaw

# Eye palette for Pixar-style layered eyes (sclera + amber iris + gloss highlight).
# Godot still overrides these at runtime; matching here keeps Blender previews honest.
EYE_WHITE_COLOR = (0.95, 0.94, 0.92, 1.0)
EYE_IRIS_COLOR = (0.52, 0.36, 0.11, 1.0)
EYE_PUPIL_COLOR = (0.02, 0.015, 0.01, 1.0)
EYE_HIGHLIGHT_COLOR = (1.0, 1.0, 1.0, 1.0)

# Eye placement on the sculpt, in the same world-space frame as the armature.
# Sockets sit on the upper-sides of the head; the orb fills the socket.
EYE_CENTER_XY = (0.19, -0.78)   # (|x|, y) for left/right pair
EYE_CENTER_Z = 1.70
EYE_SCLERA_SCALE = (0.105, 0.095, 0.105)        # big dark orb, slightly squashed front-to-back
EYE_IRIS_FORWARD_OFFSET = -0.095
EYE_IRIS_SCALE = (0.062, 0.014, 0.062)
EYE_PUPIL_FORWARD_OFFSET = -0.103
EYE_PUPIL_SCALE = (0.026, 0.010, 0.026)
EYE_HIGHLIGHT_FORWARD_OFFSET = -0.108
EYE_HIGHLIGHT_SCALE = (0.014, 0.006, 0.014)
EYE_HIGHLIGHT_LIFT_Z = 0.038


def _count_triangles(mesh_obj: bpy.types.Object) -> int:
    total = 0
    for polygon in mesh_obj.data.polygons:
        verts = len(polygon.vertices)
        if verts >= 3:
            total += verts - 2
    return total


def _import_sculpt() -> bpy.types.Object:
    if not os.path.exists(SOURCE_GLB):
        raise FileNotFoundError(
            "Expected sculpt asset at %s. Drop the high-poly Dino Buddy GLB here "
            "before running this script." % SOURCE_GLB
        )

    pre_existing = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=SOURCE_GLB)
    new_objects = [obj for obj in bpy.data.objects if obj not in pre_existing]

    mesh_obj = next((obj for obj in new_objects if obj.type == "MESH"), None)
    if mesh_obj is None:
        raise RuntimeError("Sculpt GLB did not contain a mesh object.")

    # Drop everything else the GLB brought in (empties, cameras, etc.) so we keep
    # a clean scene graph under the armature we're about to build.
    for obj in new_objects:
        if obj is mesh_obj:
            continue
        bpy.data.objects.remove(obj, do_unlink=True)

    mesh_obj.name = "DinoBuddySculpt"
    mesh_obj.data.name = "DinoBuddySculptMesh"

    base.select_objects([mesh_obj], mesh_obj)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    return mesh_obj


def _armature_deform_bbox(armature: bpy.types.Object):
    """Return (min_v, max_v) world-space AABB covering all deform bones."""
    from mathutils import Vector  # noqa: WPS433 (Blender dep only available at runtime)

    mat = armature.matrix_world
    xs, ys, zs = [], [], []
    for bone in armature.data.bones:
        if not bone.use_deform:
            continue
        for local in (bone.head_local, bone.tail_local):
            world = mat @ local
            xs.append(world.x)
            ys.append(world.y)
            zs.append(world.z)
    if not xs:
        raise RuntimeError("Armature has no deform bones to fit sculpt against.")
    return Vector((min(xs), min(ys), min(zs))), Vector((max(xs), max(ys), max(zs)))


def _normalize_sculpt_to_armature(mesh_obj: bpy.types.Object, armature: bpy.types.Object) -> None:
    """Scale + translate the sculpt so its bbox matches the armature's bones.

    We fit to the armature's tightest-axis (height, Z) so the sculpt doesn't
    squash, then center the sculpt's X/Y bbox around the armature's bone bbox.
    Padding ensures the mesh surface fully envelopes the bones (required for
    bone-heat weighting to solve).
    """
    base.select_objects([mesh_obj], mesh_obj)

    if SCULPT_FACES_POSITIVE_Y:
        mesh_obj.rotation_euler = (0.0, 0.0, 3.141592653589793)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)

    arm_min, arm_max = _armature_deform_bbox(armature)
    arm_size = arm_max - arm_min
    target_height = max(arm_size.z, 0.001) + ARMATURE_FIT_PADDING * 2.0

    current_height = max(mesh_obj.dimensions.z, 1e-6)
    scale_factor = target_height / current_height
    mesh_obj.scale = (scale_factor, scale_factor, scale_factor)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    verts_world = [mesh_obj.matrix_world @ v.co for v in mesh_obj.data.vertices]
    if not verts_world:
        return

    mesh_min_x = min(v.x for v in verts_world)
    mesh_max_x = max(v.x for v in verts_world)
    mesh_min_y = min(v.y for v in verts_world)
    mesh_max_y = max(v.y for v in verts_world)
    mesh_min_z = min(v.z for v in verts_world)

    mesh_center_x = (mesh_min_x + mesh_max_x) * 0.5
    mesh_center_y = (mesh_min_y + mesh_max_y) * 0.5
    arm_center_x = (arm_min.x + arm_max.x) * 0.5
    arm_center_y = (arm_min.y + arm_max.y) * 0.5

    mesh_obj.location.x += arm_center_x - mesh_center_x
    mesh_obj.location.y += arm_center_y - mesh_center_y
    mesh_obj.location.z += arm_min.z - mesh_min_z - ARMATURE_FIT_PADDING
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)

    verts_world = [mesh_obj.matrix_world @ v.co for v in mesh_obj.data.vertices]
    final_min = [
        min(v.x for v in verts_world),
        min(v.y for v in verts_world),
        min(v.z for v in verts_world),
    ]
    final_max = [
        max(v.x for v in verts_world),
        max(v.y for v in verts_world),
        max(v.z for v in verts_world),
    ]
    print(
        "Armature bone bbox: ({:.2f},{:.2f},{:.2f}) -> ({:.2f},{:.2f},{:.2f})".format(
            arm_min.x, arm_min.y, arm_min.z, arm_max.x, arm_max.y, arm_max.z
        )
    )
    print(
        "Sculpt fit bbox:   ({:.2f},{:.2f},{:.2f}) -> ({:.2f},{:.2f},{:.2f})".format(
            final_min[0], final_min[1], final_min[2], final_max[0], final_max[1], final_max[2]
        )
    )


def _decimate_to_budget(mesh_obj: bpy.types.Object) -> None:
    base.select_objects([mesh_obj], mesh_obj)
    triangles_before = _count_triangles(mesh_obj)
    if triangles_before <= TARGET_TRIANGLE_COUNT:
        print(f"Sculpt already under budget ({triangles_before} tris); skipping decimate.")
        return

    ratio = max(0.001, min(1.0, TARGET_TRIANGLE_COUNT / float(triangles_before)))
    modifier = mesh_obj.modifiers.new("SculptDecimate", "DECIMATE")
    modifier.decimate_type = "COLLAPSE"
    modifier.ratio = ratio
    modifier.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.ops.object.shade_smooth()

    triangles_after = _count_triangles(mesh_obj)
    print(f"Decimated sculpt: {triangles_before} -> {triangles_after} triangles "
          f"(ratio {ratio:.3f}).")


def _apply_skin_material(mesh_obj: bpy.types.Object) -> None:
    """Vertex-color-driven skin so the sculpt reads as a two-tone chibi dino.

    Base color is pure white so the per-vertex colors written by
    `_paint_body_tones` come through unmodulated. Godot's glTF importer picks
    up the `COLOR_0` attribute and the `StandardMaterial3D.vertex_color_use_as_albedo`
    flag, which ensures the tones show up in-engine.
    """
    mat = bpy.data.materials.new("DinoSculptSkin")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links

    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.52
    bsdf.inputs["Metallic"].default_value = 0.03
    # Viewport parity with Godot's skin SSS approximation (when present on this BSDF).
    for _socket_name in ("Subsurface Weight", "Subsurface"):
        _inp = bsdf.inputs.get(_socket_name)
        if _inp is not None and hasattr(_inp, "default_value"):
            _inp.default_value = 0.12 if isinstance(_inp.default_value, float) else 0.12
            break

    vertex_color_node = nodes.new(type="ShaderNodeVertexColor")
    vertex_color_node.layer_name = "Col"
    vertex_color_node.location = (-300, 200)
    links.new(vertex_color_node.outputs["Color"], bsdf.inputs["Base Color"])

    mesh_obj.data.materials.clear()
    mesh_obj.data.materials.append(mat)


def _smoothstep(edge_low: float, edge_high: float, value: float) -> float:
    if edge_high <= edge_low:
        return 0.0 if value < edge_low else 1.0
    t = (value - edge_low) / (edge_high - edge_low)
    if t < 0.0:
        return 0.0
    if t > 1.0:
        return 1.0
    return t * t * (3.0 - 2.0 * t)


def _paint_body_tones(mesh_obj: bpy.types.Object, armature: bpy.types.Object) -> None:
    """Write a per-vertex color ramp across the sculpt.

    Mapping rule (world-space, Blender Z-up):
      - Back / top-facing surfaces (normal.z > +0.3)      -> BACK_COLOR
      - Belly / downward-facing surfaces (normal.z < -0.2) -> BELLY_COLOR
      - Throat region under the jaw                        -> THROAT_HIGHLIGHT
      - Everything else                                    -> BODY_COLOR
    The ramp uses smoothstep blends so there are no hard seams between zones.
    """
    mesh = mesh_obj.data

    color_layer_name = "Col"
    if color_layer_name in mesh.color_attributes:
        mesh.color_attributes.remove(mesh.color_attributes[color_layer_name])
    color_attr = mesh.color_attributes.new(
        name=color_layer_name,
        type="BYTE_COLOR",
        domain="POINT",
    )

    arm_min, arm_max = _armature_deform_bbox(armature)
    throat_center_y = arm_min.y + (arm_max.y - arm_min.y) * 0.15
    throat_top_z = arm_max.z - (arm_max.z - arm_min.z) * 0.20
    throat_bottom_z = arm_max.z - (arm_max.z - arm_min.z) * 0.40

    mesh_matrix = mesh_obj.matrix_world
    for index, vertex in enumerate(mesh.vertices):
        world_pos = mesh_matrix @ vertex.co
        world_normal = (mesh_matrix.to_3x3() @ vertex.normal).normalized()

        # On a bipedal dino the chest/belly surfaces don't face straight down
        # -- most chest normals are forward (-Y) combined with slightly downward.
        # So belly_signal mixes downward AND forward components.
        up_signal = max(0.0, world_normal.z)
        down_signal = max(0.0, -world_normal.z)
        forward_signal = max(0.0, -world_normal.y)

        back_factor = _smoothstep(0.15, 0.65, up_signal)
        belly_signal = down_signal + forward_signal * 0.55
        belly_factor = _smoothstep(0.15, 0.75, belly_signal)

        # Clamp so a back-facing vertex never also claims belly weight.
        belly_factor = min(belly_factor, max(0.0, 1.0 - back_factor))

        side_factor = max(0.0, 1.0 - back_factor - belly_factor)

        color = [0.0, 0.0, 0.0, 1.0]
        for channel in range(3):
            color[channel] = (
                BODY_COLOR[channel] * side_factor
                + BACK_COLOR[channel] * back_factor
                + BELLY_COLOR[channel] * belly_factor
            )

        throat_proximity = (
            _smoothstep(0.35, 0.0, abs(world_pos.y - throat_center_y))
            * _smoothstep(throat_bottom_z, throat_top_z, world_pos.z)
            * _smoothstep(0.30, 0.0, abs(world_pos.x))
            * _smoothstep(-0.2, 0.5, -world_normal.z)
        )
        if throat_proximity > 0.0:
            for channel in range(3):
                color[channel] = (
                    color[channel] * (1.0 - throat_proximity)
                    + THROAT_HIGHLIGHT[channel] * throat_proximity
                )

        color_attr.data[index].color = (color[0], color[1], color[2], 1.0)


def _parent_to_bone_at_rest(obj: bpy.types.Object, armature: bpy.types.Object, bone_name: str) -> None:
    """Keep `obj` at its current world pose when parenting to a bone.

    `base.parent_to_bone` computes `matrix_parent_inverse` from the bone's
    HEAD matrix, but Blender's "BONE" parent type uses the bone's TAIL as the
    origin of the local frame. That mismatch produces a constant offset equal
    to (tail - head) for every bone-parented child. In the primitive rig all
    mesh parts shift together so the bug is invisible; here the sculpt body
    is weight-bound at rest position while the eyes are bone-parented, so the
    offset makes them float past the snout. This helper computes the matrix
    Blender actually uses and inverts that instead.
    """
    from mathutils import Matrix  # noqa: WPS433 (runtime Blender dep)

    pose_bone = armature.pose.bones[bone_name]

    desired_world = obj.matrix_world.copy()

    obj.parent = armature
    obj.parent_type = "BONE"
    obj.parent_bone = bone_name

    bone_tail_world = (
        armature.matrix_world
        @ pose_bone.matrix
        @ Matrix.Translation((0.0, pose_bone.length, 0.0))
    )
    obj.matrix_parent_inverse = bone_tail_world.inverted() @ desired_world
    obj.matrix_basis = Matrix.Identity(4)


def _add_eye_assembly(armature: bpy.types.Object):
    """Add bone-parented eye spheres (sclera / iris / pupil / highlight)."""
    eye_white_mat = base.make_material("DinoEyeWhite", EYE_WHITE_COLOR)
    iris_mat = base.make_material("DinoEyeIris", EYE_IRIS_COLOR)
    pupil_mat = base.make_material("DinoEyePupil", EYE_PUPIL_COLOR)
    highlight_mat = base.make_material("DinoEyeHighlight", EYE_HIGHLIGHT_COLOR, emission_strength=2.1)

    created = []
    abs_x, center_y = EYE_CENTER_XY
    for sign in (-1.0, 1.0):
        x = abs_x * sign

        sclera = base.add_scaled_sphere(
            f"EyeWhite_{int(sign)}",
            (x, center_y, EYE_CENTER_Z),
            EYE_SCLERA_SCALE,
            eye_white_mat,
        )
        iris = base.add_scaled_sphere(
            f"EyeIris_{int(sign)}",
            (x, center_y + EYE_IRIS_FORWARD_OFFSET, EYE_CENTER_Z),
            EYE_IRIS_SCALE,
            iris_mat,
        )
        pupil = base.add_scaled_sphere(
            f"EyePupil_{int(sign)}",
            (x, center_y + EYE_PUPIL_FORWARD_OFFSET, EYE_CENTER_Z),
            EYE_PUPIL_SCALE,
            pupil_mat,
        )
        highlight = base.add_scaled_sphere(
            f"EyeHighlight_{int(sign)}",
            (
                x + 0.015 * sign,
                center_y + EYE_HIGHLIGHT_FORWARD_OFFSET,
                EYE_CENTER_Z + EYE_HIGHLIGHT_LIFT_Z,
            ),
            EYE_HIGHLIGHT_SCALE,
            highlight_mat,
        )

        for obj in (sclera, iris, pupil, highlight):
            _parent_to_bone_at_rest(obj, armature, "Head")
            created.append(obj)

    return created


def _has_useful_weights(mesh_obj: bpy.types.Object) -> bool:
    for vertex in mesh_obj.data.vertices:
        for group in vertex.groups:
            if group.weight > 0.0:
                return True
    return False


# Subset of the armature's bones used for proximity skinning on the sculpt.
# Limb bones (FrontLegX / BackLegX) deform the mesh in ugly ways when the
# animation rotates them and a vertex ends up on the "wrong" side of an
# elbow / knee. Keeping only spine-oriented bones gives clean whole-body
# bob / head-turn / tail-wag deformation without limb melting.
PROXIMITY_WEIGHT_BONES = (
    "Hips",
    "Chest",
    "Neck",
    "Head",
    "Jaw",
    "TailBase",
    "TailMid",
    "TailTip",
)


def _deform_bone_centers(armature: bpy.types.Object):
    """World-space (head+tail)/2 for each spine bone we allow to deform the sculpt."""
    centers = {}
    mat = armature.matrix_world
    allowed = set(PROXIMITY_WEIGHT_BONES)
    for bone in armature.data.bones:
        if not bone.use_deform:
            continue
        if bone.name not in allowed:
            continue
        head = mat @ bone.head_local
        tail = mat @ bone.tail_local
        centers[bone.name] = (head + tail) * 0.5
    return centers


def _apply_proximity_weights(mesh_obj: bpy.types.Object, armature: bpy.types.Object) -> None:
    """Crude fallback skin weights: 1.0 to nearest deform bone, 0.35 to second.

    Produces usable deformation for any sculpt whose topology/orientation defeats
    bone-heat weighting. Not art-quality, but guarantees the mesh actually moves
    with the armature instead of floating past it as an un-skinned prop.
    """
    for vg in list(mesh_obj.vertex_groups):
        mesh_obj.vertex_groups.remove(vg)

    bone_centers = _deform_bone_centers(armature)
    if not bone_centers:
        raise RuntimeError("Armature has no deform bones for proximity weighting.")

    groups = {name: mesh_obj.vertex_groups.new(name=name) for name in bone_centers}

    mesh_matrix = mesh_obj.matrix_world
    for index, vertex in enumerate(mesh_obj.data.vertices):
        vertex_world = mesh_matrix @ vertex.co
        ranked = sorted(
            bone_centers.items(),
            key=lambda kv: (vertex_world - kv[1]).length,
        )
        primary = ranked[0][0]
        groups[primary].add([index], 1.0, "REPLACE")
        if len(ranked) > 1:
            groups[ranked[1][0]].add([index], 0.35, "REPLACE")

    # Smooth weights so the seams between nearest-bone assignments aren't visible
    # across animation frames.
    base.select_objects([mesh_obj], mesh_obj)
    try:
        bpy.ops.object.vertex_group_smooth(
            group_select_mode="ALL",
            factor=0.5,
            repeat=4,
            expand=0.0,
        )
    except (RuntimeError, AttributeError):
        pass


def _ensure_armature_modifier(mesh_obj: bpy.types.Object, armature: bpy.types.Object) -> None:
    for modifier in mesh_obj.modifiers:
        if modifier.type == "ARMATURE":
            if modifier.object is None:
                modifier.object = armature
            return
    modifier = mesh_obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = armature


def _bind_to_armature(mesh_obj: bpy.types.Object, armature: bpy.types.Object) -> None:
    base.select_objects([mesh_obj, armature], armature)
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")

    _ensure_armature_modifier(mesh_obj, armature)

    if _has_useful_weights(mesh_obj):
        print("Auto-weights succeeded.")
        return

    print("Auto-weights produced no useful weights; falling back to proximity skinning.")
    if mesh_obj.parent is not armature:
        mesh_obj.parent = armature
        mesh_obj.parent_type = "OBJECT"
    _apply_proximity_weights(mesh_obj, armature)
    _ensure_armature_modifier(mesh_obj, armature)

    if not _has_useful_weights(mesh_obj):
        raise RuntimeError("Failed to produce any skin weights for the sculpt.")


def _export(mesh_obj: bpy.types.Object, armature: bpy.types.Object) -> None:
    base.reset_pose(armature)
    bpy.context.scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)

    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    mesh_obj.select_set(True)
    bpy.context.view_layer.objects.active = armature
    for obj in bpy.data.objects:
        if obj.parent == armature:
            obj.select_set(True)

    export_kwargs = dict(
        filepath=GLB_PATH,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_animations=True,
        export_nla_strips=False,
        export_apply=True,
    )
    try:
        bpy.ops.export_scene.gltf(**export_kwargs, export_animation_mode="ACTIONS")
    except TypeError:
        bpy.ops.export_scene.gltf(**export_kwargs)


def main() -> None:
    base.clean_scene()
    base.set_scene_defaults()

    # Armature must exist before normalizing so we can fit the sculpt bbox to
    # the armature's bone bbox. Actions are baked before binding so pose mode
    # changes don't interfere with auto-weights.
    armature = base.create_armature()
    base.build_actions(armature)
    base.reset_pose(armature)

    sculpt = _import_sculpt()
    _decimate_to_budget(sculpt)
    _normalize_sculpt_to_armature(sculpt, armature)
    _paint_body_tones(sculpt, armature)
    _apply_skin_material(sculpt)

    _bind_to_armature(sculpt, armature)
    _add_eye_assembly(armature)

    _export(sculpt, armature)

    print(f"Saved blend: {BLEND_PATH}")
    print(f"Exported glb: {GLB_PATH}")
    print(f"Final triangle count: {_count_triangles(sculpt)}")


if __name__ == "__main__":
    main()
