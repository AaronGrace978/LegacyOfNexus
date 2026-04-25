extends CanvasLayer

const InputLabelHelper := preload("res://scripts/ui/input_label_helper.gd")

signal resumed
signal quit_to_title_requested
signal save_requested

var _root: Control
var _status_label: Label
var _resume_button: Button
var _previous_mouse_mode := Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()


func is_open() -> bool:
	return visible


func open_menu() -> void:
	if visible:
		return
	_previous_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	visible = true
	_refresh_status()
	call_deferred("_grab_pause_focus")


func close_menu() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	Input.mouse_mode = _previous_mouse_mode if _previous_mouse_mode != Input.MOUSE_MODE_VISIBLE else Input.MOUSE_MODE_CAPTURED
	emit_signal("resumed")


func toggle() -> void:
	if visible:
		close_menu()
	else:
		open_menu()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_menu()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.02, 0.06, 0.75)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-240.0, -250.0)
	panel.custom_minimum_size = Vector2(480.0, 500.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.07, 0.14, 0.97)
	sb.border_color = Color(0.36, 0.58, 0.88, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", sb)
	_root.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)

	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.88, 0.94, 1.0, 1.0))
	v.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "~ Legacy of Nexus ~"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.5, 0.65, 0.85, 0.75))
	v.add_child(subtitle)

	v.add_child(_spacer(18))

	_resume_button = _menu_button("Resume")
	_resume_button.pressed.connect(close_menu)
	v.add_child(_resume_button)

	var save_btn := _menu_button("Quick Save")
	save_btn.pressed.connect(_on_save_pressed)
	v.add_child(save_btn)

	var controls_btn := _menu_button("Show Controls")
	controls_btn.pressed.connect(_show_controls)
	v.add_child(controls_btn)

	var quit_btn := _menu_button("Quit to Title")
	quit_btn.pressed.connect(_on_quit_pressed)
	v.add_child(quit_btn)

	v.add_child(_spacer(12))

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", Color(0.65, 0.78, 0.92, 0.82))
	v.add_child(_status_label)


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _menu_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(380, 44)
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(0.95, 1.0, 1.0, 1.0))

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.1, 0.15, 0.26, 0.92)
	normal.border_color = Color(0.3, 0.48, 0.8, 0.55)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(6)
	normal.set_content_margin_all(8)

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.16, 0.24, 0.42, 0.96)
	hover.border_color = Color(0.45, 0.72, 1.0, 0.95)
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(6)
	hover.set_content_margin_all(8)

	var focus := hover.duplicate() as StyleBoxFlat
	focus.border_color = Color(0.55, 0.82, 1.0, 1.0)
	focus.set_border_width_all(3)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", focus)
	return btn


func _grab_pause_focus() -> void:
	if is_instance_valid(_resume_button):
		_resume_button.grab_focus()


func _on_save_pressed() -> void:
	emit_signal("save_requested")
	_status_label.text = "Quick saving..."
	var tree := get_tree()
	await tree.create_timer(0.2).timeout
	_refresh_status()


func _show_controls() -> void:
	_status_label.text = _controls_text()


func _on_quit_pressed() -> void:
	close_menu()
	emit_signal("quit_to_title_requested")


func _refresh_status() -> void:
	if _status_label == null:
		return
	var party_mgr: Node = get_node_or_null("/root/PartyManager")
	var party_count := 0
	if party_mgr != null and party_mgr.has_method("get_party_for_display"):
		var party: Array = party_mgr.call("get_party_for_display")
		for slot: Variant in party:
			if typeof(slot) == TYPE_DICTIONARY and not bool((slot as Dictionary).get("empty", true)):
				party_count += 1

	var echoes_label := ""
	var echo_mgr: Node = get_node_or_null("/root/EchoManager")
	if echo_mgr != null and echo_mgr.has_method("get_collected_count"):
		var c := int(echo_mgr.call("get_collected_count"))
		var t := int(echo_mgr.call("get_total_count"))
		echoes_label = "  ·  Echoes %d/%d" % [c, t]

	var objective := ""
	var qm: Node = get_node_or_null("/root/QuestManager")
	if qm != null and qm.has_method("get_tracked_quest_id"):
		var quest_id := String(qm.call("get_tracked_quest_id"))
		if quest_id != "":
			var info: Dictionary = qm.call("get_quest_info", quest_id)
			objective = "\nCurrent: %s — %s" % [String(info.get("title", "")), String(info.get("objective_text", ""))]

	_status_label.text = "Party: %d Buddies%s%s" % [party_count, echoes_label, objective]


func _controls_text() -> String:
	var m_l := InputLabelHelper.action_pretty("move_left")
	var m_r := InputLabelHelper.action_pretty("move_right")
	var m_f := InputLabelHelper.action_pretty("move_forward")
	var m_b := InputLabelHelper.action_pretty("move_back")
	var sp := InputLabelHelper.action_pretty("sprint")
	var jp := InputLabelHelper.action_pretty("jump")
	var it := InputLabelHelper.action_pretty("interact")
	var pr := InputLabelHelper.action_pretty("party_menu")
	var jr := InputLabelHelper.action_pretty("journal")
	var dn := InputLabelHelper.action_pretty("dino_chat")
	var esc := InputLabelHelper.action_pretty("ui_cancel")
	return (
		"Controls\nMove: %s / %s / %s / %s   ·   Sprint: %s   ·   Jump: %s\nMouse: Camera\nInteract: %s   ·   Party: %s   ·   Journal: %s   ·   Dino chat: %s\nF5: Quick Save   ·   Pause: %s\n\n'Be kind to them. They are trying so hard to be real.'"
		% [m_l, m_r, m_f, m_b, sp, jp, it, pr, jr, dn, esc]
	)
