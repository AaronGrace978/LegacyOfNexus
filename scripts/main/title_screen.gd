extends Node3D

signal start_game_requested
signal continue_game_requested

var _camera: Camera3D
var _camera_angle := 0.0
var _floating_shapes: Array[MeshInstance3D] = []
var _title_label: Label
var _continue_button: Button
var _save_info_label: Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_environment()
	_build_3d_scene()
	_build_ui()


func _process(delta: float) -> void:
	_camera_angle += delta * 0.08
	if _camera:
		_camera.position = Vector3(sin(_camera_angle) * 8.0, 3.8 + sin(_camera_angle * 0.6) * 0.4, cos(_camera_angle) * 8.0)
		_camera.look_at(Vector3(0.0, 1.0, 0.0))

	var time := Time.get_ticks_msec() * 0.001
	for shape in _floating_shapes:
		if not is_instance_valid(shape):
			continue
		var offset: float = shape.get_meta("f_offset")
		var speed: float = shape.get_meta("f_speed")
		var height: float = shape.get_meta("f_height")
		var spin: float = shape.get_meta("f_spin")
		var base_y: float = shape.get_meta("f_base_y")
		shape.position.y = base_y + sin(time * speed + offset) * height
		shape.rotation.y += delta * spin
		shape.rotation.x += delta * spin * 0.4

	if _title_label:
		var pulse := 0.88 + sin(time * 1.2) * 0.12
		_title_label.modulate = Color(pulse, pulse, 1.0, 1.0)


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.04, 0.06, 0.14, 1.0)
	sky_mat.sky_horizon_color = Color(0.08, 0.10, 0.22, 1.0)
	sky_mat.ground_bottom_color = Color(0.02, 0.03, 0.08, 1.0)
	sky_mat.ground_horizon_color = Color(0.06, 0.08, 0.18, 1.0)

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.15, 0.18, 0.35, 1.0)
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.15
	env.fog_enabled = true
	env.fog_light_color = Color(0.08, 0.10, 0.25, 1.0)
	env.fog_density = 0.012

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func _build_3d_scene() -> void:
	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 4.0, 8.0)
	_camera.look_at_from_position(_camera.position, Vector3.ZERO)
	_camera.fov = 60.0
	_camera.current = true
	add_child(_camera)

	var key_light := DirectionalLight3D.new()
	key_light.rotation = Vector3(-0.7, 0.5, 0.0)
	key_light.light_color = Color(0.4, 0.5, 0.9, 1.0)
	key_light.light_energy = 1.2
	add_child(key_light)

	var accent_light := OmniLight3D.new()
	accent_light.position = Vector3(2.0, 3.0, -1.0)
	accent_light.light_color = Color(0.3, 0.8, 0.5, 1.0)
	accent_light.light_energy = 4.0
	accent_light.omni_range = 12.0
	add_child(accent_light)

	var accent_light_2 := OmniLight3D.new()
	accent_light_2.position = Vector3(-3.0, 2.0, 2.0)
	accent_light_2.light_color = Color(0.7, 0.3, 0.9, 1.0)
	accent_light_2.light_energy = 3.0
	accent_light_2.omni_range = 10.0
	add_child(accent_light_2)

	_spawn_floating_shapes()
	_spawn_title_particles()
	_spawn_ground_ring()


func _spawn_floating_shapes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var palette: Array[Color] = [
		Color(0.3, 0.5, 0.95, 1.0),
		Color(0.2, 0.85, 0.5, 1.0),
		Color(0.6, 0.3, 0.9, 1.0),
		Color(0.9, 0.4, 0.3, 1.0),
		Color(0.1, 0.7, 0.8, 1.0),
		Color(0.85, 0.7, 0.2, 1.0),
	]

	for i in range(14):
		var mesh_node := MeshInstance3D.new()
		var color: Color = palette[i % palette.size()]

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(color.r, color.g, color.b, 0.78)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = color * 0.55
		mat.emission_energy_multiplier = 1.5
		mat.roughness = 0.3
		mat.metallic = 0.4

		if rng.randf() < 0.4:
			var box := BoxMesh.new()
			var s := rng.randf_range(0.25, 0.7)
			box.size = Vector3(s, s, s)
			mesh_node.mesh = box
		elif rng.randf() < 0.6:
			var sphere := SphereMesh.new()
			sphere.radius = rng.randf_range(0.18, 0.55)
			sphere.height = sphere.radius * 2.0
			mesh_node.mesh = sphere
		else:
			var prism := PrismMesh.new()
			prism.size = Vector3(rng.randf_range(0.3, 0.6), rng.randf_range(0.4, 0.8), rng.randf_range(0.3, 0.6))
			mesh_node.mesh = prism

		mesh_node.set_surface_override_material(0, mat)
		mesh_node.position = Vector3(
			rng.randf_range(-6.0, 6.0),
			rng.randf_range(0.5, 5.0),
			rng.randf_range(-6.0, 6.0)
		)
		mesh_node.set_meta("f_offset", rng.randf() * TAU)
		mesh_node.set_meta("f_speed", rng.randf_range(0.3, 0.8))
		mesh_node.set_meta("f_height", rng.randf_range(0.3, 0.8))
		mesh_node.set_meta("f_spin", rng.randf_range(0.15, 0.55))
		mesh_node.set_meta("f_base_y", mesh_node.position.y)
		add_child(mesh_node)
		_floating_shapes.append(mesh_node)


func _spawn_title_particles() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(10.0, 4.0, 10.0)
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 30.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.45
	pm.gravity = Vector3(0.0, -0.02, 0.0)
	pm.scale_min = 0.3
	pm.scale_max = 1.2
	pm.color = Color(0.3, 0.7, 0.9, 0.45)

	var sphere := SphereMesh.new()
	sphere.radius = 0.028
	sphere.height = 0.056
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.3, 0.85, 0.6, 0.5)
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.emission_enabled = true
	glow.emission = Color(0.2, 0.75, 0.5, 1.0)
	glow.emission_energy_multiplier = 3.5
	glow.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sphere.material = glow

	var particles := GPUParticles3D.new()
	particles.amount = 140
	particles.lifetime = 8.0
	particles.process_material = pm
	particles.draw_pass_1 = sphere
	particles.material_override = glow
	particles.visibility_aabb = AABB(Vector3(-15.0, -5.0, -15.0), Vector3(30.0, 15.0, 30.0))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)


func _spawn_ground_ring() -> void:
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.12, 0.18, 0.35, 0.5)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.15, 0.25, 0.55, 1.0)
	ring_mat.emission_energy_multiplier = 0.6
	ring_mat.roughness = 0.2
	ring_mat.metallic = 0.5

	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 3.5
	ring_mesh.outer_radius = 4.0
	ring_mesh.rings = 32
	ring_mesh.ring_segments = 24

	var ring := MeshInstance3D.new()
	ring.mesh = ring_mesh
	ring.set_surface_override_material(0, ring_mat)
	ring.position = Vector3(0.0, -0.5, 0.0)
	ring.rotation.x = PI * 0.5
	add_child(ring)


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root)

	var vignette := ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(0.0, 0.0, 0.0, 0.2)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vignette)

	var centre := VBoxContainer.new()
	centre.set_anchors_preset(Control.PRESET_CENTER)
	centre.position = Vector2(-260.0, -240.0)
	centre.custom_minimum_size = Vector2(520.0, 0.0)
	centre.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(centre)

	var subtitle := Label.new()
	subtitle.text = "~ A Buddy RPG ~"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(0.5, 0.75, 0.9, 0.7))
	centre.add_child(subtitle)

	_title_label = Label.new()
	_title_label.text = "LEGACY  OF  NEXUS"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 56)
	_title_label.add_theme_color_override("font_color", Color(0.88, 0.92, 1.0, 1.0))
	centre.add_child(_title_label)

	var tagline := Label.new()
	tagline.text = "Bond. Battle. Belong."
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.add_theme_font_size_override("font_size", 15)
	tagline.add_theme_color_override("font_color", Color(0.55, 0.7, 0.85, 0.6))
	centre.add_child(tagline)

	centre.add_child(_spacer(70.0))

	var btn_normal := _panel_style(Color(0.10, 0.14, 0.26, 0.88), Color(0.28, 0.45, 0.78, 0.6))
	var btn_hover := _panel_style(Color(0.16, 0.22, 0.40, 0.95), Color(0.4, 0.65, 1.0, 0.9))
	var btn_disabled := _panel_style(Color(0.08, 0.10, 0.18, 0.6), Color(0.2, 0.22, 0.3, 0.3))

	var new_game := _menu_button("New Game", btn_normal, btn_hover)
	new_game.pressed.connect(_on_new_game)
	centre.add_child(new_game)

	centre.add_child(_spacer(6.0))

	_continue_button = _menu_button("Continue", btn_normal, btn_hover)
	_continue_button.add_theme_stylebox_override("disabled", btn_disabled)
	_continue_button.pressed.connect(_on_continue_game)
	centre.add_child(_continue_button)

	centre.add_child(_spacer(6.0))

	var quit := _menu_button("Quit", btn_normal, btn_hover)
	quit.pressed.connect(func() -> void: get_tree().quit())
	centre.add_child(quit)

	centre.add_child(_spacer(12.0))

	_save_info_label = Label.new()
	_save_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_save_info_label.add_theme_font_size_override("font_size", 13)
	_save_info_label.add_theme_color_override("font_color", Color(0.66, 0.76, 0.9, 0.72))
	_save_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	centre.add_child(_save_info_label)

	centre.add_child(_spacer(40.0))

	var version := Label.new()
	version.text = "v0.1 — Prototype Build"
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.add_theme_font_size_override("font_size", 13)
	version.add_theme_color_override("font_color", Color(0.38, 0.44, 0.58, 0.45))
	centre.add_child(version)

	root.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var tween := create_tween()
	tween.tween_property(root, "modulate:a", 1.0, 1.8).set_ease(Tween.EASE_OUT)
	_refresh_continue_state()


func _spacer(height: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0.0, height)
	return s


func _panel_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(12)
	return sb


func _menu_button(text: String, normal: StyleBoxFlat, hover: StyleBoxFlat) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(300.0, 50.0)
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color", Color(0.8, 0.88, 1.0, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(0.92, 0.96, 1.0, 1.0))
	btn.add_theme_color_override("font_disabled_color", Color(0.32, 0.35, 0.42, 0.5))
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return btn


func _on_new_game() -> void:
	emit_signal("start_game_requested")


func _on_continue_game() -> void:
	if _continue_button == null or _continue_button.disabled:
		return
	emit_signal("continue_game_requested")


func _refresh_continue_state() -> void:
	var save_manager: Node = get_node_or_null("/root/SaveManager")
	var summary: Dictionary = {}
	if save_manager != null and save_manager.has_method("get_save_summary"):
		summary = save_manager.call("get_save_summary")

	var has_save := bool(summary.get("has_save", false))
	if _continue_button != null:
		_continue_button.disabled = not has_save

	if _save_info_label == null:
		return
	if not has_save:
		_save_info_label.text = "No save file yet. Start a new run, then press F5 in Greenbelt Park to quick-save."
		return

	_save_info_label.text = "Continue from %s  ·  %d buddies  ·  %s" % [
		str(summary.get("location", "Greenbelt Park")),
		int(summary.get("party_count", 1)),
		str(summary.get("time_label", "12:00 PM")),
	]
