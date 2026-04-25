class_name BattleActionUI
extends CanvasLayer

signal action_selected(action_name: String)
signal swap_selected(party_index: int)
signal swap_cancelled
signal item_selected(item_id: String)
signal item_picker_cancelled

@onready var hud_panel: PanelContainer = $BattleHud/Panel
@onready var turn_label: Label = $BattleHud/Panel/VBox/TurnLabel
@onready var status_label: Label = $BattleHud/Panel/VBox/StatusLabel
@onready var move_buttons_parent: GridContainer = $BattleHud/Panel/VBox/MoveButtons
@onready var item_button: Button = $BattleHud/Panel/VBox/UtilityRow/ItemButton
@onready var swap_button: Button = $BattleHud/Panel/VBox/UtilityRow/SwapButton
@onready var run_button: Button = $BattleHud/Panel/VBox/UtilityRow/RunButton
@onready var swap_panel: PanelContainer = $BattleHud/SwapPanel
@onready var swap_prompt_label: Label = $BattleHud/SwapPanel/SwapVBox/SwapPrompt
@onready var swap_buttons_container: VBoxContainer = $BattleHud/SwapPanel/SwapVBox/SwapButtons
@onready var swap_cancel_button: Button = $BattleHud/SwapPanel/SwapVBox/CancelButton

var _move_buttons: Array[Button] = []
var _utility_buttons: Array[Button] = []
var _item_picker_active := false


func _ready() -> void:
	_utility_buttons = [item_button, swap_button, run_button]
	_apply_theme()
	item_button.pressed.connect(_emit_action.bind("item"))
	swap_button.pressed.connect(_emit_action.bind("swap"))
	run_button.pressed.connect(_emit_action.bind("run"))
	swap_cancel_button.pressed.connect(_on_swap_cancelled)
	set_status("Battle start.")
	set_turn_indicator("Awaiting turn.")
	hide_swap_options()
	clear_move_buttons()


func set_status(text: String) -> void:
	status_label.text = text


func set_turn_indicator(text: String) -> void:
	turn_label.text = text


func clear_move_buttons() -> void:
	for child: Node in move_buttons_parent.get_children():
		move_buttons_parent.remove_child(child)
		child.queue_free()
	_move_buttons.clear()


func set_move_options(move_entries: Array) -> void:
	clear_move_buttons()
	for entry: Variant in move_entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var dict: Dictionary = entry
		var move_id: String = str(dict.get("id", ""))
		var label_text: String = str(dict.get("label", move_id))
		var enabled: bool = bool(dict.get("enabled", true))

		var button := Button.new()
		button.text = label_text
		button.set_meta("base_disabled", not enabled)
		button.disabled = not enabled
		button.custom_minimum_size = Vector2(168, 48)
		_style_action_button(button, "move")
		button.pressed.connect(_emit_action.bind("move:%s" % move_id))
		move_buttons_parent.add_child(button)
		_move_buttons.append(button)


func set_actions_enabled(enabled: bool, can_swap: bool = true) -> void:
	for button: Button in _move_buttons:
		var base_disabled: bool = bool(button.get_meta("base_disabled", false))
		button.disabled = (not enabled) or base_disabled

	for button: Button in _utility_buttons:
		button.disabled = not enabled

	swap_button.disabled = (not enabled) or (not can_swap)

	if enabled:
		_focus_first_enabled_move()


func _focus_first_enabled_move() -> void:
	for button: Button in _move_buttons:
		if not button.disabled:
			button.grab_focus()
			return
	if not item_button.disabled:
		item_button.grab_focus()


func show_swap_options(prompt: String, options: Array[Dictionary], allow_cancel: bool = true) -> void:
	hide_swap_options()
	_item_picker_active = false
	swap_prompt_label.text = prompt
	swap_panel.visible = true
	swap_cancel_button.visible = allow_cancel

	for option: Dictionary in options:
		var button := Button.new()
		button.text = option.get("label", "Party Buddy")
		button.disabled = not option.get("enabled", true)
		button.custom_minimum_size = Vector2(260, 44)
		button.pressed.connect(_emit_swap_selected.bind(option.get("party_index", -1)))
		swap_buttons_container.add_child(button)

	if swap_buttons_container.get_child_count() > 0:
		var first_button := swap_buttons_container.get_child(0) as Button
		if first_button and not first_button.disabled:
			first_button.grab_focus()


func show_item_picker(prompt: String, options: Array[Dictionary]) -> void:
	hide_swap_options()
	_item_picker_active = true
	swap_prompt_label.text = prompt
	swap_panel.visible = true
	swap_cancel_button.visible = true

	for option: Variant in options:
		if typeof(option) != TYPE_DICTIONARY:
			continue
		var dict: Dictionary = option
		var item_id: String = str(dict.get("id", ""))
		if item_id.is_empty():
			continue
		var label_text: String = str(dict.get("label", item_id))
		var count: int = int(dict.get("count", 1))
		var enabled: bool = bool(dict.get("enabled", true))

		var button := Button.new()
		button.text = "%s  ×%d" % [label_text, count]
		button.disabled = not enabled
		button.custom_minimum_size = Vector2(280, 44)
		_style_action_button(button, "utility")
		button.pressed.connect(_emit_item_chosen.bind(item_id))
		swap_buttons_container.add_child(button)

	if swap_buttons_container.get_child_count() > 0:
		var first_button := swap_buttons_container.get_child(0) as Button
		if first_button and not first_button.disabled:
			first_button.grab_focus()


func hide_swap_options() -> void:
	swap_panel.visible = false
	for child: Node in swap_buttons_container.get_children():
		swap_buttons_container.remove_child(child)
		child.queue_free()
	_item_picker_active = false
	# Caller may inspect was_item via separate cancel path; flag is cleared above.


func _emit_action(action_name: String) -> void:
	emit_signal("action_selected", action_name)


func _emit_swap_selected(party_index: int) -> void:
	emit_signal("swap_selected", party_index)


func _emit_item_chosen(item_id: String) -> void:
	hide_swap_options()
	emit_signal("item_selected", item_id)


func _on_swap_cancelled() -> void:
	var was_item_picker := _item_picker_active
	hide_swap_options()
	if was_item_picker:
		emit_signal("item_picker_cancelled")
	else:
		emit_signal("swap_cancelled")


func _apply_theme() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.04, 0.06, 0.08, 0.88)
	panel_style.border_color = Color(0.36, 0.62, 0.54, 0.48)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(18)
	panel_style.set_content_margin_all(16)
	hud_panel.add_theme_stylebox_override("panel", panel_style)

	var swap_style := StyleBoxFlat.new()
	swap_style.bg_color = Color(0.05, 0.07, 0.09, 0.94)
	swap_style.border_color = Color(0.48, 0.68, 0.86, 0.34)
	swap_style.set_border_width_all(1)
	swap_style.set_corner_radius_all(18)
	swap_style.set_content_margin_all(16)
	swap_panel.add_theme_stylebox_override("panel", swap_style)

	turn_label.add_theme_font_size_override("font_size", 26)
	turn_label.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 1.0))
	status_label.add_theme_font_size_override("font_size", 18)
	status_label.add_theme_color_override("font_color", Color(0.80, 0.88, 0.92, 0.98))
	swap_prompt_label.add_theme_font_size_override("font_size", 18)
	swap_prompt_label.add_theme_color_override("font_color", Color(0.90, 0.95, 1.0, 1.0))

	_style_action_button(item_button, "utility")
	_style_action_button(swap_button, "utility")
	_style_action_button(run_button, "danger")
	_style_action_button(swap_cancel_button, "utility")


func _style_action_button(button: Button, kind: String) -> void:
	if button == null:
		return

	var bg := Color(0.12, 0.20, 0.18, 0.96)
	var hover := Color(0.16, 0.28, 0.24, 0.98)
	var border := Color(0.32, 0.58, 0.48, 0.45)

	match kind:
		"move":
			bg = Color(0.10, 0.18, 0.16, 0.96)
			hover = Color(0.14, 0.25, 0.22, 0.98)
			border = Color(0.32, 0.58, 0.48, 0.45)
		"danger":
			bg = Color(0.22, 0.12, 0.12, 0.96)
			hover = Color(0.30, 0.16, 0.16, 0.98)
			border = Color(0.74, 0.38, 0.38, 0.48)
		_:
			bg = Color(0.12, 0.16, 0.18, 0.96)
			hover = Color(0.18, 0.22, 0.25, 0.98)
			border = Color(0.46, 0.60, 0.68, 0.40)

	var normal_style := _button_style(bg, border)
	var hover_style := _button_style(hover, border.lightened(0.12))
	var pressed_style := _button_style(bg.darkened(0.10), border)
	var disabled_style := _button_style(Color(bg.r, bg.g, bg.b, 0.42), Color(border.r, border.g, border.b, 0.16))

	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.add_theme_stylebox_override("disabled", disabled_style)
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", Color(0.93, 0.97, 1.0, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	button.add_theme_color_override("font_disabled_color", Color(0.52, 0.58, 0.62, 0.82))


func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(10)
	return style
