extends Node3D

const OVERWORLD_IDLE_ANIMS: Array[StringName] = [&"Idle", &"CharacterArmature|Idle"]
const OVERWORLD_WALK_ANIMS: Array[StringName] = [&"Walk", &"CharacterArmature|Walk", &"Run", &"CharacterArmature|Run"]
const OVERWORLD_HAPPY_ANIMS: Array[StringName] = [&"HappyChirp", &"CharacterArmature|Yes", &"CharacterArmature|Wave", &"Yes", &"Wave"]
const QUATERNIUS_OVERWORLD_SCALE := Vector3(0.42, 0.42, 0.42)
const SCULPT_OVERWORLD_SCALE := Vector3(0.42, 0.42, 0.42)
const SPEECH_BUBBLE_LINE_LENGTH := 24
const SPEECH_BUBBLE_BASE_HEIGHT := 2.7
## 2× internal resolution so the billboard sprite stays sharp on high-DPI / Forward+.
const SPEECH_BUBBLE_UI_SCALE := 2.0
const SPEECH_BUBBLE_VIEWPORT_SIZE := Vector2i(768, 416)
const SPEECH_BUBBLE_MIN_WIDTH := 360.0
const SPEECH_BUBBLE_MAX_WIDTH := 608.0

@export var min_follow_distance := 3.5
@export var max_follow_distance := 5.8
@export var follow_speed := 6.7
@export var catchup_speed := 10.8
@export var sprint_follow_multiplier := 1.28
@export var target_lag_speed := 4.2
@export var follow_acceleration := 7.5
@export var follow_deceleration := 10.5
@export var arrival_slow_radius := 2.35
@export var arrival_stop_radius := 0.12
@export var turn_speed := 8.0
@export var player_spacing_radius := 2.2
@export var player_spacing_resolve_speed := 8.5
@export var near_player_sound_distance := 2.25
@export var near_player_sound_cooldown := 2.0
@export var idle_glance_min := 2.0
@export var idle_glance_max := 4.5
@export var idle_glance_duration_min := 0.7
@export var idle_glance_duration_max := 1.4
@export var happy_idle_min := 2.6
@export var happy_idle_max := 5.4
@export var happy_tilt_duration := 0.7
@export var happy_hop_duration := 0.58
@export var happy_hop_height := 0.16
@export var walk_anim_speed_threshold := 0.42
@export var follow_sway_amplitude := 1.65
@export var follow_sway_speed := 0.55
@export var roam_after_still_seconds := 1.2
@export var roam_radius_min := 4.0
@export var roam_radius_max := 12.0
@export var roam_time_limit := 14.0
@export var roam_max_distance_from_player := 22.0
@export var roam_cooldown_seconds := 2.0
@export var player_anticipation_distance := 1.5
@export var follow_side_offset_min := 1.2
@export var follow_side_offset_max := 2.1

# Autonomy — Dino has his own life in his world.
@export var poi_chance := 0.75
@export var poi_lingering_min := 2.6
@export var poi_lingering_max := 6.5
@export var poi_refresh_interval := 4.0
@export var poi_arrival_radius := 1.4
@export var poi_visit_random_chance := 0.55
@export var poi_max_search_radius := 45.0
# Dino rubber-bands back when the player leaves him too far out.
@export var leash_radius := 28.0
@export var sprint_return_boost := 1.6
# Even when following, Dino nudges toward interesting things nearby.
@export var curiosity_chance_per_second := 0.35
@export var curiosity_sniff_duration := 2.2

@onready var model_root: Node3D = $ModelRoot

var player: Node3D
var rng := RandomNumberGenerator.new()
var look_target := Vector3.ZERO
var glance_cooldown := 0.0
var glance_time_left := 0.0

var _idle_phase := 0.0
var _last_position := Vector3.ZERO
var _follow_anchor := Vector3.ZERO
var _tail_pivot: Node3D
var _head_parts: Array[Node3D] = []
var _head_part_base_rotations: Array[Vector3] = []
var _happy_idle_cooldown := 0.0
var _happy_mode := ""
var _happy_timer := 0.0
var _happy_duration := 0.0
var _happy_head_sign := 1.0
var _happy_hop_offset := 0.0
var _near_player_sound_time_left := 0.0
var _was_close_to_player := false
var _sway_phase := 0.0
var _player_still_timer := 0.0
var _roam_active := false
var _roam_goal := Vector3.ZERO
var _roam_timer := 0.0
var _roam_cooldown := 0.0
var _last_travel_speed := 0.0
var _move_velocity := Vector3.ZERO

var _anim_player: AnimationPlayer
var _overworld_locomotion_clip := ""
var _happy_chirp_anim_active := false
var _happy_chirp_anim_name: StringName = &""

var _poi_refresh_timer := 0.0
var _poi_linger_timer := 0.0
var _current_poi: Vector3 = Vector3.ZERO
var _has_current_poi := false
var _curiosity_timer := 0.0
var _sniffing := false
var _sniff_time_left := 0.0
var _speech_bubble_root: Node3D
var _speech_bubble_sprite: Sprite3D
var _speech_bubble_viewport: SubViewport
var _speech_bubble_panel: PanelContainer
var _speech_bubble_tail: ColorRect
var _speech_bubble_label: Label
var _speech_bubble_time_left := 0.0


func _ready() -> void:
	top_level = true
	player = get_parent() as Node3D
	rng.randomize()
	global_position = _get_desired_follow_position()
	_follow_anchor = global_position
	_last_position = global_position
	look_target = global_position + Vector3.FORWARD
	_reset_glance_cooldown()
	_reset_happy_idle_cooldown()
	if model_root:
		_apply_visual_presentation()
		_cache_animation_nodes()
		_anim_player = _find_first_animation_player(model_root)
		var on_anim_finished := Callable(self, "_on_overworld_anim_finished")
		if _anim_player != null and not _anim_player.is_connected(&"animation_finished", on_anim_finished):
			_anim_player.animation_finished.connect(on_anim_finished)
		_refresh_overworld_locomotion_anim(0.0)
		_apply_palette(
			model_root,
			Color(0.309804, 0.878431, 0.509804, 1.0),
			Color(0.686275, 1.0, 0.772549, 1.0)
		)
	_build_speech_bubble()


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return

	_roam_cooldown = maxf(_roam_cooldown - delta, 0.0)
	if _sniff_time_left > 0.0:
		_sniff_time_left = maxf(_sniff_time_left - delta, 0.0)
		if _sniff_time_left <= 0.0:
			_sniffing = false
	var player_move_speed := _get_player_horizontal_speed()
	_update_roam_state(delta, player_move_speed)

	var desired_position: Vector3
	if _roam_active:
		desired_position = _roam_goal
	else:
		desired_position = _get_desired_follow_position_with_sway(delta)

	_follow_anchor = _follow_anchor.lerp(desired_position, min(target_lag_speed * delta, 1.0))

	var target_position := Vector3(_follow_anchor.x, global_position.y, _follow_anchor.z)
	var to_anchor := target_position - global_position
	to_anchor.y = 0.0
	var distance_to_anchor := to_anchor.length()
	var move_speed := catchup_speed if distance_to_anchor > max_follow_distance else follow_speed
	var player_is_sprinting := _is_player_sprinting()
	if player_is_sprinting:
		move_speed *= sprint_follow_multiplier

	var desired_velocity := Vector3.ZERO
	if distance_to_anchor > arrival_stop_radius:
		var arrival_scale := 1.0
		if distance_to_anchor < arrival_slow_radius:
			arrival_scale = clampf(distance_to_anchor / maxf(arrival_slow_radius, 0.001), 0.18, 1.0)
		desired_velocity = to_anchor.normalized() * move_speed * arrival_scale

	var accel := follow_acceleration if desired_velocity.length() >= _move_velocity.length() else follow_deceleration
	_move_velocity = _move_velocity.lerp(desired_velocity, min(accel * delta, 1.0))
	global_position += _move_velocity * delta

	_enforce_player_spacing(delta)

	var horizontal_speed: float = _get_horizontal_travel_speed(delta)
	_last_travel_speed = horizontal_speed
	_update_near_player_feedback(delta)
	_update_look_behavior(delta)
	_apply_look_rotation(delta)
	_update_happy_idle(delta, player_move_speed, horizontal_speed)
	_refresh_overworld_locomotion_anim(horizontal_speed)
	_update_idle_motion(delta, horizontal_speed, player_is_sprinting)
	_update_speech_bubble(delta)


func get_activity_blurb() -> String:
	if _sniffing:
		return "sniffing around something interesting"
	if _roam_active and _has_current_poi:
		return "wandering off to check on something in the park"
	if _roam_active:
		return "exploring the park on my own"
	if _happy_chirp_anim_active:
		return "doing a happy chirp or little gesture"
	if _get_player_horizontal_speed() > walk_anim_speed_threshold + 0.35:
		return "trotting to keep up with you"
	if _last_travel_speed > walk_anim_speed_threshold:
		return "walking alongside you"
	return "idling close by, watching the park with you"


func show_speech_bubble(text: String, duration := 4.0) -> void:
	if _speech_bubble_root == null or _speech_bubble_label == null or _speech_bubble_panel == null:
		return

	var cleaned := text.strip_edges()
	if cleaned.is_empty():
		return

	var wrapped := _wrap_speech_bubble_text(cleaned, SPEECH_BUBBLE_LINE_LENGTH)
	var lines := wrapped.split("\n")
	var longest := 0
	for line in lines:
		longest = maxi(longest, line.length())

	_speech_bubble_label.text = wrapped
	_speech_bubble_root.visible = true
	_speech_bubble_time_left = maxf(duration, 1.5)

	var sc := SPEECH_BUBBLE_UI_SCALE
	var bubble_width := clampf((128.0 + float(longest) * 6.4) * sc, SPEECH_BUBBLE_MIN_WIDTH, SPEECH_BUBBLE_MAX_WIDTH)
	var bubble_height := (58.0 + float(lines.size() - 1) * 28.0) * sc
	var panel_position := Vector2(
		(float(SPEECH_BUBBLE_VIEWPORT_SIZE.x) - bubble_width) * 0.5,
		16.0 * sc
	)
	_speech_bubble_panel.position = panel_position
	_speech_bubble_panel.size = Vector2(bubble_width, bubble_height)
	_speech_bubble_label.position = Vector2(0.0, 0.0)
	_speech_bubble_label.custom_minimum_size = Vector2(bubble_width - 28.0 * sc, bubble_height - 22.0 * sc)
	_speech_bubble_tail.position = Vector2(
		panel_position.x + bubble_width * 0.5 - 10.0 * sc,
		panel_position.y + bubble_height - 4.0 * sc
	)
	_speech_bubble_root.position = Vector3(0.0, SPEECH_BUBBLE_BASE_HEIGHT, 0.0)


func _update_roam_state(delta: float, player_speed: float) -> void:
	_poi_refresh_timer = maxf(_poi_refresh_timer - delta, 0.0)

	if _roam_active:
		_roam_timer -= delta
		var flat_self := Vector2(global_position.x, global_position.z)
		var flat_goal := Vector2(_roam_goal.x, _roam_goal.z)
		var flat_player := Vector2(player.global_position.x, player.global_position.z)
		var arrival_radius := poi_arrival_radius if _has_current_poi else 0.75
		var reached := flat_self.distance_to(flat_goal) < arrival_radius
		var too_far := flat_self.distance_to(flat_player) > leash_radius
		var timed_out := _roam_timer <= 0.0
		var player_needs_me := player_speed > 1.6 and flat_self.distance_to(flat_player) > max_follow_distance * 1.4

		if reached and _has_current_poi and _poi_linger_timer <= 0.0:
			_poi_linger_timer = rng.randf_range(poi_lingering_min, poi_lingering_max)
			_start_sniff()
			return

		if _poi_linger_timer > 0.0:
			_poi_linger_timer = maxf(_poi_linger_timer - delta, 0.0)
			# Remain idle/sniffing around the POI until lingering is done.
			if _poi_linger_timer <= 0.0:
				_roam_active = false
				_has_current_poi = false
				_roam_cooldown = roam_cooldown_seconds * 0.5
				_player_still_timer = 0.0
			return

		if reached or too_far or timed_out or player_needs_me:
			_roam_active = false
			_has_current_poi = false
			_roam_cooldown = roam_cooldown_seconds
			_player_still_timer = 0.0
		return

	# Not actively roaming. Quick rule: if the player isn't rushing, Dino lives his own life.
	if player_speed > 1.5:
		# Player is moving with purpose — stay close.
		_player_still_timer = 0.0
		return

	_player_still_timer += delta
	if _player_still_timer < roam_after_still_seconds or _roam_cooldown > 0.0:
		return

	_player_still_timer = 0.0
	_start_roam_goal()


func _start_roam_goal() -> void:
	_roam_active = true
	_roam_timer = roam_time_limit
	_poi_linger_timer = 0.0
	_sniffing = false
	_has_current_poi = false

	# Prefer a real POI most of the time; otherwise pick a scenic random spot.
	if rng.randf() < poi_chance:
		var poi := _choose_random_poi()
		if poi != Vector3.INF:
			_current_poi = poi
			_has_current_poi = true
			_roam_goal = poi
			return

	# Fallback: random wander spot biased by the player's direction.
	var player_forward := _get_player_motion_direction()
	if player_forward.length_squared() <= 0.001:
		player_forward = Vector3.FORWARD
	var player_right := player_forward.cross(Vector3.UP).normalized()
	var dist := rng.randf_range(roam_radius_min, roam_radius_max)
	var forward_bias := rng.randf_range(-0.8, 0.9)
	var side_bias := -1.0 if rng.randf() < 0.5 else 1.0
	var offset := (player_forward * dist * forward_bias) + (player_right * dist * side_bias)
	_roam_goal = player.global_position + offset


func _choose_random_poi() -> Vector3:
	var candidates: Array[Vector3] = []
	var tree := get_tree()
	if tree == null:
		return Vector3.INF

	var my_flat := Vector2(global_position.x, global_position.z)
	var player_flat := Vector2(player.global_position.x, player.global_position.z)

	var collect = func(group: String, nudge_radius: float) -> void:
		for node in tree.get_nodes_in_group(group):
			if not (node is Node3D):
				continue
			var np := (node as Node3D).global_position
			var flat := Vector2(np.x, np.z)
			if flat.distance_to(player_flat) > poi_max_search_radius:
				continue
			if flat.distance_to(my_flat) < 0.8:
				continue
			# Offset slightly so Dino doesn't stand on top of the POI.
			var away := (Vector2(np.x, np.z) - player_flat).normalized()
			if away.length_squared() < 0.01:
				away = Vector2(1, 0)
			var tangent := Vector2(-away.y, away.x) * rng.randf_range(-nudge_radius, nudge_radius)
			candidates.append(Vector3(np.x + tangent.x, global_position.y, np.z + tangent.y))

	collect.call("dino_poi_tree", 0.9)
	collect.call("dino_poi_home", 1.6)
	collect.call("dino_poi_pond", 2.2)
	collect.call("park_npc", 1.8)

	if candidates.is_empty():
		return Vector3.INF
	return candidates[rng.randi() % candidates.size()]


func _start_sniff() -> void:
	_sniffing = true
	_sniff_time_left = curiosity_sniff_duration
	_move_velocity = Vector3.ZERO
	# Tilt head down as if investigating something.
	look_target = global_position + Vector3(
		rng.randf_range(-0.6, 0.6),
		0.05,
		rng.randf_range(-0.6, 0.6)
	)
	glance_time_left = curiosity_sniff_duration


func _get_desired_follow_position_with_sway(delta: float) -> Vector3:
	_sway_phase += delta * follow_sway_speed * TAU
	var base := _get_desired_follow_position()
	if player == null:
		return base

	var facing := _get_player_motion_direction()
	facing.y = 0.0
	if facing.length_squared() < 0.001:
		return base
	facing = facing.normalized()
	var right := facing.cross(Vector3.UP).normalized()
	var player_speed := _get_player_horizontal_speed()
	var sway_strength := clampf(player_speed / maxf(walk_anim_speed_threshold + 3.2, 0.1), 0.12, 1.0)
	var sway := right * sin(_sway_phase) * follow_sway_amplitude * sway_strength
	return base + sway


func _get_desired_follow_position() -> Vector3:
	var player_position := player.global_position
	var forward := _get_player_motion_direction()
	if forward.length_squared() <= 0.001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var player_speed := _get_player_horizontal_speed()
	var speed_ratio := clampf(player_speed / maxf(follow_speed, 0.1), 0.0, 1.0)

	var current_offset := global_position - player_position
	current_offset.y = 0.0
	var side_sign := 1.0
	if right.length_squared() > 0.001 and current_offset.length_squared() > 0.01:
		side_sign = signf(current_offset.dot(right))
		if absf(side_sign) < 0.001:
			side_sign = 1.0

	var trail_distance := lerpf(min_follow_distance + 0.2, max_follow_distance - 0.35, speed_ratio * 0.7)
	var side_distance := lerpf(follow_side_offset_min, follow_side_offset_max, speed_ratio)
	var anticipation := _get_player_planar_velocity().normalized() * minf(player_anticipation_distance, player_speed * 0.22)
	if player_speed < 0.2:
		anticipation = Vector3.ZERO

	var desired_position := player_position - (forward * trail_distance) + (right * side_sign * side_distance) + anticipation
	if player != null and player.has_method("get_companion_target_position"):
		var authored_target: Vector3 = player.call("get_companion_target_position")
		desired_position = authored_target.lerp(desired_position, 0.55)

	var offset := desired_position - player_position
	offset.y = 0.0
	var offset_length := offset.length()
	if offset_length > 0.001:
		offset = offset.normalized() * clamp(offset_length, min_follow_distance, max_follow_distance)

	return player_position + offset


func _update_look_behavior(delta: float) -> void:
	glance_cooldown -= delta

	if glance_time_left > 0.0:
		glance_time_left -= delta
		if glance_time_left <= 0.0:
			_reset_glance_cooldown()
	else:
		if glance_cooldown <= 0.0:
			look_target = player.global_position + Vector3(
				rng.randf_range(-6.0, 6.0),
				rng.randf_range(0.8, 2.5),
				rng.randf_range(-6.0, 6.0)
			)
			glance_time_left = rng.randf_range(idle_glance_duration_min, idle_glance_duration_max)
		elif player.has_method("get_interest_target"):
			look_target = player.call("get_interest_target")
		else:
			look_target = player.global_position + Vector3.UP


func _apply_look_rotation(delta: float) -> void:
	var target_yaw: float
	if glance_time_left > 0.0:
		var flat_target := look_target
		flat_target.y = global_position.y
		var to_look := flat_target - global_position
		to_look.y = 0.0
		if to_look.length_squared() <= 0.001:
			return
		target_yaw = atan2(to_look.x, to_look.z)
	else:
		var move_vector := _move_velocity
		move_vector.y = 0.0
		if move_vector.length_squared() > 0.12:
			target_yaw = atan2(move_vector.x, move_vector.z)
		else:
			var trainer_visual: Node3D = null
			if player != null and player.has_node("VisualRoot"):
				trainer_visual = player.get_node("VisualRoot") as Node3D
			if trainer_visual != null:
				target_yaw = trainer_visual.global_rotation.y
			elif player != null and player.has_method("get_facing_direction"):
				var facing_vector := player.call("get_facing_direction") as Vector3
				if facing_vector.length_squared() <= 0.001:
					return
				target_yaw = atan2(facing_vector.x, facing_vector.z)
			else:
				return

	rotation.y = rotate_toward(rotation.y, target_yaw, turn_speed * delta)


func _update_idle_motion(delta: float, horizontal_speed: float, player_is_sprinting: bool) -> void:
	if model_root == null:
		return

	if _anim_player != null:
		return

	var phase_speed := 0.45 + (0.18 if player_is_sprinting else 0.0)
	_idle_phase += delta * TAU * phase_speed
	model_root.position.y = sin(_idle_phase) * 0.045 + _happy_hop_offset

	if _tail_pivot != null:
		var tail_pulse_speed := 2.1 + (1.4 if player_is_sprinting else 0.0)
		var tail_amplitude := 0.22 + (0.14 if player_is_sprinting else 0.0)
		var wag := sin(_idle_phase * tail_pulse_speed) * tail_amplitude
		var excitement: float = clampf(horizontal_speed * 0.048, 0.0, 0.65)
		if player_is_sprinting:
			excitement += 0.2
		wag += excitement * sin(_idle_phase * (8.2 if player_is_sprinting else 6.0))
		_tail_pivot.rotation.z = wag


func _update_speech_bubble(delta: float) -> void:
	if _speech_bubble_root == null or not _speech_bubble_root.visible:
		return
	_speech_bubble_time_left = maxf(_speech_bubble_time_left - delta, 0.0)
	if _speech_bubble_time_left <= 0.0:
		_speech_bubble_root.visible = false
		return
	_speech_bubble_root.position.y = SPEECH_BUBBLE_BASE_HEIGHT + sin(Time.get_ticks_msec() * 0.0025) * 0.035


func _update_happy_idle(delta: float, player_speed: float, horizontal_speed: float) -> void:
	if _happy_chirp_anim_active:
		return

	var settled := player_speed < 0.2 and horizontal_speed < 0.6 and global_position.distance_to(_follow_anchor) < 0.7
	if not settled:
		_finish_happy_idle()
		_reset_happy_idle_cooldown()
		return

	if _happy_mode.is_empty():
		_happy_idle_cooldown -= delta
		if _happy_idle_cooldown <= 0.0:
			_start_happy_idle()
		return

	_happy_timer += delta
	var progress: float = clampf(_happy_timer / maxf(_happy_duration, 0.001), 0.0, 1.0)
	match _happy_mode:
		"tilt":
			_set_head_tilt(sin(progress * PI) * 0.24 * _happy_head_sign)
		"hop":
			_happy_hop_offset = sin(progress * PI) * happy_hop_height
			_set_head_tilt(sin(progress * PI) * 0.1 * _happy_head_sign)

	if progress >= 1.0:
		_finish_happy_idle()
		_reset_happy_idle_cooldown()


func _start_happy_idle() -> void:
	_happy_timer = 0.0
	var happy_anim := _resolve_anim_name(OVERWORLD_HAPPY_ANIMS)
	if _anim_player != null and not happy_anim.is_empty():
		_happy_chirp_anim_active = true
		_happy_chirp_anim_name = happy_anim
		_overworld_locomotion_clip = ""
		_anim_player.play(happy_anim, 0.08)
		return

	_happy_head_sign = -1.0 if rng.randf() < 0.5 else 1.0
	if rng.randf() < 0.55:
		_happy_mode = "tilt"
		_happy_duration = happy_tilt_duration
	else:
		_happy_mode = "hop"
		_happy_duration = happy_hop_duration


func _finish_happy_idle() -> void:
	_happy_chirp_anim_active = false
	_happy_chirp_anim_name = &""
	_happy_mode = ""
	_happy_timer = 0.0
	_happy_duration = 0.0
	_happy_hop_offset = 0.0
	_set_head_tilt(0.0)


func _set_head_tilt(angle: float) -> void:
	for index in range(_head_parts.size()):
		var head_part := _head_parts[index]
		if head_part == null:
			continue
		head_part.rotation = _head_part_base_rotations[index] + Vector3(0.0, 0.0, angle)


func _enforce_player_spacing(delta: float) -> void:
	var away_from_player := global_position - player.global_position
	away_from_player.y = 0.0
	var separation := away_from_player.length()
	if separation >= player_spacing_radius:
		return

	if separation <= 0.001:
		if player.has_method("get_facing_direction"):
			away_from_player = -(player.call("get_facing_direction") as Vector3)
		else:
			away_from_player = Vector3.BACK
		away_from_player.y = 0.0

	var safe_offset := away_from_player.normalized() * player_spacing_radius
	var safe_position := Vector3(
		player.global_position.x + safe_offset.x,
		global_position.y,
		player.global_position.z + safe_offset.z
	)
	var push_strength := clampf((player_spacing_radius - separation) / maxf(player_spacing_radius, 0.001), 0.18, 1.0)
	global_position = global_position.lerp(safe_position, min(player_spacing_resolve_speed * push_strength * delta, 1.0))
	_move_velocity += away_from_player.normalized() * push_strength * 1.8


func _update_near_player_feedback(delta: float) -> void:
	_near_player_sound_time_left = max(_near_player_sound_time_left - delta, 0.0)
	var close_to_player := global_position.distance_to(player.global_position) <= near_player_sound_distance
	if close_to_player and (not _was_close_to_player or _near_player_sound_time_left <= 0.0):
		_near_player_sound_time_left = near_player_sound_cooldown
	_was_close_to_player = close_to_player


func _get_horizontal_travel_speed(delta: float) -> float:
	var delta_position := global_position - _last_position
	delta_position.y = 0.0
	var speed: float = delta_position.length() / maxf(delta, 0.0001)
	_last_position = global_position
	return speed


func _get_player_horizontal_speed() -> float:
	if player != null and player.has_method("get_horizontal_speed"):
		return float(player.call("get_horizontal_speed"))

	if player is CharacterBody3D:
		var player_body := player as CharacterBody3D
		return Vector2(player_body.velocity.x, player_body.velocity.z).length()

	return 0.0


func _is_player_sprinting() -> bool:
	return player != null and player.has_method("is_sprinting") and bool(player.call("is_sprinting"))


func _get_player_planar_velocity() -> Vector3:
	if player != null and player is CharacterBody3D:
		var body := player as CharacterBody3D
		var planar := Vector3(body.velocity.x, 0.0, body.velocity.z)
		if planar.length_squared() > 0.001:
			return planar
	if player != null and player.has_method("get_facing_direction"):
		return player.call("get_facing_direction") as Vector3
	return Vector3.ZERO


func _get_player_motion_direction() -> Vector3:
	var planar_velocity := _get_player_planar_velocity()
	if planar_velocity.length_squared() > 0.04:
		return planar_velocity.normalized()
	if player != null and player.has_method("get_facing_direction"):
		var facing := player.call("get_facing_direction") as Vector3
		facing.y = 0.0
		if facing.length_squared() > 0.001:
			return facing.normalized()
	return Vector3.FORWARD


func _reset_glance_cooldown() -> void:
	glance_cooldown = rng.randf_range(idle_glance_min, idle_glance_max)


func _reset_happy_idle_cooldown() -> void:
	_happy_idle_cooldown = rng.randf_range(happy_idle_min, happy_idle_max)


func _build_speech_bubble() -> void:
	_speech_bubble_root = Node3D.new()
	_speech_bubble_root.name = "SpeechBubble"
	_speech_bubble_root.position = Vector3(0.0, SPEECH_BUBBLE_BASE_HEIGHT, 0.0)
	_speech_bubble_root.visible = false
	add_child(_speech_bubble_root)

	_speech_bubble_viewport = SubViewport.new()
	_speech_bubble_viewport.disable_3d = true
	_speech_bubble_viewport.transparent_bg = true
	_speech_bubble_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_speech_bubble_viewport.size = SPEECH_BUBBLE_VIEWPORT_SIZE
	_speech_bubble_viewport.msaa_2d = Viewport.MSAA_2X
	_speech_bubble_root.add_child(_speech_bubble_viewport)

	var canvas := Control.new()
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speech_bubble_viewport.add_child(canvas)

	_speech_bubble_panel = PanelContainer.new()
	_speech_bubble_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.97, 0.995, 0.99, 0.98)
	panel_style.border_color = Color(0.28, 0.78, 0.62, 0.92)
	panel_style.set_border_width_all(int(round(2.0 * SPEECH_BUBBLE_UI_SCALE)))
	panel_style.set_corner_radius_all(int(round(22.0 * SPEECH_BUBBLE_UI_SCALE)))
	panel_style.shadow_color = Color(0.02, 0.06, 0.12, 0.28)
	panel_style.shadow_size = int(round(12.0 * SPEECH_BUBBLE_UI_SCALE))
	panel_style.shadow_offset = Vector2(0, int(round(3.0 * SPEECH_BUBBLE_UI_SCALE)))
	panel_style.set_content_margin_all(0)
	_speech_bubble_panel.add_theme_stylebox_override("panel", panel_style)
	canvas.add_child(_speech_bubble_panel)

	var margin := MarginContainer.new()
	var m := int(round(14.0 * SPEECH_BUBBLE_UI_SCALE))
	var mt := int(round(11.0 * SPEECH_BUBBLE_UI_SCALE))
	margin.add_theme_constant_override("margin_left", m)
	margin.add_theme_constant_override("margin_top", mt)
	margin.add_theme_constant_override("margin_right", m)
	margin.add_theme_constant_override("margin_bottom", mt)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speech_bubble_panel.add_child(margin)

	_speech_bubble_label = Label.new()
	_speech_bubble_label.text = ""
	_speech_bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_speech_bubble_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speech_bubble_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_speech_bubble_label.add_theme_font_size_override("font_size", int(round(24.0 * SPEECH_BUBBLE_UI_SCALE)))
	_speech_bubble_label.add_theme_color_override("font_color", Color(0.06, 0.14, 0.11, 1.0))
	_speech_bubble_label.add_theme_color_override("font_shadow_color", Color(0.02, 0.08, 0.06, 0.22))
	_speech_bubble_label.add_theme_constant_override("shadow_offset_x", int(round(1.0 * SPEECH_BUBBLE_UI_SCALE)))
	_speech_bubble_label.add_theme_constant_override("shadow_offset_y", int(round(2.0 * SPEECH_BUBBLE_UI_SCALE)))
	_speech_bubble_label.add_theme_constant_override("outline_size", int(round(3.0 * SPEECH_BUBBLE_UI_SCALE)))
	_speech_bubble_label.add_theme_color_override("font_outline_color", Color(0.88, 0.98, 0.94, 0.55))
	_speech_bubble_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_speech_bubble_label)

	_speech_bubble_tail = ColorRect.new()
	_speech_bubble_tail.color = Color(0.94, 0.99, 0.97, 0.98)
	var tail_sz := 20.0 * SPEECH_BUBBLE_UI_SCALE
	_speech_bubble_tail.size = Vector2(tail_sz, tail_sz)
	_speech_bubble_tail.rotation_degrees = 45.0
	_speech_bubble_tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_speech_bubble_tail)

	_speech_bubble_sprite = Sprite3D.new()
	_speech_bubble_sprite.texture = _speech_bubble_viewport.get_texture()
	_speech_bubble_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_speech_bubble_sprite.pixel_size = 0.0051 / SPEECH_BUBBLE_UI_SCALE
	_speech_bubble_sprite.centered = true
	_speech_bubble_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_speech_bubble_sprite.modulate = Color.WHITE
	_speech_bubble_root.add_child(_speech_bubble_sprite)


func _wrap_speech_bubble_text(text: String, line_limit: int) -> String:
	var words := text.split(" ")
	if words.is_empty():
		return text

	var lines: PackedStringArray = []
	var current := ""
	for word in words:
		var candidate := word if current.is_empty() else "%s %s" % [current, word]
		if candidate.length() > line_limit and not current.is_empty():
			lines.append(current)
			current = word
		else:
			current = candidate
	if not current.is_empty():
		lines.append(current)

	return "\n".join(lines)


func _cache_animation_nodes() -> void:
	_tail_pivot = model_root.find_child("TailPivot", true, false) as Node3D

	for part_name in ["Head", "Snout", "HornL", "HornR"]:
		var part := model_root.find_child(part_name, true, false) as Node3D
		if part == null:
			continue
		_head_parts.append(part)
		_head_part_base_rotations.append(part.rotation)


func _find_first_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_first_animation_player(child)
		if found != null:
			return found
	return null


func _refresh_overworld_locomotion_anim(horizontal_speed: float) -> void:
	if _anim_player == null or _happy_chirp_anim_active:
		return
	var want_list := OVERWORLD_WALK_ANIMS if horizontal_speed > walk_anim_speed_threshold else OVERWORLD_IDLE_ANIMS
	var want := _resolve_anim_name(want_list)
	if want.is_empty():
		return
	if _overworld_locomotion_clip == String(want) and _anim_player.is_playing():
		return
	_anim_player.play(want, 0.12)
	_overworld_locomotion_clip = String(want)


func _on_overworld_anim_finished(anim_name: StringName) -> void:
	if anim_name != _happy_chirp_anim_name:
		return
	_happy_chirp_anim_active = false
	_happy_chirp_anim_name = &""
	_overworld_locomotion_clip = ""
	_reset_happy_idle_cooldown()


func _resolve_anim_name(candidates: Array[StringName]) -> StringName:
	if _anim_player == null:
		return &""
	for candidate in candidates:
		if _anim_player.has_animation(candidate):
			return candidate
	return &""


func _apply_visual_presentation() -> void:
	if _is_quaternius_dino_model(model_root):
		model_root.scale = QUATERNIUS_OVERWORLD_SCALE
		model_root.position = Vector3(0.0, -0.02, 0.0)
	elif _is_sculpt_dino_model(model_root):
		model_root.scale = SCULPT_OVERWORLD_SCALE
		model_root.position = Vector3.ZERO


func _apply_palette(root: Node, primary: Color, accent: Color) -> void:
	for child in root.get_children():
		_apply_palette(child, primary, accent)

	if root is MeshInstance3D:
		var mesh_node := root as MeshInstance3D
		if mesh_node.mesh == null:
			return
		if mesh_node.is_in_group("buddy_palette_primary"):
			var mat := StandardMaterial3D.new()
			mat.albedo_color = primary
			mat.roughness = 0.55
			mat.metallic = 0.06
			mesh_node.set_surface_override_material(0, mat)
		elif mesh_node.is_in_group("buddy_palette_accent"):
			var mat_a := StandardMaterial3D.new()
			mat_a.albedo_color = accent
			mat_a.roughness = 0.45
			mat_a.metallic = 0.05
			mat_a.emission_enabled = true
			mat_a.emission = accent * 0.35
			mat_a.emission_energy_multiplier = 0.45
			mesh_node.set_surface_override_material(0, mat_a)
		else:
			_apply_imported_palette(mesh_node, primary, accent)


func _is_quaternius_dino_model(root: Node) -> bool:
	return root != null and root.find_child("CharacterArmature", true, false) != null and root.find_child("Dino", true, false) != null


func _is_sculpt_dino_model(root: Node) -> bool:
	if root == null:
		return false
	if root.find_child("DinoBuddySculpt", true, false) != null:
		return true
	# Godot's glTF importer occasionally prefixes/suffixes names; fall back to
	# a scan that matches any mesh whose name starts with "DinoBuddySculpt".
	return _has_descendant_starting_with(root, "DinoBuddySculpt")


func _has_descendant_starting_with(node: Node, prefix: String) -> bool:
	if node.name.begins_with(prefix):
		return true
	for child in node.get_children():
		if _has_descendant_starting_with(child, prefix):
			return true
	return false


func _apply_imported_palette(mesh_node: MeshInstance3D, primary: Color, accent: Color) -> void:
	var surface_count := mesh_node.mesh.get_surface_count()
	var node_name_lower := mesh_node.name.to_lower()
	var is_sculpt_skin_mesh := node_name_lower.begins_with("dinobuddysculpt") or node_name_lower == "dinobuddysculpt"

	for surface_index in range(surface_count):
		var source_material: Material = mesh_node.get_active_material(surface_index)
		if source_material == null:
			source_material = mesh_node.mesh.surface_get_material(surface_index)
		var material_name := ""
		if source_material != null:
			material_name = ("%s %s" % [source_material.resource_name, source_material.resource_path]).to_lower()

		var surface_has_vertex_colors := false
		if mesh_node.mesh is ArrayMesh:
			var fmt := (mesh_node.mesh as ArrayMesh).surface_get_format(surface_index)
			surface_has_vertex_colors = (fmt & Mesh.ARRAY_FORMAT_COLOR) != 0

		var override_material: Material = null
		# Any surface carrying per-vertex colors is the sculpt body ramp - the
		# eye / halo / primitive meshes never export COLOR_0. Use vertex colors
		# directly as albedo instead of Godot's default-imported flat material.
		if surface_has_vertex_colors or is_sculpt_skin_mesh or "dinosculpt" in material_name:
			override_material = _make_vertex_color_material(
				Color(1.0, 1.0, 1.0, 1.0), 0.5, source_material
			)
		elif "dino_main" in material_name:
			override_material = _make_imported_material(primary.lightened(0.05), 0.58)
		elif "dino_secondary" in material_name:
			override_material = _make_imported_material(accent.lightened(0.03), 0.44, accent * 0.14, 0.14)
		elif "dino_tongue" in material_name:
			override_material = _make_imported_material(Color(0.89, 0.49, 0.50, 1.0), 0.58)
		elif "dino_teeth" in material_name:
			override_material = _make_imported_material(Color(0.98, 0.96, 0.90, 1.0), 0.78)
		elif "dinoeyewhite" in material_name or "eye_white" in material_name:
			# Bright wet sclera (Pixar / feature-film board style).
			override_material = _make_imported_material(Color(0.95, 0.95, 0.93, 1.0), 0.26)
			override_material.metallic_specular = 0.58
		elif "dinoeyeiris" in material_name:
			override_material = _make_imported_material(Color(0.48, 0.32, 0.10, 1.0), 0.24)
			override_material.metallic_specular = 0.52
			override_material.clearcoat_enabled = true
			override_material.clearcoat = 0.38
			override_material.clearcoat_roughness = 0.14
		elif "dinoeyepupil" in material_name or "eye_black" in material_name:
			override_material = _make_imported_material(Color(0.02, 0.015, 0.01, 1.0), 0.35)
		elif "dinoeyehighlight" in material_name:
			override_material = _make_imported_material(Color(1.0, 1.0, 1.0, 1.0), 0.18, Color(1.0, 1.0, 1.0, 1.0), 2.2)

		# Never leave imported buddy surfaces without a bound material, because
		# null materials can trigger renderer errors on some Godot/Vulkan setups.
		if override_material == null:
			if source_material != null:
				var dup: Resource = source_material.duplicate()
				if dup is Material:
					override_material = dup as Material
			if override_material == null:
				override_material = _make_imported_material(primary, 0.62)
		mesh_node.set_surface_override_material(surface_index, override_material)


func _make_imported_material(color: Color, roughness: float, emission: Color = Color(0, 0, 0, 1), emission_strength := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	# Keep buddy surfaces non-metallic and less mirror-like so outdoor sky tint
	# does not wash skin toward cyan under Forward+ lighting.
	mat.metallic = 0.0
	mat.metallic_specular = 0.22
	if emission_strength > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = emission_strength
	return mat


func _make_vertex_color_material(tint: Color, roughness: float, source_material: Material = null) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	# Sculpt vertex colors are authored in sRGB space in Blender color tools.
	# Decoding them as sRGB in Godot preserves the intended darker green ramp.
	mat.vertex_color_is_srgb = true
	mat.albedo_color = tint
	# Satin skin (not chalky matte) so scale edges catch soft highlights like the reference.
	mat.roughness = clampf(roughness, 0.42, 0.62)
	mat.metallic = 0.0
	mat.metallic_specular = 0.42
	# Real-time approximation of the reference boards' subsurface flesh (Godot 4.6+ API).
	mat.subsurf_scatter_enabled = true
	mat.subsurf_scatter_skin_mode = true
	mat.subsurf_scatter_strength = 0.27
	mat.subsurf_scatter_transmittance_enabled = true
	mat.subsurf_scatter_transmittance_color = Color(0.42, 0.62, 0.32)
	mat.subsurf_scatter_transmittance_depth = 0.18
	if source_material is StandardMaterial3D:
		var src := source_material as StandardMaterial3D
		if src.normal_texture != null:
			mat.normal_enabled = true
			mat.normal_texture = src.normal_texture
			mat.normal_scale = src.normal_scale
	return mat
