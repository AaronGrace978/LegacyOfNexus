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

- Live Dino Buddy visual scene: `res://scenes/buddies/dino_buddy_meshy_visual.tscn`
  (Meshy AI emerald baby dinosaur — see `art/exports/dino_buddy/README_MESHY.md`).
  Hand-sculpt and Quaternius variants remain wired and selectable via
  `data/buddies/buddy_definitions.json`.
- Buddy data source: `data/buddies/buddy_definitions.json`
- Follower controller: `scripts/player/dino_buddy.gd`

## Development Notes

- Keep generated Godot cache files out of commits when possible (`.godot/`).
- Large binary tool downloads (like local installers) should remain local-only unless explicitly versioned.
- Use the rig validation script when changing Dino assets:
  - `res://scripts/tools/validate_dino_rig.gd`

### Blender GPT addon (optional art pipeline boost)

Blender GPT-style addons run **inside Blender only**. They do not load into Godot; they speed up modeling, rigging, and Python automation, then you export the same `*.glb` files the game already imports.

**Install (this repo’s portable Blender 5.1)**

1. Open `Blender\blender.exe` from this project (or your own Blender 5.x build).
2. **Edit → Preferences → Add-ons → Install…** and pick `blendergpt_addon_v2.1.0.zip` (or extract the add-on folder into `Blender\5.1\scripts\addons\` and enable it in Preferences).
3. Configure the addon’s API key or provider settings per its README (keep keys out of git).

**Make the game better without breaking the pipeline**

- Treat the addon as a **copilot for `art/blender/**/*.py`** and manual mesh work. After changes, re-run the documented rebuild commands in `art/blender/dino_buddy/README.md` and **`validate_dino_rig.gd`** so bone names, action names, and export paths still match what Godot expects.
- When prompting, paste the **exact bone and action lists** from that README so generated rig or script edits stay compatible with `dino_buddy.gd` and battle scenes.
- Prefer **headless rebuild + validation** (same PowerShell one-liners in the Dino README) so you catch regressions before opening Godot.

### Nexus Importer (Blender → Godot glTF)

The **Nexus Importer** Godot addon is vendored at `addons/nexus_importer/` and enabled in `project.godot`. It post-processes glTF files exported with the **[Nexus: Godot Pipeline](https://superhivemarket.com/products/nexus-godot-pipeline)** Blender addon (metadata for collision, external materials, groups, etc.).

- **Without the Blender addon:** ordinary `*.glb` / `*.gltf` imports behave as they always have; Nexus only adds behavior when Nexus export metadata is present.
- **With the Blender addon:** export from Blender into this project (for example `art/exports/nexus/` for Nexus-tagged levels and props, alongside existing folders like `art/exports/dino_buddy/`) and use Nexus’s import tooling so collision, material links, and wrapper scenes stay in sync across re-exports.
- **Submodule / updates:** to track upstream releases instead of the vendored copy, see [SUBMODULE_SETUP.md](https://github.com/undomick/godot-nexus-importer/blob/main/SUBMODULE_SETUP.md) in the importer repo.

## Roadmap (Short-Term)

- Improve buddy battle readability and VFX feedback.
- Expand companion dialogue context and reactions.
- Add save/load UX polish and quest progression clarity.
- Continue art polish on buddy variants and world landmarks.
