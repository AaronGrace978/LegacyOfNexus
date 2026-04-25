extends Node

signal bond_changed(buddy_name: String, bond_value: int, delta: int)
signal personality_shifted(buddy_name: String, personality: String)

# Bond range: 0..100. Thresholds for narrative/mechanical gating.
const BOND_MAX := 100
const BOND_LEVELS := [
	{"threshold": 0, "label": "Neutral"},
	{"threshold": 10, "label": "Warming Up"},
	{"threshold": 25, "label": "Trusting"},
	{"threshold": 50, "label": "Close"},
	{"threshold": 75, "label": "Devoted"},
	{"threshold": 100, "label": "Soul-Bonded"},
]

# Personality axes shift based on how the player talks to them.
# Derived dominant axis is the "personality" label.
const PERSONALITY_AXES := ["brave", "calm", "playful", "wary"]

var _bonds: Dictionary = {}              # buddy_name -> int
var _personality: Dictionary = {}        # buddy_name -> {axis: int}
var _pending_notices: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Dino Buddy is the permanent partner — begin with a small head-start bond.
	if not _bonds.has("Dino Buddy"):
		_bonds["Dino Buddy"] = 5


func get_bond(buddy_name: String) -> int:
	return int(_bonds.get(buddy_name, 0))


func get_bond_label(buddy_name: String) -> String:
	var value := get_bond(buddy_name)
	var label := "Neutral"
	for entry: Variant in BOND_LEVELS:
		var threshold := int((entry as Dictionary).get("threshold", 0))
		if value >= threshold:
			label = String((entry as Dictionary).get("label", "Neutral"))
	return label


func add_bond(buddy_name: String, delta: int, _reason: String = "") -> int:
	if buddy_name.is_empty():
		return 0
	var before := int(_bonds.get(buddy_name, 0))
	var after: int = clampi(before + delta, 0, BOND_MAX)
	_bonds[buddy_name] = after
	emit_signal("bond_changed", buddy_name, after, after - before)

	# Notify quest manager so quests keyed to bond thresholds advance.
	var qm: Node = get_node_or_null("/root/QuestManager")
	if qm != null and qm.has_method("report_event"):
		qm.call("report_event", "bond_reached", buddy_name, {"value": after})

	if after >= BOND_MAX and before < BOND_MAX:
		_queue_notice("%s feels soul-bonded with you." % buddy_name)

	return after


func add_bond_all(delta: int, reason: String = "") -> void:
	var party_manager: Node = get_node_or_null("/root/PartyManager")
	if party_manager == null or not party_manager.has_method("get_party_for_display"):
		add_bond("Dino Buddy", delta, reason)
		return
	var party: Array = party_manager.call("get_party_for_display")
	for slot: Variant in party:
		if typeof(slot) != TYPE_DICTIONARY:
			continue
		if bool((slot as Dictionary).get("empty", true)):
			continue
		add_bond(String((slot as Dictionary).get("name", "")), delta, reason)


func adjust_personality(buddy_name: String, axis: String, delta: int) -> void:
	if buddy_name.is_empty() or not PERSONALITY_AXES.has(axis):
		return
	var axes: Dictionary = _personality.get(buddy_name, {})
	axes[axis] = int(axes.get(axis, 0)) + delta
	_personality[buddy_name] = axes
	emit_signal("personality_shifted", buddy_name, get_dominant_personality(buddy_name))


func get_dominant_personality(buddy_name: String) -> String:
	var axes: Dictionary = _personality.get(buddy_name, {})
	if axes.is_empty():
		return "Neutral"
	var best_axis := "Neutral"
	var best_value := -9999
	for axis: Variant in axes.keys():
		var value := int(axes[axis])
		if value > best_value:
			best_value = value
			best_axis = String(axis).capitalize()
	if best_value <= 0:
		return "Neutral"
	return best_axis


func get_all_tracked_buddies() -> Array:
	var names: Dictionary = {}
	for key: Variant in _bonds.keys():
		names[String(key)] = true
	for key: Variant in _personality.keys():
		names[String(key)] = true
	# Also reflect current party so buddies show up even at 0 bond.
	var party_manager: Node = get_node_or_null("/root/PartyManager")
	if party_manager != null and party_manager.has_method("get_party_for_display"):
		var party: Array = party_manager.call("get_party_for_display")
		for slot: Variant in party:
			if typeof(slot) != TYPE_DICTIONARY:
				continue
			if bool((slot as Dictionary).get("empty", true)):
				continue
			names[String((slot as Dictionary).get("name", ""))] = true
	var out: Array = []
	for key: Variant in names.keys():
		out.append(String(key))
	out.sort()
	return out


func consume_notices() -> Array[Dictionary]:
	var out := _pending_notices.duplicate()
	_pending_notices.clear()
	return out


func _queue_notice(text: String) -> void:
	_pending_notices.append({"text": text, "duration": 2.8})


func get_save_data() -> Dictionary:
	return {
		"bonds": _bonds.duplicate(true),
		"personality": _personality.duplicate(true),
	}


func load_from_save_data(data: Dictionary) -> void:
	_bonds.clear()
	_personality.clear()
	var bonds: Variant = data.get("bonds", {})
	if typeof(bonds) == TYPE_DICTIONARY:
		for k: Variant in (bonds as Dictionary).keys():
			_bonds[String(k)] = int((bonds as Dictionary)[k])
	var pers: Variant = data.get("personality", {})
	if typeof(pers) == TYPE_DICTIONARY:
		for k: Variant in (pers as Dictionary).keys():
			var axes_raw: Variant = (pers as Dictionary)[k]
			if typeof(axes_raw) == TYPE_DICTIONARY:
				var axes: Dictionary = {}
				for a: Variant in (axes_raw as Dictionary).keys():
					axes[String(a)] = int((axes_raw as Dictionary)[a])
				_personality[String(k)] = axes
	if not _bonds.has("Dino Buddy"):
		_bonds["Dino Buddy"] = 5


func reset() -> void:
	_bonds.clear()
	_personality.clear()
	_bonds["Dino Buddy"] = 5
