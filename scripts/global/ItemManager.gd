extends Node

const DEFINITIONS_PATH := "res://data/items/item_definitions.json"

## item_id -> count
var _counts: Dictionary = {}
var _definitions: Array = []


func _ready() -> void:
	_load_definitions()
	if _counts.is_empty():
		_apply_default_inventory()


func reset() -> void:
	_counts.clear()
	_apply_default_inventory()


func _apply_default_inventory() -> void:
	_counts["repair_gel"] = 2
	_counts["team_salve"] = 1
	_counts["reboot_chip"] = 1


func _load_definitions() -> void:
	_definitions.clear()
	if not FileAccess.file_exists(DEFINITIONS_PATH):
		push_warning("ItemManager: missing definitions at %s" % DEFINITIONS_PATH)
		return
	var f := FileAccess.open(DEFINITIONS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var root: Dictionary = parsed
	var arr: Variant = root.get("items", [])
	if arr is Array:
		_definitions = arr


func get_item_definition(item_id: String) -> Dictionary:
	for entry: Variant in _definitions:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = entry
		if str(d.get("id", "")) == item_id:
			return d
	return {}


func get_item_count(item_id: String) -> int:
	return int(_counts.get(item_id, 0))


func add_item(item_id: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	var def := get_item_definition(item_id)
	if def.is_empty():
		return
	_counts[item_id] = get_item_count(item_id) + amount


func consume_item(item_id: String, amount: int = 1) -> bool:
	if get_item_count(item_id) < amount:
		return false
	_counts[item_id] = get_item_count(item_id) - amount
	if get_item_count(item_id) <= 0:
		_counts.erase(item_id)
	return true


func get_save_data() -> Dictionary:
	return {"counts": _counts.duplicate(true)}


func load_from_save_data(data: Dictionary) -> void:
	var counts: Variant = data.get("counts", {})
	if counts is Dictionary:
		_counts = (counts as Dictionary).duplicate(true)
	else:
		_counts.clear()
	if _counts.is_empty():
		_apply_default_inventory()


## Returns rows for battle item picker: id, label, count, enabled
func get_battle_item_rows(
	acting_unit: Node,
	ally_support: Node,
	active_second_party_index: int
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for entry: Variant in _definitions:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var def: Dictionary = entry
		var id: String = str(def.get("id", ""))
		if id.is_empty():
			continue
		var cnt := get_item_count(id)
		if cnt <= 0:
			continue
		var kind: String = str(def.get("kind", ""))
		var enabled := _is_item_usable_in_battle(
			kind,
			def,
			acting_unit,
			ally_support,
			active_second_party_index
		)
		rows.append({
			"id": id,
			"label": str(def.get("label", id)),
			"count": cnt,
			"enabled": enabled,
		})
	return rows


func _is_item_usable_in_battle(
	kind: String,
	def: Dictionary,
	acting_unit: Node,
	ally_support: Node,
	active_second_party_index: int
) -> bool:
	match kind:
		"heal_self":
			if acting_unit == null or not acting_unit.has_method("is_defeated"):
				return false
			if acting_unit.call("is_defeated"):
				return false
			if acting_unit.has_method("get_health_ratio"):
				return float(acting_unit.call("get_health_ratio")) < 0.999
			return true
		"heal_all_allies":
			var any_hurt := false
			for u: Node in [acting_unit, ally_support]:
				if u == null or not u.has_method("is_defeated"):
					continue
				if bool(u.call("is_defeated")):
					continue
				if u.has_method("get_health_ratio") and float(u.call("get_health_ratio")) < 0.999:
					any_hurt = true
					break
			return any_hurt
		"revive_partner":
			if active_second_party_index <= 0:
				return false
			if ally_support == null:
				return false
			if not ally_support.has_method("is_defeated"):
				return false
			return bool(ally_support.call("is_defeated"))
		_:
			return false
