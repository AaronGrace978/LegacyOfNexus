# Godot 3D Foundation

## Current Direction
`Legacy of Nexus` is now targeting a `3D` implementation in `Godot` with:
- third-person overworld exploration
- separate battle arena transitions
- a prototype-first workflow using placeholder environments and meshes

## Current Project Structure
- `project.godot`: Godot project configuration and input actions
- `scenes/main/main.tscn`: game root scene
- `scenes/world/overworld.tscn`: third-person exploration prototype
- `scenes/player/player.tscn`: player controller and camera rig
- `scenes/battle/battle_arena.tscn`: separate battle-space prototype
- `scripts/main/game_root.gd`: simple overworld/battle scene switching
- `scripts/player/player_controller.gd`: third-person movement and camera control
- `scripts/battle/battle_arena.gd`: battle placeholder scene logic

## Prototype Controls
- `WASD`: move
- `Shift`: sprint
- `Space`: jump
- `Q`: toggle battle prototype
- `Esc`: release or recapture mouse

## Next Build Priorities
1. Replace the debug arena toggle with real encounter triggers.
2. Add a Buddy follower placeholder beside the player.
3. Build the phone UI as a Godot `Control` scene layered over the 3D world.
4. Create a battle state machine for `2v2` turn order, actions, and pair abilities.
5. Add data resources for Buddies, personalities, bond levels, and moves.
