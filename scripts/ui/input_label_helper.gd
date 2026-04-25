extends Object


static func action_pretty(action_name: String) -> String:
	if not InputMap.has_action(action_name):
		return action_name
	var events := InputMap.action_get_events(action_name)
	if events.is_empty():
		return action_name
	var ev: InputEvent = events[0]
	return ev.as_text()
