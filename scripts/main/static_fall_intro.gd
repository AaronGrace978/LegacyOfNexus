extends Node3D

signal intro_finished

const BEATS := [
	{"text": "Greenbelt Park. 3:14 PM.", "duration": 3.2, "color": Color(0.6, 0.72, 0.9, 1.0)},
	{"text": "The sky tears open.", "duration": 2.8, "color": Color(0.95, 0.6, 0.4, 1.0)},
	{"text": "They call it the Static Fall.", "duration": 3.2, "color": Color(0.85, 0.95, 1.0, 1.0)},
	{"text": "Digital creatures spill into the world,\ninjured and terrified.", "duration": 4.0, "color": Color(0.7, 0.85, 0.95, 1.0)},
	{"text": "You find one hiding in the grass.\nSmall. Shaking. Alive.", "duration": 4.2, "color": Color(0.7, 1.0, 0.75, 1.0)},
	{"text": "It touches your phone…", "duration": 3.0, "color": Color(0.8, 1.0, 0.85, 1.0)},
	{"text": "…and decides to stay.", "duration": 3.4, "color": Color(0.4, 0.95, 0.6, 1.0)},
	{"text": "This is how your story begins.", "duration": 3.0, "color": Color(0.92, 0.96, 1.0, 1.0)},
]

var _label: Label
var _skip_hint: Label
var _bg_rect: ColorRect
var _beat_index := -1
var _bg_overlay: ColorRect
var _camera: Camera3D
var _camera_angle := 0.0
var _floating_shards: Array[MeshInstance3D] = []
var _rift_mesh: MeshInstance3D
var _finishing := false
var _tween: Tween


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_environment()
	_build_3d_scene()
	_build_ui()
	_advance_beat()


func _unhandled_input(event: InputEvent) -> void:
	if _finishing:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("jump") or event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_skip_to_end()


func _process(delta: float) -> void:
	_camera_angle += delta * 0.06
	if _camera:
		_camera.position = Vector3(sin(_camera_angle) * 6.5, 3.0 + sin(_camera_angle * 0.4) * 0.5, cos(_camera_angle) * 6.5)
		_camera.look_at(Vector3(0.0, 1.0, 0.0))

	var time := Time.get_ticks_msec() * 0.001
	for shard in _floating_shards:
		if not is_instance_valid(shard):
			continue
		var base_y: float = shard.get_meta("base_y")
		var speed: float = shard.get_meta("speed")
		var offset: float = shard.get_meta("offset")
		shard.position.y = base_y + sin(time * speed + offset) * 0.4
		shard.rotation.y += delta * 0.5
		shard.rotation.x += delta * 0.2

	if _rift_mesh:
		var pulse := 0.9 + sin(time * 2.1) * 0.1
		_rift_mesh.scale = Vector3(pulse, pulse, pulse)
		_rift_mesh.rotation.z += delta * 0.35


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.05, 0.03, 0.12, 1.0)
	sky_mat.sky_horizon_color = Color(0.18, 0.08, 0.22, 1.0)
	sky_mat.ground_bottom_color = Color(0.02, 0.01, 0.06, 1.0)
	sky_mat.ground_horizon_color = Color(0.08, 0.04, 0.18, 1.0)

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.18, 0.32, 1.0)
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.65
	env.glow_bloom = 0.12
	env.ssao_enabled = true
	env.ssao_intensity = 2.5
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.15
	env.fog_enabled = true
	env.fog_light_color = Color(0.22, 0.1, 0.28, 1.0)
	env.fog_density = 0.018

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func _build_3d_scene() -> void:
	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 3.0, 6.5)
	_camera.fov = 60.0
	_camera.current = true
	add_child(_camera)

	var key_light := DirectionalLight3D.new()
	key_light.rotation = Vector3(-0.7, 0.3, 0.0)
	key_light.light_color = Color(0.85, 0.6, 1.0, 1.0)
	key_light.light_energy = 1.1
	add_child(key_light)

	var rift_light := OmniLight3D.new()
	rift_light.position = Vector3(0.0, 2.5, 0.0)
	rift_light.light_color = Color(0.95, 0.45, 0.85, 1.0)
	rift_light.light_energy = 6.0
	rift_light.omni_range = 14.0
	add_child(rift_light)

	_build_rift()
	_build_floating_shards()
	_build_particle_field()


func _build_rift() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.4, 0.85, 0.72)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.95, 0.35, 0.85, 1.0)
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var mesh := TorusMesh.new()
	mesh.inner_radius = 1.1
	mesh.outer_radius = 1.6
	mesh.rings = 48
	mesh.ring_segments = 32

	_rift_mesh = MeshInstance3D.new()
	_rift_mesh.mesh = mesh
	_rift_mesh.set_surface_override_material(0, mat)
	_rift_mesh.position = Vector3(0.0, 2.5, 0.0)
	_rift_mesh.rotation.y = 0.35
	add_child(_rift_mesh)


func _build_floating_shards() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var palette: Array[Color] = [
		Color(0.3, 0.85, 0.5, 1.0),
		Color(0.35, 0.6, 1.0, 1.0),
		Color(0.95, 0.5, 0.9, 1.0),
		Color(0.95, 0.75, 0.3, 1.0),
	]

	for i in range(18):
		var mi := MeshInstance3D.new()
		var color: Color = palette[i % palette.size()]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(color.r, color.g, color.b, 0.8)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.5
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

		var prism := PrismMesh.new()
		var s: float = rng.randf_range(0.12, 0.32)
		prism.size = Vector3(s, s * 1.6, s)
		mi.mesh = prism
		mi.set_surface_override_material(0, mat)

		var angle := rng.randf() * TAU
		var dist := rng.randf_range(1.5, 5.0)
		var height := rng.randf_range(0.3, 3.5)
		mi.position = Vector3(cos(angle) * dist, height, sin(angle) * dist)
		mi.set_meta("base_y", mi.position.y)
		mi.set_meta("speed", rng.randf_range(0.6, 1.4))
		mi.set_meta("offset", rng.randf() * TAU)
		add_child(mi)
		_floating_shards.append(mi)


func _build_particle_field() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(12.0, 6.0, 12.0)
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.spread = 15.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3(0.0, -0.1, 0.0)
	pm.scale_min = 0.25
	pm.scale_max = 0.9
	pm.color = Color(0.8, 0.5, 0.9, 0.65)

	var sphere := SphereMesh.new()
	sphere.radius = 0.03
	sphere.height = 0.06
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.8, 0.5, 1.0, 0.7)
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.emission_enabled = true
	glow.emission = Color(0.85, 0.45, 1.0, 1.0)
	glow.emission_energy_multiplier = 3.0
	glow.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sphere.material = glow

	var particles := GPUParticles3D.new()
	particles.amount = 240
	particles.lifetime = 6.0
	particles.process_material = pm
	particles.draw_pass_1 = sphere
	particles.material_override = glow
	particles.visibility_aabb = AABB(Vector3(-16.0, -6.0, -16.0), Vector3(32.0, 16.0, 32.0))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 30
	add_child(canvas)

	_bg_overlay = ColorRect.new()
	_bg_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_overlay.color = Color(0.0, 0.0, 0.0, 1.0)
	canvas.add_child(_bg_overlay)

	var fade_in := create_tween()
	fade_in.tween_property(_bg_overlay, "color:a", 0.35, 2.0).set_ease(Tween.EASE_OUT)

	_bg_rect = ColorRect.new()
	_bg_rect.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bg_rect.offset_top = -240.0
	_bg_rect.offset_bottom = -40.0
	_bg_rect.color = Color(0.0, 0.0, 0.0, 0.55)
	canvas.add_child(_bg_rect)

	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_label.offset_top = -200.0
	_label.offset_bottom = -80.0
	_label.offset_left = 80.0
	_label.offset_right = -80.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 28)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 0))
	canvas.add_child(_label)

	_skip_hint = Label.new()
	_skip_hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skip_hint.position = Vector2(-180.0, 14.0)
	_skip_hint.custom_minimum_size = Vector2(160.0, 0.0)
	_skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skip_hint.text = "[Esc / Space] Skip"
	_skip_hint.add_theme_font_size_override("font_size", 13)
	_skip_hint.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9, 0.55))
	canvas.add_child(_skip_hint)


func _advance_beat() -> void:
	if _finishing:
		return
	_beat_index += 1
	if _beat_index >= BEATS.size():
		_finish()
		return

	var beat: Dictionary = BEATS[_beat_index]
	var beat_color: Color = beat.get("color", Color.WHITE) as Color
	_label.text = String(beat.get("text", ""))
	_label.add_theme_color_override("font_color", beat_color)
	_label.modulate = Color(1.0, 1.0, 1.0, 0.0)

	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_label, "modulate:a", 1.0, 0.7).set_ease(Tween.EASE_OUT)
	var hold: float = float(beat.get("duration", 3.0)) - 1.2
	_tween.tween_interval(max(0.4, hold))
	_tween.tween_property(_label, "modulate:a", 0.0, 0.5).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_advance_beat)


func _skip_to_end() -> void:
	_finish()


func _finish() -> void:
	if _finishing:
		return
	_finishing = true
	if _tween:
		_tween.kill()

	var fade := create_tween()
	fade.tween_property(_bg_overlay, "color:a", 1.0, 1.0).set_ease(Tween.EASE_IN)
	fade.tween_callback(func() -> void: emit_signal("intro_finished"))
