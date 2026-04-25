extends Node

## Appends sensible joypad events when an action only has keyboard/mouse bindings
## (keeps existing project.godot mappings intact).


func _ready() -> void:
	_ensure_joypad_events()


func _ensure_joypad_events() -> void:
	_add_axis_threshold("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_axis_threshold("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_axis_threshold("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_add_axis_threshold("move_back", JOY_AXIS_LEFT_Y, 1.0)

	_add_joy_button_if_missing("jump", JOY_BUTTON_A)
	_add_joy_button_if_missing("interact", JOY_BUTTON_X)
	_add_joy_button_if_missing("sprint", JOY_BUTTON_LEFT_SHOULDER)
	_add_joy_button_if_missing("party_menu", JOY_BUTTON_Y)
	_add_joy_button_if_missing("journal", JOY_BUTTON_RIGHT_SHOULDER)
	_add_joy_button_if_missing("dino_chat", JOY_BUTTON_BACK)


func _action_has_joy_like_event(action_name: String) -> bool:
	for ev: InputEvent in InputMap.action_get_events(action_name):
		if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
			return true
	return false


func _add_joy_button_if_missing(action_name: String, button: JoyButton) -> void:
	if not InputMap.has_action(action_name):
		return
	if _action_has_joy_like_event(action_name):
		return
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action_name, ev)


func _add_axis_threshold(action_name: String, axis: JoyAxis, axis_value: float) -> void:
	if not InputMap.has_action(action_name):
		return
	if _action_has_joy_like_event(action_name):
		return
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = axis_value
	InputMap.action_add_event(action_name, ev)
