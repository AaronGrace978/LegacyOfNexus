extends Node

const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 1

var _queued_continue := false


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func request_continue() -> bool:
	if not has_save():
		return false
	_queued_continue = true
	return true


func cancel_continue_request() -> void:
	_queued_continue = false


func consume_continue_request() -> bool:
	var consume := _queued_continue
	_queued_continue = false
	return consume


func write_overworld_save(overworld: Node) -> bool:
	if overworld == null or not overworld.has_method("get_save_data"):
		return false

	var data: Dictionary = overworld.call("get_save_data")
	if data.is_empty():
		return false

	data["save_version"] = SAVE_VERSION
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false

	file.store_string(JSON.stringify(data, "\t"))
	return true


func load_save_data() -> Dictionary:
	if not has_save():
		return {}

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}

	return parsed as Dictionary


func get_save_summary() -> Dictionary:
	var data := load_save_data()
	if data.is_empty():
		return {"has_save": false}

	var party_data := _as_dictionary(data.get("party", {}))
	var slots := _as_array(party_data.get("slots", []))
	var party_count := 0
	for slot in slots:
		if typeof(slot) == TYPE_DICTIONARY:
			party_count += 1

	return {
		"has_save": true,
		"location": str(data.get("location", "Greenbelt Park")),
		"party_count": party_count,
		"time_label": _format_world_time(float(data.get("time_of_day", 0.30))),
	}


func apply_overworld_save(overworld: Node) -> bool:
	if overworld == null or not overworld.has_method("apply_save_data"):
		return false

	var data := load_save_data()
	if data.is_empty():
		return false

	if str(data.get("scene", "")) != "overworld":
		return false

	overworld.call("apply_save_data", data)
	return true


func _format_world_time(time_of_day: float) -> String:
	var total_minutes := int(clampf(time_of_day, 0.0, 0.9999) * 1440.0)
	var hours := (total_minutes / 60) % 24
	var minutes := total_minutes % 60
	var period := "AM" if hours < 12 else "PM"
	var display_hour := hours % 12
	if display_hour == 0:
		display_hour = 12
	return "%d:%02d %s" % [display_hour, minutes, period]


func _as_dictionary(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value as Dictionary
	return {}


func _as_array(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value as Array
	return []
