extends Node3D

signal echo_collected(echo_id: String, data: Dictionary)

const ECHO_DATA_PATH := "res://data/echoes/echoes.json"
const INTERACT_RADIUS := 1.9

static var _echo_cache: Dictionary = {}

@export var echo_id := "echo_park_01"
@export var hover_height := 0.2
@export var visual_color := Color(0.55, 0.85, 1.0, 1.0)

var _player_in_range := false
var _collected := false
var _prompt: Label3D
var _crystal: MeshInstance3D
var _glow_light: OmniLight3D
var _halo: MeshInstance3D
var _time := 0.0
var _reveal_canvas: CanvasLayer
var _reveal_label_title: Label
var _reveal_label_body: Label
var _reveal_label_hint: Label


func _ready() -> void:
	_build_visual()
	_build_prompt()
	_build_reveal_ui()
	_load_echo_cache()


func _process(delta: float) -> void:
	_time += delta
	if _crystal:
		_crystal.rotation.y += delta * 0.9
		_crystal.position.y = hover_height + sin(_time * 2.2) * 0.08
	if _halo:
		_halo.rotation.y -= delta * 0.6

	if _collected:
		return

	var player := _find_player()
	if player == null:
		_player_in_range = false
		_prompt.visible = false
		return
	var distance := global_position.distance_to(player.global_position)
	_player_in_range = distance <= INTERACT_RADIUS
	_prompt.visible = _player_in_range


func _unhandled_input(event: InputEvent) -> void:
	if _collected:
		return
	if not _player_in_range:
		return
	if event.is_action_pressed("interact"):
		_collect()
		get_viewport().set_input_as_handled()


func _collect() -> void:
	if _collected:
		return
	_collected = true
	_prompt.visible = false

	var data: Dictionary = _get_echo_data(echo_id)
	_show_reveal(data)

	var qm: Node = get_node_or_null("/root/QuestManager")
	if qm != null and qm.has_method("report_event"):
		qm.call("report_event", "echo_collected", echo_id, {"data": data})

	var bond: Node = get_node_or_null("/root/BondManager")
	if bond != null and bond.has_method("add_bond"):
		bond.call("add_bond", "Dino Buddy", 2, "echo_shared")

	var tween := create_tween()
	tween.set_parallel(true)
	if _crystal:
		tween.tween_property(_crystal, "scale", Vector3(0.0, 0.0, 0.0), 0.6).set_ease(Tween.EASE_IN)
	if _glow_light:
		tween.tween_property(_glow_light, "light_energy", 0.0, 0.6)

	emit_signal("echo_collected", echo_id, data)


func is_collected() -> bool:
	return _collected


func mark_collected_from_save() -> void:
	_collected = true
	if _crystal:
		_crystal.visible = false
	if _halo:
		_halo.visible = false
	if _glow_light:
		_glow_light.visible = false
	if _prompt:
		_prompt.visible = false


func _show_reveal(data: Dictionary) -> void:
	if _reveal_canvas == null:
		return
	_reveal_canvas.visible = true
	_reveal_label_title.text = "Echo Recovered — %s" % String(data.get("title", echo_id))
	var speaker := String(data.get("speaker", ""))
	var body := String(data.get("text", ""))
	if speaker != "":
		_reveal_label_body.text = "“%s”\n\n— %s" % [body, speaker]
	else:
		_reveal_label_body.text = "“%s”" % body
	_reveal_label_hint.text = "[E] Continue"

	var player := _find_player()
	if player and player.has_method("set_controls_enabled"):
		player.call("set_controls_enabled", false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_reveal() -> void:
	if _reveal_canvas == null:
		return
	_reveal_canvas.visible = false
	var player := _find_player()
	if player and player.has_method("set_controls_enabled"):
		player.call("set_controls_enabled", true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var delay := get_tree().create_timer(0.7)
	delay.timeout.connect(queue_free)


func _find_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Node3D


# ---- Visual construction ----

func _build_visual() -> void:
	var crystal_mesh := PrismMesh.new()
	crystal_mesh.size = Vector3(0.28, 0.55, 0.28)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(visual_color.r, visual_color.g, visual_color.b, 0.72)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = visual_color
	mat.emission_energy_multiplier = 2.4
	mat.metallic = 0.4
	mat.roughness = 0.2

	_crystal = MeshInstance3D.new()
	_crystal.mesh = crystal_mesh
	_crystal.set_surface_override_material(0, mat)
	_crystal.position = Vector3(0.0, hover_height, 0.0)
	add_child(_crystal)

	# Halo ring
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(visual_color.r, visual_color.g, visual_color.b, 0.22)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.emission_enabled = true
	ring_mat.emission = visual_color
	ring_mat.emission_energy_multiplier = 1.2

	var torus := TorusMesh.new()
	torus.inner_radius = 0.32
	torus.outer_radius = 0.44
	torus.rings = 24
	torus.ring_segments = 18
	_halo = MeshInstance3D.new()
	_halo.mesh = torus
	_halo.set_surface_override_material(0, ring_mat)
	_halo.position = Vector3(0.0, 0.05, 0.0)
	_halo.rotation.x = PI * 0.5
	add_child(_halo)

	_glow_light = OmniLight3D.new()
	_glow_light.light_color = visual_color
	_glow_light.light_energy = 2.6
	_glow_light.omni_range = 4.5
	_glow_light.position = Vector3(0.0, 0.4, 0.0)
	add_child(_glow_light)


func _build_prompt() -> void:
	_prompt = Label3D.new()
	_prompt.text = "[E] Collect Echo Shard"
	_prompt.position = Vector3(0.0, 1.05, 0.0)
	_prompt.pixel_size = 0.005
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.modulate = Color(0.92, 0.98, 1.0, 0.9)
	_prompt.outline_size = 4
	_prompt.visible = false
	add_child(_prompt)


func _build_reveal_ui() -> void:
	_reveal_canvas = CanvasLayer.new()
	_reveal_canvas.layer = 12
	_reveal_canvas.visible = false
	add_child(_reveal_canvas)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_reveal_canvas.add_child(root)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.03, 0.06, 0.78)
	root.add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-360.0, -160.0)
	panel.custom_minimum_size = Vector2(720.0, 320.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.08, 0.16, 0.96)
	sb.border_color = Color(0.4, 0.75, 1.0, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)

	_reveal_label_title = Label.new()
	_reveal_label_title.add_theme_font_size_override("font_size", 22)
	_reveal_label_title.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0, 1.0))
	v.add_child(_reveal_label_title)

	_reveal_label_body = Label.new()
	_reveal_label_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reveal_label_body.add_theme_font_size_override("font_size", 17)
	_reveal_label_body.add_theme_color_override("font_color", Color(0.88, 0.92, 1.0, 1.0))
	v.add_child(_reveal_label_body)

	_reveal_label_hint = Label.new()
	_reveal_label_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_reveal_label_hint.add_theme_font_size_override("font_size", 13)
	_reveal_label_hint.add_theme_color_override("font_color", Color(0.45, 0.55, 0.7, 0.85))
	v.add_child(_reveal_label_hint)

	# Input handling — close on E or Space.
	set_process_input(true)


func _input(event: InputEvent) -> void:
	if _reveal_canvas == null or not _reveal_canvas.visible:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("jump") or event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close_reveal()


# ---- Data cache ----

static func get_echo_data_static(echo_id: String) -> Dictionary:
	_load_echo_cache_static()
	var map: Dictionary = _echo_cache.get("echoes", {})
	if map.has(echo_id):
		return (map[echo_id] as Dictionary).duplicate(true)
	return {"title": echo_id, "text": "", "speaker": ""}


static func list_all_echo_ids() -> Array:
	_load_echo_cache_static()
	var map: Dictionary = _echo_cache.get("echoes", {})
	var ids: Array = []
	for k: Variant in map.keys():
		ids.append(String(k))
	ids.sort()
	return ids


func _get_echo_data(id: String) -> Dictionary:
	return get_echo_data_static(id)


func _load_echo_cache() -> void:
	_load_echo_cache_static()


static func _load_echo_cache_static() -> void:
	if not _echo_cache.is_empty():
		return
	if not FileAccess.file_exists(ECHO_DATA_PATH):
		_echo_cache = {"echoes": {}}
		return
	var file := FileAccess.open(ECHO_DATA_PATH, FileAccess.READ)
	if file == null:
		_echo_cache = {"echoes": {}}
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		_echo_cache = parsed as Dictionary
	else:
		_echo_cache = {"echoes": {}}
