class_name BattleUnit
extends Node3D

const BuddyVisualCatalog := preload("res://scripts/buddies/buddy_visual_catalog.gd")
const BattleMoveCatalog := preload("res://scripts/battle/battle_move_catalog.gd")
const BATTLE_IDLE_ANIMS: Array[StringName] = [&"BattleIdle", &"CharacterArmature|Idle", &"Idle", &"CharacterArmature|Weapon", &"Weapon"]
const BATTLE_ATTACK_ANIMS: Array[StringName] = [&"Attack", &"CharacterArmature|Punch", &"Punch", &"CharacterArmature|Weapon", &"Weapon"]
const BATTLE_VICTORY_ANIMS: Array[StringName] = [&"Victory", &"CharacterArmature|Wave", &"Wave", &"CharacterArmature|Yes", &"Yes"]
const QUATERNIUS_BATTLE_SCALE := Vector3(0.34, 0.34, 0.34)

signal attack_hit(attacker: BattleUnit, target: BattleUnit)
signal attack_finished(attacker: BattleUnit)
signal defeated(unit: BattleUnit)
signal clicked(unit: BattleUnit)
signal health_changed(unit: BattleUnit, current_health: int, max_health: int)

@export var unit_name := "Buddy"
@export var max_health := 24
@export var attack_power := 5
@export var primary_color := Color(1.0, 1.0, 1.0, 1.0)
@export var accent_color := Color(0.9, 0.9, 0.9, 1.0)
@export var idle_bob_height := 0.08
@export var idle_bob_speed := 2.3

@onready var pivot: Node3D = $Pivot
@onready var visual_slot: Node3D = $Pivot/VisualSlot
@onready var name_label: Label3D = $Pivot/NameLabel
@onready var health_label: Label3D = $Pivot/HealthLabel
@onready var capture_ready_label: Label3D = $Pivot/CaptureReadyLabel
@onready var collision_area: Area3D = $CollisionArea
@onready var selection_ring: MeshInstance3D = $SelectionRing
@onready var shadow_disc: MeshInstance3D = $ShadowDisc
@onready var health_fill: MeshInstance3D = $Pivot/HealthBarRoot/HealthBarFill
@onready var health_back: MeshInstance3D = $Pivot/HealthBarRoot/HealthBarBack

var current_health := 0
var bob_time := 0.0
var is_animating := false
var health_bar_width := 1.2

## Next player-side attack damage multiplier (e.g. Loyal Roar); consumed when damage is dealt.
var next_attack_damage_multiplier := 1.0
## When true, this unit skips its next action (simple paralyze).
var paralyzed := false
## When true, this unit can be pulled into Resonance Sync.
var capture_ready := false

var _tail_pivot: Node3D
var _wing_pivot_l: Node3D
var _wing_pivot_r: Node3D

var _battle_anim_player: AnimationPlayer
var _battle_victory_pose := false


func _ready() -> void:
	if current_health <= 0:
		current_health = max_health
	collision_area.input_ray_pickable = true
	collision_area.input_event.connect(_on_collision_input_event)
	_apply_config_to_visuals()
	set_target_highlight(false)


func _process(delta: float) -> void:
	if _battle_anim_player != null and not is_animating and not _battle_victory_pose:
		_ensure_battle_idle_animation()

	if is_animating:
		return

	if _battle_anim_player != null:
		return

	bob_time += delta * idle_bob_speed
	pivot.position.y = 0.05 + sin(bob_time) * idle_bob_height

	if _tail_pivot != null:
		_tail_pivot.rotation.z = sin(bob_time * 2.35) * 0.38

	if _wing_pivot_l != null and _wing_pivot_r != null:
		var flap := sin(bob_time * 2.9) * 0.35
		_wing_pivot_l.rotation.z = flap
		_wing_pivot_r.rotation.z = -flap


func configure(
	display_name: String,
	health: int,
	current_hp: int,
	power: int,
	body_tint: Color,
	head_tint: Color
) -> void:
	unit_name = display_name
	max_health = health
	current_health = clamp(current_hp, 0, health)
	attack_power = power
	primary_color = body_tint
	accent_color = head_tint
	is_animating = false
	if _can_apply_visual_config():
		_apply_config_to_visuals()

	if is_inside_tree():
		emit_signal("health_changed", self, current_health, max_health)


func perform_attack(target_position: Vector3, target: BattleUnit) -> void:
	if current_health <= 0 or is_animating:
		emit_signal("attack_finished", self)
		return

	is_animating = true
	_play_skinned_animation(BATTLE_ATTACK_ANIMS, 0.07)
	var start_position: Vector3 = global_position
	var to_target := (target_position - start_position)
	to_target.y = 0.0
	var forward := to_target.normalized() if to_target.length_squared() > 0.0001 else -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.0001:
		forward = forward.normalized()
	else:
		forward = Vector3(0, 0, 1)
	var windup := start_position - forward * 0.32
	var strike_position: Vector3 = start_position.lerp(target_position, 0.48)
	strike_position.y = start_position.y
	windup.y = start_position.y

	var tween: Tween = create_tween()
	tween.tween_property(self, "global_position", windup, 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", strike_position, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_callback(Callable(self, "_emit_attack_hit").bind(target))
	tween.tween_property(self, "global_position", start_position, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished

	_play_skinned_animation(BATTLE_IDLE_ANIMS, 0.12)
	is_animating = false
	emit_signal("attack_finished", self)


func take_damage(amount: int) -> void:
	if current_health <= 0:
		return

	current_health = max(current_health - amount, 0)
	_update_labels()
	emit_signal("health_changed", self, current_health, max_health)

	var original_scale: Vector3 = pivot.scale
	var tween: Tween = create_tween()
	tween.tween_property(pivot, "scale", original_scale * 1.12, 0.06).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(pivot, "scale", original_scale, 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	if current_health <= 0:
		emit_signal("defeated", self)


func heal(amount: int) -> int:
	if current_health <= 0:
		return 0

	var healed_amount: int = maxi(0, min(max_health - current_health, amount))
	if healed_amount <= 0:
		return 0

	current_health += healed_amount
	_update_labels()
	emit_signal("health_changed", self, current_health, max_health)
	return healed_amount


## Bring a defeated unit back with the given HP (used by items / future skills).
func revive_with_health(hit_points: int) -> void:
	if hit_points <= 0:
		return
	if current_health > 0:
		return

	current_health = clampi(hit_points, 1, max_health)
	_battle_victory_pose = false
	is_animating = false
	_update_labels()
	emit_signal("health_changed", self, current_health, max_health)


func is_defeated() -> bool:
	return current_health <= 0


func get_health_ratio() -> float:
	return float(current_health) / float(maxi(max_health, 1))


func set_capture_ready(value: bool) -> void:
	capture_ready = value and not is_defeated()
	_update_labels()


func is_capture_ready() -> bool:
	return capture_ready and not is_defeated()


func get_move_entries() -> Array:
	return BattleMoveCatalog.get_entries_for_unit(unit_name)


func grant_next_attack_damage_buff(multiplier: float) -> void:
	next_attack_damage_multiplier = maxf(next_attack_damage_multiplier, multiplier)


func take_next_attack_damage_multiplier() -> float:
	var mult: float = next_attack_damage_multiplier
	next_attack_damage_multiplier = 1.0
	return mult


func peek_next_attack_damage_multiplier() -> float:
	return next_attack_damage_multiplier


func set_paralyzed(value: bool) -> void:
	paralyzed = value
	_update_labels()


func consume_paralyze_skip() -> bool:
	if not paralyzed:
		return false
	paralyzed = false
	_update_labels()
	return true


func is_paralyzed() -> bool:
	return paralyzed


func set_target_highlight(enabled: bool) -> void:
	selection_ring.visible = enabled and not is_defeated()


func flash_target_selection() -> void:
	if is_defeated():
		return

	var tween: Tween = create_tween()
	tween.tween_property(selection_ring, "scale", Vector3(1.15, 1.0, 1.15), 0.12)
	tween.tween_property(selection_ring, "scale", Vector3.ONE, 0.12)


func get_hit_position() -> Vector3:
	return global_position + Vector3.UP * 1.0


func set_facing_direction(direction: Vector3) -> void:
	var flat_direction: Vector3 = direction
	flat_direction.y = 0.0
	if flat_direction.length_squared() <= 0.001:
		return

	rotation.y = atan2(flat_direction.x, flat_direction.z)


func play_battle_victory() -> void:
	if _battle_anim_player == null:
		return
	var victory_anim := _resolve_anim_name(BATTLE_VICTORY_ANIMS)
	if victory_anim.is_empty():
		return
	_battle_victory_pose = true
	_battle_anim_player.play(victory_anim, 0.12)


func _emit_attack_hit(target: BattleUnit) -> void:
	emit_signal("attack_hit", self, target)


func _can_apply_visual_config() -> bool:
	return pivot != null and visual_slot != null and name_label != null and health_label != null and capture_ready_label != null and health_fill != null and health_back != null


func _apply_config_to_visuals() -> void:
	if not _can_apply_visual_config():
		return

	pivot.scale = Vector3.ONE
	pivot.position.y = 0.05
	_rebuild_visual_model(unit_name)
	_apply_materials()
	_update_labels()


func _rebuild_visual_model(display_name: String) -> void:
	for index in range(visual_slot.get_child_count() - 1, -1, -1):
		visual_slot.get_child(index).queue_free()

	var scene: PackedScene = BuddyVisualCatalog.resolve_battle_visual(display_name)
	if scene == null:
		_tail_pivot = null
		_wing_pivot_l = null
		_wing_pivot_r = null
		_battle_anim_player = null
		_battle_victory_pose = false
		return

	var model_root := scene.instantiate() as Node3D
	_apply_model_presentation(model_root, display_name)
	_apply_palette_to_visual_subtree(model_root)
	visual_slot.add_child(model_root)

	_tail_pivot = visual_slot.find_child("TailPivot", true, false) as Node3D
	_wing_pivot_l = visual_slot.find_child("WingPivotL", true, false) as Node3D
	_wing_pivot_r = visual_slot.find_child("WingPivotR", true, false) as Node3D

	_battle_anim_player = _find_first_animation_player(visual_slot)
	_battle_victory_pose = false
	if _battle_anim_player != null:
		_ensure_battle_idle_animation()


func _apply_materials() -> void:
	_apply_palette_to_visual_subtree(visual_slot)

	var ring_material := StandardMaterial3D.new()
	ring_material.albedo_color = Color(1.0, 0.92549, 0.447059, 1.0)
	ring_material.emission_enabled = true
	ring_material.emission = Color(1.0, 0.92549, 0.447059, 1.0)
	ring_material.emission_energy_multiplier = 0.22
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.albedo_color.a = 0.24
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	selection_ring.material_override = ring_material

	var shadow_material := StandardMaterial3D.new()
	shadow_material.albedo_color = Color(0.02, 0.03, 0.05, 0.28)
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if shadow_disc != null:
		shadow_disc.material_override = shadow_material

	var health_back_material := StandardMaterial3D.new()
	health_back_material.albedo_color = Color(0.06, 0.08, 0.10, 1.0)
	health_back_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	health_back.material_override = health_back_material

	var health_fill_material := StandardMaterial3D.new()
	health_fill_material.albedo_color = primary_color.lightened(0.2)
	health_fill_material.emission_enabled = true
	health_fill_material.emission = primary_color * 0.5
	health_fill_material.emission_energy_multiplier = 0.14
	health_fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	health_fill.material_override = health_fill_material

	name_label.modulate = Color(0.95, 0.98, 1.0, 1.0)
	name_label.outline_modulate = Color(0.05, 0.08, 0.12, 1.0)
	name_label.font_size = 28
	health_label.modulate = Color(0.84, 0.90, 0.96, 0.96)
	health_label.outline_modulate = Color(0.05, 0.08, 0.12, 1.0)
	health_label.font_size = 22
	capture_ready_label.modulate = accent_color.lightened(0.28)
	capture_ready_label.outline_modulate = Color(0.04, 0.05, 0.08, 1.0)
	capture_ready_label.font_size = 24


func _apply_palette_to_visual_subtree(root: Node) -> void:
	if root == null:
		return

	for child in root.get_children():
		_apply_palette_to_visual_subtree(child)

	if root is MeshInstance3D:
		var mesh_node := root as MeshInstance3D
		if mesh_node.mesh == null:
			return
		if mesh_node.is_in_group("buddy_palette_primary"):
			var body_material := StandardMaterial3D.new()
			body_material.albedo_color = primary_color
			body_material.roughness = 0.38
			body_material.metallic = 0.1
			body_material.metallic_specular = 0.65
			body_material.rim_enabled = true
			body_material.rim = 0.65
			body_material.rim_tint = 0.8
			body_material.clearcoat_enabled = true
			body_material.clearcoat = 0.3
			body_material.clearcoat_roughness = 0.45
			body_material.emission_enabled = true
			body_material.emission = primary_color * 0.28
			body_material.emission_energy_multiplier = 0.55
			mesh_node.material_override = body_material
		elif mesh_node.is_in_group("buddy_palette_accent"):
			var accent_material := StandardMaterial3D.new()
			accent_material.albedo_color = accent_color
			accent_material.roughness = 0.22
			accent_material.metallic = 0.3
			accent_material.metallic_specular = 0.85
			accent_material.rim_enabled = true
			accent_material.rim = 0.8
			accent_material.rim_tint = 0.85
			accent_material.emission_enabled = true
			accent_material.emission = accent_color * 0.9
			accent_material.emission_energy_multiplier = 1.2
			accent_material.anisotropy_enabled = true
			accent_material.anisotropy = 0.3
			mesh_node.material_override = accent_material
		else:
			_apply_imported_palette(mesh_node)


func _update_labels() -> void:
	if current_health <= 0:
		name_label.text = "%s Down" % unit_name
	else:
		var status_suffix := " [Paralyzed]" if paralyzed else ""
		name_label.text = "%s%s" % [unit_name, status_suffix]
	health_label.text = "HP %d/%d" % [current_health, max_health]
	capture_ready_label.visible = is_capture_ready()
	var health_ratio: float = float(current_health) / float(max(max_health, 1))
	health_fill.scale.x = max(health_ratio, 0.001)
	health_fill.position.x = -((1.0 - health_fill.scale.x) * health_bar_width * 0.5)
	selection_ring.visible = selection_ring.visible and not is_defeated()
	if shadow_disc != null:
		shadow_disc.visible = not is_defeated()


func _on_collision_input_event(
	_camera: Node,
	event: InputEvent,
	_event_position: Vector3,
	_normal: Vector3,
	_shape_idx: int
) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		emit_signal("clicked", self)


func _find_first_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_first_animation_player(child)
		if found != null:
			return found
	return null


func _apply_model_presentation(model_root: Node3D, display_name: String) -> void:
	if display_name == "Dino Buddy" and _is_quaternius_dino_model(model_root):
		model_root.scale = QUATERNIUS_BATTLE_SCALE
		model_root.position = Vector3(0.0, -0.58, 0.0)


func _is_quaternius_dino_model(root: Node) -> bool:
	return root != null and root.find_child("CharacterArmature", true, false) != null and root.find_child("Dino", true, false) != null


func _apply_imported_palette(mesh_node: MeshInstance3D) -> void:
	var surface_count := mesh_node.mesh.get_surface_count()
	for surface_index in range(surface_count):
		var source_material: Material = mesh_node.get_active_material(surface_index)
		if source_material == null:
			source_material = mesh_node.mesh.surface_get_material(surface_index)
		var material_name := ""
		if source_material != null:
			material_name = ("%s %s" % [source_material.resource_name, source_material.resource_path]).to_lower()

		var override_material: Material = null
		if "dino_main" in material_name:
			override_material = _make_imported_material(primary_color.lightened(0.08), 0.62)
		elif "dino_secondary" in material_name:
			override_material = _make_imported_material(accent_color, 0.48, accent_color * 0.18, 0.18)
		elif "dino_tongue" in material_name:
			override_material = _make_invisible_material()
		elif "dino_teeth" in material_name:
			override_material = _make_imported_material(Color(0.98, 0.96, 0.90, 1.0), 0.78)
		elif "eye_white" in material_name:
			override_material = _make_imported_material(Color(0.98, 0.99, 1.0, 1.0), 0.28)
		elif "eye_black" in material_name:
			override_material = _make_imported_material(Color(0.08, 0.10, 0.12, 1.0), 0.22)

		if override_material != null:
			mesh_node.set_surface_override_material(surface_index, override_material)
		elif mesh_node.get_active_material(surface_index) == null:
			mesh_node.set_surface_override_material(surface_index, _make_imported_material(primary_color, 0.62))


func _make_imported_material(color: Color, roughness: float, emission: Color = Color(0, 0, 0, 1), emission_strength := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = 0.03
	if emission_strength > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = emission_strength
	return mat


func _make_invisible_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0, 0, 0, 0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_receive_shadows = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _ensure_battle_idle_animation() -> void:
	if _battle_anim_player == null:
		return
	var idle_anim := _resolve_anim_name(BATTLE_IDLE_ANIMS)
	if idle_anim.is_empty():
		return
	if _battle_anim_player.is_playing() and _battle_anim_player.current_animation == String(idle_anim):
		return
	var attack_anim := _resolve_anim_name(BATTLE_ATTACK_ANIMS)
	if _battle_anim_player.is_playing() and not attack_anim.is_empty() and _battle_anim_player.current_animation == String(attack_anim):
		return
	_battle_anim_player.play(idle_anim, 0.12)


func _play_skinned_animation(candidates: Array[StringName], blend: float) -> void:
	if _battle_anim_player == null:
		return
	var anim_name := _resolve_anim_name(candidates)
	if anim_name.is_empty():
		return
	_battle_anim_player.play(anim_name, blend)


func _resolve_anim_name(candidates: Array[StringName]) -> StringName:
	if _battle_anim_player == null:
		return &""
	for candidate in candidates:
		if _battle_anim_player.has_animation(candidate):
			return candidate
	return &""
