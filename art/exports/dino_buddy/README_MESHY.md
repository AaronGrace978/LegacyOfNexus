Meshy AI "Emerald Baby Dinosaur (biped)" assets used as the live Dino Buddy.

Source files (renamed from the raw Meshy exports):

- `dino_buddy_meshy_character.glb` — base character with skin and armature.
- `dino_buddy_meshy_walk.glb` — walking clip on the same armature ("...Animation_Walking_withSkin").
- `dino_buddy_meshy_run.glb` — running clip on the same armature ("...Animation_Running_withSkin").

Live wiring:

- `data/buddies/buddy_definitions.json` points Dino Buddy at
  `res://scenes/buddies/dino_buddy_meshy_visual.tscn` for both battle and
  overworld.
- `scenes/player/player.tscn` instances the same Meshy visual scene as the
  `DinoBuddy/ModelRoot` so the follower in the park uses these meshes too.
- `scenes/buddies/dino_buddy_meshy_visual.tscn` instances the character GLB
  and adds a `MeshyAnimationMerger` node that, on `_ready`, copies the
  walk/run animations from the sibling GLBs into the character's
  `AnimationPlayer` and registers them under the project-standard
  `Walk` / `Run` names so existing buddy and battle animation lookups
  resolve them with no further changes.
- `scripts/player/dino_buddy.gd` and `scripts/battle/battle_unit.gd` detect
  the Meshy model by the presence of `MeshyAnimationMerger` and:
    - apply `MESHY_OVERWORLD_SCALE` / `MESHY_BATTLE_SCALE`,
    - skip palette tinting so Meshy's baked PBR materials remain intact.

Tuning notes:

- Default scales (`0.65` overworld, `0.95` battle) are best-effort — adjust
  in `dino_buddy.gd` / `battle_unit.gd` constants if the buddy reads too
  small or too tall in your park / battle framing.
- If the merged animation tracks do not drive the rig, the source GLBs
  likely use a different armature node-path than the character GLB.
  Confirm in the Godot Inspector that all four GLBs share the same
  `Armature/Skeleton3D` hierarchy, or re-export them together from a
  shared rig.
- To revert to the hand-sculpt buddy without losing any assets, change the
  two Dino Buddy scene paths in `data/buddies/buddy_definitions.json`
  back to `res://scenes/buddies/dino_buddy_sculpt_visual.tscn` and update
  the `1_dino_visual` `ext_resource` in `scenes/player/player.tscn`.
