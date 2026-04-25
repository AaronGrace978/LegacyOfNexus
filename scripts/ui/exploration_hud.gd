extends CanvasLayer

var _compass_label: Label
var _phase_label: Label
var _buddy_name_label: Label
var _buddy_hp_label: Label
var _buddy_health_bar: ProgressBar
var _time_label: Label
var _prompt_label: Label
var _sprint_bar: ProgressBar
var _notification_label: Label
var _notification_time_left := 0.0

var _quest_panel: PanelContainer
var _quest_title_label: Label
var _quest_objective_label: Label
var _quest_tracked_id := ""
var _echo_counter_label: Label
var _bond_flash_label: Label
var _bond_flash_time_left := 0.0

var _cached_party_mgr: Node
var _cached_echo_mgr: Node
var _cached_qm: Node
var _cached_bm: Node
var _cached_overworld: Node
var _cached_party_menu: Node
var _cached_rift: Node3D
var _cached_cycle: Node
var _cached_player: CharacterBody3D
var _last_buddy_sig := ""
var _last_echo_sig := ""
var _last_quest_sig := ""


func _ready() -> void:
	layer = 5
	_build_hud()
	_bind_hud_caches()
	_connect_quest_signals()
	_connect_bond_signals()


func _bind_hud_caches() -> void:
	_cached_party_mgr = get_node_or_null("/root/PartyManager")
	_cached_echo_mgr = get_node_or_null("/root/EchoManager")
	_cached_qm = get_node_or_null("/root/QuestManager")
	_cached_bm = get_node_or_null("/root/BondManager")
	_cached_overworld = get_parent()
	if _cached_overworld != null:
		_cached_cycle = _cached_overworld.get_node_or_null("DayNightCycle")
		_cached_party_menu = _cached_overworld.get_node_or_null("PartyMenu")
		_cached_rift = _cached_overworld.get_node_or_null("UnstableRift") as Node3D


func _get_cached_player() -> CharacterBody3D:
	if is_instance_valid(_cached_player) and _cached_player.is_inside_tree():
		return _cached_player
	var found: Node = get_tree().get_first_node_in_group("player")
	_cached_player = found as CharacterBody3D
	return _cached_player


func _process(delta: float) -> void:
	_update_compass()
	_update_buddy_info()
	_update_time_display()
	_update_sprint_bar()
	_update_proximity_hints()
	_update_notification(delta)
	_update_bond_flash(delta)
	_update_echo_counter()


func _build_hud() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_compass(root)
	_build_buddy_panel(root)
	_build_time_display(root)
	_build_sprint_meter(root)
	_build_prompt(root)
	_build_notification(root)
	_build_quest_tracker(root)
	_build_echo_counter(root)
	_build_bond_flash(root)


# ---- Compass ----

func _build_compass(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.position = Vector2(-65.0, 12.0)
	panel.custom_minimum_size = Vector2(140.0, 52.0)
	panel.add_theme_stylebox_override("panel", _hud_panel(Color(0.0, 0.0, 0.0, 0.42)))
	parent.add_child(panel)

	var v := VBoxContainer.new()
	panel.add_child(v)

	_compass_label = Label.new()
	_compass_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_compass_label.add_theme_font_size_override("font_size", 16)
	_compass_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 0.92))
	v.add_child(_compass_label)

	_phase_label = Label.new()
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.add_theme_font_size_override("font_size", 12)
	_phase_label.add_theme_color_override("font_color", Color(0.55, 0.68, 0.82, 0.62))
	v.add_child(_phase_label)


# ---- Lead buddy info ----

func _build_buddy_panel(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.position = Vector2(16.0, -84.0)
	panel.custom_minimum_size = Vector2(210.0, 60.0)
	panel.add_theme_stylebox_override("panel", _hud_panel(Color(0.04, 0.06, 0.12, 0.68), Color(0.2, 0.38, 0.6, 0.4)))
	parent.add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var top_row := HBoxContainer.new()
	vbox.add_child(top_row)

	_buddy_name_label = Label.new()
	_buddy_name_label.text = "Dino Buddy"
	_buddy_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buddy_name_label.add_theme_font_size_override("font_size", 15)
	_buddy_name_label.add_theme_color_override("font_color", Color(0.65, 0.95, 0.72, 0.92))
	top_row.add_child(_buddy_name_label)

	_buddy_hp_label = Label.new()
	_buddy_hp_label.text = ""
	_buddy_hp_label.add_theme_font_size_override("font_size", 13)
	_buddy_hp_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.82, 0.7))
	top_row.add_child(_buddy_hp_label)

	_buddy_health_bar = ProgressBar.new()
	_buddy_health_bar.custom_minimum_size = Vector2(190.0, 12.0)
	_buddy_health_bar.max_value = 100
	_buddy_health_bar.value = 100
	_buddy_health_bar.show_percentage = false
	_buddy_health_bar.add_theme_stylebox_override("background", _bar_style(Color(0.08, 0.08, 0.12, 0.85)))
	_buddy_health_bar.add_theme_stylebox_override("fill", _bar_style(Color(0.28, 0.85, 0.42, 0.92)))
	vbox.add_child(_buddy_health_bar)


# ---- Time of day ----

func _build_time_display(parent: Control) -> void:
	_time_label = Label.new()
	_time_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_time_label.position = Vector2(-120.0, -32.0)
	_time_label.add_theme_font_size_override("font_size", 14)
	_time_label.add_theme_color_override("font_color", Color(0.62, 0.68, 0.78, 0.55))
	parent.add_child(_time_label)


# ---- Sprint meter (cosmetic feedback) ----

func _build_sprint_meter(parent: Control) -> void:
	_sprint_bar = ProgressBar.new()
	_sprint_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_sprint_bar.position = Vector2(-100.0, -28.0)
	_sprint_bar.custom_minimum_size = Vector2(200.0, 5.0)
	_sprint_bar.max_value = 100.0
	_sprint_bar.value = 0.0
	_sprint_bar.show_percentage = false
	_sprint_bar.add_theme_stylebox_override("background", _bar_style(Color(0.06, 0.07, 0.1, 0.75)))
	_sprint_bar.add_theme_stylebox_override("fill", _bar_style(Color(0.35, 0.72, 0.95, 0.85)))
	parent.add_child(_sprint_bar)


# ---- Interaction prompt ----

func _build_prompt(parent: Control) -> void:
	_prompt_label = Label.new()
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.position = Vector2(-120.0, -52.0)
	_prompt_label.custom_minimum_size = Vector2(240.0, 0.0)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 17)
	_prompt_label.add_theme_color_override("font_color", Color(0.88, 0.92, 1.0, 0.88))
	_prompt_label.visible = false
	parent.add_child(_prompt_label)


func _build_quest_tracker(parent: Control) -> void:
	_quest_panel = PanelContainer.new()
	_quest_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_quest_panel.position = Vector2(-330.0, 16.0)
	_quest_panel.custom_minimum_size = Vector2(312.0, 0.0)
	_quest_panel.add_theme_stylebox_override("panel", _hud_panel(Color(0.03, 0.05, 0.11, 0.72), Color(0.32, 0.58, 0.9, 0.45)))
	_quest_panel.visible = false
	parent.add_child(_quest_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	_quest_panel.add_child(vbox)

	var tag := Label.new()
	tag.text = "Current Quest"
	tag.add_theme_font_size_override("font_size", 11)
	tag.add_theme_color_override("font_color", Color(0.55, 0.7, 0.9, 0.65))
	vbox.add_child(tag)

	_quest_title_label = Label.new()
	_quest_title_label.add_theme_font_size_override("font_size", 15)
	_quest_title_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0, 0.95))
	vbox.add_child(_quest_title_label)

	_quest_objective_label = Label.new()
	_quest_objective_label.add_theme_font_size_override("font_size", 13)
	_quest_objective_label.add_theme_color_override("font_color", Color(0.78, 0.88, 1.0, 0.82))
	_quest_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quest_objective_label.custom_minimum_size = Vector2(296.0, 0.0)
	vbox.add_child(_quest_objective_label)


func _build_echo_counter(parent: Control) -> void:
	_echo_counter_label = Label.new()
	_echo_counter_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_echo_counter_label.position = Vector2(-140.0, 14.0)
	_echo_counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_echo_counter_label.add_theme_font_size_override("font_size", 12)
	_echo_counter_label.add_theme_color_override("font_color", Color(0.6, 0.78, 0.95, 0.7))
	_echo_counter_label.visible = false
	parent.add_child(_echo_counter_label)


func _build_bond_flash(parent: Control) -> void:
	_bond_flash_label = Label.new()
	_bond_flash_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_bond_flash_label.position = Vector2(-240.0, 110.0)
	_bond_flash_label.custom_minimum_size = Vector2(480.0, 0.0)
	_bond_flash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bond_flash_label.add_theme_font_size_override("font_size", 14)
	_bond_flash_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.8, 0.95))
	_bond_flash_label.visible = false
	parent.add_child(_bond_flash_label)


func _build_notification(parent: Control) -> void:
	_notification_label = Label.new()
	_notification_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_notification_label.position = Vector2(-180.0, 64.0)
	_notification_label.custom_minimum_size = Vector2(360.0, 0.0)
	_notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notification_label.add_theme_font_size_override("font_size", 16)
	_notification_label.add_theme_color_override("font_color", Color(0.93, 0.98, 1.0, 0.96))
	_notification_label.visible = false
	parent.add_child(_notification_label)


# ---- Updates ----

func _update_compass() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var forward := -camera.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		return
	forward = forward.normalized()

	var angle := atan2(forward.x, forward.z)
	var deg := fmod(rad_to_deg(angle) + 360.0, 360.0)

	var dir: String
	if deg >= 337.5 or deg < 22.5:
		dir = "N"
	elif deg < 67.5:
		dir = "NE"
	elif deg < 112.5:
		dir = "E"
	elif deg < 157.5:
		dir = "SE"
	elif deg < 202.5:
		dir = "S"
	elif deg < 247.5:
		dir = "SW"
	elif deg < 292.5:
		dir = "W"
	else:
		dir = "NW"

	_compass_label.text = "%s  %d°" % [dir, int(deg)]

	if _phase_label:
		var cycle: Node = _cached_cycle
		if cycle != null and cycle.has_method("get_time_of_day"):
			var tod: float = float(cycle.call("get_time_of_day"))
			_phase_label.text = _phase_name(tod)
		else:
			_phase_label.text = ""


func _phase_name(tod: float) -> String:
	if tod < 0.22:
		return "Night"
	if tod < 0.35:
		return "Dawn"
	if tod < 0.65:
		return "Day"
	if tod < 0.78:
		return "Dusk"
	return "Night"


func _update_buddy_info() -> void:
	if _cached_party_mgr == null or not _cached_party_mgr.has_method("get_party_for_display"):
		return

	var party: Array = _cached_party_mgr.call("get_party_for_display")
	if party.is_empty():
		return

	var lead: Dictionary = party[0]
	if lead.get("empty", true):
		return

	var hp: int = int(lead.get("hp", 0))
	var max_hp: int = int(lead.get("max_hp", 1))
	var sig := "%s|%d|%d" % [str(lead.get("name", "Buddy")), hp, max_hp]
	if sig == _last_buddy_sig:
		return
	_last_buddy_sig = sig

	_buddy_name_label.text = str(lead.get("name", "Buddy"))
	_buddy_hp_label.text = "%d/%d" % [hp, max_hp]
	_buddy_health_bar.max_value = max_hp
	_buddy_health_bar.value = hp


func _update_time_display() -> void:
	if _cached_cycle == null or not _cached_cycle.has_method("get_time_of_day"):
		_time_label.text = ""
		return

	var tod: float = _cached_cycle.call("get_time_of_day")
	var total_minutes := int(tod * 1440.0)
	var hours := (total_minutes / 60) % 24
	var minutes := total_minutes % 60
	var period := "AM" if hours < 12 else "PM"
	var display_hour := hours % 12
	if display_hour == 0:
		display_hour = 12

	_time_label.text = "%d:%02d %s" % [display_hour, minutes, period]


func _update_sprint_bar() -> void:
	if _sprint_bar == null:
		return
	var player := _get_cached_player()
	if player == null or not player.has_method("is_sprinting"):
		_sprint_bar.value = lerpf(_sprint_bar.value, 0.0, 0.2)
		return
	var sprinting: bool = player.is_sprinting()
	var target: float = 100.0 if (sprinting and Input.is_action_pressed("sprint")) else 0.0
	_sprint_bar.value = lerpf(_sprint_bar.value, target, 0.18)


func _update_proximity_hints() -> void:
	if _cached_overworld == null:
		return

	if _cached_overworld.get("capture_active") == true:
		hide_prompt()
		return

	var party_menu: Node = _cached_party_menu
	if party_menu:
		if party_menu is CanvasItem and (party_menu as CanvasItem).visible:
			hide_prompt()
			return
		if party_menu is CanvasLayer and (party_menu as CanvasLayer).visible:
			hide_prompt()
			return

	var player := _get_cached_player()
	if player == null:
		hide_prompt()
		return

	var rift: Node3D = _cached_rift
	if rift and rift.has_method("build_encounter"):
		var tr: float = float(rift.get("trigger_radius"))
		var d: float = player.global_position.distance_to(rift.global_position)
		if d > tr * 0.95 and d < tr * 2.4:
			show_prompt("Rift energy ahead — move closer to engage")
			return

	hide_prompt()


func _find_player() -> CharacterBody3D:
	return _get_cached_player()


func show_prompt(text: String) -> void:
	_prompt_label.text = text
	_prompt_label.visible = true


func hide_prompt() -> void:
	_prompt_label.visible = false


func push_notification(text: String, duration := 2.2) -> void:
	if _notification_label == null:
		return
	_notification_label.text = text
	_notification_label.visible = true
	_notification_time_left = maxf(duration, 0.1)


func _update_notification(delta: float) -> void:
	if _notification_label == null or not _notification_label.visible:
		return
	_notification_time_left = maxf(_notification_time_left - delta, 0.0)
	if _notification_time_left <= 0.0:
		_notification_label.visible = false


func _update_bond_flash(delta: float) -> void:
	if _bond_flash_label == null or not _bond_flash_label.visible:
		return
	_bond_flash_time_left = maxf(_bond_flash_time_left - delta, 0.0)
	if _bond_flash_time_left <= 0.0:
		_bond_flash_label.visible = false


func _update_echo_counter() -> void:
	if _echo_counter_label == null:
		return
	if _cached_echo_mgr == null or not _cached_echo_mgr.has_method("get_collected_count"):
		_echo_counter_label.visible = false
		return
	var c := int(_cached_echo_mgr.call("get_collected_count"))
	var t := int(_cached_echo_mgr.call("get_total_count"))
	var sig := "%d|%d" % [c, t]
	if sig == _last_echo_sig and _echo_counter_label.visible:
		return
	_last_echo_sig = sig
	if c <= 0 and t <= 0:
		_echo_counter_label.visible = false
		return
	_echo_counter_label.visible = true
	_echo_counter_label.text = "✧ Echoes  %d / %d" % [c, t]


func _connect_quest_signals() -> void:
	var qm: Node = _cached_qm
	if qm == null:
		return
	if qm.has_signal("quest_started") and not qm.quest_started.is_connected(_on_quest_state_changed):
		qm.quest_started.connect(_on_quest_state_changed)
	if qm.has_signal("quest_updated") and not qm.quest_updated.is_connected(_on_quest_state_changed):
		qm.quest_updated.connect(_on_quest_state_changed)
	if qm.has_signal("quest_completed") and not qm.quest_completed.is_connected(_on_quest_completed):
		qm.quest_completed.connect(_on_quest_completed)
	_refresh_quest_tracker()


func _connect_bond_signals() -> void:
	var bm: Node = _cached_bm
	if bm == null:
		return
	if bm.has_signal("bond_changed") and not bm.bond_changed.is_connected(_on_bond_changed):
		bm.bond_changed.connect(_on_bond_changed)


func _on_quest_state_changed(_quest_id: String) -> void:
	_refresh_quest_tracker()


func _on_quest_completed(quest_id: String) -> void:
	var qm: Node = _cached_qm
	if qm != null and qm.has_method("get_quest_info"):
		var info: Dictionary = qm.call("get_quest_info", quest_id)
		push_notification("Quest complete: %s" % String(info.get("title", "Quest")), 3.0)
	_refresh_quest_tracker()


func _on_bond_changed(buddy_name: String, value: int, delta: int) -> void:
	if delta == 0 or _bond_flash_label == null:
		return
	var sign_str := "+" if delta > 0 else ""
	_bond_flash_label.text = "%s  %s%d Bond  (%d)" % [buddy_name, sign_str, delta, value]
	_bond_flash_label.visible = true
	_bond_flash_time_left = 2.2


func _refresh_quest_tracker() -> void:
	if _quest_panel == null:
		return
	var qm: Node = _cached_qm
	if qm == null:
		_quest_panel.visible = false
		return
	var id := String(qm.call("get_tracked_quest_id"))
	if id == "":
		_quest_panel.visible = false
		_quest_tracked_id = ""
		_last_quest_sig = ""
		return
	var info: Dictionary = qm.call("get_quest_info", id)
	var title := String(info.get("title", "Quest"))
	var objective := String(info.get("objective_text", ""))
	var sig := "%s|%s|%s" % [id, title, objective]
	if sig == _last_quest_sig and _quest_panel.visible:
		return
	_last_quest_sig = sig
	_quest_tracked_id = id
	_quest_title_label.text = title
	_quest_objective_label.text = "» %s" % objective
	_quest_panel.visible = true


# ---- Helpers ----

func _hud_panel(bg: Color, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1 if border.a > 0.05 else 0)
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(8)
	return sb


func _bar_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(3)
	return sb
