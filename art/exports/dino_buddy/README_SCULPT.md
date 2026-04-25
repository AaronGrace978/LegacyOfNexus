Hand-sculpted hero mesh for Dino Buddy.

Source:
- `dino_buddy_sculpt.glb` -- raw sculpt export (~285k tri, no rig, single material).
- `source/dino_buddy_sculpt.stl` -- STL backup of the same sculpt (kept behind
  `.gdignore` since Godot cannot import STL directly).

Generated:
- `dino_buddy_sculpt_rigged.glb` -- decimated (~12k tri), rigged to the shared
  Dino Buddy armature, with the full `Idle / Walk / BattleIdle / Attack /
  HappyChirp / Victory` action set. The GLB also includes:
    - Per-vertex belly/back/throat color ramp (stored in `COLOR_0`) so the
      chibi two-tone look comes through without needing a texture.
    - Four bone-parented eye assemblies per side (sclera / amber iris / dark
      pupil / emissive highlight) attached to the `Head` bone so they
      follow every head animation.
  Produced by `art/blender/dino_buddy/build_dino_buddy_sculpt_rig.py`.

Live wiring:
- `data/buddies/buddy_definitions.json` points Dino Buddy at
  `res://scenes/buddies/dino_buddy_sculpt_visual.tscn`, which instances the
  rigged GLB.
- `scripts/player/dino_buddy.gd` applies `SCULPT_OVERWORLD_SCALE` when it
  detects a `DinoBuddySculpt` child node on the model root. The same script's
  `_apply_imported_palette` swaps the sculpt skin material for a
  vertex-color-driven `StandardMaterial3D` (`vertex_color_use_as_albedo = true`)
  so the belly/back ramp stays visible through palette tinting.
- `scenes/player/player.tscn` overrides the `DinoBuddy` node with calmer
  roaming / follow-sway / curiosity values so the new sculpt buddy stays
  close to the player instead of darting around.

See `art/blender/dino_buddy/README.md` for the full pipeline description
and rebuild commands.
