# Dino Buddy Rig Pipeline

## Primitive rig (baseline)

Generated assets:

- `art/blender/dino_buddy/dino_buddy_rigged.blend`
- `art/exports/dino_buddy/dino_buddy_rigged.glb`
- `art/blender/dino_buddy/build_dino_buddy_rig.py`

Included bones:

- `Root`
- `Hips`
- `Chest`
- `Neck`
- `Head`
- `Jaw`
- `TailBase`
- `TailMid`
- `TailTip`
- `FrontLegL_Upper`
- `FrontLegL_Lower`
- `FrontLegL_Foot`
- `FrontLegR_Upper`
- `FrontLegR_Lower`
- `FrontLegR_Foot`
- `BackLegL_Upper`
- `BackLegL_Lower`
- `BackLegL_Foot`
- `BackLegR_Upper`
- `BackLegR_Lower`
- `BackLegR_Foot`

Included actions:

- `Idle`
- `Walk`
- `BattleIdle`
- `Attack`
- `HappyChirp`
- `Victory`

Rebuild command:

```powershell
& "G:\Legacy of Nexus\Blender\blender.exe" --background --python "G:\Legacy of Nexus\art\blender\dino_buddy\build_dino_buddy_rig.py"
```

Validation command:

```powershell
& "G:\Legacy of Nexus\Godot_v4.6.2-stable_win64_console.exe" --headless --path "G:\Legacy of Nexus" -s "res://scripts/tools/validate_dino_rig.gd"
```

## Sculpt rig (current live Dino Buddy)

Built by rigging the hand-sculpted hero mesh onto the same armature so it
inherits every action the primitive rig already authored. Shares the same
bones and animation names with the primitive rig, so the gameplay scripts
don't need to know which variant is loaded.

Source / generated assets:

- Source sculpt:      `art/exports/dino_buddy/dino_buddy_sculpt.glb`
- Sculpt STL backup:  `art/exports/dino_buddy/source/dino_buddy_sculpt.stl` (behind `.gdignore`)
- Build script:       `art/blender/dino_buddy/build_dino_buddy_sculpt_rig.py`
- Rig .blend:         `art/blender/dino_buddy/dino_buddy_sculpt_rigged.blend`
- Rigged GLB:         `art/exports/dino_buddy/dino_buddy_sculpt_rigged.glb`
- Preview render:     `art/blender/dino_buddy/sculpt_preview.png`
- Godot scene:        `scenes/buddies/dino_buddy_sculpt_visual.tscn`

Pipeline overview:

1. Import `dino_buddy_sculpt.glb` (~285k raw triangles).
2. Decimate with a COLLAPSE modifier to a ~12k triangle game budget.
3. Fit the sculpt bbox to the armature's deform-bone bbox (scaled, centered,
   with small padding so the mesh envelopes the bones).
4. Reuse `build_dino_buddy_rig.create_armature()` and `build_actions()` from
   the primitive pipeline so the bones (`Root`, `Hips`, `Chest`, `Neck`,
   `Head`, `Jaw`, `TailBase/Mid/Tip`, `Front/BackLegL/R_Upper/Lower/Foot`)
   and actions (`Idle`, `Walk`, `BattleIdle`, `Attack`, `HappyChirp`,
   `Victory`) match exactly.
5. Bind with Blender's automatic weights (`ARMATURE_AUTO`). If bone-heat
   weighting fails to produce any useful weights (common with a sculpt whose
   topology doesn't match the armature), fall back to proximity weighting
   (1.0 to the nearest deform bone, 0.35 to the second-nearest, smoothed).
6. Export with animations, Y-up, and apply-modifiers on.

Rebuild command:

```powershell
& "G:\Legacy of Nexus\Blender\blender.exe" --background --python `
  "G:\Legacy of Nexus\art\blender\dino_buddy\build_dino_buddy_sculpt_rig.py"
```

Preview render command:

```powershell
& "G:\Legacy of Nexus\Blender\blender.exe" --background --python `
  "G:\Legacy of Nexus\.tools\render_dino_sculpt_preview.py"
```

If after rebuilding, the dino's snout ends up on the tail side of the rig
(i.e. animations look mirrored), flip the `SCULPT_FACES_POSITIVE_Y` flag at
the top of `build_dino_buddy_sculpt_rig.py` and re-run.

Engine-side hooks:

- `scripts/player/dino_buddy.gd` detects the sculpt rig via a
  `DinoBuddySculpt` child node and applies `SCULPT_OVERWORLD_SCALE` at
  runtime. Bond palette recoloring also recognizes the `DinoSculptSkin`
  material name.
- `data/buddies/buddy_definitions.json` points Dino Buddy's battle and
  overworld-follower visual scenes at `dino_buddy_sculpt_visual.tscn`.
- `scripts/tools/validate_dino_rig.gd` asserts that the rigged GLB loads,
  exposes an `AnimationPlayer` with all six expected animations, and that
  the catalog resolves Dino Buddy through the sculpt scene.

To revert to the animated Quaternius model without losing any assets, change
the two `Dino Buddy` scene paths in `data/buddies/buddy_definitions.json`
back to `res://scenes/buddies/dino_buddy_visual.tscn`.
