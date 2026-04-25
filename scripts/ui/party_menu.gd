extends CanvasLayer

signal menu_toggled(is_open: bool)

const BuddyVisualCatalog := preload("res://scripts/buddies/buddy_visual_catalog.gd")
const SLOT_PREVIEW_SIZE := 112
## Internal render resolution multiplier (supersampling for party slot portraits).
const SLOT_PREVIEW_RENDER_SCALE := 3
const QUATERNIUS_PREVIEW_SCALE := Vector3(0.42, 0.42, 0.42)

@onready var close_button: Button = $Center/MainPanel/MainVBox/HeaderRow/CloseButton
@onready var slots_vbox: VBoxContainer = $Center/MainPanel/MainVBox/SlotsVBox
@onready var info_label: Label = $Center/MainPanel/MainVBox/InfoLabel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide_menu()
	close_button.pressed.connect(hide_menu)

	var party_manager: Node = get_node_or_null("/root/PartyManager")
	if party_manager != null and party_manager.has_signal("party_changed"):
		party_manager.party_changed.connect(_on_party_manager_changed)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		hide_menu()
		get_viewport().set_input_as_handled()
		return

	if not event.is_action_pressed("party_menu"):
		return

	var parent_node: Node = get_parent()
	if parent_node != null and parent_node.has_method("is_party_menu_input_allowed"):
		if not parent_node.is_party_menu_input_allowed():
			return

	toggle_menu()
	get_viewport().set_input_as_handled()


func _on_party_manager_changed() -> void:
	if visible:
		refresh()


func toggle_menu() -> void:
	if visible:
		hide_menu()
	else:
		show_menu()


func show_menu() -> void:
	get_tree().paused = true
	visible = true
	refresh()
	emit_signal("menu_toggled", true)
	call_deferred("_grab_party_focus")


func hide_menu() -> void:
	get_tree().paused = false
	visible = false
	emit_signal("menu_toggled", false)


func _grab_party_focus() -> void:
	if not visible:
		return
	if slots_vbox.get_child_count() > 0:
		var row: Control = slots_vbox.get_child(0) as Control
		if row:
			row.grab_focus()
			return
	close_button.grab_focus()


func refresh() -> void:
	var party_manager: Node = get_node_or_null("/root/PartyManager")
	if party_manager == null or not party_manager.has_method("get_party_for_display"):
		return

	var display_data: Array[Dictionary] = party_manager.get_party_for_display()
	_rebuild_slot_rows(display_data)


func _rebuild_slot_rows(display_data: Array[Dictionary]) -> void:
	for child: Node in slots_vbox.get_children():
		child.queue_free()

	for slot_index in range(display_data.size()):
		var slot_info: Dictionary = display_data[slot_index]
		var row: Button = _build_slot_row(slot_index, slot_info)
		slots_vbox.add_child(row)


func _build_slot_row(slot_index: int, slot_info: Dictionary) -> Button:
	var btn := Button.new()
	btn.flat = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 102)
	btn.tooltip_text = _slot_tooltip(slot_index, slot_info)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_stylebox_override("normal", _make_slot_stylebox())
	var hover_style := _make_slot_stylebox()
	hover_style.border_color = Color(0.42, 0.62, 0.95, 0.78)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", _make_slot_stylebox())
	btn.pressed.connect(_on_slot_pressed.bind(slot_index, slot_info))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 4)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)

	var preview := _make_slot_preview(slot_info)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(preview)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_theme_constant_override("separation", 4)

	if slot_index == 0:
		var badge := Label.new()
		badge.text = "Permanent Partner"
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45, 1.0))
		badge.add_theme_font_size_override("font_size", 13)
		text_col.add_child(badge)

	var title := Label.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if slot_info.get("empty", false):
		title.text = "Slot %d — Empty" % (slot_index + 1)
		title.add_theme_font_size_override("font_size", 17)
	else:
		title.text = str(slot_info.get("name", "Buddy"))
		title.add_theme_font_size_override("font_size", 18)

	var detail := Label.new()
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.add_theme_font_size_override("font_size", 14)
	detail.add_theme_color_override("font_color", Color(0.72, 0.78, 0.9, 1.0))
	if slot_info.get("empty", false):
		detail.text = "Capture Buddies in the field to fill this slot."
	else:
		detail.text = "HP %d / %d   ·   Lv %d" % [
			int(slot_info.get("hp", 0)),
			int(slot_info.get("max_hp", 0)),
			int(slot_info.get("level", 1)),
		]

	text_col.add_child(title)
	text_col.add_child(detail)
	row.add_child(text_col)
	margin.add_child(row)
	btn.add_child(margin)
	return btn


func _on_slot_pressed(slot_index: int, slot_info: Dictionary) -> void:
	info_label.text = _slot_detail_text(slot_index, slot_info)


func _slot_tooltip(slot_index: int, slot_info: Dictionary) -> String:
	if slot_info.get("empty", false):
		return "Slot %d\n(Empty)" % (slot_index + 1)
	var name: String = str(slot_info.get("name", "Buddy"))
	var hp: int = int(slot_info.get("hp", 0))
	var mx: int = int(slot_info.get("max_hp", 0))
	return "%s\nHP %d / %d" % [name, hp, mx]


func _slot_detail_text(slot_index: int, slot_info: Dictionary) -> String:
	if slot_info.get("empty", false):
		return "Slot %d is empty. Capture a Buddy to add them here." % (slot_index + 1)
	var name: String = str(slot_info.get("name", "Buddy"))
	var hp: int = int(slot_info.get("hp", 0))
	var mx: int = int(slot_info.get("max_hp", 0))
	var lv: int = int(slot_info.get("level", 1))
	if slot_index == 0:
		return "Permanent Partner — %s\nHP %d / %d   (Lv %d)" % [name, hp, mx, lv]
	return "%s\nHP %d / %d   (Lv %d)" % [name, hp, mx, lv]


func _make_slot_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0627451, 0.0862745, 0.141176, 0.92)
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_right = 12
	sb.corner_radius_bottom_left = 12
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.294118, 0.482353, 0.870588, 0.45)
	sb.content_margin_left = 12
	sb.content_margin_top = 10
	sb.content_margin_right = 12
	sb.content_margin_bottom = 10
	return sb


func _make_slot_preview(slot_info: Dictionary) -> Control:
	if slot_info.get("empty", false):
		return _make_empty_preview()

	var unit_name: String = str(slot_info.get("name", "Buddy"))
	var scene: PackedScene = BuddyVisualCatalog.resolve_battle_visual(unit_name)
	if scene == null:
		return _make_color_preview(slot_info)

	var primary: Color = slot_info.get("primary_color", Color(0.45, 0.95, 1.0)) as Color
	var accent: Color = slot_info.get("accent_color", Color(0.85, 1.0, 1.0)) as Color

	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(SLOT_PREVIEW_SIZE, SLOT_PREVIEW_SIZE)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = primary.darkened(0.72)
	panel_style.corner_radius_top_left = 10
	panel_style.corner_radius_top_right = 10
	panel_style.corner_radius_bottom_right = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.border_color = primary.lightened(0.1)
	panel_style.border_color.a = 0.6
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	holder.add_theme_stylebox_override("panel", panel_style)

	var vpc := SubViewportContainer.new()
	vpc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vpc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vpc.stretch = true
	vpc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(vpc)

	var vp := SubViewport.new()
	var rs := SLOT_PREVIEW_RENDER_SCALE
	vp.size = Vector2i(SLOT_PREVIEW_SIZE * rs, SLOT_PREVIEW_SIZE * rs)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.handle_input_locally = false
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA

	var world := World3D.new()
	vp.world_3d = world

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = primary.lightened(0.2)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.2

	var world_root := Node3D.new()
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	world_root.add_child(world_env)

	# Three-point lighting for portrait feel.
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-38.0, 34.0, 0.0)
	key_light.light_energy = 1.4
	key_light.light_color = Color(1.0, 0.96, 0.88)
	world_root.add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-15.0, -125.0, 0.0)
	fill_light.light_energy = 0.6
	fill_light.light_color = primary.lightened(0.4)
	world_root.add_child(fill_light)

	var rim_light := DirectionalLight3D.new()
	rim_light.rotation_degrees = Vector3(-10.0, 170.0, 0.0)
	rim_light.light_energy = 1.1
	rim_light.light_color = accent.lightened(0.2)
	world_root.add_child(rim_light)

	var model: Node3D = scene.instantiate() as Node3D
	_prep_preview_model(model, unit_name)
	_apply_preview_palette(model, primary, accent)
	world_root.add_child(model)

	var cam := Camera3D.new()
	cam.current = true
	_frame_preview_camera(cam, model)
	world_root.add_child(cam)

	vp.add_child(world_root)
	vpc.add_child(vp)
	return holder


func _prep_preview_model(model: Node3D, unit_name: String) -> void:
	# Disable any buddy_animator script that would otherwise animate the pose.
	if model.get_script() != null:
		model.set_script(null)

	# Quaternius Dino: scale the GLB down so it reads properly in the portrait.
	if unit_name == "Dino Buddy":
		var imported := model.find_child("ImportedDino", true, false) as Node3D
		if imported != null:
			imported.scale = QUATERNIUS_PREVIEW_SCALE
			imported.position = Vector3(0.0, 0.0, 0.0)
			imported.rotation = Vector3(0.0, PI, 0.0)


func _apply_preview_palette(root: Node, primary: Color, accent: Color) -> void:
	for child in root.get_children():
		_apply_preview_palette(child, primary, accent)

	if not (root is MeshInstance3D):
		return
	var mesh_node := root as MeshInstance3D
	if mesh_node.mesh == null:
		return

	if mesh_node.is_in_group("buddy_palette_primary"):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = primary
		mat.roughness = 0.42
		mat.metallic = 0.08
		mat.rim_enabled = true
		mat.rim = 0.65
		mat.rim_tint = 0.75
		mat.clearcoat_enabled = true
		mat.clearcoat = 0.25
		mat.emission_enabled = true
		mat.emission = primary * 0.22
		mat.emission_energy_multiplier = 0.5
		mesh_node.material_override = mat
	elif mesh_node.is_in_group("buddy_palette_accent"):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = accent
		mat.roughness = 0.25
		mat.metallic = 0.3
		mat.rim_enabled = true
		mat.rim = 0.8
		mat.rim_tint = 0.85
		mat.emission_enabled = true
		mat.emission = accent * 0.9
		mat.emission_energy_multiplier = 1.15
		mesh_node.material_override = mat
	else:
		_apply_preview_imported_palette(mesh_node, primary, accent)


func _apply_preview_imported_palette(mesh_node: MeshInstance3D, primary: Color, accent: Color) -> void:
	var mesh := mesh_node.mesh
	if mesh == null:
		return
	var surface_count := mesh.get_surface_count()
	for surface_index in range(surface_count):
		var source_material: Material = mesh_node.get_active_material(surface_index)
		if source_material == null:
			source_material = mesh.surface_get_material(surface_index)
		var material_name := ""
		if source_material != null:
			material_name = ("%s %s" % [source_material.resource_name, source_material.resource_path]).to_lower()

		var override_material: Material = null
		if "dino_tongue" in material_name:
			var invis := StandardMaterial3D.new()
			invis.albedo_color = Color(0, 0, 0, 0)
			invis.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			invis.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			invis.cull_mode = BaseMaterial3D.CULL_DISABLED
			override_material = invis
		elif "dino_main" in material_name:
			override_material = _make_preview_material(primary.lightened(0.08), 0.55)
		elif "dino_secondary" in material_name:
			override_material = _make_preview_material(accent, 0.4, accent * 0.25, 0.3)
		elif "dino_teeth" in material_name:
			override_material = _make_preview_material(Color(0.98, 0.96, 0.9, 1.0), 0.7)
		elif "eye_white" in material_name:
			override_material = _make_preview_material(Color(0.98, 0.99, 1.0, 1.0), 0.25)
		elif "eye_black" in material_name:
			override_material = _make_preview_material(Color(0.08, 0.1, 0.12, 1.0), 0.22)

		if override_material != null:
			mesh_node.set_surface_override_material(surface_index, override_material)
		elif mesh_node.get_active_material(surface_index) == null:
			mesh_node.set_surface_override_material(surface_index, _make_preview_material(primary, 0.55))


func _make_preview_material(color: Color, roughness: float, emission := Color(0, 0, 0, 1), emission_strength := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = 0.05
	mat.rim_enabled = true
	mat.rim = 0.45
	mat.rim_tint = 0.7
	if emission_strength > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = emission_strength
	return mat


func _frame_preview_camera(cam: Camera3D, model: Node3D) -> void:
	var aabb := _compute_visual_aabb(model, Transform3D.IDENTITY)
	if aabb.size == Vector3.ZERO:
		aabb = AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 1.3, 1.0))

	var centre := aabb.get_center()
	var longest_side: float = maxf(maxf(aabb.size.x, aabb.size.y * 1.1), aabb.size.z)
	var fov := 34.0
	cam.fov = fov
	var fit_radius: float = longest_side * 0.62
	var distance: float = fit_radius / tan(deg_to_rad(fov * 0.5))
	distance = maxf(distance, 1.2)

	var forward := Vector3(0.0, 0.12, 1.0).normalized()
	cam.position = centre + forward * distance
	cam.look_at_from_position(cam.position, centre + Vector3(0.0, aabb.size.y * 0.08, 0.0), Vector3.UP)


func _compute_visual_aabb(node: Node, accum: Transform3D) -> AABB:
	var combined := AABB()
	var first := true
	var local_xform := accum
	if node is Node3D:
		local_xform = accum * (node as Node3D).transform

	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null and mi.visible:
			var local_aabb := mi.get_aabb()
			combined = local_xform * local_aabb
			first = false

	for child in node.get_children():
		var sub := _compute_visual_aabb(child, local_xform)
		if sub.size == Vector3.ZERO:
			continue
		if first:
			combined = sub
			first = false
		else:
			combined = combined.merge(sub)
	return combined


func _make_empty_preview() -> Control:
	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(SLOT_PREVIEW_SIZE, SLOT_PREVIEW_SIZE)
	var inner := StyleBoxFlat.new()
	inner.bg_color = Color(0.08, 0.1, 0.14, 1.0)
	inner.corner_radius_top_left = 8
	inner.corner_radius_top_right = 8
	inner.corner_radius_bottom_right = 8
	inner.corner_radius_bottom_left = 8
	inner.border_color = Color(0.25, 0.35, 0.5, 0.55)
	inner.border_width_left = 1
	inner.border_width_top = 1
	inner.border_width_right = 1
	inner.border_width_bottom = 1
	holder.add_theme_stylebox_override("panel", inner)

	var label := Label.new()
	label.text = "—"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(0.45, 0.5, 0.6, 1.0))
	holder.add_child(label)
	return holder


func _make_color_preview(slot_info: Dictionary) -> Control:
	var rect := ColorRect.new()
	rect.custom_minimum_size = Vector2(SLOT_PREVIEW_SIZE, SLOT_PREVIEW_SIZE)
	var c: Color = slot_info.get("primary_color", Color(0.3, 0.55, 0.75)) as Color
	rect.color = c.darkened(0.15)
	return rect
