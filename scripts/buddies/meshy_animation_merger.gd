extends Node
## Merges animations from sibling GLB scenes into the AnimationPlayer of the
## buddy mesh that lives next to this node. Designed for Meshy AI exports
## where each motion (Walking / Running / Jumping / etc.) ships as a separate
## "_withSkin" GLB that shares the base character's armature.
##
## Place this node anywhere under the buddy visual root. On `_ready` it walks
## the parent's subtree, finds the first AnimationPlayer, then copies in
## animations from each entry in `animation_sources`. Aliases let us register
## the same Meshy clip under both its original name and a project-standard
## name (e.g. "Walk", "Run") so `buddy_animator.gd` and `battle_unit.gd` can
## resolve them with their existing lookup tables.
##
## When `ensure_idle` is true and no Idle animation ends up registered, a
## tiny looping `Idle` clip is fabricated from the first frame of any
## available animation so the buddy holds a rest pose instead of freezing on
## the last walk frame.

@export var animation_sources: Array[String] = []
## Map of source animation names -> renamed copy that will also be registered.
## The original name is preserved as well, so existing systems keep working.
@export var animation_aliases: Dictionary = {}
@export var ensure_idle: bool = true
@export var idle_anim_names: Array[StringName] = [
	&"Idle",
	&"CharacterArmature|Idle",
]


func _ready() -> void:
	var target := _find_animation_player(get_parent())
	if target == null:
		push_warning("MeshyAnimationMerger: no AnimationPlayer under %s" % get_parent())
		return

	for source_path in animation_sources:
		var path := String(source_path).strip_edges()
		if path == "":
			continue
		_merge_from(path, target)

	if ensure_idle and not _has_any_anim(target, idle_anim_names):
		_fabricate_idle_pose(target)


func _merge_from(scene_path: String, target_player: AnimationPlayer) -> void:
	var resource: Resource = ResourceLoader.load(scene_path)
	var packed := resource as PackedScene
	if packed == null:
		push_warning("MeshyAnimationMerger: failed to load %s" % scene_path)
		return

	var instance := packed.instantiate()
	var src_player := _find_animation_player(instance)
	if src_player == null:
		push_warning("MeshyAnimationMerger: no AnimationPlayer in %s" % scene_path)
		instance.free()
		return

	var dest_lib := _ensure_default_library(target_player)
	for lib_name in src_player.get_animation_library_list():
		var lib: AnimationLibrary = src_player.get_animation_library(lib_name)
		if lib == null:
			continue
		for anim_name in lib.get_animation_list():
			var anim: Animation = lib.get_animation(anim_name)
			if anim == null:
				continue

			var preserved_name := String(anim_name)
			if not dest_lib.has_animation(preserved_name):
				dest_lib.add_animation(preserved_name, anim.duplicate(true) as Animation)

			var alias_key := "%s/%s" % [String(lib_name), String(anim_name)]
			var renamed := ""
			if animation_aliases.has(alias_key):
				renamed = String(animation_aliases[alias_key])
			elif animation_aliases.has(String(anim_name)):
				renamed = String(animation_aliases[String(anim_name)])
			if renamed != "" and renamed != preserved_name:
				if dest_lib.has_animation(renamed):
					dest_lib.remove_animation(renamed)
				dest_lib.add_animation(renamed, anim.duplicate(true) as Animation)

	instance.free()


func _ensure_default_library(player: AnimationPlayer) -> AnimationLibrary:
	if player.has_animation_library(&""):
		return player.get_animation_library(&"")
	var lib := AnimationLibrary.new()
	player.add_animation_library(&"", lib)
	return lib


func _has_any_anim(player: AnimationPlayer, names: Array[StringName]) -> bool:
	for n in names:
		if player.has_animation(n):
			return true
	return false


func _fabricate_idle_pose(player: AnimationPlayer) -> void:
	var lib := _ensure_default_library(player)
	var seed_name := _pick_seed_animation(player)
	if seed_name.is_empty():
		return

	var seed_anim: Animation = player.get_animation(seed_name)
	if seed_anim == null:
		return

	var idle := Animation.new()
	idle.length = 0.6
	idle.loop_mode = Animation.LOOP_LINEAR
	for track_index in range(seed_anim.get_track_count()):
		var ttype := seed_anim.track_get_type(track_index)
		var path := seed_anim.track_get_path(track_index)
		var new_track := idle.add_track(ttype)
		idle.track_set_path(new_track, path)
		if seed_anim.track_get_key_count(track_index) > 0:
			var value: Variant = seed_anim.track_get_key_value(track_index, 0)
			idle.track_insert_key(new_track, 0.0, value)
			idle.track_insert_key(new_track, idle.length, value)

	if lib.has_animation("Idle"):
		lib.remove_animation("Idle")
	lib.add_animation("Idle", idle)


func _pick_seed_animation(player: AnimationPlayer) -> String:
	for candidate in [&"Walk", &"CharacterArmature|Walk", &"Run", &"CharacterArmature|Run"]:
		if player.has_animation(candidate):
			return String(candidate)
	var names := player.get_animation_list()
	if names.size() > 0:
		return String(names[0])
	return ""


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
