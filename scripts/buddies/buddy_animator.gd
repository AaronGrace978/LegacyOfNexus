extends Node3D

# Universal idle animation for buddy visuals:
#  - gentle breathing scale on anything named "Body" / "Core" / "ImportedDino"
#  - bob + sway on the whole visual root
#  - tail wag on "TailPivot"
#  - wing flap on "WingPivotL" / "WingPivotR"
#  - ring spin on "Ring"
#  - floating hover for non-grounded buddies (set `hover = true`)
#  - subtle yaw drift so they never feel frozen

@export var hover := false
@export var bob_amplitude := 0.05
@export var bob_speed := 1.6
@export var breath_amplitude := 0.03
@export var breath_speed := 1.4
@export var sway_amplitude := 0.04
@export var yaw_drift_amplitude := 0.08
@export var tail_wag_amplitude := 0.22
@export var tail_wag_speed := 2.2
@export var wing_flap_amplitude := 0.55
@export var wing_flap_speed := 3.8
@export var ring_spin_speed := 0.9
@export var random_phase := true

var _phase_bob := 0.0
var _phase_breath := 0.0
var _phase_sway := 0.0
var _phase_yaw := 0.0
var _phase_tail := 0.0
var _phase_wing := 0.0
var _root_base_y := 0.0
var _root_base_yaw := 0.0
var _body_base_scale := Vector3.ONE
var _tail: Node3D
var _wing_l: Node3D
var _wing_r: Node3D
var _ring: Node3D
var _body: Node3D
var _captured := false


func _ready() -> void:
	_capture_state()
	_fix_vertex_color_materials(self)
	if random_phase:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		_phase_bob = rng.randf() * TAU
		_phase_breath = rng.randf() * TAU
		_phase_sway = rng.randf() * TAU
		_phase_yaw = rng.randf() * TAU
		_phase_tail = rng.randf() * TAU
		_phase_wing = rng.randf() * TAU


func _fix_vertex_color_materials(node: Node) -> void:
	# Any mesh authored with per-vertex colors (COLOR_0 attribute) is expected
	# to render those colors as albedo. Godot's glTF importer does not always
	# set `vertex_color_use_as_albedo` on the generated StandardMaterial3D, so
	# we walk the tree once and force the flag on any matching surface. Safe
	# for buddies without vertex colors (loop simply finds no matches).
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		var mesh := mesh_node.mesh
		if mesh is ArrayMesh:
			var array_mesh := mesh as ArrayMesh
			for surface_index in range(array_mesh.get_surface_count()):
				var fmt := array_mesh.surface_get_format(surface_index)
				if (fmt & Mesh.ARRAY_FORMAT_COLOR) == 0:
					continue
				var existing := mesh_node.get_active_material(surface_index)
				var standard := existing as StandardMaterial3D
				if standard != null:
					var fixed := standard.duplicate() as StandardMaterial3D
					fixed.vertex_color_use_as_albedo = true
					fixed.vertex_color_is_srgb = false
					fixed.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
					mesh_node.set_surface_override_material(surface_index, fixed)
				else:
					var fallback := StandardMaterial3D.new()
					fallback.vertex_color_use_as_albedo = true
					fallback.vertex_color_is_srgb = false
					fallback.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
					fallback.roughness = 0.6
					fallback.metallic = 0.03
					mesh_node.set_surface_override_material(surface_index, fallback)
	for child in node.get_children():
		_fix_vertex_color_materials(child)


func _capture_state() -> void:
	if _captured:
		return
	_captured = true
	_root_base_y = position.y
	_root_base_yaw = rotation.y

	_tail = _find_first_named(["TailPivot", "Tail"])
	_wing_l = _find_first_named(["WingPivotL"])
	_wing_r = _find_first_named(["WingPivotR"])
	_ring = _find_first_named(["Ring"])
	_body = _find_first_named(["Body", "Core", "ImportedDino"])
	if _body != null and _body is Node3D:
		_body_base_scale = (_body as Node3D).scale


func _process(delta: float) -> void:
	_phase_bob += delta * bob_speed
	_phase_breath += delta * breath_speed
	_phase_sway += delta * (bob_speed * 0.55)
	_phase_yaw += delta * 0.4
	_phase_tail += delta * tail_wag_speed
	_phase_wing += delta * wing_flap_speed

	var bob := sin(_phase_bob) * bob_amplitude
	if hover:
		bob += bob_amplitude * 0.55
	position.y = _root_base_y + bob

	var sway := sin(_phase_sway) * sway_amplitude
	rotation.z = sway
	rotation.y = _root_base_yaw + sin(_phase_yaw) * yaw_drift_amplitude

	if _body != null and _body is Node3D:
		var breath := 1.0 + sin(_phase_breath) * breath_amplitude
		(_body as Node3D).scale = Vector3(
			_body_base_scale.x * breath,
			_body_base_scale.y * (1.0 + sin(_phase_breath + 0.4) * breath_amplitude * 0.6),
			_body_base_scale.z * breath,
		)

	if _tail != null and _tail is Node3D:
		var wag := sin(_phase_tail) * tail_wag_amplitude
		(_tail as Node3D).rotation.y = wag

	if _wing_l != null and _wing_l is Node3D:
		(_wing_l as Node3D).rotation.z = sin(_phase_wing) * wing_flap_amplitude
	if _wing_r != null and _wing_r is Node3D:
		(_wing_r as Node3D).rotation.z = -sin(_phase_wing) * wing_flap_amplitude

	if _ring != null and _ring is Node3D:
		(_ring as Node3D).rotation.y += delta * ring_spin_speed


func _find_first_named(candidates: Array) -> Node:
	for name in candidates:
		var n := find_child(String(name), true, false)
		if n != null:
			return n
	return null
