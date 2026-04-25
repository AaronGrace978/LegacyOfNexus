extends Node

var _pending_encounter: Dictionary = {}
var _pending_restore: bool = false
var _restore_position: Vector3 = Vector3.ZERO
var _restore_rotation: Vector3 = Vector3.ZERO

var _suppress_anchor: Vector3 = Vector3(INF, INF, INF)
var _suppress_clear_radius: float = 0.0


func start_overworld_battle(
	encounter: Dictionary,
	player: Node3D,
	suppress_anchor: Vector3,
	suppress_clear_distance: float
) -> void:
	_pending_encounter = encounter.duplicate(true) if encounter else {}
	if player != null and is_instance_valid(player):
		_restore_position = player.global_position
		_restore_rotation = player.global_rotation
		_pending_restore = true
	else:
		_pending_restore = false

	_suppress_anchor = suppress_anchor
	_suppress_clear_radius = maxf(suppress_clear_distance, 0.0)


func take_pending_encounter() -> Dictionary:
	var copy: Dictionary = _pending_encounter.duplicate(true)
	_pending_encounter.clear()
	return copy


func apply_overworld_restore_if_needed(player: Node3D) -> void:
	if not _pending_restore:
		return
	if player == null or not is_instance_valid(player):
		return

	player.global_position = _restore_position
	player.global_rotation = _restore_rotation
	_pending_restore = false


func update_auto_encounter_suppression(player_position: Vector3) -> void:
	if _suppress_clear_radius <= 0.0:
		return
	if _suppress_anchor.distance_to(player_position) > _suppress_clear_radius:
		_suppress_clear_radius = 0.0
		_suppress_anchor = Vector3(INF, INF, INF)


func is_auto_encounter_suppressed(player_position: Vector3) -> bool:
	if _suppress_clear_radius <= 0.0:
		return false
	return _suppress_anchor.distance_to(player_position) <= _suppress_clear_radius
