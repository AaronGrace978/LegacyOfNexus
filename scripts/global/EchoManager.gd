extends Node

signal echo_collected(echo_id: String)

const EchoShard := preload("res://scripts/world/echo_shard.gd")

var _collected: Dictionary = {}


func mark_collected(echo_id: String) -> void:
	if echo_id.is_empty():
		return
	if _collected.has(echo_id):
		return
	_collected[echo_id] = true
	emit_signal("echo_collected", echo_id)


func is_collected(echo_id: String) -> bool:
	return _collected.has(echo_id)


func get_collected_ids() -> Array:
	var out: Array = []
	for key: Variant in _collected.keys():
		out.append(String(key))
	out.sort()
	return out


func get_total_count() -> int:
	return EchoShard.list_all_echo_ids().size()


func get_collected_count() -> int:
	return _collected.size()


func get_save_data() -> Dictionary:
	return {"collected": _collected.duplicate(true)}


func load_from_save_data(data: Dictionary) -> void:
	_collected.clear()
	var raw: Variant = data.get("collected", {})
	if typeof(raw) == TYPE_DICTIONARY:
		for key: Variant in (raw as Dictionary).keys():
			_collected[String(key)] = true


func reset() -> void:
	_collected.clear()
