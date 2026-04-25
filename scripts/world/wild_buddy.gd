extends Node3D

const BuddyCatalog := preload("res://scripts/buddies/buddy_catalog.gd")
const BuddyVisualCatalog := preload("res://scripts/buddies/buddy_visual_catalog.gd")

signal capture_requested(wild_buddy: Node3D, buddy_name: String)

@export var buddy_name := "Sparklet"
@export var interact_radius := 2.6
@export var auto_battle_radius := 5.5
@export var encounter_level := 3
@export var rear_encounter_buddy_name := ""
@export var rear_encounter_level := 1

@onready var model_holder: Node3D = $ModelHolder
@onready var prompt_label: Label3D = $PromptLabel

var player_in_range := false


func _ready() -> void:
	_spawn_visual_model()
	prompt_label.text = "Approach to battle | E: Capture %s" % buddy_name
	prompt_label.visible = false


func _process(_delta: float) -> void:
	var player := _find_player()
	if player == null:
		player_in_range = false
		prompt_label.visible = false
		return

	var distance := global_position.distance_to(player.global_position)
	player_in_range = distance <= interact_radius
	prompt_label.visible = player_in_range


func _unhandled_input(event: InputEvent) -> void:
	if not player_in_range:
		return

	if event.is_action_pressed("interact"):
		emit_signal("capture_requested", self, buddy_name)
		get_viewport().set_input_as_handled()


func _find_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Node3D


func _spawn_visual_model() -> void:
	for index in range(model_holder.get_child_count() - 1, -1, -1):
		model_holder.get_child(index).free()

	var scene: PackedScene = BuddyVisualCatalog.resolve_battle_visual(buddy_name)
	if scene == null:
		return

	var model := scene.instantiate() as Node3D
	var palette: Dictionary = BuddyCatalog.get_palette(buddy_name)
	_apply_palette(model, palette["primary"], palette["accent"], true)
	model_holder.add_child(model)


func _apply_palette(root: Node, primary: Color, accent: Color, wild_boost: bool) -> void:
	for child in root.get_children():
		_apply_palette(child, primary, accent, wild_boost)

	if root is MeshInstance3D:
		var mesh_node := root as MeshInstance3D
		if mesh_node.is_in_group("buddy_palette_primary"):
			mesh_node.set_surface_override_material(0, _build_primary_material(primary, wild_boost))
		elif mesh_node.is_in_group("buddy_palette_accent"):
			mesh_node.set_surface_override_material(0, _build_accent_material(accent, wild_boost))


func _build_primary_material(primary: Color, wild_boost: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = primary
	mat.roughness = 0.38
	mat.metallic = 0.1
	mat.metallic_specular = 0.65
	# Stylized rim gives the toon-ish halo on silhouette edges.
	mat.rim_enabled = true
	mat.rim = 0.65
	mat.rim_tint = 0.75
	# Subtle clearcoat adds a soft gloss pass on the surface.
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.35
	mat.clearcoat_roughness = 0.4
	mat.emission_enabled = true
	mat.emission = primary * (0.45 if wild_boost else 0.22)
	mat.emission_energy_multiplier = 0.85 if wild_boost else 0.45
	return mat


func _build_accent_material(accent: Color, wild_boost: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = accent
	mat.roughness = 0.22
	mat.metallic = 0.35
	mat.metallic_specular = 0.85
	mat.rim_enabled = true
	mat.rim = 0.8
	mat.rim_tint = 0.85
	mat.emission_enabled = true
	mat.emission = accent * (1.25 if wild_boost else 0.7)
	mat.emission_energy_multiplier = 1.6 if wild_boost else 0.95
	# Light anisotropy gives accent parts a "glowing wire" look under motion.
	mat.anisotropy_enabled = true
	mat.anisotropy = 0.35
	return mat
