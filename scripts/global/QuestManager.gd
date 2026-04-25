extends Node

signal quest_started(quest_id: String)
signal quest_updated(quest_id: String)
signal quest_completed(quest_id: String)
signal objective_changed(quest_id: String, objective_text: String)

# Quest definitions — data-driven so designers can add more without code changes.
# Each quest: id, title, summary, objectives[] (description + completion rule).
# Completion rules use "event" names that the game emits via `report_event()`.
const QUEST_DATA := {
	"static_aftermath": {
		"title": "Static Aftermath",
		"summary": "The Static Fall tore open the sky above Greenbelt Park. Help people understand what happened.",
		"reward_text": "Bond +10 with Dino Buddy  ·  Echo Journal unlocked",
		"objectives": [
			{
				"id": "find_lily",
				"text": "Talk to Lily near the community center",
				"event": "npc_talked",
				"target": "Lily",
			},
			{
				"id": "find_marcus",
				"text": "Hear Marcus's research on the breach",
				"event": "npc_talked",
				"target": "Marcus",
			},
			{
				"id": "collect_echoes",
				"text": "Collect 3 Echo Shards scattered across the park",
				"event": "echo_collected",
				"target": "any",
				"count": 3,
			},
			{
				"id": "bond_dino",
				"text": "Strengthen your bond with Dino Buddy (Chat with T)",
				"event": "bond_reached",
				"target": "Dino Buddy",
				"threshold": 15,
			},
		],
		"on_complete": {"bond": {"Dino Buddy": 10}, "unlock": "echo_journal"},
		"auto_start": true,
	},
	"wild_friends": {
		"title": "Wild Friends",
		"summary": "Tommy is curious about Buddies. Show him one you've captured.",
		"reward_text": "Bond boost across the party  ·  Neon Sprawl rumor",
		"objectives": [
			{
				"id": "capture_one",
				"text": "Capture any wild Buddy in the park",
				"event": "buddy_captured",
				"target": "any",
			},
			{
				"id": "show_tommy",
				"text": "Return to Tommy and share the news",
				"event": "npc_talked",
				"target": "Tommy",
				"requires_prior": "capture_one",
			},
		],
		"on_complete": {"bond_all": 3, "unlock": "neon_sprawl_rumor"},
		"prereq": "static_aftermath",
	},
	"spring_of_light": {
		"title": "Spring of Light",
		"summary": "Officer Chen mentioned a glowing shrine where buddies feel safe. Find it and rest your team.",
		"reward_text": "Free rest point unlocked",
		"objectives": [
			{
				"id": "find_spring",
				"text": "Locate the Data Spring in Greenbelt Park",
				"event": "spring_discovered",
				"target": "greenbelt_spring",
			},
			{
				"id": "rest_spring",
				"text": "Rest at the Data Spring to restore your party",
				"event": "spring_used",
				"target": "greenbelt_spring",
			},
		],
		"on_complete": {"bond_all": 2, "unlock": "fast_heal"},
		"prereq": "static_aftermath",
	},
}

var _active_quests: Dictionary = {}      # quest_id -> state dict
var _completed_quests: Dictionary = {}   # quest_id -> true
var _unlocks: Dictionary = {}            # unlock_id -> true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func auto_start_available_quests() -> void:
	for quest_id: String in QUEST_DATA.keys():
		var data: Dictionary = QUEST_DATA[quest_id]
		if not bool(data.get("auto_start", false)):
			continue
		if _active_quests.has(quest_id) or _completed_quests.has(quest_id):
			continue
		if not _prereqs_met(quest_id):
			continue
		start_quest(quest_id)


func start_quest(quest_id: String) -> bool:
	if _active_quests.has(quest_id) or _completed_quests.has(quest_id):
		return false
	if not QUEST_DATA.has(quest_id):
		return false
	if not _prereqs_met(quest_id):
		return false

	_active_quests[quest_id] = {
		"objective_index": 0,
		"progress": {},
	}
	emit_signal("quest_started", quest_id)
	emit_signal("objective_changed", quest_id, get_current_objective_text(quest_id))
	return true


func report_event(event_name: String, target: String = "", payload: Dictionary = {}) -> void:
	var quest_ids := _active_quests.keys()
	for quest_id: Variant in quest_ids:
		_progress_quest(String(quest_id), event_name, target, payload)

	# Check prereq-based auto-advance (e.g. wild_friends unlocks when static_aftermath done)
	_check_auto_unlock_chain()


func _progress_quest(quest_id: String, event_name: String, target: String, payload: Dictionary) -> void:
	if not QUEST_DATA.has(quest_id):
		return
	var quest: Dictionary = QUEST_DATA[quest_id]
	var state: Dictionary = _active_quests[quest_id]
	var objectives: Array = quest.get("objectives", [])
	var idx: int = int(state.get("objective_index", 0))
	if idx >= objectives.size():
		return

	var obj: Dictionary = objectives[idx]
	if String(obj.get("event", "")) != event_name:
		return

	var target_value := String(obj.get("target", ""))
	if target_value != "" and target_value != "any" and target_value != target:
		return

	var requires_prior := String(obj.get("requires_prior", ""))
	if requires_prior != "" and not bool(state.get("progress", {}).get(requires_prior, false)):
		return

	var count_target := int(obj.get("count", 1))
	var progress_key := String(obj.get("id", ""))
	var prog: Dictionary = state.get("progress", {})
	if event_name == "bond_reached":
		var threshold := int(obj.get("threshold", 0))
		var value := int(payload.get("value", 0))
		if value < threshold:
			return
		prog[progress_key] = true
		state["progress"] = prog
		_advance_objective(quest_id, state, objectives)
		return

	var current := int(prog.get(progress_key, 0))
	if typeof(prog.get(progress_key, 0)) == TYPE_BOOL:
		current = 1 if bool(prog.get(progress_key, false)) else 0
	current += 1
	if count_target > 1:
		prog[progress_key] = current
	else:
		prog[progress_key] = true
	state["progress"] = prog

	if current >= count_target:
		_advance_objective(quest_id, state, objectives)
	else:
		emit_signal("quest_updated", quest_id)
		emit_signal("objective_changed", quest_id, get_current_objective_text(quest_id))


func _advance_objective(quest_id: String, state: Dictionary, objectives: Array) -> void:
	var idx: int = int(state.get("objective_index", 0))
	idx += 1
	state["objective_index"] = idx
	if idx >= objectives.size():
		_complete_quest(quest_id)
	else:
		emit_signal("quest_updated", quest_id)
		emit_signal("objective_changed", quest_id, get_current_objective_text(quest_id))


func _complete_quest(quest_id: String) -> void:
	if not QUEST_DATA.has(quest_id):
		return
	_active_quests.erase(quest_id)
	_completed_quests[quest_id] = true
	var data: Dictionary = QUEST_DATA[quest_id]
	var rewards: Dictionary = data.get("on_complete", {})
	_apply_rewards(rewards)
	emit_signal("quest_completed", quest_id)


func _apply_rewards(rewards: Dictionary) -> void:
	var bond_mgr: Node = get_node_or_null("/root/BondManager")
	if bond_mgr == null:
		bond_mgr = null

	var bond_gains: Variant = rewards.get("bond", {})
	if typeof(bond_gains) == TYPE_DICTIONARY and bond_mgr != null:
		for buddy_name: Variant in (bond_gains as Dictionary).keys():
			var gain := int((bond_gains as Dictionary)[buddy_name])
			if bond_mgr.has_method("add_bond"):
				bond_mgr.call("add_bond", String(buddy_name), gain, "quest_reward")

	var bond_all_gain: int = int(rewards.get("bond_all", 0))
	if bond_all_gain > 0 and bond_mgr != null and bond_mgr.has_method("add_bond_all"):
		bond_mgr.call("add_bond_all", bond_all_gain, "quest_reward")

	var unlock_id := String(rewards.get("unlock", ""))
	if unlock_id != "":
		_unlocks[unlock_id] = true


func _prereqs_met(quest_id: String) -> bool:
	var data: Dictionary = QUEST_DATA.get(quest_id, {})
	var prereq := String(data.get("prereq", ""))
	if prereq == "":
		return true
	return _completed_quests.has(prereq)


func _check_auto_unlock_chain() -> void:
	for quest_id: String in QUEST_DATA.keys():
		var data: Dictionary = QUEST_DATA[quest_id]
		if bool(data.get("auto_start", false)):
			if not _active_quests.has(quest_id) and not _completed_quests.has(quest_id) and _prereqs_met(quest_id):
				start_quest(quest_id)
		else:
			# Quests that should activate when their prereq is completed, if not explicitly started.
			var prereq := String(data.get("prereq", ""))
			if prereq != "" and _completed_quests.has(prereq):
				if not _active_quests.has(quest_id) and not _completed_quests.has(quest_id):
					start_quest(quest_id)


func get_active_quests() -> Array:
	var result: Array = []
	for quest_id: Variant in _active_quests.keys():
		result.append(String(quest_id))
	return result


func get_completed_quests() -> Array:
	var result: Array = []
	for quest_id: Variant in _completed_quests.keys():
		result.append(String(quest_id))
	return result


func has_unlock(unlock_id: String) -> bool:
	return _unlocks.has(unlock_id)


func get_quest_info(quest_id: String) -> Dictionary:
	if not QUEST_DATA.has(quest_id):
		return {}
	var data: Dictionary = QUEST_DATA[quest_id]
	return {
		"id": quest_id,
		"title": String(data.get("title", "Quest")),
		"summary": String(data.get("summary", "")),
		"reward_text": String(data.get("reward_text", "")),
		"objective_text": get_current_objective_text(quest_id),
		"is_complete": _completed_quests.has(quest_id),
		"is_active": _active_quests.has(quest_id),
	}


func get_current_objective_text(quest_id: String) -> String:
	if _completed_quests.has(quest_id):
		return "Complete."
	if not _active_quests.has(quest_id):
		return ""
	var state: Dictionary = _active_quests[quest_id]
	var idx: int = int(state.get("objective_index", 0))
	var objectives: Array = QUEST_DATA[quest_id].get("objectives", [])
	if idx >= objectives.size():
		return "Complete."
	var obj: Dictionary = objectives[idx]
	var text := String(obj.get("text", ""))
	var count_target := int(obj.get("count", 1))
	if count_target > 1:
		var prog: Dictionary = state.get("progress", {})
		var current := int(prog.get(String(obj.get("id", "")), 0))
		return "%s (%d/%d)" % [text, min(current, count_target), count_target]
	return text


func get_tracked_quest_id() -> String:
	for quest_id: Variant in _active_quests.keys():
		return String(quest_id)
	return ""


func get_save_data() -> Dictionary:
	return {
		"active": _active_quests.duplicate(true),
		"completed": _completed_quests.duplicate(true),
		"unlocks": _unlocks.duplicate(true),
	}


func load_from_save_data(data: Dictionary) -> void:
	_active_quests.clear()
	_completed_quests.clear()
	_unlocks.clear()
	var active: Variant = data.get("active", {})
	if typeof(active) == TYPE_DICTIONARY:
		for k: Variant in (active as Dictionary).keys():
			var state_raw: Variant = (active as Dictionary)[k]
			if typeof(state_raw) == TYPE_DICTIONARY:
				_active_quests[String(k)] = (state_raw as Dictionary).duplicate(true)
	var completed: Variant = data.get("completed", {})
	if typeof(completed) == TYPE_DICTIONARY:
		for k: Variant in (completed as Dictionary).keys():
			_completed_quests[String(k)] = true
	var unlocks: Variant = data.get("unlocks", {})
	if typeof(unlocks) == TYPE_DICTIONARY:
		for k: Variant in (unlocks as Dictionary).keys():
			_unlocks[String(k)] = true


func reset() -> void:
	_active_quests.clear()
	_completed_quests.clear()
	_unlocks.clear()
