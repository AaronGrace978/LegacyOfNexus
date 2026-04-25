extends CanvasLayer

const EchoShard := preload("res://scripts/world/echo_shard.gd")
const InputLabelHelper := preload("res://scripts/ui/input_label_helper.gd")

var _root: Control
var _tab_buttons: Array[Button] = []
var _content_container: VBoxContainer
var _current_tab := 0
var _detail_label: RichTextLabel
var _previous_mouse_mode := Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	layer = 18
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()


func toggle() -> void:
	if visible:
		close_menu()
	else:
		open_menu()


func open_menu() -> void:
	if visible:
		return
	_previous_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	visible = true
	_select_tab(_current_tab)
	call_deferred("_grab_journal_focus")


func close_menu() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	Input.mouse_mode = _previous_mouse_mode if _previous_mouse_mode != Input.MOUSE_MODE_VISIBLE else Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_right"):
		_select_tab((_current_tab + 1) % _tab_buttons.size())
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_left"):
		_select_tab((_current_tab - 1 + _tab_buttons.size()) % _tab_buttons.size())
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("journal"):
		get_viewport().set_input_as_handled()
		close_menu()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.02, 0.06, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-520.0, -340.0)
	panel.custom_minimum_size = Vector2(1040.0, 680.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.12, 0.97)
	sb.border_color = Color(0.4, 0.65, 0.95, 0.75)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", sb)
	_root.add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	panel.add_child(outer)

	var title := Label.new()
	title.text = "Journal"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.88, 0.95, 1.0, 1.0))
	outer.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "A living record of your time since the Static Fall."
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(0.55, 0.7, 0.9, 0.75))
	outer.add_child(subtitle)

	var tabs_row := HBoxContainer.new()
	tabs_row.add_theme_constant_override("separation", 8)
	outer.add_child(tabs_row)

	var tab_names := ["Quests", "Echoes", "Bonds"]
	for i in range(tab_names.size()):
		var btn := _tab_button(tab_names[i])
		btn.pressed.connect(_select_tab.bind(i))
		tabs_row.add_child(btn)
		_tab_buttons.append(btn)

	var body_row := HBoxContainer.new()
	body_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_row.add_theme_constant_override("separation", 16)
	outer.add_child(body_row)

	var left_panel := PanelContainer.new()
	left_panel.custom_minimum_size = Vector2(440.0, 480.0)
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var left_sb := StyleBoxFlat.new()
	left_sb.bg_color = Color(0.05, 0.08, 0.14, 0.92)
	left_sb.border_color = Color(0.2, 0.35, 0.6, 0.5)
	left_sb.set_border_width_all(1)
	left_sb.set_corner_radius_all(8)
	left_sb.set_content_margin_all(14)
	left_panel.add_theme_stylebox_override("panel", left_sb)
	body_row.add_child(left_panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(scroll)

	_content_container = VBoxContainer.new()
	_content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_container.add_theme_constant_override("separation", 8)
	scroll.add_child(_content_container)

	var right_panel := PanelContainer.new()
	right_panel.custom_minimum_size = Vector2(520.0, 480.0)
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right_sb := StyleBoxFlat.new()
	right_sb.bg_color = Color(0.06, 0.08, 0.14, 0.95)
	right_sb.border_color = Color(0.3, 0.55, 0.88, 0.55)
	right_sb.set_border_width_all(1)
	right_sb.set_corner_radius_all(8)
	right_sb.set_content_margin_all(18)
	right_panel.add_theme_stylebox_override("panel", right_sb)
	body_row.add_child(right_panel)

	_detail_label = RichTextLabel.new()
	_detail_label.bbcode_enabled = true
	_detail_label.fit_content = false
	_detail_label.scroll_active = true
	_detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_label.add_theme_font_size_override("normal_font_size", 16)
	right_panel.add_child(_detail_label)

	var close_row := HBoxContainer.new()
	close_row.alignment = BoxContainer.ALIGNMENT_END
	outer.add_child(close_row)

	var hint := Label.new()
	var esc_txt := InputLabelHelper.action_pretty("ui_cancel")
	var j_txt := InputLabelHelper.action_pretty("journal")
	hint.text = "[%s] / [%s] Close  ·  ← / → tabs" % [esc_txt, j_txt]
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.5, 0.6, 0.75, 0.7))
	close_row.add_child(hint)


func _tab_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(140, 36)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", Color(0.78, 0.86, 0.98, 1.0))

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.07, 0.11, 0.19, 0.85)
	normal.border_color = Color(0.25, 0.4, 0.68, 0.55)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(5)
	normal.set_content_margin_all(6)

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.13, 0.2, 0.35, 0.9)
	hover.border_color = Color(0.45, 0.7, 1.0, 0.9)
	hover.set_border_width_all(2)
	hover.set_corner_radius_all(5)
	hover.set_content_margin_all(6)

	var focus := hover.duplicate() as StyleBoxFlat
	focus.border_color = Color(0.55, 0.85, 1.0, 1.0)
	focus.set_border_width_all(3)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", focus)
	return btn


func _grab_journal_focus() -> void:
	if not visible or _tab_buttons.is_empty():
		return
	var btn: Button = _tab_buttons[_current_tab]
	if btn:
		btn.grab_focus()


func _select_tab(index: int) -> void:
	_current_tab = index
	for i in range(_tab_buttons.size()):
		var is_selected := i == index
		var btn: Button = _tab_buttons[i]
		btn.modulate = Color(1, 1, 1, 1) if is_selected else Color(0.75, 0.78, 0.85, 0.82)
		if is_selected:
			btn.add_theme_color_override("font_color", Color(0.98, 0.96, 0.82, 1.0))
		else:
			btn.add_theme_color_override("font_color", Color(0.78, 0.86, 0.98, 1.0))

	for child in _content_container.get_children():
		child.queue_free()

	if index == 0:
		_populate_quests()
	elif index == 1:
		_populate_echoes()
	else:
		_populate_bonds()


func _populate_quests() -> void:
	var qm: Node = get_node_or_null("/root/QuestManager")
	if qm == null:
		_detail_label.text = "[i]Quest system unavailable.[/i]"
		return
	var active: Array = qm.call("get_active_quests")
	var completed: Array = qm.call("get_completed_quests")

	if active.is_empty() and completed.is_empty():
		_detail_label.text = "[i]No quests yet. Go explore and talk to the people of Greenbelt Park.[/i]"
		return

	if not active.is_empty():
		_content_container.add_child(_section_header("Active"))
	for quest_id: Variant in active:
		var info: Dictionary = qm.call("get_quest_info", String(quest_id))
		_content_container.add_child(_quest_entry(info, false))

	if not completed.is_empty():
		_content_container.add_child(_section_header("Completed"))
	for quest_id: Variant in completed:
		var info: Dictionary = qm.call("get_quest_info", String(quest_id))
		_content_container.add_child(_quest_entry(info, true))

	if not active.is_empty():
		var first_info: Dictionary = qm.call("get_quest_info", String(active[0]))
		_show_quest_detail(first_info, false)
	elif not completed.is_empty():
		var done_info: Dictionary = qm.call("get_quest_info", String(completed[0]))
		_show_quest_detail(done_info, true)


func _quest_entry(info: Dictionary, is_done: bool) -> Button:
	var btn := _list_button()
	btn.text = "%s  —  %s" % [("✓" if is_done else "◆"), String(info.get("title", "Quest"))]
	btn.pressed.connect(_show_quest_detail.bind(info, is_done))
	return btn


func _show_quest_detail(info: Dictionary, is_done: bool) -> void:
	var status := "[color=#8aff9a]Complete[/color]" if is_done else "[color=#ffd97a]Active[/color]"
	var text := "[b][font_size=22]%s[/font_size][/b]  %s\n\n" % [String(info.get("title", "Quest")), status]
	text += "%s\n\n" % String(info.get("summary", ""))
	if not is_done:
		text += "[b]Current objective:[/b]\n%s\n\n" % String(info.get("objective_text", ""))
	var reward := String(info.get("reward_text", ""))
	if reward != "":
		text += "[color=#8cd0ff][i]Reward: %s[/i][/color]" % reward
	_detail_label.text = text


func _populate_echoes() -> void:
	var echo_mgr: Node = get_node_or_null("/root/EchoManager")
	var collected: Dictionary = {}
	if echo_mgr != null and echo_mgr.has_method("get_collected_ids"):
		for id: Variant in echo_mgr.call("get_collected_ids"):
			collected[String(id)] = true

	var all_ids: Array = EchoShard.list_all_echo_ids()
	if all_ids.is_empty():
		_detail_label.text = "[i]No echoes known yet.[/i]"
		return

	_content_container.add_child(_section_header("Echo Fragments  %d/%d" % [collected.size(), all_ids.size()]))

	for echo_id: Variant in all_ids:
		var is_found := collected.has(String(echo_id))
		var btn := _list_button()
		var data: Dictionary = EchoShard.get_echo_data_static(String(echo_id))
		btn.text = "%s  —  %s" % [("✧" if is_found else "·"), (String(data.get("title", "Unknown Echo")) if is_found else "Unknown Echo")]
		btn.pressed.connect(_show_echo_detail.bind(String(echo_id), is_found))
		_content_container.add_child(btn)

	# Default detail
	_detail_label.text = "[i]Select an echo to read its fragment.[/i]"


func _show_echo_detail(echo_id: String, found: bool) -> void:
	if not found:
		_detail_label.text = "[i]Somewhere in this world, a story is waiting. Keep exploring.[/i]"
		return
	var data: Dictionary = EchoShard.get_echo_data_static(echo_id)
	var text := "[b][font_size=20]%s[/font_size][/b]\n[color=#8cd0ff]%s · %s[/color]\n\n" % [
		String(data.get("title", "Echo")),
		String(data.get("location", "Unknown")),
		String(data.get("speaker", "Unknown")),
	]
	text += "[i]“%s”[/i]" % String(data.get("text", ""))
	_detail_label.text = text


func _populate_bonds() -> void:
	var bond_mgr: Node = get_node_or_null("/root/BondManager")
	if bond_mgr == null:
		_detail_label.text = "[i]Bond system unavailable.[/i]"
		return
	var names: Array = bond_mgr.call("get_all_tracked_buddies")
	if names.is_empty():
		_detail_label.text = "[i]No buddies bonded yet.[/i]"
		return

	_content_container.add_child(_section_header("Bonded Buddies"))
	for n: Variant in names:
		var name_str := String(n)
		var btn := _list_button()
		var bond_value := int(bond_mgr.call("get_bond", name_str))
		var label := String(bond_mgr.call("get_bond_label", name_str))
		btn.text = "%s  —  %s  (%d)" % [name_str, label, bond_value]
		btn.pressed.connect(_show_bond_detail.bind(name_str))
		_content_container.add_child(btn)

	_show_bond_detail(String(names[0]))


func _show_bond_detail(buddy_name: String) -> void:
	var bond_mgr: Node = get_node_or_null("/root/BondManager")
	if bond_mgr == null:
		return
	var bond_value := int(bond_mgr.call("get_bond", buddy_name))
	var label := String(bond_mgr.call("get_bond_label", buddy_name))
	var personality := String(bond_mgr.call("get_dominant_personality", buddy_name))

	var bar_count := 20
	var filled := int(round(float(bond_value) / 100.0 * float(bar_count)))
	var bar := ""
	for i in range(bar_count):
		bar += "█" if i < filled else "░"

	var text := "[b][font_size=22]%s[/font_size][/b]\n" % buddy_name
	text += "[color=#8cd0ff]%s[/color]  ·  Personality: %s\n\n" % [label, personality]
	text += "Bond:  [color=#8aff9a]%s[/color]  %d/100\n\n" % [bar, bond_value]
	text += _bond_flavor(buddy_name, bond_value)
	_detail_label.text = text


func _bond_flavor(buddy_name: String, value: int) -> String:
	if buddy_name == "Dino Buddy":
		if value >= 75:
			return "[i]%s moves like your shadow. You don't need words anymore.[/i]" % buddy_name
		if value >= 50:
			return "[i]%s checks on you without asking. They've decided to stay.[/i]" % buddy_name
		if value >= 25:
			return "[i]%s watches you settle in. They flinch less every day.[/i]" % buddy_name
		if value >= 10:
			return "[i]%s is starting to believe you mean it.[/i]" % buddy_name
		return "[i]%s is still figuring out what you are to them.[/i]" % buddy_name
	if value >= 75:
		return "[i]%s trusts you with everything they remember.[/i]" % buddy_name
	if value >= 50:
		return "[i]%s leans in when you call their name.[/i]" % buddy_name
	if value >= 25:
		return "[i]%s is quietly glad to see you.[/i]" % buddy_name
	if value >= 10:
		return "[i]%s is cautious, but curious.[/i]" % buddy_name
	return "[i]%s is still a stranger. Be patient.[/i]" % buddy_name


func _section_header(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.55, 0.75, 0.95, 0.8))
	return lbl


func _list_button() -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(0, 32)
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 0.95))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.06, 0.09, 0.16, 0.0)
	normal.set_content_margin_all(6)

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.12, 0.2, 0.34, 0.7)
	hover.set_corner_radius_all(4)
	hover.set_content_margin_all(6)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	return btn
