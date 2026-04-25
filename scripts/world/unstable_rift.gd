extends Node3D

@export var trigger_radius := 3.0
@export var enemy_front_name := "Red Rogue"
@export var enemy_front_level := 2
@export var enemy_rear_name := "Red Shade"
@export var enemy_rear_level := 2
@export var include_rear_enemy := true
@export var suppress_hysteresis := 1.25

var _mesh: MeshInstance3D
var _omni: OmniLight3D
var _pulse: float


func _ready() -> void:
	_mesh = get_node_or_null("MeshInstance3D") as MeshInstance3D
	_omni = OmniLight3D.new()
	_omni.light_color = Color(0.62, 0.38, 1.0, 1.0)
	_omni.light_energy = 3.2
	_omni.omni_range = 10.0
	_omni.shadow_enabled = false
	add_child(_omni)


func _process(delta: float) -> void:
	_pulse += delta * 2.35
	var breathe := 1.0 + sin(_pulse) * 0.07
	if _mesh:
		_mesh.scale = Vector3(breathe, breathe, breathe)
	if _omni:
		_omni.light_energy = 2.85 + sin(_pulse * 1.07) * 0.75


func build_encounter() -> Dictionary:
	var enemies: Array = [
		{"name": enemy_front_name, "level": enemy_front_level},
	]
	if include_rear_enemy and str(enemy_rear_name).strip_edges() != "":
		enemies.append({"name": enemy_rear_name, "level": enemy_rear_level})
	return {"enemies": enemies}


func get_suppress_clear_distance() -> float:
	return trigger_radius + suppress_hysteresis
