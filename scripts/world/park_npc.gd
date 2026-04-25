extends Node3D

@export var npc_name := "Citizen"
@export var interact_radius := 2.8
@export var body_color := Color(0.5, 0.38, 0.25, 1.0)
@export var clothes_color := Color(0.35, 0.45, 0.6, 1.0)

var _player_in_range := false
var _dialogue_active := false
var _dialogue_index := 0
var _prompt_label: Label3D
var _dialogue_canvas: CanvasLayer
var _dialogue_text_label: Label
var _name_label: Label
var _hint_label: Label
var _visual_root: Node3D

const NPC_DIALOGUE := {
	"Lily": [
		"Oh my... did you see the sky earlier? Those poor creatures falling through the static...",
		"I found one hiding behind the community center. It was shaking so hard.",
		"Please, if you can help them, do. They're just scared, like us.",
	],
	"Marcus": [
		"Fascinating. These digital lifeforms respond to emotional stimuli.",
		"I've been recording my findings. Their signal patterns shift when you stay calm around them.",
		"The phenomenon they're calling 'Static Fall' wasn't random. There's a pattern to the breach points.",
		"I think these creatures carry memories from wherever they came from. Real memories.",
	],
	"Officer Chen": [
		"Park's been chaos since the outbreak. Stay alert out there.",
		"Some folks are trying to capture these things to sell them. Watch your back.",
		"If you see anything dangerous, keep distance. We still don't understand what they can do.",
		"Between you and me... I think some of them are more afraid of us than we are of them.",
	],
	"Tommy": [
		"Wow! Did you see that one?! It was glowing GREEN!",
		"I want a buddy SO BAD. Mom says I have to wait until they figure out the rules.",
		"My friend Kai says if you're nice to them, they'll like you back!",
		"Do you have one? Can I see it? Pleeeease?",
	],
}


func _ready() -> void:
	add_to_group("park_npc")
	_build_visual()
	_build_prompt_label()
	_build_dialogue_ui()


func _process(delta: float) -> void:
	var player := _find_player()
	if player == null:
		_player_in_range = false
		_prompt_label.visible = false
		return

	var distance := global_position.distance_to(player.global_position)
	_player_in_range = distance <= interact_radius
	_prompt_label.visible = _player_in_range and not _dialogue_active

	if _player_in_range and _visual_root:
		var look_pos := player.global_position
		look_pos.y = global_position.y
		if look_pos.distance_to(global_position) > 0.1:
			var dir := (look_pos - global_position).normalized()
			var target_y := atan2(dir.x, dir.z)
			_visual_root.rotation.y = lerp_angle(_visual_root.rotation.y, target_y, delta * 4.0)


func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_range:
		return

	if event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		if _dialogue_active:
			_advance_dialogue()
		else:
			_start_dialogue()


func _start_dialogue() -> void:
	var lines := _get_lines()
	if lines.is_empty():
		return
	_dialogue_active = true
	_dialogue_index = 0
	_show_line()
	_dialogue_canvas.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var player := _find_player()
	if player and player.has_method("set_controls_enabled"):
		player.set_controls_enabled(false)


func _advance_dialogue() -> void:
	_dialogue_index += 1
	if _dialogue_index >= _get_lines().size():
		_end_dialogue()
		return
	_show_line()


func _end_dialogue() -> void:
	_dialogue_active = false
	_dialogue_canvas.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var player := _find_player()
	if player and player.has_method("set_controls_enabled"):
		player.set_controls_enabled(true)
	_report_npc_talked()


func _report_npc_talked() -> void:
	var qm: Node = get_node_or_null("/root/QuestManager")
	if qm != null and qm.has_method("report_event"):
		qm.call("report_event", "npc_talked", npc_name, {})
	var bond: Node = get_node_or_null("/root/BondManager")
	if bond != null and bond.has_method("add_bond"):
		bond.call("add_bond", "Dino Buddy", 1, "npc_dialogue")


func _show_line() -> void:
	var lines := _get_lines()
	_name_label.text = npc_name
	_dialogue_text_label.text = lines[_dialogue_index]
	var remaining := lines.size() - _dialogue_index - 1
	_hint_label.text = "[E] Continue" if remaining > 0 else "[E] Close"


func _get_lines() -> Array:
	var base: Array = []
	if NPC_DIALOGUE.has(npc_name):
		base = (NPC_DIALOGUE[npc_name] as Array).duplicate()
	else:
		base = ["..."]
	var extra: Array = _quest_aware_lines()
	if extra.is_empty():
		return base
	return base + extra


func _quest_aware_lines() -> Array:
	var qm: Node = get_node_or_null("/root/QuestManager")
	if qm == null:
		return []
	var extras: Array = []

	# Special quest-triggered lines.
	if npc_name == "Tommy":
		var party_manager: Node = get_node_or_null("/root/PartyManager")
		var captured_any := false
		if party_manager != null and party_manager.has_method("get_party_for_display"):
			var party: Array = party_manager.call("get_party_for_display")
			for i in range(1, party.size()):
				var slot: Variant = party[i]
				if typeof(slot) == TYPE_DICTIONARY and not bool((slot as Dictionary).get("empty", true)):
					captured_any = true
					break
		if captured_any:
			extras.append("Whoa — you actually have one with you?! Can I see it? PLEASE??")
			extras.append("Okay okay, my mom says I can't touch it. But I'm gonna draw one just like yours.")
			var report_qm: Node = qm
			# We want to credit this conversation toward the "show_tommy" objective even if dialogue ends naturally.
			if report_qm.has_method("report_event"):
				report_qm.call("report_event", "npc_talked", "Tommy", {"showed_buddy": true})

	if npc_name == "Officer Chen":
		if qm.has_method("get_active_quests"):
			var actives: Array = qm.call("get_active_quests")
			if "spring_of_light" in actives:
				extras.append("If you're looking for that glowing shrine… some kids say they saw it near the north edge of the park. Blue light, like water.")

	if npc_name == "Marcus":
		var echo_mgr: Node = get_node_or_null("/root/EchoManager")
		if echo_mgr != null and echo_mgr.has_method("get_collected_count") and int(echo_mgr.call("get_collected_count")) > 0:
			extras.append("You've been finding the fragments too. Good. Read them. They're not noise — they're voices.")

	return extras


func _find_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Node3D


# ---- Visual ----

func _build_visual() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "VisualRoot"
	add_child(_visual_root)

	var skin_mat := _make_skin(Color(0.88, 0.76, 0.64, 1.0))
	var clothes_mat := _make_clothes(clothes_color)
	var pants_mat := _make_pants(body_color)
	var shoes_mat := _make_simple(Color(0.09, 0.1, 0.14, 1.0), 0.4, 0.15)
	var hair_mat := _make_hair(Color(0.16, 0.1, 0.08, 1.0))
	var eye_mat := _make_simple(Color(0.04, 0.06, 0.1, 1.0), 0.15, 0.3)
	var trim_mat := _make_emissive(clothes_color.lightened(0.55), 1.2)

	# Legs / shoes
	for side in [-0.13, 0.13]:
		_add_part(_visual_root, _capsule(0.1, 0.72), pants_mat, Vector3(side, 0.42, 0.0))
		_add_part(_visual_root, _box(0.22, 0.12, 0.32), shoes_mat, Vector3(side, 0.06, 0.04))

	# Torso + jacket trim
	_add_part(_visual_root, _capsule(0.3, 0.78), clothes_mat, Vector3(0.0, 1.18, 0.0))
	_add_part(_visual_root, _box(0.62, 0.04, 0.36), trim_mat, Vector3(0.0, 0.86, 0.0))

	# Arms
	for side in [-0.4, 0.4]:
		_add_part(_visual_root, _capsule(0.085, 0.58), clothes_mat, Vector3(side, 1.16, 0.0))
		_add_part(_visual_root, _sphere(0.1, 0.2), skin_mat, Vector3(side, 0.8, 0.0))

	# Neck + head
	_add_part(_visual_root, _capsule(0.08, 0.18), skin_mat, Vector3(0.0, 1.55, 0.0))
	_add_part(_visual_root, _sphere(0.24, 0.48), skin_mat, Vector3(0.0, 1.78, -0.02))

	# Eyes
	for side in [-0.08, 0.08]:
		_add_part(_visual_root, _sphere(0.025, 0.05), eye_mat, Vector3(side, 1.8, -0.22))

	# Hair — name-aware style
	_build_hair(hair_mat)

	# Accessory — personality touch
	_build_accessory(trim_mat, skin_mat)


func _build_hair(hair_mat: StandardMaterial3D) -> void:
	if npc_name == "Tommy":
		# Short spiky cap
		_add_part(_visual_root, _box(0.4, 0.16, 0.32), hair_mat, Vector3(0.0, 1.94, 0.0))
		_add_part(_visual_root, _prism(0.12, 0.18, 0.1), hair_mat, Vector3(0.08, 2.06, -0.06))
	elif npc_name == "Lily":
		# Long hair back + bang
		_add_part(_visual_root, _box(0.44, 0.34, 0.3), hair_mat, Vector3(0.0, 1.84, 0.06))
		_add_part(_visual_root, _prism(0.38, 0.14, 0.08), hair_mat, Vector3(0.0, 1.95, -0.2))
	elif npc_name == "Marcus":
		# Sleek back hair
		_add_part(_visual_root, _box(0.4, 0.18, 0.3), hair_mat, Vector3(0.0, 1.9, 0.04))
	elif npc_name == "Officer Chen":
		# Hat-like block
		var hat_mat := _make_simple(Color(0.12, 0.14, 0.22, 1.0), 0.45, 0.1)
		_add_part(_visual_root, _box(0.5, 0.14, 0.42), hat_mat, Vector3(0.0, 1.95, 0.0))
		_add_part(_visual_root, _box(0.58, 0.04, 0.5), hat_mat, Vector3(0.0, 1.87, 0.02))
	else:
		_add_part(_visual_root, _box(0.42, 0.22, 0.3), hair_mat, Vector3(0.0, 1.9, 0.02))
		_add_part(_visual_root, _prism(0.36, 0.12, 0.08), hair_mat, Vector3(0.0, 1.96, -0.2))


func _build_accessory(trim_mat: StandardMaterial3D, skin_mat: StandardMaterial3D) -> void:
	if npc_name == "Marcus":
		# Glasses bar and a glowing tablet
		var tablet_mat := _make_emissive(Color(0.35, 0.85, 1.0, 1.0), 1.6)
		_add_part(_visual_root, _box(0.22, 0.015, 0.02), trim_mat, Vector3(0.0, 1.81, -0.25))
		_add_part(_visual_root, _box(0.18, 0.22, 0.015), tablet_mat, Vector3(-0.42, 0.92, -0.04))
	elif npc_name == "Officer Chen":
		# Badge on chest
		var badge_mat := _make_emissive(Color(1.0, 0.85, 0.25, 1.0), 1.4)
		_add_part(_visual_root, _box(0.08, 0.1, 0.02), badge_mat, Vector3(-0.14, 1.28, -0.3))
	elif npc_name == "Lily":
		# Flower tucked behind ear
		var flower_mat := _make_emissive(Color(1.0, 0.55, 0.75, 1.0), 0.8)
		_add_part(_visual_root, _sphere(0.06, 0.12), flower_mat, Vector3(-0.22, 1.84, -0.06))
	elif npc_name == "Tommy":
		# Toy — a small orbiting sparklet-like sphere on a string
		var toy_mat := _make_emissive(Color(0.5, 1.0, 0.8, 1.0), 1.6)
		_add_part(_visual_root, _sphere(0.07, 0.14), toy_mat, Vector3(0.42, 0.65, -0.2))


func _add_part(parent: Node3D, mesh: Mesh, mat: StandardMaterial3D, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.set_surface_override_material(0, mat)
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)


func _box(x: float, y: float, z: float) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(x, y, z)
	return m


func _sphere(r: float, h: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 20
	m.rings = 12
	return m


func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 14
	m.rings = 8
	return m


func _prism(x: float, y: float, z: float) -> PrismMesh:
	var m := PrismMesh.new()
	m.size = Vector3(x, y, z)
	return m


func _make_skin(c: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = 0.55
	mat.metallic_specular = 0.5
	mat.rim_enabled = true
	mat.rim = 0.5
	mat.rim_tint = 0.75
	return mat


func _make_clothes(c: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = 0.45
	mat.metallic = 0.08
	mat.metallic_specular = 0.6
	mat.rim_enabled = true
	mat.rim = 0.55
	mat.rim_tint = 0.8
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.2
	mat.clearcoat_roughness = 0.5
	return mat


func _make_pants(c: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = 0.65
	mat.metallic_specular = 0.4
	mat.rim_enabled = true
	mat.rim = 0.35
	mat.rim_tint = 0.55
	return mat


func _make_hair(c: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = 0.5
	mat.metallic = 0.1
	mat.anisotropy_enabled = true
	mat.anisotropy = 0.6
	mat.rim_enabled = true
	mat.rim = 0.5
	mat.rim_tint = 0.85
	return mat


func _make_simple(c: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = roughness
	mat.metallic = metallic
	return mat


func _make_emissive(c: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.roughness = 0.25
	mat.metallic = 0.3
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = energy
	mat.rim_enabled = true
	mat.rim = 0.6
	return mat


# ---- Prompt label ----

func _build_prompt_label() -> void:
	_prompt_label = Label3D.new()
	_prompt_label.text = "[E] Talk to %s" % npc_name
	_prompt_label.position = Vector3(0.0, 2.2, 0.0)
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.pixel_size = 0.005
	_prompt_label.modulate = Color(0.9, 0.95, 1.0, 0.88)
	_prompt_label.outline_size = 4
	_prompt_label.visible = false
	add_child(_prompt_label)


# ---- Dialogue UI ----

func _build_dialogue_ui() -> void:
	_dialogue_canvas = CanvasLayer.new()
	_dialogue_canvas.layer = 8
	_dialogue_canvas.visible = false
	add_child(_dialogue_canvas)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue_canvas.add_child(root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.25)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -155.0
	panel.offset_left = 60.0
	panel.offset_right = -60.0
	panel.offset_bottom = -18.0

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.07, 0.13, 0.94)
	panel_style.border_color = Color(0.22, 0.38, 0.68, 0.72)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(10)
	panel_style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", panel_style)
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 19)
	_name_label.add_theme_color_override("font_color", Color(0.55, 0.82, 0.95, 1.0))
	vbox.add_child(_name_label)

	_dialogue_text_label = Label.new()
	_dialogue_text_label.add_theme_font_size_override("font_size", 16)
	_dialogue_text_label.add_theme_color_override("font_color", Color(0.85, 0.88, 0.94, 1.0))
	_dialogue_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_dialogue_text_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 4.0)
	vbox.add_child(spacer)

	_hint_label = Label.new()
	_hint_label.text = "[E] Continue"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.add_theme_font_size_override("font_size", 13)
	_hint_label.add_theme_color_override("font_color", Color(0.48, 0.52, 0.62, 0.55))
	vbox.add_child(_hint_label)
