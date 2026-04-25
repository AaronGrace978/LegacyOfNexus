extends Node3D

signal spring_used(spring_id: String)

@export var spring_id := "greenbelt_spring"
@export var interact_radius := 2.6

var _player_in_range := false
var _prompt: Label3D
var _ring: MeshInstance3D
var _pillar_lights: Array[OmniLight3D] = []
var _time := 0.0
var _cooldown_left := 0.0
var _discovered := false


func _ready() -> void:
	_build_visual()
	_build_prompt()


func _process(delta: float) -> void:
	_time += delta
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)

	if _ring:
		_ring.rotation.y += delta * 0.35
	for i in range(_pillar_lights.size()):
		var light: OmniLight3D = _pillar_lights[i]
		if light == null:
			continue
		var pulse: float = 1.3 + sin(_time * 1.4 + i * 0.8) * 0.4
		light.light_energy = pulse

	var player := _find_player()
	if player == null:
		_player_in_range = false
		_prompt.visible = false
		return
	var distance := global_position.distance_to(player.global_position)
	_player_in_range = distance <= interact_radius

	if _player_in_range and not _discovered:
		_discovered = true
		var qm: Node = get_node_or_null("/root/QuestManager")
		if qm != null and qm.has_method("report_event"):
			qm.call("report_event", "spring_discovered", spring_id, {})

	_prompt.visible = _player_in_range
	if _player_in_range:
		_prompt.text = _current_prompt_text()


func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_range:
		return
	if event.is_action_pressed("interact"):
		_try_use()
		get_viewport().set_input_as_handled()


func _try_use() -> void:
	if _cooldown_left > 0.0:
		_notify("The spring is still settling… (%.0fs)" % _cooldown_left, 1.6)
		return

	var party_manager: Node = get_node_or_null("/root/PartyManager")
	if party_manager == null:
		return

	var restored := _restore_party_full_hp(party_manager)
	if restored == 0:
		_notify("Your party is already at full strength.", 2.0)
		return

	_cooldown_left = 3.0
	var bond: Node = get_node_or_null("/root/BondManager")
	if bond != null and bond.has_method("add_bond_all"):
		bond.call("add_bond_all", 1, "spring_rest")

	var qm: Node = get_node_or_null("/root/QuestManager")
	if qm != null and qm.has_method("report_event"):
		qm.call("report_event", "spring_used", spring_id, {})

	emit_signal("spring_used", spring_id)
	_notify("Data Spring resonates… %d buddies restored." % restored, 2.4)
	_spawn_burst()


func _restore_party_full_hp(party_manager: Node) -> int:
	var restored := 0
	if not party_manager.has_method("get_party_snapshot"):
		return 0
	var snapshot: Array = party_manager.call("get_party_snapshot")
	for member: Variant in snapshot:
		if member == null:
			continue
		if member.current_health < member.max_health:
			restored += 1
			member.current_health = member.max_health

	if party_manager.has_method("save_party_snapshot"):
		var active_idx: int = 1
		if party_manager.has_method("get_active_battle_partner_index"):
			active_idx = int(party_manager.call("get_active_battle_partner_index"))
		party_manager.call("save_party_snapshot", snapshot, active_idx)
	return restored


func _current_prompt_text() -> String:
	if _cooldown_left > 0.0:
		return "Data Spring cooling down (%.0fs)" % _cooldown_left
	return "[E] Rest at Data Spring"


func _spawn_burst() -> void:
	var burst := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.5
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 35.0
	pm.initial_velocity_min = 1.4
	pm.initial_velocity_max = 2.8
	pm.gravity = Vector3(0.0, -0.8, 0.0)
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	pm.color = Color(0.55, 0.95, 1.0, 0.9)

	var sphere := SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.1
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.55, 0.95, 1.0, 0.9)
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.emission_enabled = true
	glow.emission = Color(0.4, 0.85, 1.0, 1.0)
	glow.emission_energy_multiplier = 3.0
	glow.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sphere.material = glow

	burst.amount = 80
	burst.lifetime = 1.5
	burst.one_shot = true
	burst.explosiveness = 0.9
	burst.process_material = pm
	burst.draw_pass_1 = sphere
	burst.material_override = glow
	burst.position = Vector3(0.0, 0.8, 0.0)
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(burst)
	burst.emitting = true
	var delay := get_tree().create_timer(2.5)
	delay.timeout.connect(burst.queue_free)


func _notify(text: String, duration: float = 2.0) -> void:
	var overworld: Node = get_parent()
	if overworld == null:
		return
	var hud: Node = overworld.get_node_or_null("ExplorationHUD")
	if hud != null and hud.has_method("push_notification"):
		hud.call("push_notification", text, duration)


# ---- Visual ----

func _build_visual() -> void:
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.12, 0.2, 0.3, 1.0)
	base_mat.roughness = 0.45
	base_mat.metallic = 0.6

	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 1.2
	base_mesh.bottom_radius = 1.45
	base_mesh.height = 0.3
	base.mesh = base_mesh
	base.set_surface_override_material(0, base_mat)
	base.position = Vector3(0.0, 0.15, 0.0)
	add_child(base)

	# Glowing ring
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 1.0
	ring_mesh.outer_radius = 1.2
	ring_mesh.rings = 48
	ring_mesh.ring_segments = 24

	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.3, 0.8, 1.0, 0.9)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.3, 0.85, 1.0, 1.0)
	ring_mat.emission_energy_multiplier = 2.5
	ring_mat.metallic = 0.3
	ring_mat.roughness = 0.2

	_ring = MeshInstance3D.new()
	_ring.mesh = ring_mesh
	_ring.set_surface_override_material(0, ring_mat)
	_ring.position = Vector3(0.0, 0.35, 0.0)
	_ring.rotation.x = PI * 0.5
	add_child(_ring)

	# Three glowing pillars
	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = Color(0.18, 0.45, 0.7, 1.0)
	pillar_mat.emission_enabled = true
	pillar_mat.emission = Color(0.35, 0.82, 1.0, 1.0)
	pillar_mat.emission_energy_multiplier = 1.6
	pillar_mat.metallic = 0.6
	pillar_mat.roughness = 0.3

	var radius := 0.82
	for i in range(3):
		var angle := (TAU / 3.0) * float(i)
		var pos := Vector3(cos(angle) * radius, 0.8, sin(angle) * radius)
		var pillar := MeshInstance3D.new()
		var pillar_mesh := CapsuleMesh.new()
		pillar_mesh.radius = 0.12
		pillar_mesh.height = 1.4
		pillar.mesh = pillar_mesh
		pillar.set_surface_override_material(0, pillar_mat)
		pillar.position = pos
		add_child(pillar)

		var light := OmniLight3D.new()
		light.light_color = Color(0.4, 0.82, 1.0, 1.0)
		light.light_energy = 1.8
		light.omni_range = 5.0
		light.position = pos + Vector3(0.0, 0.3, 0.0)
		add_child(light)
		_pillar_lights.append(light)

	# Central beam
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.08
	beam_mesh.bottom_radius = 0.16
	beam_mesh.height = 2.4

	var beam_mat := StandardMaterial3D.new()
	beam_mat.albedo_color = Color(0.65, 0.95, 1.0, 0.55)
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.emission_enabled = true
	beam_mat.emission = Color(0.55, 0.95, 1.0, 1.0)
	beam_mat.emission_energy_multiplier = 3.5
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var beam := MeshInstance3D.new()
	beam.mesh = beam_mesh
	beam.set_surface_override_material(0, beam_mat)
	beam.position = Vector3(0.0, 1.5, 0.0)
	add_child(beam)


func _build_prompt() -> void:
	_prompt = Label3D.new()
	_prompt.text = "[E] Rest at Data Spring"
	_prompt.position = Vector3(0.0, 3.1, 0.0)
	_prompt.pixel_size = 0.005
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.modulate = Color(0.85, 0.96, 1.0, 0.92)
	_prompt.outline_size = 4
	_prompt.visible = false
	add_child(_prompt)


func _find_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Node3D
