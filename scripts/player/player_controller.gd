extends CharacterBody3D

@export var walk_speed := 6.0
@export var sprint_speed := 9.5
@export var acceleration := 14.0
@export var deceleration := 16.0
@export var rotation_speed := 10.0
@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.0035
@export var min_pitch := -55.0
@export var max_pitch := 20.0

@onready var visual_root: Node3D = $VisualRoot
@onready var camera_rig: Node3D = $CameraRig
@onready var camera_yaw: Node3D = $CameraRig/YawPivot
@onready var camera_pitch: Node3D = $CameraRig/YawPivot/PitchPivot
@onready var _camera: Camera3D = $CameraRig/YawPivot/PitchPivot/SpringArm3D/Camera3D

@export var base_fov := 70.0
@export var sprint_fov := 78.0
@export var fov_lerp_speed := 5.0
@export var head_bob_walk := 0.02
@export var head_bob_sprint := 0.034
@export var land_dip := 0.14
@export var coyote_time := 0.12
@export var jump_buffer_time := 0.12

var gravity := ProjectSettings.get_setting("physics/3d/default_gravity") as float
var facing_direction := Vector3.FORWARD
var last_move_direction := Vector3.ZERO
var controls_enabled := true
var _foot_particles: GPUParticles3D
var _bob_phase := 0.0
var _land_kick := 0.0
var _was_on_floor := true
var _coyote_time_left := 0.0
var _jump_buffer_left := 0.0
const CAMERA_RIG_BASE := Vector3(0.0, 1.55, 0.0)


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_create_foot_particles()


func _create_foot_particles() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.3, 0.02, 0.3)
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 50.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.1
	pm.gravity = Vector3(0.0, -3.5, 0.0)
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	pm.color = Color(0.32, 0.48, 0.22, 0.55)

	var sphere := SphereMesh.new()
	sphere.radius = 0.018
	sphere.height = 0.036
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.45, 0.2, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sphere.material = mat

	_foot_particles = GPUParticles3D.new()
	_foot_particles.amount = 14
	_foot_particles.lifetime = 0.7
	_foot_particles.emitting = false
	_foot_particles.process_material = pm
	_foot_particles.draw_pass_1 = sphere
	_foot_particles.material_override = mat
	_foot_particles.position = Vector3(0.0, 0.05, 0.0)
	_foot_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_foot_particles)


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_yaw.rotation.y -= event.relative.x * mouse_sensitivity
		camera_pitch.rotation.x -= event.relative.y * mouse_sensitivity
		camera_pitch.rotation.x = clamp(
			camera_pitch.rotation.x,
			deg_to_rad(min_pitch),
			deg_to_rad(max_pitch)
		)

	# ui_cancel is reserved for the pause menu (handled elsewhere).


func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()
	if on_floor:
		_coyote_time_left = coyote_time
	else:
		_coyote_time_left = maxf(0.0, _coyote_time_left - delta)

	if not on_floor:
		velocity.y -= gravity * delta

	if controls_enabled and Input.is_action_just_pressed("jump"):
		_jump_buffer_left = jump_buffer_time
	else:
		_jump_buffer_left = maxf(0.0, _jump_buffer_left - delta)

	if controls_enabled and _jump_buffer_left > 0.0 and (on_floor or _coyote_time_left > 0.0):
		velocity.y = jump_velocity
		_jump_buffer_left = 0.0
		_coyote_time_left = 0.0

	var input_vector: Vector2 = Vector2.ZERO
	if controls_enabled:
		input_vector = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var camera_basis: Basis = camera_yaw.global_basis
	var move_direction: Vector3 = (camera_basis.x * input_vector.x) + (camera_basis.z * input_vector.y)
	move_direction.y = 0.0
	move_direction = move_direction.normalized()

	var target_speed: float = sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var target_velocity: Vector3 = move_direction * target_speed
	var horizontal_velocity: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	var blend: float = min((acceleration if move_direction != Vector3.ZERO else deceleration) * delta, 1.0)
	horizontal_velocity = horizontal_velocity.lerp(target_velocity, blend)

	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z

	if move_direction.length_squared() > 0.01:
		last_move_direction = move_direction
		facing_direction = move_direction
		var facing_target: float = atan2(move_direction.x, move_direction.z)
		visual_root.rotation.y = rotate_toward(visual_root.rotation.y, facing_target, rotation_speed * delta)

	move_and_slide()

	var on_floor_now := is_on_floor()
	if on_floor_now and not _was_on_floor and velocity.y <= 0.35:
		_land_kick = land_dip
	_was_on_floor = on_floor_now

	if _foot_particles:
		_foot_particles.emitting = on_floor_now and get_horizontal_speed() > 1.5

	_update_camera_feel(delta, on_floor_now)


func _update_camera_feel(delta: float, on_floor: bool) -> void:
	if _camera == null or camera_rig == null:
		return

	var sprinting := is_sprinting()
	var target_fov: float = sprint_fov if sprinting else base_fov
	_camera.fov = lerpf(_camera.fov, target_fov, clampf(fov_lerp_speed * delta, 0.0, 1.0))

	var h_speed := get_horizontal_speed()
	var moving := controls_enabled and on_floor and h_speed > 0.45
	if moving:
		var bob_rate: float = TAU * (2.35 if sprinting else 1.65)
		_bob_phase += delta * bob_rate * clampf(h_speed / walk_speed, 0.35, 1.35)
	else:
		_bob_phase = lerpf(_bob_phase, 0.0, 6.0 * delta)

	var bob_amp: float = (head_bob_sprint if sprinting else head_bob_walk) * (1.0 if moving else 0.0)
	var bob_y: float = sin(_bob_phase) * bob_amp
	_land_kick = move_toward(_land_kick, 0.0, delta * 3.8)
	camera_rig.position = CAMERA_RIG_BASE + Vector3(0.0, bob_y - _land_kick, 0.0)


func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	if not enabled:
		velocity.x = 0.0
		velocity.z = 0.0


func get_companion_target_position() -> Vector3:
	var forward: Vector3 = get_facing_direction()
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	var offset: Vector3 = (-forward * 4.3) + (right * 1.85)
	return global_position + offset


func get_facing_direction() -> Vector3:
	if last_move_direction.length_squared() > 0.001:
		return last_move_direction.normalized()

	if visual_root == null:
		return Vector3.FORWARD

	var visual_forward: Vector3 = -visual_root.global_basis.z
	visual_forward.y = 0.0
	if visual_forward.length_squared() > 0.001:
		return visual_forward.normalized()

	return Vector3.FORWARD


func get_interest_target() -> Vector3:
	return global_position + get_facing_direction() * 6.0 + Vector3.UP * 1.25


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func is_sprinting() -> bool:
	return controls_enabled and Input.is_action_pressed("sprint") and get_horizontal_speed() > walk_speed + 0.25


func get_save_state() -> Dictionary:
	return {
		"position": _vector3_to_array(global_position),
		"camera_yaw": camera_yaw.rotation.y if camera_yaw != null else 0.0,
		"camera_pitch": camera_pitch.rotation.x if camera_pitch != null else 0.0,
		"visual_yaw": visual_root.rotation.y if visual_root != null else 0.0,
		"facing_direction": _vector3_to_array(get_facing_direction()),
	}


func apply_save_state(state: Dictionary) -> void:
	global_position = _vector3_from_variant(state.get("position", []), global_position)
	velocity = Vector3.ZERO

	if camera_yaw != null:
		camera_yaw.rotation.y = float(state.get("camera_yaw", camera_yaw.rotation.y))
	if camera_pitch != null:
		camera_pitch.rotation.x = clampf(
			float(state.get("camera_pitch", camera_pitch.rotation.x)),
			deg_to_rad(min_pitch),
			deg_to_rad(max_pitch)
		)
	if visual_root != null:
		visual_root.rotation.y = float(state.get("visual_yaw", visual_root.rotation.y))

	facing_direction = _vector3_from_variant(state.get("facing_direction", []), facing_direction)
	if facing_direction.length_squared() <= 0.001:
		facing_direction = Vector3.FORWARD
	last_move_direction = facing_direction


func _vector3_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _vector3_from_variant(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array:
		var raw := value as Array
		if raw.size() >= 3:
			return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return fallback
