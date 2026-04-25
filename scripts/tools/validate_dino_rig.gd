extends SceneTree

const BuddyVisualCatalog := preload("res://scripts/buddies/buddy_visual_catalog.gd")

const EXPECTED_SCULPT_ANIMATIONS := [
	"Idle",
	"Walk",
	"BattleIdle",
	"Attack",
	"HappyChirp",
	"Victory",
]


func _init() -> void:
	_validate_quaternius_rig()
	_validate_sculpt_rig()
	_validate_dino_buddy_catalog()
	print("validate_dino_rig: OK")
	quit(0)


func _validate_quaternius_rig() -> void:
	var rig_scene: PackedScene = load("res://art/exports/dino_buddy/dino_buddy_quaternius.glb")
	assert(rig_scene != null, "Quaternius dino GLB failed to load")
	var rig_instance := rig_scene.instantiate()
	assert(rig_instance != null)
	rig_instance.queue_free()


func _validate_sculpt_rig() -> void:
	var sculpt_scene: PackedScene = load("res://art/exports/dino_buddy/dino_buddy_sculpt_rigged.glb")
	assert(sculpt_scene != null, "Sculpt-rigged dino GLB failed to load")
	var sculpt_instance := sculpt_scene.instantiate()
	assert(sculpt_instance != null)
	assert(sculpt_instance.find_child("DinoBuddySculpt", true, false) != null,
		"Sculpt rig missing DinoBuddySculpt mesh node")
	var anim_player := _find_first_animation_player(sculpt_instance)
	assert(anim_player != null, "Sculpt rig missing AnimationPlayer")
	for anim_name in EXPECTED_SCULPT_ANIMATIONS:
		assert(anim_player.has_animation(anim_name),
			"Sculpt rig missing expected animation: %s" % anim_name)
	sculpt_instance.queue_free()


func _validate_dino_buddy_catalog() -> void:
	var battle_scene: PackedScene = BuddyVisualCatalog.resolve_battle_visual("Dino Buddy")
	assert(battle_scene != null, "Dino Buddy battle visual scene missing from catalog")
	var battle_instance := battle_scene.instantiate()
	assert(battle_instance != null)
	assert(battle_instance.find_child("ImportedDino", true, false) != null,
		"Dino Buddy visual scene missing ImportedDino mount")
	battle_instance.queue_free()

	var follower_scene: PackedScene = BuddyVisualCatalog.resolve_overworld_follower_visual("Dino Buddy")
	assert(follower_scene != null, "Dino Buddy overworld follower visual scene missing")
	follower_scene.instantiate().queue_free()


func _find_first_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_first_animation_player(child)
		if found != null:
			return found
	return null
