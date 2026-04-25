extends Node3D

signal battle_exit_requested

const BATTLE_UNIT_SCENE := preload("res://scenes/battle/battle_unit.tscn")
const BattleUnitScript := preload("res://scripts/battle/battle_unit.gd")
const BattleActionUIScript := preload("res://scripts/battle/battle_action_ui.gd")
const BattlePartyMemberScript := preload("res://scripts/battle/battle_party_member.gd")
const BuddyCatalog := preload("res://scripts/buddies/buddy_catalog.gd")
const BattleMoveCatalog := preload("res://scripts/battle/battle_move_catalog.gd")
const EncounterResolver := preload("res://scripts/battle/encounter_resolver.gd")
const DEFAULT_ENCOUNTER := {
	"enemies": [
		{"name": "Red Rogue", "level": 4},
		{"name": "Red Shade", "level": 3},
	]
}

const DINO_MOVE_LINES := {
	"hype_tackle": ["Let's gooo!", "Boom—opening play!", "You feel that? That's momentum!"],
	"combo_tail_whip": ["Clear the lane—I spin for two!", "Tail check! Everyone eats this!", "Two-for-one special coming up!"],
	"loyal_roar": ["I got your back!", "Hold the line—stack the hype!", "We win this together—dig in, partner!"],
}

enum BattleState {
	BUSY,
	PLAYER_CHOICE,
	TARGET_SELECT,
	SWAP_SELECT,
	ITEM_PICKING,
	CAPTURE_SYNC,
	ENEMY_ACTION,
	VICTORY,
	DEFEAT,
	RETURNING,
}

@onready var action_ui: BattleActionUIScript = $BattleActionUI
@onready var ally_front_slot: Marker3D = $Slots/Allies/FrontLeft
@onready var ally_back_slot: Marker3D = $Slots/Allies/BackLeft
@onready var enemy_front_slot: Marker3D = $Slots/Enemies/FrontRight
@onready var enemy_back_slot: Marker3D = $Slots/Enemies/BackRight
@onready var units_container: Node3D = $Units
@onready var capture_ui: CanvasLayer = $CaptureRhythmUI
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun
@onready var fill_light: OmniLight3D = $FillLight
@onready var rim_light: OmniLight3D = $RimLight
@onready var camera_rig: Node3D = $CameraRig
@onready var battle_camera: Camera3D = $CameraRig/Camera3D
@onready var arena_floor_mesh: MeshInstance3D = $ArenaFloor/MeshInstance3D
@onready var backdrop: MeshInstance3D = $Backdrop
@onready var backdrop_left: MeshInstance3D = $BackdropLeft
@onready var backdrop_right: MeshInstance3D = $BackdropRight

var dino_buddy: BattleUnitScript
var ally_support: BattleUnitScript
var front_enemy: BattleUnitScript
var rear_enemy: BattleUnitScript
var state := BattleState.BUSY
var party_roster: Array = []
var active_second_party_index := -1
var selectable_targets: Array[BattleUnitScript] = []
var pending_move_id := ""
var acting_unit: BattleUnitScript
var acting_turn_key := ""
var pending_damage_overrides: Dictionary = {}
var turn_order := ["player_1", "player_2", "enemy_1", "enemy_2"]
var turn_index := -1
var swap_forced := false
var battle_rng := RandomNumberGenerator.new()
var active_capture_target: BattleUnitScript
var skip_capture_offer_once := false
var _encounter_data: Dictionary = {}
var _arena_theme: Dictionary = {}
var _arena_vfx_root: Node3D
var _ambient_shards: Array[MeshInstance3D] = []
var _pulse_meshes: Array[MeshInstance3D] = []
var _arena_time := 0.0
var _camera_base_position := Vector3.ZERO
var _camera_base_rotation := Vector3.ZERO


func _ready() -> void:
	battle_rng.randomize()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	action_ui.action_selected.connect(_on_action_selected)
	action_ui.swap_selected.connect(_on_swap_selected)
	action_ui.swap_cancelled.connect(_on_swap_cancelled)
	action_ui.item_selected.connect(_on_battle_item_selected)
	action_ui.item_picker_cancelled.connect(_on_item_picker_cancelled)
	if capture_ui != null:
		if capture_ui.has_signal("capture_succeeded"):
			capture_ui.capture_succeeded.connect(_on_capture_succeeded)
		if capture_ui.has_signal("capture_failed"):
			capture_ui.capture_failed.connect(_on_capture_failed)
	_load_party_from_manager()
	_load_encounter_data()
	_apply_battle_theme()
	_build_battle_set_dressing()
	_spawn_units()
	_advance_turn()


func _process(delta: float) -> void:
	_arena_time += delta
	_animate_battle_stage(delta)


func _load_party_from_manager() -> void:
	var party_manager: Node = get_node_or_null("/root/PartyManager")
	if party_manager != null and party_manager.has_method("get_party_snapshot"):
		party_roster = party_manager.get_party_snapshot()
		active_second_party_index = party_manager.get_active_battle_partner_index()
		return

	party_roster = BuddyCatalog.build_default_party()
	active_second_party_index = 1


func _spawn_units() -> void:
	dino_buddy = _create_unit(ally_front_slot, Vector3(0.0, 0.0, -1.0))
	_apply_party_member_to_unit(dino_buddy, party_roster[0], ally_front_slot)

	var second_member = _get_active_second_member()
	if second_member != null:
		ally_support = _create_unit(ally_back_slot, Vector3(0.0, 0.0, -1.0))
		_apply_party_member_to_unit(ally_support, second_member, ally_back_slot)
	else:
		ally_support = null

	var enemy_entries: Array = _encounter_data.get("enemies", [])
	if enemy_entries.is_empty():
		enemy_entries = DEFAULT_ENCOUNTER["enemies"]

	var front_stats: Dictionary = EncounterResolver.build_enemy_stats(enemy_entries[0] if enemy_entries.size() > 0 else {})
	front_enemy = _create_unit(enemy_front_slot, Vector3(0.0, 0.0, 1.0))
	front_enemy.configure(
		str(front_stats.get("name", "Buddy")),
		int(front_stats.get("max_health", 20)),
		int(front_stats.get("current_health", 20)),
		int(front_stats.get("attack_power", 4)),
		front_stats.get("primary_color", Color.WHITE),
		front_stats.get("accent_color", Color.WHITE)
	)

	if enemy_entries.size() > 1:
		var rear_stats: Dictionary = EncounterResolver.build_enemy_stats(enemy_entries[1])
		rear_enemy = _create_unit(enemy_back_slot, Vector3(0.0, 0.0, 1.0))
		rear_enemy.configure(
			str(rear_stats.get("name", "Buddy")),
			int(rear_stats.get("max_health", 20)),
			int(rear_stats.get("current_health", 20)),
			int(rear_stats.get("attack_power", 4)),
			rear_stats.get("primary_color", Color.WHITE),
			rear_stats.get("accent_color", Color.WHITE)
		)
	else:
		rear_enemy = null

	_refresh_combat_facing()
	_refresh_capture_ready_markers()


func _create_unit(
	slot: Marker3D,
	facing_direction: Vector3
) -> BattleUnitScript:
	var unit: BattleUnitScript = BATTLE_UNIT_SCENE.instantiate()
	units_container.add_child(unit)
	unit.global_position = slot.global_position
	unit.set_facing_direction(facing_direction)
	unit.attack_hit.connect(_on_unit_attack_hit)
	unit.defeated.connect(_on_unit_defeated)
	unit.clicked.connect(_on_unit_clicked)
	unit.health_changed.connect(_on_unit_health_changed)
	return unit


func _apply_party_member_to_unit(unit: BattleUnitScript, member: BattlePartyMemberScript, slot: Marker3D) -> void:
	unit.global_position = slot.global_position
	unit.configure(
		member.unit_name,
		member.max_health,
		member.current_health,
		member.attack_power,
		member.primary_color,
		member.accent_color
	)
	unit.set_target_highlight(false)


func _get_active_second_member():
	if active_second_party_index <= 0 or active_second_party_index >= party_roster.size():
		return null

	return party_roster[active_second_party_index]


## Aim allies at living enemies and vice versa (slots are diagonal; pure ±Z was wrong).
func _refresh_combat_facing() -> void:
	var ally_focus: BattleUnitScript = null
	if dino_buddy != null and is_instance_valid(dino_buddy) and not dino_buddy.is_defeated():
		ally_focus = dino_buddy
	elif ally_support != null and is_instance_valid(ally_support) and not ally_support.is_defeated():
		ally_focus = ally_support

	if dino_buddy != null and is_instance_valid(dino_buddy) and not dino_buddy.is_defeated():
		var mark := _nearest_living_enemy_marker(dino_buddy.global_position)
		if mark != Vector3.ZERO:
			dino_buddy.face_toward_point(mark)
	if ally_support != null and is_instance_valid(ally_support) and not ally_support.is_defeated():
		var mark2 := _nearest_living_enemy_marker(ally_support.global_position)
		if mark2 != Vector3.ZERO:
			ally_support.face_toward_point(mark2)

	if front_enemy != null and is_instance_valid(front_enemy) and not front_enemy.is_defeated() and ally_focus != null:
		front_enemy.face_toward_point(ally_focus.global_position)
	if rear_enemy != null and is_instance_valid(rear_enemy) and not rear_enemy.is_defeated() and ally_focus != null:
		rear_enemy.face_toward_point(ally_focus.global_position)


func _nearest_living_enemy_marker(from: Vector3) -> Vector3:
	var best: Vector3 = Vector3.ZERO
	var best_d2 := -1.0
	for enemy: BattleUnitScript in [front_enemy, rear_enemy]:
		if enemy == null or not is_instance_valid(enemy) or enemy.is_defeated():
			continue
		var d2 := from.distance_squared_to(enemy.global_position)
		if best_d2 < 0.0 or d2 < best_d2:
			best_d2 = d2
			best = enemy.global_position
	return best


func _ensure_second_ally_unit() -> void:
	if ally_support == null:
		ally_support = _create_unit(ally_back_slot, Vector3(0.0, 0.0, -1.0))


func _advance_turn() -> void:
	_clear_target_highlights()
	action_ui.hide_swap_options()

	if _all_enemies_defeated():
		_end_battle(true)
		return

	if dino_buddy == null or dino_buddy.is_defeated():
		_end_battle(false)
		return

	for _step in range(turn_order.size()):
		turn_index = (turn_index + 1) % turn_order.size()
		var next_turn_key: String = turn_order[turn_index]

		match next_turn_key:
			"player_1":
				if dino_buddy != null and not dino_buddy.is_defeated():
					_begin_player_turn(dino_buddy, next_turn_key)
					return
			"player_2":
				if ally_support != null and not ally_support.is_defeated():
					_begin_player_turn(ally_support, next_turn_key)
					return
				elif _has_available_swap_candidates():
					acting_unit = ally_support
					acting_turn_key = next_turn_key
					_begin_swap_selection(true)
					return
			"enemy_1":
				if _try_begin_resonance_sync():
					return
				if front_enemy != null and not front_enemy.is_defeated():
					_start_enemy_turn(front_enemy, next_turn_key)
					return
			"enemy_2":
				if rear_enemy != null and not rear_enemy.is_defeated():
					_start_enemy_turn(rear_enemy, next_turn_key)
					return


func _begin_player_turn(unit: BattleUnitScript, turn_key: String) -> void:
	state = BattleState.PLAYER_CHOICE
	acting_unit = unit
	acting_turn_key = turn_key
	pending_move_id = ""
	action_ui.set_turn_indicator("%s Turn" % unit.unit_name)
	action_ui.set_status("Choose a move for %s." % unit.unit_name)

	var partner_ok := ally_support != null and not ally_support.is_defeated()
	var ui_entries: Array = []
	for entry: Variant in unit.get_move_entries():
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = (entry as Dictionary).duplicate(true)
		if bool(row.get("requires_partner", false)) and not partner_ok:
			row["enabled"] = false
		else:
			row["enabled"] = true
		ui_entries.append(row)

	action_ui.set_move_options(ui_entries)
	action_ui.set_actions_enabled(true, turn_key == "player_2" and _has_available_swap_candidates())


func _on_action_selected(action_name: String) -> void:
	if state != BattleState.PLAYER_CHOICE:
		return

	if action_name.begins_with("move:"):
		var move_id: String = action_name.substr(5)
		_on_move_chosen(move_id)
		return

	match action_name:
		"swap":
			if acting_turn_key == "player_2":
				_begin_swap_selection(false)
		"item":
			_begin_item_selection()
		"run":
			action_ui.set_status("Retreating to the overworld.")
			_save_party_to_manager()
			_return_to_overworld(0.1)


func _on_move_chosen(move_id: String) -> void:
	var entry: Dictionary = BattleMoveCatalog.get_entry_by_id(acting_unit.unit_name, move_id)
	if entry.is_empty():
		action_ui.set_status("Unknown move.")
		return

	if bool(entry.get("requires_partner", false)) and (ally_support == null or ally_support.is_defeated()):
		action_ui.set_status("No partner on the field for that move.")
		return

	_maybe_print_dino_personality_line(move_id)

	var kind: String = str(entry.get("kind", BattleMoveCatalog.KIND_SINGLE))
	match kind:
		BattleMoveCatalog.KIND_SINGLE:
			pending_move_id = move_id
			_begin_target_selection(move_id)
		BattleMoveCatalog.KIND_ALL_ENEMIES:
			pending_move_id = move_id
			await _execute_all_enemies_attack(entry, false)
		BattleMoveCatalog.KIND_ALL_ENEMIES_STATUS:
			pending_move_id = move_id
			await _execute_all_enemies_attack(entry, true)
		BattleMoveCatalog.KIND_BUFF_PARTNER_NEXT_ATTACK:
			await _execute_loyal_roar(entry)
		_:
			action_ui.set_status("Unsupported move type.")


func _maybe_print_dino_personality_line(move_id: String) -> void:
	if acting_unit == null or acting_unit.unit_name != "Dino Buddy":
		return
	var lines: Variant = DINO_MOVE_LINES.get(move_id, ["Let's roll!"])
	if not (lines is Array) or (lines as Array).is_empty():
		print("[Dino Buddy] Let's roll!")
		return
	var arr: Array = lines as Array
	var line: String = str(arr[battle_rng.randi() % arr.size()])
	print("[Dino Buddy] %s" % line)


func _begin_target_selection(move_id: String) -> void:
	pending_move_id = move_id
	state = BattleState.TARGET_SELECT
	action_ui.set_actions_enabled(false)
	selectable_targets = _get_alive_enemy_units()
	for target: BattleUnitScript in selectable_targets:
		target.set_target_highlight(true)

	var entry: Dictionary = BattleMoveCatalog.get_entry_by_id(acting_unit.unit_name, move_id)
	var move_label: String = str(entry.get("label", move_id))
	action_ui.set_status("Choose a target for %s." % move_label)


func _start_player_attack(target: BattleUnitScript) -> void:
	state = BattleState.BUSY
	_clear_target_highlights()
	var entry: Dictionary = BattleMoveCatalog.get_entry_by_id(acting_unit.unit_name, pending_move_id)
	var power_mult: float = float(entry.get("power_mult", 1.0))
	var base_damage: int = int(round(float(acting_unit.attack_power) * power_mult))
	var buff_mult: float = acting_unit.take_next_attack_damage_multiplier()
	var damage: int = int(round(float(base_damage) * buff_mult))

	var move_label: String = str(entry.get("label", "Move"))
	action_ui.set_status("%s uses %s on %s!" % [acting_unit.unit_name, move_label, target.unit_name])

	pending_damage_overrides[acting_unit.get_instance_id()] = damage
	acting_unit.perform_attack(target.get_hit_position(), target)
	await acting_unit.attack_finished
	_refresh_combat_facing()

	if _all_enemies_defeated():
		_end_battle(true)
		return

	await _resolve_post_player_turn(0.45)


func _execute_all_enemies_attack(entry: Dictionary, apply_paralyze: bool) -> void:
	state = BattleState.BUSY
	action_ui.set_actions_enabled(false)
	var targets: Array[BattleUnitScript] = _get_alive_enemy_units()
	if targets.is_empty():
		_advance_turn()
		return

	var power_mult: float = float(entry.get("power_mult", 1.0))
	var base_damage: int = int(round(float(acting_unit.attack_power) * power_mult))
	var buff_mult: float = acting_unit.take_next_attack_damage_multiplier()
	var per_hit: int = int(round(float(base_damage) * buff_mult))
	var move_label: String = str(entry.get("label", "Move"))

	for target: BattleUnitScript in targets:
		pending_damage_overrides[acting_unit.get_instance_id()] = per_hit
		action_ui.set_status("%s uses %s on %s!" % [acting_unit.unit_name, move_label, target.unit_name])
		acting_unit.perform_attack(target.get_hit_position(), target)
		await acting_unit.attack_finished

		if apply_paralyze:
			var chance: float = float(entry.get("status_chance", 0.0))
			if battle_rng.randf() < chance and not target.is_defeated():
				target.set_paralyzed(true)
				action_ui.set_status("%s is paralyzed!" % target.unit_name)
				await get_tree().create_timer(0.35).timeout

		if _all_enemies_defeated():
			_end_battle(true)
			return

	_refresh_combat_facing()
	await _resolve_post_player_turn(0.4)


func _execute_loyal_roar(entry: Dictionary) -> void:
	state = BattleState.BUSY
	action_ui.set_actions_enabled(false)
	if ally_support == null or ally_support.is_defeated():
		action_ui.set_status("Loyal Roar echoes, but there's no partner to empower...")
		await get_tree().create_timer(0.75).timeout
		_advance_turn()
		return

	var mult: float = float(entry.get("partner_buff_mult", 1.55))
	ally_support.grant_next_attack_damage_buff(mult)
	action_ui.set_status(
		"%s — Loyal Roar! %s's next strike hits harder!" % [acting_unit.unit_name, ally_support.unit_name]
	)
	await _resolve_post_player_turn(0.85)


func _try_begin_resonance_sync() -> bool:
	if capture_ui == null:
		return false

	if skip_capture_offer_once:
		skip_capture_offer_once = false
		return false

	var candidate: BattleUnitScript = _find_capture_candidate()
	if candidate == null:
		return false

	_begin_resonance_sync(candidate)
	return true


func _find_capture_candidate() -> BattleUnitScript:
	var best_target: BattleUnitScript
	for unit: BattleUnitScript in [front_enemy, rear_enemy]:
		if not _is_capture_ready_enemy(unit):
			continue
		if best_target == null or unit.get_health_ratio() < best_target.get_health_ratio():
			best_target = unit
	return best_target


func _is_capture_ready_enemy(unit: BattleUnitScript) -> bool:
	return unit != null and is_instance_valid(unit) and not unit.is_defeated() and unit.get_health_ratio() <= 0.30


func _begin_resonance_sync(target: BattleUnitScript) -> void:
	active_capture_target = target
	state = BattleState.CAPTURE_SYNC
	_clear_target_highlights()
	action_ui.hide_swap_options()
	action_ui.set_actions_enabled(false)
	action_ui.set_turn_indicator("Resonance Sync")
	action_ui.set_status("%s is stabilized. Resonance Sync starting..." % target.unit_name)
	if capture_ui.has_method("start_capture"):
		capture_ui.start_capture(target.unit_name)


func _on_capture_succeeded(buddy_name: String) -> void:
	if state != BattleState.CAPTURE_SYNC:
		return

	var captured_target: BattleUnitScript = active_capture_target
	active_capture_target = null
	skip_capture_offer_once = false
	_clear_target_highlights()

	if captured_target != null and is_instance_valid(captured_target):
		if captured_target == front_enemy:
			front_enemy = null
		elif captured_target == rear_enemy:
			rear_enemy = null
		captured_target.queue_free()

	_refresh_party_roster_after_capture()
	_refresh_capture_ready_markers()
	action_ui.set_turn_indicator("Resonance Sync")
	action_ui.set_status("%s Captured!" % buddy_name)
	await get_tree().create_timer(0.6).timeout
	_save_party_to_manager()
	_return_to_overworld(0.8)


func _on_capture_failed(reason: String) -> void:
	if state != BattleState.CAPTURE_SYNC:
		return

	var target: BattleUnitScript = active_capture_target
	active_capture_target = null
	skip_capture_offer_once = true
	state = BattleState.BUSY

	if target != null and is_instance_valid(target) and not target.is_defeated():
		var recovery_amount: int = maxi(2, int(round(float(target.max_health) * 0.15)))
		var recovered: int = target.heal(recovery_amount)
		action_ui.set_status("%s resisted the sync (%s) and recovered %d HP." % [
			target.unit_name,
			reason.replace("_", " "),
			recovered,
		])
	else:
		action_ui.set_status("Resonance Sync failed.")

	_refresh_capture_ready_markers()
	await get_tree().create_timer(0.75).timeout
	if _all_enemies_defeated():
		_end_battle(true)
		return
	_advance_turn()


func _resolve_post_player_turn(delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout

	if _all_enemies_defeated():
		_end_battle(true)
		return

	if _try_begin_resonance_sync():
		return

	_advance_turn()


func _refresh_party_roster_after_capture() -> void:
	var party_manager: Node = get_node_or_null("/root/PartyManager")
	if party_manager == null or not party_manager.has_method("get_party_snapshot"):
		return

	var refreshed_roster: Array = party_manager.get_party_snapshot()
	if refreshed_roster.is_empty():
		return

	party_roster = refreshed_roster
	if dino_buddy != null and not party_roster.is_empty() and party_roster[0] != null:
		party_roster[0].current_health = dino_buddy.current_health

	if ally_support != null and active_second_party_index > 0 and active_second_party_index < party_roster.size():
		if party_roster[active_second_party_index] != null:
			party_roster[active_second_party_index].current_health = ally_support.current_health


func _begin_swap_selection(forced: bool) -> void:
	state = BattleState.SWAP_SELECT
	swap_forced = forced
	action_ui.set_turn_indicator("Second Slot Turn")
	action_ui.set_actions_enabled(false)

	var options: Array[Dictionary] = []
	for member in party_roster:
		if member == null:
			continue
		if member.party_index == 0:
			continue

		var enabled: bool = member.party_index != active_second_party_index and member.current_health > 0
		options.append({
			"party_index": member.party_index,
			"label": "%d. %s  HP %d/%d" % [member.party_index + 1, member.unit_name, member.current_health, member.max_health],
			"enabled": enabled,
		})

	if forced:
		action_ui.set_status("Second slot is down. Choose a Buddy to swap in.")
	else:
		action_ui.set_status("Choose a Buddy to swap into slot 2.")
	action_ui.show_swap_options("Party Swap", options, not forced)


func _begin_item_selection() -> void:
	var item_mgr: Node = get_node_or_null("/root/ItemManager")
	if item_mgr == null or not item_mgr.has_method("get_battle_item_rows"):
		action_ui.set_status("Items unavailable.")
		return

	var rows: Array = item_mgr.call("get_battle_item_rows", acting_unit, ally_support, active_second_party_index)
	if rows.is_empty():
		action_ui.set_status("No items in your pack.")
		return

	var any_usable := false
	for row: Variant in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if bool((row as Dictionary).get("enabled", false)):
			any_usable = true
			break
	if not any_usable:
		action_ui.set_status("No items can be used right now.")
		return

	state = BattleState.ITEM_PICKING
	action_ui.set_actions_enabled(false)
	action_ui.show_item_picker("Use an item", rows)


func _on_item_picker_cancelled() -> void:
	if state != BattleState.ITEM_PICKING:
		return

	state = BattleState.PLAYER_CHOICE
	_begin_player_turn(acting_unit, acting_turn_key)


func _on_battle_item_selected(item_id: String) -> void:
	if state != BattleState.ITEM_PICKING:
		return

	var item_mgr: Node = get_node_or_null("/root/ItemManager")
	if item_mgr == null:
		state = BattleState.PLAYER_CHOICE
		_begin_player_turn(acting_unit, acting_turn_key)
		return

	var rows: Array = item_mgr.call("get_battle_item_rows", acting_unit, ally_support, active_second_party_index)
	var row_ok := false
	for row: Variant in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = row
		if str(d.get("id", "")) != item_id:
			continue
		row_ok = bool(d.get("enabled", false))
		break

	if not row_ok or int(item_mgr.call("get_item_count", item_id)) <= 0:
		action_ui.set_status("Can't use that right now.")
		state = BattleState.PLAYER_CHOICE
		_begin_player_turn(acting_unit, acting_turn_key)
		return

	if not bool(item_mgr.call("consume_item", item_id)):
		action_ui.set_status("Item unavailable.")
		state = BattleState.PLAYER_CHOICE
		_begin_player_turn(acting_unit, acting_turn_key)
		return

	var def: Dictionary = item_mgr.call("get_item_definition", item_id)
	var kind: String = str(def.get("kind", ""))
	state = BattleState.BUSY
	action_ui.set_status("")

	match kind:
		"heal_self":
			var amt: int = int(def.get("heal_amount", 12))
			var healed: int = acting_unit.heal(amt)
			action_ui.set_status("%s used %s (+%d HP)." % [acting_unit.unit_name, str(def.get("label", "Item")), healed])
		"heal_all_allies":
			var amt_all: int = int(def.get("heal_amount", 8))
			var total_healed := 0
			for ally: BattleUnitScript in [dino_buddy, ally_support]:
				if ally != null and not ally.is_defeated():
					total_healed += ally.heal(amt_all)
			action_ui.set_status(
				"%s used %s (+%d HP to the team)." % [acting_unit.unit_name, str(def.get("label", "Item")), total_healed]
			)
		"revive_partner":
			if ally_support == null or active_second_party_index <= 0:
				action_ui.set_status("No partner to reboot.")
			else:
				var frac: float = float(def.get("hp_fraction", 0.3))
				var hp: int = maxi(1, int(floor(float(ally_support.max_health) * frac)))
				ally_support.revive_with_health(hp)
				if active_second_party_index < party_roster.size() and party_roster[active_second_party_index] != null:
					party_roster[active_second_party_index].current_health = ally_support.current_health
				action_ui.set_status(
					"%s used %s — %s is back (%d HP)!"
					% [acting_unit.unit_name, str(def.get("label", "Item")), ally_support.unit_name, ally_support.current_health]
				)
		_:
			action_ui.set_status("Unknown item effect.")

	await get_tree().create_timer(0.55).timeout
	_save_party_to_manager()
	_advance_turn()


func _on_swap_selected(party_index: int) -> void:
	if state != BattleState.SWAP_SELECT:
		return

	if not _is_valid_swap_choice(party_index):
		return

	active_second_party_index = party_index
	_ensure_second_ally_unit()
	_apply_party_member_to_unit(ally_support, party_roster[active_second_party_index], ally_back_slot)
	_refresh_combat_facing()
	action_ui.hide_swap_options()
	swap_forced = false
	action_ui.set_status("%s swapped into slot 2." % party_roster[active_second_party_index].unit_name)
	await _resolve_post_player_turn(0.35)


func _on_swap_cancelled() -> void:
	if state != BattleState.SWAP_SELECT:
		return

	if swap_forced:
		_begin_swap_selection(true)
		return

	state = BattleState.PLAYER_CHOICE
	_begin_player_turn(ally_support, "player_2")


func _start_enemy_turn(enemy_unit: BattleUnitScript, turn_key: String) -> void:
	if enemy_unit.consume_paralyze_skip():
		state = BattleState.BUSY
		acting_unit = enemy_unit
		acting_turn_key = turn_key
		action_ui.set_turn_indicator("%s's Turn" % enemy_unit.unit_name)
		action_ui.set_status("%s is paralyzed and can't move!" % enemy_unit.unit_name)
		await get_tree().create_timer(0.65).timeout
		_advance_turn()
		return

	state = BattleState.ENEMY_ACTION
	acting_unit = enemy_unit
	acting_turn_key = turn_key
	action_ui.set_turn_indicator("%s Turn" % enemy_unit.unit_name)

	var target: BattleUnitScript = _choose_enemy_target(turn_key)
	if target == null:
		_advance_turn()
		return

	action_ui.set_status("%s attacks %s." % [enemy_unit.unit_name, target.unit_name])
	pending_damage_overrides[enemy_unit.get_instance_id()] = enemy_unit.attack_power
	enemy_unit.perform_attack(target.get_hit_position(), target)
	await enemy_unit.attack_finished
	_refresh_combat_facing()

	if dino_buddy != null and dino_buddy.is_defeated():
		_end_battle(false)
		return

	if _all_enemies_defeated():
		_end_battle(true)
		return

	await get_tree().create_timer(0.25).timeout
	_advance_turn()


func _on_unit_attack_hit(attacker: BattleUnitScript, target: BattleUnitScript) -> void:
	if attacker == null or target == null:
		return

	var damage: int = attacker.attack_power
	if pending_damage_overrides.has(attacker.get_instance_id()):
		damage = pending_damage_overrides[attacker.get_instance_id()]
		pending_damage_overrides.erase(attacker.get_instance_id())

	target.take_damage(damage)
	var status_text := "%s hits %s for %d damage." % [
		attacker.unit_name,
		target.unit_name,
		damage,
	]
	if target in [front_enemy, rear_enemy] and _is_capture_ready_enemy(target):
		status_text += " %s is weakened and ready for Resonance Sync." % target.unit_name
	action_ui.set_status(status_text)


func _on_unit_defeated(unit: BattleUnitScript) -> void:
	unit.set_target_highlight(false)
	if unit in selectable_targets:
		selectable_targets.erase(unit)

	if unit in [front_enemy, rear_enemy] and _all_enemies_defeated():
		action_ui.set_status("%s goes down. Battle won." % unit.unit_name)
	elif unit == dino_buddy:
		action_ui.set_status("Dino Buddy is down. Battle lost.")


func _on_unit_health_changed(unit: BattleUnitScript, current_health: int, _max_health: int) -> void:
	if unit == dino_buddy:
		party_roster[0].current_health = current_health
	elif unit == ally_support and active_second_party_index >= 0 and active_second_party_index < party_roster.size():
		if party_roster[active_second_party_index] != null:
			party_roster[active_second_party_index].current_health = current_health

	if unit in [front_enemy, rear_enemy]:
		_refresh_capture_ready_markers()


func _end_battle(player_won: bool) -> void:
	if state == BattleState.RETURNING:
		return

	state = BattleState.VICTORY if player_won else BattleState.DEFEAT
	_clear_target_highlights()
	action_ui.set_actions_enabled(false)
	if player_won:
		if dino_buddy != null:
			dino_buddy.play_battle_victory()
		if ally_support != null:
			ally_support.play_battle_victory()
		action_ui.set_status("Victory. Dino Buddy holds the field.")
	else:
		action_ui.set_status("Defeat. Dino Buddy needs to recover.")

	_save_party_to_manager()
	_return_to_overworld()


func _return_to_overworld(delay: float = 1.6) -> void:
	state = BattleState.RETURNING
	await get_tree().create_timer(delay).timeout
	emit_signal("battle_exit_requested")


func _on_unit_clicked(unit: BattleUnitScript) -> void:
	if state != BattleState.TARGET_SELECT:
		return

	if unit == null or unit.is_defeated():
		return

	if not selectable_targets.has(unit):
		return

	unit.flash_target_selection()
	_start_player_attack(unit)


func _get_alive_enemy_units() -> Array[BattleUnitScript]:
	var alive_units: Array[BattleUnitScript] = []
	for unit: BattleUnitScript in [front_enemy, rear_enemy]:
		if unit != null and not unit.is_defeated():
			alive_units.append(unit)
	return alive_units


func _clear_target_highlights() -> void:
	for unit: BattleUnitScript in [front_enemy, rear_enemy]:
		if unit != null:
			unit.set_target_highlight(false)
	selectable_targets.clear()


func _all_enemies_defeated() -> bool:
	for unit: BattleUnitScript in [front_enemy, rear_enemy]:
		if unit != null and not unit.is_defeated():
			return false
	return true


func _choose_enemy_target(turn_key: String) -> BattleUnitScript:
	var candidates: Array[BattleUnitScript] = []
	if dino_buddy != null and not dino_buddy.is_defeated():
		candidates.append(dino_buddy)
	if ally_support != null and not ally_support.is_defeated():
		candidates.append(ally_support)
	if candidates.is_empty():
		return null

	# Rear-line enemies still prefer the support, but not 100% of the time.
	if turn_key == "enemy_2" and ally_support != null and not ally_support.is_defeated():
		if battle_rng.randf() < 0.62:
			return ally_support

	if candidates.size() == 1:
		return candidates[0]

	return _weighted_enemy_target_choice(candidates)


func _weighted_enemy_target_choice(candidates: Array[BattleUnitScript]) -> BattleUnitScript:
	var weights: Array[float] = []
	for unit: BattleUnitScript in candidates:
		var hurt: float = 1.0 - clampf(unit.get_health_ratio(), 0.0, 1.0)
		var w: float = 0.45 + hurt * 2.1 + battle_rng.randf() * 0.55
		weights.append(w)

	var total: float = 0.0
	for w: float in weights:
		total += w

	var pick: float = battle_rng.randf() * total
	var acc: float = 0.0
	for i: int in range(candidates.size()):
		acc += weights[i]
		if pick <= acc:
			return candidates[i]

	return candidates[candidates.size() - 1]


func _has_available_swap_candidates() -> bool:
	for member in party_roster:
		if member == null:
			continue
		if member.party_index == 0:
			continue
		if member.party_index != active_second_party_index and member.current_health > 0:
			return true
	return false


func _is_valid_swap_choice(party_index: int) -> bool:
	if party_index <= 0 or party_index >= party_roster.size():
		return false

	return party_roster[party_index] != null and party_index != active_second_party_index and party_roster[party_index].current_health > 0


func _save_party_to_manager() -> void:
	var party_manager: Node = get_node_or_null("/root/PartyManager")
	if party_manager != null and party_manager.has_method("save_party_snapshot"):
		party_manager.save_party_snapshot(party_roster, active_second_party_index)


func _refresh_capture_ready_markers() -> void:
	for unit: BattleUnitScript in [front_enemy, rear_enemy]:
		if unit != null and is_instance_valid(unit):
			unit.set_capture_ready(_is_capture_ready_enemy(unit))


func _load_encounter_data() -> void:
	var encounter_bridge: Node = get_node_or_null("/root/EncounterBridge")
	if encounter_bridge != null and encounter_bridge.has_method("take_pending_encounter"):
		_encounter_data = encounter_bridge.call("take_pending_encounter")
	if _encounter_data.is_empty():
		_encounter_data = DEFAULT_ENCOUNTER.duplicate(true)


func _apply_battle_theme() -> void:
	_arena_theme = _resolve_battle_theme(_encounter_data)
	if battle_camera != null:
		_camera_base_position = battle_camera.position
		_camera_base_rotation = battle_camera.rotation
		battle_camera.fov = float(_arena_theme.get("camera_fov", 52.0))

	if world_environment != null and world_environment.environment != null:
		var env := world_environment.environment
		var sky_material := ProceduralSkyMaterial.new()
		sky_material.sky_top_color = _arena_theme.get("sky_top", _arena_theme.get("bg", Color(0.03, 0.05, 0.10)))
		sky_material.sky_horizon_color = _arena_theme.get("sky_horizon", _arena_theme.get("ambient", Color(0.55, 0.64, 0.83)))
		sky_material.ground_bottom_color = _arena_theme.get("ground_bottom", _arena_theme.get("floor", Color(0.08, 0.14, 0.24)))
		sky_material.ground_horizon_color = _arena_theme.get("ground_horizon", _arena_theme.get("grass", Color(0.20, 0.30, 0.18)))
		var sky := Sky.new()
		sky.sky_material = sky_material
		env.background_mode = Environment.BG_SKY
		env.sky = sky
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.ambient_light_color = _arena_theme.get("ambient", Color(0.55, 0.64, 0.83))
		env.ambient_light_energy = float(_arena_theme.get("ambient_energy", 0.72))
		env.glow_intensity = float(_arena_theme.get("glow_intensity", 0.7))
		env.glow_bloom = float(_arena_theme.get("glow_bloom", 0.15))
		env.fog_enabled = true
		env.fog_density = float(_arena_theme.get("fog_density", 0.01))
		env.fog_aerial_perspective = float(_arena_theme.get("fog_aerial", 0.45))
		env.fog_light_color = _arena_theme.get("fog_light", _arena_theme.get("ambient", Color(0.55, 0.64, 0.83)))

	if sun != null:
		sun.light_color = _arena_theme.get("sun", Color(0.92, 0.96, 1.0))
		sun.light_energy = float(_arena_theme.get("sun_energy", 2.2))

	if fill_light != null:
		fill_light.light_color = _arena_theme.get("fill", Color(0.50, 0.68, 1.0))
		fill_light.light_energy = float(_arena_theme.get("fill_energy", 3.6))

	if rim_light != null:
		rim_light.light_color = _arena_theme.get("rim", Color(1.0, 0.46, 0.45))
		rim_light.light_energy = float(_arena_theme.get("rim_energy", 2.0))

	_apply_floor_material()
	for mesh: MeshInstance3D in [backdrop, backdrop_left, backdrop_right]:
		_apply_backdrop_material(mesh)


func _build_battle_set_dressing() -> void:
	_arena_vfx_root = Node3D.new()
	_arena_vfx_root.name = "ArenaVfx"
	add_child(_arena_vfx_root)

	_add_grass_field()
	_add_clearing_layers()
	_add_tree_line()
	_add_rock_border()
	_add_floor_ring(2.35, 2.7, _arena_theme.get("ally", Color(0.26, 0.82, 0.62)), 0.014)
	_add_floor_ring(3.95, 4.3, _arena_theme.get("enemy", Color(0.86, 0.34, 0.68)), 0.013)

	_add_slot_glow(ally_front_slot.position, _arena_theme.get("ally", Color(0.26, 0.82, 0.62)), 1.35)
	_add_slot_glow(ally_back_slot.position, _arena_theme.get("ally", Color(0.26, 0.82, 0.62)).darkened(0.18), 1.0)
	_add_slot_glow(enemy_front_slot.position, _arena_theme.get("enemy", Color(0.86, 0.34, 0.68)), 1.35)
	_add_slot_glow(enemy_back_slot.position, _arena_theme.get("enemy", Color(0.86, 0.34, 0.68)).darkened(0.18), 1.0)

	if bool(_arena_theme.get("rift_like", false)):
		_add_rift_core()
	_add_fog_walls()
	_add_ambient_motes()
	_add_battle_particles()


func _animate_battle_stage(delta: float) -> void:
	if battle_camera != null:
		battle_camera.position = _camera_base_position + Vector3(
			sin(_arena_time * 0.38) * 0.08,
			sin(_arena_time * 0.72) * 0.05,
			cos(_arena_time * 0.31) * 0.04
		)
		battle_camera.rotation = _camera_base_rotation + Vector3(
			sin(_arena_time * 0.5) * 0.006,
			sin(_arena_time * 0.24) * 0.012,
			0.0
		)

	for mesh: MeshInstance3D in _ambient_shards:
		if mesh == null or not is_instance_valid(mesh):
			continue
		var base_y := float(mesh.get_meta("base_y", mesh.position.y))
		var drift := float(mesh.get_meta("drift", 0.6))
		var offset := float(mesh.get_meta("offset", 0.0))
		var spin := float(mesh.get_meta("spin", 0.3))
		mesh.position.y = base_y + sin(_arena_time * drift + offset) * 0.42
		mesh.rotation.y += delta * spin
		mesh.rotation.x += delta * spin * 0.38

	for mesh: MeshInstance3D in _pulse_meshes:
		if mesh == null or not is_instance_valid(mesh):
			continue
		var material := mesh.get_active_material(0) as StandardMaterial3D
		if material == null:
			continue
		var pulse_speed := float(mesh.get_meta("pulse_speed", 1.0))
		var pulse_offset := float(mesh.get_meta("pulse_offset", 0.0))
		var base_energy := float(mesh.get_meta("base_energy", material.emission_energy_multiplier))
		material.emission_energy_multiplier = base_energy + sin(_arena_time * pulse_speed + pulse_offset) * base_energy * 0.35
		if mesh.get_meta("pulse_scale", false):
			var scale_base := float(mesh.get_meta("scale_base", 1.0))
			var s := scale_base + sin(_arena_time * pulse_speed + pulse_offset) * 0.035
			mesh.scale = Vector3.ONE * s


func _resolve_battle_theme(encounter: Dictionary) -> Dictionary:
	var names: PackedStringArray = []
	for entry: Variant in encounter.get("enemies", []):
		if typeof(entry) == TYPE_DICTIONARY:
			names.append(str((entry as Dictionary).get("name", "")).to_lower())

	var rift_like := false
	for name in names:
		if name.contains("shade") or name.contains("rift") or name.contains("rogue") or name.contains("void"):
			rift_like = true
			break

	if rift_like:
		return {
			"rift_like": true,
			"bg": Color(0.035, 0.045, 0.075),
			"ambient": Color(0.34, 0.38, 0.54),
			"ambient_energy": 0.56,
			"glow_intensity": 0.52,
			"glow_bloom": 0.11,
			"sun": Color(0.65, 0.70, 0.92),
			"sun_energy": 1.6,
			"fill": Color(0.50, 0.36, 0.88),
			"fill_energy": 2.5,
			"rim": Color(0.96, 0.42, 0.70),
			"rim_energy": 1.9,
			"floor": Color(0.11, 0.13, 0.16),
			"floor_emission": Color(0.12, 0.10, 0.18),
			"backdrop": Color(0.09, 0.11, 0.14),
			"backdrop_emission": Color(0.10, 0.08, 0.16),
			"ally": Color(0.32, 0.88, 0.72),
			"enemy": Color(0.90, 0.42, 0.74),
			"accent": Color(0.62, 0.54, 0.95),
			"grass": Color(0.12, 0.20, 0.16),
			"dirt": Color(0.20, 0.18, 0.20),
			"fog": Color(0.30, 0.22, 0.46, 0.18),
			"tree_leaf": Color(0.11, 0.16, 0.18),
			"tree_trunk": Color(0.19, 0.15, 0.14),
			"rock": Color(0.32, 0.30, 0.36),
			"camera_fov": 47.0,
			"particle": Color(0.62, 0.56, 0.92, 0.28),
			"sky_top": Color(0.06, 0.05, 0.12),
			"sky_horizon": Color(0.20, 0.14, 0.28),
			"ground_bottom": Color(0.06, 0.05, 0.08),
			"ground_horizon": Color(0.14, 0.12, 0.16),
			"fog_light": Color(0.34, 0.26, 0.46),
			"fog_density": 0.026,
			"fog_aerial": 0.62,
		}

	return {
		"rift_like": false,
		"bg": Color(0.20, 0.30, 0.40),
		"ambient": Color(0.58, 0.66, 0.62),
		"ambient_energy": 0.82,
		"glow_intensity": 0.16,
		"glow_bloom": 0.04,
		"sun": Color(1.0, 0.95, 0.82),
		"sun_energy": 2.1,
		"fill": Color(0.38, 0.68, 0.58),
		"fill_energy": 2.1,
		"rim": Color(0.70, 0.84, 1.0),
		"rim_energy": 1.2,
		"floor": Color(0.21, 0.30, 0.18),
		"floor_emission": Color(0.10, 0.14, 0.08),
		"backdrop": Color(0.28, 0.38, 0.32),
		"backdrop_emission": Color(0.08, 0.12, 0.10),
		"ally": Color(0.30, 0.84, 0.60),
		"enemy": Color(0.86, 0.64, 0.30),
		"accent": Color(0.42, 0.66, 0.92),
		"grass": Color(0.22, 0.40, 0.18),
		"dirt": Color(0.40, 0.32, 0.22),
		"fog": Color(0.70, 0.84, 0.76, 0.16),
		"tree_leaf": Color(0.16, 0.32, 0.16),
		"tree_trunk": Color(0.38, 0.27, 0.18),
		"rock": Color(0.44, 0.42, 0.38),
		"camera_fov": 48.5,
		"particle": Color(0.76, 0.92, 0.68, 0.18),
		"sky_top": Color(0.34, 0.52, 0.76),
		"sky_horizon": Color(0.72, 0.84, 0.92),
		"ground_bottom": Color(0.14, 0.20, 0.12),
		"ground_horizon": Color(0.34, 0.44, 0.24),
		"fog_light": Color(0.76, 0.88, 0.82),
		"fog_density": 0.014,
		"fog_aerial": 0.42,
	}


func _apply_floor_material() -> void:
	if arena_floor_mesh == null:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = _arena_theme.get("grass", _arena_theme.get("floor", Color(0.08, 0.14, 0.24)))
	material.roughness = 0.92
	material.metallic = 0.02
	material.emission_enabled = true
	material.emission = _arena_theme.get("floor_emission", Color(0.08, 0.20, 0.38))
	material.emission_energy_multiplier = 0.08
	arena_floor_mesh.set_surface_override_material(0, material)


func _apply_backdrop_material(mesh: MeshInstance3D) -> void:
	if mesh == null:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = _arena_theme.get("backdrop", Color(0.06, 0.08, 0.15))
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.36
	material.roughness = 1.0
	material.emission_enabled = true
	material.emission = _arena_theme.get("backdrop_emission", Color(0.15, 0.25, 0.52))
	material.emission_energy_multiplier = 0.05
	mesh.set_surface_override_material(0, material)


func _add_floor_ring(inner_radius: float, outer_radius: float, color: Color, y: float) -> void:
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = inner_radius
	ring_mesh.outer_radius = outer_radius
	ring_mesh.rings = 48
	ring_mesh.ring_segments = 24

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.14
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.18
	material.roughness = 0.6

	var mesh := MeshInstance3D.new()
	mesh.mesh = ring_mesh
	mesh.position = Vector3(0.0, y, 0.0)
	mesh.rotation.x = PI * 0.5
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.set_surface_override_material(0, material)
	mesh.set_meta("pulse_speed", battle_rng.randf_range(1.2, 2.0))
	mesh.set_meta("pulse_offset", battle_rng.randf() * TAU)
	mesh.set_meta("base_energy", 0.55)
	_arena_vfx_root.add_child(mesh)
	_pulse_meshes.append(mesh)


func _add_slot_glow(slot_position: Vector3, color: Color, radius: float) -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius * 0.92
	cylinder.height = 0.05
	cylinder.radial_segments = 28
	cylinder.rings = 1

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, 0.16)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.22
	material.roughness = 0.28

	var mesh := MeshInstance3D.new()
	mesh.mesh = cylinder
	mesh.position = slot_position + Vector3(0.0, 0.03, 0.0)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.set_surface_override_material(0, material)
	mesh.set_meta("pulse_speed", battle_rng.randf_range(1.5, 2.3))
	mesh.set_meta("pulse_offset", battle_rng.randf() * TAU)
	mesh.set_meta("base_energy", 0.7)
	_arena_vfx_root.add_child(mesh)
	_pulse_meshes.append(mesh)


func _add_rift_core() -> void:
	var orb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.55
	sphere.height = 1.1
	orb.mesh = sphere
	orb.position = Vector3(0.0, 1.8, -8.4)
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var orb_material := StandardMaterial3D.new()
	var accent: Color = _arena_theme.get("accent", Color(0.48, 0.72, 1.0))
	orb_material.albedo_color = Color(accent.r, accent.g, accent.b, 0.22)
	orb_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	orb_material.emission_enabled = true
	orb_material.emission = accent
	orb_material.emission_energy_multiplier = 0.55
	orb_material.roughness = 0.02
	orb.set_surface_override_material(0, orb_material)
	orb.set_meta("pulse_speed", 1.1)
	orb.set_meta("pulse_offset", 0.0)
	orb.set_meta("base_energy", 1.1)
	orb.set_meta("pulse_scale", true)
	orb.set_meta("scale_base", 1.0)
	_arena_vfx_root.add_child(orb)
	_pulse_meshes.append(orb)

	for side in [-1.0, 1.0]:
		var pillar := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.45, 4.6, 0.45)
		pillar.mesh = box
		pillar.position = Vector3(2.8 * side, 1.8, -8.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = _arena_theme.get("backdrop", Color(0.08, 0.07, 0.16))
		mat.emission_enabled = true
		mat.emission = accent.darkened(0.18)
		mat.emission_energy_multiplier = 0.12
		mat.roughness = 0.2
		pillar.set_surface_override_material(0, mat)
		_arena_vfx_root.add_child(pillar)


func _add_grass_field() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = _arena_theme.get("grass", Color(0.22, 0.40, 0.18))
	material.roughness = 0.86
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.06, 0.34, 0.01)

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = 1800

	for i in range(multimesh.instance_count):
		var angle := battle_rng.randf() * TAU
		var dist := lerpf(5.8, 13.5, sqrt(battle_rng.randf()))
		var pos := Vector3(cos(angle) * dist, 0.16, sin(angle) * dist)
		var basis := Basis(Vector3.UP, battle_rng.randf() * TAU)
		basis = basis.rotated(basis.x, battle_rng.randf_range(-0.16, 0.16))
		basis = basis.scaled(Vector3(1.0, battle_rng.randf_range(0.7, 1.45), 1.0))
		multimesh.set_instance_transform(i, Transform3D(basis, pos))

	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arena_vfx_root.add_child(instance)


func _add_clearing_layers() -> void:
	var dirt_mesh := CylinderMesh.new()
	dirt_mesh.top_radius = 6.4
	dirt_mesh.bottom_radius = 6.6
	dirt_mesh.height = 0.05
	dirt_mesh.radial_segments = 48

	var dirt_material := StandardMaterial3D.new()
	dirt_material.albedo_color = _arena_theme.get("dirt", Color(0.40, 0.32, 0.22))
	dirt_material.roughness = 0.96

	var dirt := MeshInstance3D.new()
	dirt.mesh = dirt_mesh
	dirt.position = Vector3(0.0, 0.03, 0.0)
	dirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dirt.set_surface_override_material(0, dirt_material)
	_arena_vfx_root.add_child(dirt)

	var inner_mesh := CylinderMesh.new()
	inner_mesh.top_radius = 4.5
	inner_mesh.bottom_radius = 4.7
	inner_mesh.height = 0.03
	inner_mesh.radial_segments = 40

	var inner_material := StandardMaterial3D.new()
	inner_material.albedo_color = _arena_theme.get("dirt", Color(0.40, 0.32, 0.22)).darkened(0.12)
	inner_material.roughness = 0.98

	var inner := MeshInstance3D.new()
	inner.mesh = inner_mesh
	inner.position = Vector3(0.0, 0.045, 0.0)
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inner.set_surface_override_material(0, inner_material)
	_arena_vfx_root.add_child(inner)


func _add_tree_line() -> void:
	for i in range(18):
		var angle := float(i) / 18.0 * TAU + battle_rng.randf_range(-0.10, 0.10)
		var dist := battle_rng.randf_range(10.8, 14.5)
		var tree := Node3D.new()
		tree.position = Vector3(cos(angle) * dist, 0.0, sin(angle) * dist - 1.8)

		var trunk_height := battle_rng.randf_range(2.8, 4.6)
		var canopy_radius := battle_rng.randf_range(1.3, 2.4)

		var trunk_mesh := CylinderMesh.new()
		trunk_mesh.top_radius = 0.10
		trunk_mesh.bottom_radius = 0.16
		trunk_mesh.height = trunk_height
		var trunk := MeshInstance3D.new()
		trunk.mesh = trunk_mesh
		trunk.position = Vector3(0.0, trunk_height * 0.5, 0.0)
		var trunk_mat := StandardMaterial3D.new()
		trunk_mat.albedo_color = _arena_theme.get("tree_trunk", Color(0.38, 0.27, 0.18))
		trunk_mat.roughness = 0.94
		trunk.set_surface_override_material(0, trunk_mat)
		tree.add_child(trunk)

		var canopy_mesh := SphereMesh.new()
		canopy_mesh.radius = canopy_radius
		canopy_mesh.height = canopy_radius * 1.6
		canopy_mesh.radial_segments = 10
		canopy_mesh.rings = 6
		var canopy := MeshInstance3D.new()
		canopy.mesh = canopy_mesh
		canopy.position = Vector3(0.0, trunk_height + canopy_radius * 0.35, 0.0)
		var canopy_mat := StandardMaterial3D.new()
		canopy_mat.albedo_color = _arena_theme.get("tree_leaf", Color(0.16, 0.32, 0.16))
		canopy_mat.roughness = 0.86
		canopy_mat.emission_enabled = true
		canopy_mat.emission = _arena_theme.get("tree_leaf", Color(0.16, 0.32, 0.16)) * 0.12
		canopy_mat.emission_energy_multiplier = 0.06
		canopy.set_surface_override_material(0, canopy_mat)
		tree.add_child(canopy)

		_arena_vfx_root.add_child(tree)


func _add_rock_border() -> void:
	for _i in range(20):
		var angle := battle_rng.randf() * TAU
		var dist := battle_rng.randf_range(7.2, 10.0)
		var rock := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = battle_rng.randf_range(0.45, 0.82)
		sphere.radial_segments = battle_rng.randi_range(5, 8)
		sphere.rings = battle_rng.randi_range(3, 5)
		rock.mesh = sphere
		rock.position = Vector3(cos(angle) * dist, battle_rng.randf_range(0.08, 0.22), sin(angle) * dist)
		rock.rotation = Vector3(
			battle_rng.randf_range(-0.18, 0.18),
			battle_rng.randf() * TAU,
			battle_rng.randf_range(-0.18, 0.18)
		)
		rock.scale = Vector3.ONE * battle_rng.randf_range(0.55, 1.4)
		var rock_mat := StandardMaterial3D.new()
		rock_mat.albedo_color = _arena_theme.get("rock", Color(0.44, 0.42, 0.38))
		rock_mat.roughness = 0.95
		rock.set_surface_override_material(0, rock_mat)
		_arena_vfx_root.add_child(rock)


func _add_fog_walls() -> void:
	for pos in [
		Vector3(0.0, 2.3, -10.8),
		Vector3(-12.0, 2.1, -2.5),
		Vector3(12.0, 2.1, -2.5)
	]:
		var wall := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(12.0, 6.0)
		wall.mesh = plane
		wall.position = pos
		wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var fog_mat := StandardMaterial3D.new()
		var fog_color: Color = _arena_theme.get("fog", Color(0.7, 0.84, 0.76, 0.16))
		fog_mat.albedo_color = fog_color
		fog_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fog_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fog_mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		fog_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		wall.set_surface_override_material(0, fog_mat)
		wall.set_meta("base_y", wall.position.y)
		wall.set_meta("drift", battle_rng.randf_range(0.12, 0.24))
		wall.set_meta("offset", battle_rng.randf() * TAU)
		wall.set_meta("spin", 0.0)
		_arena_vfx_root.add_child(wall)
		_ambient_shards.append(wall)


func _add_ambient_motes() -> void:
	var accent: Color = _arena_theme.get("accent", Color(0.48, 0.72, 1.0))
	for _i in range(18):
		var mote := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = battle_rng.randf_range(0.04, 0.10)
		sphere.height = sphere.radius * 2.0
		mote.mesh = sphere
		mote.position = Vector3(
			battle_rng.randf_range(-9.0, 9.0),
			battle_rng.randf_range(0.8, 3.6),
			battle_rng.randf_range(-8.5, 3.0)
		)
		mote.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		var tint := accent.lerp(Color.WHITE, battle_rng.randf_range(0.15, 0.45))
		mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.16)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = tint
		mat.emission_energy_multiplier = battle_rng.randf_range(0.06, 0.18)
		mat.roughness = 0.4
		mote.set_surface_override_material(0, mat)
		mote.set_meta("base_y", mote.position.y)
		mote.set_meta("drift", battle_rng.randf_range(0.15, 0.35))
		mote.set_meta("offset", battle_rng.randf() * TAU)
		mote.set_meta("spin", battle_rng.randf_range(0.02, 0.08))
		_arena_vfx_root.add_child(mote)
		_ambient_shards.append(mote)


func _add_ambient_shards() -> void:
	var accent: Color = _arena_theme.get("accent", Color(0.48, 0.72, 1.0))
	for index in range(12):
		var mesh := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(
			battle_rng.randf_range(0.28, 0.58),
			battle_rng.randf_range(0.45, 1.1),
			battle_rng.randf_range(0.22, 0.4)
		)
		mesh.mesh = prism
		mesh.position = Vector3(
			battle_rng.randf_range(-9.5, 9.5),
			battle_rng.randf_range(1.2, 5.0),
			battle_rng.randf_range(-7.5, 5.0)
		)
		mesh.rotation = Vector3(
			battle_rng.randf() * TAU,
			battle_rng.randf() * TAU,
			battle_rng.randf() * TAU
		)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var material := StandardMaterial3D.new()
		var tint := accent.lerp(Color.WHITE, battle_rng.randf_range(0.08, 0.28))
		material.albedo_color = Color(tint.r, tint.g, tint.b, 0.52)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.emission_enabled = true
		material.emission = tint
		material.emission_energy_multiplier = battle_rng.randf_range(0.35, 0.75)
		material.roughness = 0.1
		mesh.set_surface_override_material(0, material)
		mesh.set_meta("base_y", mesh.position.y)
		mesh.set_meta("drift", battle_rng.randf_range(0.35, 0.8))
		mesh.set_meta("offset", battle_rng.randf() * TAU)
		mesh.set_meta("spin", battle_rng.randf_range(0.18, 0.44))
		_arena_vfx_root.add_child(mesh)
		_ambient_shards.append(mesh)
		if index % 3 == 0:
			mesh.set_meta("pulse_speed", battle_rng.randf_range(0.9, 1.6))
			mesh.set_meta("pulse_offset", battle_rng.randf() * TAU)
			mesh.set_meta("base_energy", material.emission_energy_multiplier)
			_pulse_meshes.append(mesh)


func _add_battle_particles() -> void:
	var particles := GPUParticles3D.new()
	particles.amount = 70
	particles.lifetime = 7.8
	particles.position = Vector3(0.0, 0.0, -1.0)
	particles.visibility_aabb = AABB(Vector3(-14.0, -2.0, -12.0), Vector3(28.0, 12.0, 24.0))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(11.0, 0.5, 9.0)
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 18.0
	process.initial_velocity_min = 0.02
	process.initial_velocity_max = 0.18
	process.gravity = Vector3(0.0, -0.01, 0.0)
	process.scale_min = 0.10
	process.scale_max = 0.42
	process.color = _arena_theme.get("particle", Color(0.45, 0.84, 0.72, 0.48))
	particles.process_material = process

	var draw_mesh := SphereMesh.new()
	draw_mesh.radius = 0.035
	draw_mesh.height = 0.07
	var material := StandardMaterial3D.new()
	var mote_color: Color = _arena_theme.get("particle", Color(0.45, 0.84, 0.72, 0.48))
	material.albedo_color = mote_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = mote_color
	material.emission_energy_multiplier = 0.25
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw_mesh.material = material
	particles.draw_pass_1 = draw_mesh
	particles.material_override = material

	_arena_vfx_root.add_child(particles)
