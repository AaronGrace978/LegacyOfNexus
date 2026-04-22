# Legacy of Nexus

<img width="656" height="602" alt="image" src="https://github.com/user-attachments/assets/0abe9ab0-54aa-48a7-aaed-13da33fdcad0" />


<img width="1098" height="711" alt="image" src="https://github.com/user-attachments/assets/4a784a6d-de8c-461e-aa64-ef648d2ca95f" />

<img width="1161" height="843" alt="image" src="https://github.com/user-attachments/assets/1278e985-ea58-4da1-91fa-26a9352c1e0c" />


Legacy of Nexus is a Godot 4 action-RPG prototype focused on companion-driven exploration, real-time roaming, and buddy battles.

## Current Focus

- Third-person park exploration with a controllable trainer.
- Companion party systems and encounter scaffolding.
- Dino Buddy social gameplay, including contextual chat hooks.
- Stylized buddy visuals and animation pipelines (Godot + Blender).

## Tech Stack

- Godot 4.6 (Forward+ renderer)
- GDScript gameplay systems
- Blender content pipeline for buddy rigs and animation clips
- Optional local backend integration for Dino chat (`ActivatePrime`)

## Project Structure

- `scenes/` game scenes (main world, player, buddies, UI)
- `scripts/` gameplay logic, systems, UI, and tools
- `data/` buddy definitions and game tuning data
- `art/` exported and source art assets
- `tools/` local helper scripts and launch utilities
- `docs/` supplemental design documentation

## Running The Game (Windows)

### Quick Start (with Dino backend)

1. Ensure `ActivatePrime` exists (or set `ACTIVATE_PRIME_DIR`).
2. Run `Launch_Legacy_of_Nexus_With_Dino_Backend.bat`.
3. The script will:
   - start backend server on `127.0.0.1:8001`
   - wait for `/health`
   - launch Godot with this project
   - stop backend when Godot closes

### Editor / Direct Launch

1. Open project folder in Godot (`project.godot`).
2. Run the main scene: `res://scenes/main/main.tscn`.

## Controls (Default)

- `W A S D`: move
- `Space`: jump
- `Shift`: sprint
- `E`: interact
- `P`: party menu
- `T`: Dino chat
- `J`: journal

## Dino Buddy Notes

- Live Dino Buddy visual scene: `res://scenes/buddies/dino_buddy_visual.tscn`
- Buddy data source: `data/buddies/buddy_definitions.json`
- Follower controller: `scripts/player/dino_buddy.gd`

## Development Notes

- Keep generated Godot cache files out of commits when possible (`.godot/`).
- Large binary tool downloads (like local installers) should remain local-only unless explicitly versioned.
- Use the rig validation script when changing Dino assets:
  - `res://scripts/tools/validate_dino_rig.gd`

## Roadmap (Short-Term)

- Improve buddy battle readability and VFX feedback.
- Expand companion dialogue context and reactions.
- Add save/load UX polish and quest progression clarity.
- Continue art polish on buddy variants and world landmarks.
