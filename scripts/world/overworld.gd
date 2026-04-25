extends Node3D

signal battle_enter_requested

signal quit_to_title_requested

@export var proximity_battle_hysteresis := 1.25

@onready var player: CharacterBody3D = $Player
@onready var party_menu: Node = $PartyMenu
@onready var capture_ui: CanvasLayer = $CaptureRhythmUI
@onready var unstable_rift: Node3D = $UnstableRift
@onready var exploration_hud: CanvasLayer = $ExplorationHUD
@onready var pause_menu: CanvasLayer = $PauseMenu
@onready var journal_ui: CanvasLayer = $JournalUI

var capture_active := false
var _wild_buddies: Array[Node3D] = []
var _wild_battle_edge_map: Dictionary = {}
var _capturing_wild_buddy: Node3D = null
var _rift_battle_edge_ready := true
var _captured_wild_ids: Dictionary = {}


func _ready() -> void:
	add_to_group("overworld")
	_sanitize_missing_materials()
	_sanitize_multimesh_surface_materials(self)
	if party_menu.has_signal("menu_toggled"):
		party_menu.menu_toggled.connect(_on_party_menu_visibility_changed)

	_collect_wild_buddies()

	if capture_ui:
		if capture_ui.has_signal("capture_succeeded"):
			capture_ui.capture_succeeded.connect(_on_capture_succeeded)
		if capture_ui.has_signal("capture_failed"):
			capture_ui.capture_failed.connect(_on_capture_failed)

	var encounter_bridge := _get_encounter_bridge()
	if encounter_bridge != null and encounter_bridge.has_method("apply_overworld_restore_if_needed"):
		encounter_bridge.call("apply_overworld_restore_if_needed", player)

	_connect_echo_shards()
	_connect_pause_menu()
	_connect_journal()
	_auto_start_intro_quest()


func _sanitize_missing_materials() -> void:
	var fallback := StandardMaterial3D.new()
	fallback.albedo_color = Color(0.45, 0.56, 0.42, 1.0)
	fallback.roughness = 0.82
	fallback.metallic = 0.0
	fallback.metallic_specular = 0.2

	_apply_fallback_materials_recursive(self, fallback)


func _apply_fallback_materials_recursive(node: Node, fallback: Material) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			var surface_count := mesh_node.mesh.get_surface_count()
			for surface_idx in range(surface_count):
				var mat := mesh_node.get_active_material(surface_idx)
				if mat == null:
					mat = mesh_node.mesh.surface_get_material(surface_idx)
				if mat == null:
					mesh_node.set_surface_override_material(surface_idx, fallback)

	for child in node.get_children():
		_apply_fallback_materials_recursive(child, fallback)


func _sanitize_multimesh_surface_materials(root: Node) -> void:
	if root is MultiMeshInstance3D:
		_patch_multimesh_null_surfaces(root as MultiMeshInstance3D)
	for child in root.get_children():
		_sanitize_multimesh_surface_materials(child)


func _patch_multimesh_null_surfaces(mmi: MultiMeshInstance3D) -> void:
	var mm := mmi.multimesh
	if mm == null or mm.mesh == null:
		return
	if mmi.material_override != null:
		return
	var src_mesh: Mesh = mm.mesh
	if src_mesh is ArrayMesh:
		var am := src_mesh.duplicate() as ArrayMesh
		var patched := false
		for si in range(am.get_surface_count()):
			if am.surface_get_material(si) == null:
				var fb := StandardMaterial3D.new()
				fb.albedo_color = Color(0.55, 0.58, 0.64)
				fb.roughness = 0.82
				fb.metallic = 0.02
				am.surface_set_material(si, fb)
				patched = true
		if patched:
			mm.mesh = am
		return
	for si in range(src_mesh.get_surface_count()):
		if src_mesh.surface_get_material(si) == null:
			var fb2 := StandardMaterial3D.new()
			fb2.albedo_color = Color(0.55, 0.58, 0.64)
			fb2.roughness = 0.82
			mmi.material_override = fb2
			return


func _exit_tree() -> void:
	get_tree().paused = false


func _collect_wild_buddies() -> void:
	for child in get_children():
		if child is Node3D and child.has_signal("capture_requested"):
			_wild_buddies.append(child)
			_wild_battle_edge_map[child] = true
			child.capture_requested.connect(_on_wild_buddy_capture_requested)


func is_party_menu_input_allowed() -> bool:
	return not capture_active


func _process(_delta: float) -> void:
	if capture_active:
		return
	if player == null or not is_instance_valid(player):
		return

	var encounter_bridge := _get_encounter_bridge()
	if encounter_bridge != null and encounter_bridge.has_method("update_auto_encounter_suppression"):
		encounter_bridge.call("update_auto_encounter_suppression", player.global_position)

	if _party_menu_blocks_world():
		return

	_update_wild_proximity_battle()
	_update_rift_proximity_battle()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F5:
		if capture_active:
			_notify("Can't quick-save during capture.", 2.0)
		elif _party_menu_blocks_world():
			_notify("Close the party menu before saving.", 2.0)
		else:
			_write_quick_save("Adventure saved.", 2.2)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_cancel"):
		if capture_active:
			return
		if journal_ui != null and journal_ui.visible:
			return
		if _party_menu_blocks_world():
			return
		_toggle_pause_menu()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("journal"):
		if capture_active:
			return
		if pause_menu != null and pause_menu.has_method("is_open") and pause_menu.call("is_open"):
			return
		if _party_menu_blocks_world():
			return
		_toggle_journal()
		get_viewport().set_input_as_handled()
		return


func _party_menu_blocks_world() -> bool:
	if party_menu == null:
		return false
	if party_menu is CanvasItem:
		return (party_menu as CanvasItem).visible
	if party_menu is CanvasLayer:
		return (party_menu as CanvasLayer).visible
	return false


func _get_encounter_bridge() -> Node:
	return get_node_or_null("/root/EncounterBridge")


func _update_wild_proximity_battle() -> void:
	var encounter_bridge := _get_encounter_bridge()
	var suppressed: bool = false
	if encounter_bridge != null and encounter_bridge.has_method("is_auto_encounter_suppressed"):
		suppressed = bool(encounter_bridge.call("is_auto_encounter_suppressed", player.global_position))

	for buddy in _wild_buddies:
		if not is_instance_valid(buddy):
			continue

		var battle_radius: float = buddy.auto_battle_radius
		if battle_radius <= 0.0:
			continue

		var distance: float = player.global_position.distance_to(buddy.global_position)
		if distance > battle_radius + proximity_battle_hysteresis:
			_wild_battle_edge_map[buddy] = true

		if suppressed:
			continue

		var edge_ready: bool = _wild_battle_edge_map.get(buddy, true)
		if distance <= battle_radius and edge_ready:
			_wild_battle_edge_map[buddy] = false
			var encounter: Dictionary = _build_encounter_from_wild(buddy)
			var clear_distance: float = battle_radius + proximity_battle_hysteresis
			if encounter_bridge != null and encounter_bridge.has_method("start_overworld_battle"):
				encounter_bridge.call("start_overworld_battle", encounter, player, buddy.global_position, clear_distance)
			emit_signal("battle_enter_requested")
			return


func _update_rift_proximity_battle() -> void:
	if unstable_rift == null or not is_instance_valid(unstable_rift):
		return
	if not unstable_rift.has_method("build_encounter"):
		return

	var encounter_bridge := _get_encounter_bridge()
	var trigger_radius: float = float(unstable_rift.get("trigger_radius"))
	if trigger_radius <= 0.0:
		return

	var distance: float = player.global_position.distance_to(unstable_rift.global_position)
	if distance > trigger_radius + proximity_battle_hysteresis:
		_rift_battle_edge_ready = true

	if encounter_bridge != null and encounter_bridge.has_method("is_auto_encounter_suppressed") and encounter_bridge.call("is_auto_encounter_suppressed", player.global_position):
		return

	if distance <= trigger_radius and _rift_battle_edge_ready:
		_rift_battle_edge_ready = false
		var encounter: Dictionary = unstable_rift.call("build_encounter")
		var clear_distance: float = float(unstable_rift.call("get_suppress_clear_distance"))
		if encounter_bridge != null and encounter_bridge.has_method("start_overworld_battle"):
			encounter_bridge.call("start_overworld_battle", encounter, player, unstable_rift.global_position, clear_distance)
		emit_signal("battle_enter_requested")


func _build_encounter_from_wild(wild: Node) -> Dictionary:
	var enemies: Array = [
		{"name": wild.buddy_name, "level": wild.encounter_level},
	]
	var rear_name: String = str(wild.rear_encounter_buddy_name).strip_edges()
	if rear_name != "":
		enemies.append({"name": rear_name, "level": wild.rear_encounter_level})
	return {"enemies": enemies}


func _on_party_menu_visibility_changed(is_open: bool) -> void:
	if capture_active:
		return

	if player and player.has_method("set_controls_enabled"):
		player.set_controls_enabled(not is_open)

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if is_open else Input.MOUSE_MODE_CAPTURED


func _on_wild_buddy_capture_requested(wild_node: Node3D, buddy_name: String) -> void:
	if capture_active:
		return

	if party_menu and party_menu.has_method("hide_menu"):
		party_menu.hide_menu()

	capture_active = true
	_capturing_wild_buddy = wild_node
	if player and player.has_method("set_controls_enabled"):
		player.set_controls_enabled(false)

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if capture_ui and capture_ui.has_method("start_capture"):
		capture_ui.start_capture(buddy_name)


func _on_capture_succeeded(_buddy_name: String) -> void:
	capture_active = false
	if player and player.has_method("set_controls_enabled"):
		player.set_controls_enabled(true)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var captured_name := ""
	if is_instance_valid(_capturing_wild_buddy):
		captured_name = str(_capturing_wild_buddy.get("buddy_name"))
		_mark_wild_buddy_captured(_capturing_wild_buddy)
		_wild_buddies.erase(_capturing_wild_buddy)
		_wild_battle_edge_map.erase(_capturing_wild_buddy)
		_capturing_wild_buddy.queue_free()
	_capturing_wild_buddy = null

	var qm: Node = get_node_or_null("/root/QuestManager")
	if qm != null and qm.has_method("report_event"):
		qm.call("report_event", "buddy_captured", captured_name, {})
	var bond: Node = get_node_or_null("/root/BondManager")
	if bond != null and bond.has_method("add_bond"):
		if captured_name != "":
			bond.call("add_bond", captured_name, 10, "capture")
		bond.call("add_bond", "Dino Buddy", 3, "capture_witness")

	_write_quick_save("Buddy captured. Progress saved.", 2.6)


func _on_capture_failed(_reason: String) -> void:
	capture_active = false
	if player and player.has_method("set_controls_enabled"):
		player.set_controls_enabled(true)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if is_instance_valid(_capturing_wild_buddy):
		_mark_wild_buddy_captured(_capturing_wild_buddy)
		_wild_buddies.erase(_capturing_wild_buddy)
		_wild_battle_edge_map.erase(_capturing_wild_buddy)
		_capturing_wild_buddy.queue_free()
	_capturing_wild_buddy = null


func get_save_data() -> Dictionary:
	var party_manager: Node = get_node_or_null("/root/PartyManager")
	var party_data: Dictionary = {}
	if party_manager != null and party_manager.has_method("get_save_data"):
		party_data = party_manager.call("get_save_data")

	var cycle: Node = get_node_or_null("DayNightCycle")
	var time_of_day := 0.30
	if cycle != null and cycle.has_method("get_time_of_day"):
		time_of_day = float(cycle.call("get_time_of_day"))

	var captured_ids: Array = []
	for key in _captured_wild_ids.keys():
		captured_ids.append(str(key))

	var quest_data: Dictionary = {}
	var qm: Node = get_node_or_null("/root/QuestManager")
	if qm != null and qm.has_method("get_save_data"):
		quest_data = qm.call("get_save_data")

	var bond_data: Dictionary = {}
	var bm: Node = get_node_or_null("/root/BondManager")
	if bm != null and bm.has_method("get_save_data"):
		bond_data = bm.call("get_save_data")

	var echo_data: Dictionary = {}
	var em: Node = get_node_or_null("/root/EchoManager")
	if em != null and em.has_method("get_save_data"):
		echo_data = em.call("get_save_data")

	var inventory_data: Dictionary = {}
	var item_mgr: Node = get_node_or_null("/root/ItemManager")
	if item_mgr != null and item_mgr.has_method("get_save_data"):
		inventory_data = item_mgr.call("get_save_data")

	return {
		"scene": "overworld",
		"location": "Greenbelt Park",
		"time_of_day": time_of_day,
		"player": player.call("get_save_state") if player != null and player.has_method("get_save_state") else {},
		"party": party_data,
		"captured_wild_ids": captured_ids,
		"quests": quest_data,
		"bonds": bond_data,
		"echoes": echo_data,
		"inventory": inventory_data,
	}


func apply_save_data(data: Dictionary) -> void:
	var party_manager: Node = get_node_or_null("/root/PartyManager")
	if party_manager != null and party_manager.has_method("load_from_save_data"):
		party_manager.call("load_from_save_data", _as_dictionary(data.get("party", {})))

	var cycle: Node = get_node_or_null("DayNightCycle")
	if cycle != null and cycle.has_method("set_time_of_day"):
		cycle.call("set_time_of_day", float(data.get("time_of_day", 0.30)))

	if player != null and player.has_method("apply_save_state"):
		player.call("apply_save_state", _as_dictionary(data.get("player", {})))
	if player != null and player.has_method("set_controls_enabled"):
		player.call("set_controls_enabled", true)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	capture_active = false
	_apply_captured_wild_ids(_as_array(data.get("captured_wild_ids", [])))

	var qm: Node = get_node_or_null("/root/QuestManager")
	if qm != null and qm.has_method("load_from_save_data"):
		qm.call("load_from_save_data", _as_dictionary(data.get("quests", {})))

	var bm: Node = get_node_or_null("/root/BondManager")
	if bm != null and bm.has_method("load_from_save_data"):
		bm.call("load_from_save_data", _as_dictionary(data.get("bonds", {})))

	var em: Node = get_node_or_null("/root/EchoManager")
	if em != null and em.has_method("load_from_save_data"):
		em.call("load_from_save_data", _as_dictionary(data.get("echoes", {})))

	var im_load: Node = get_node_or_null("/root/ItemManager")
	if im_load != null and im_load.has_method("load_from_save_data"):
		im_load.call("load_from_save_data", _as_dictionary(data.get("inventory", {})))
	_sync_echo_shard_collected_state()

	if exploration_hud != null and exploration_hud.has_method("_refresh_quest_tracker"):
		exploration_hud.call("_refresh_quest_tracker")

	_notify("Continue loaded.", 2.5)


func _write_quick_save(success_text: String, duration := 2.2) -> void:
	var save_manager: Node = get_node_or_null("/root/SaveManager")
	if save_manager == null or not save_manager.has_method("write_overworld_save"):
		_notify("Save system unavailable.", 2.0)
		return

	var ok: bool = bool(save_manager.call("write_overworld_save", self))
	_notify(success_text if ok else "Save failed.", duration)


func _notify(text: String, duration := 2.2) -> void:
	if exploration_hud != null and exploration_hud.has_method("push_notification"):
		exploration_hud.call("push_notification", text, duration)


func _mark_wild_buddy_captured(wild_node: Node3D) -> void:
	if wild_node == null:
		return
	var wild_id := str(wild_node.name).strip_edges()
	if wild_id.is_empty():
		return
	_captured_wild_ids[wild_id] = true


func _apply_captured_wild_ids(raw_ids: Array) -> void:
	_captured_wild_ids.clear()
	for value in raw_ids:
		var wild_id := str(value).strip_edges()
		if wild_id.is_empty():
			continue
		_captured_wild_ids[wild_id] = true

	var remaining_wilds: Array[Node3D] = []
	var remaining_edges: Dictionary = {}
	for buddy in _wild_buddies:
		if buddy == null or not is_instance_valid(buddy):
			continue
		if _captured_wild_ids.has(str(buddy.name)):
			buddy.queue_free()
			continue
		remaining_wilds.append(buddy)
		remaining_edges[buddy] = _wild_battle_edge_map.get(buddy, true)

	_wild_buddies = remaining_wilds
	_wild_battle_edge_map = remaining_edges


func _as_dictionary(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value as Dictionary
	return {}


func _as_array(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value as Array
	return []


func _connect_echo_shards() -> void:
	for child in get_children():
		if child.has_signal("echo_collected"):
			if not child.echo_collected.is_connected(_on_echo_collected):
				child.echo_collected.connect(_on_echo_collected)


func _on_echo_collected(echo_id: String, data: Dictionary) -> void:
	var em: Node = get_node_or_null("/root/EchoManager")
	if em != null and em.has_method("mark_collected"):
		em.call("mark_collected", echo_id)
	var title := String(data.get("title", "Echo"))
	_notify("Echo recovered: %s" % title, 3.0)


func _sync_echo_shard_collected_state() -> void:
	var em: Node = get_node_or_null("/root/EchoManager")
	if em == null or not em.has_method("is_collected"):
		return
	for child in get_children():
		if child.has_method("mark_collected_from_save") and child.get("echo_id") != null:
			var id := String(child.get("echo_id"))
			if bool(em.call("is_collected", id)):
				child.call("mark_collected_from_save")


func _connect_pause_menu() -> void:
	if pause_menu == null:
		return
	if pause_menu.has_signal("save_requested") and not pause_menu.save_requested.is_connected(_on_pause_save):
		pause_menu.save_requested.connect(_on_pause_save)
	if pause_menu.has_signal("quit_to_title_requested") and not pause_menu.quit_to_title_requested.is_connected(_on_quit_to_title):
		pause_menu.quit_to_title_requested.connect(_on_quit_to_title)
	if pause_menu.has_signal("resumed") and not pause_menu.resumed.is_connected(_on_pause_resumed):
		pause_menu.resumed.connect(_on_pause_resumed)


func _connect_journal() -> void:
	# Journal binds its own input handlers internally.
	pass


func _toggle_pause_menu() -> void:
	if pause_menu == null:
		return
	if pause_menu.has_method("toggle"):
		pause_menu.call("toggle")


func _toggle_journal() -> void:
	if journal_ui == null:
		return
	if journal_ui.has_method("toggle"):
		journal_ui.call("toggle")


func _on_pause_save() -> void:
	_write_quick_save("Adventure saved.", 2.2)


func _on_pause_resumed() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_quit_to_title() -> void:
	emit_signal("quit_to_title_requested")


func _auto_start_intro_quest() -> void:
	var qm: Node = get_node_or_null("/root/QuestManager")
	if qm == null or not qm.has_method("auto_start_available_quests"):
		return
	qm.call("auto_start_available_quests")
