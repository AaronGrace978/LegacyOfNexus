extends SceneTree

const BuddyCatalog := preload("res://scripts/buddies/buddy_catalog.gd")
const BattleMoveCatalog := preload("res://scripts/battle/battle_move_catalog.gd")
const EncounterResolver := preload("res://scripts/battle/encounter_resolver.gd")
const PartyManagerScript := preload("res://scripts/global/PartyManager.gd")


func _init() -> void:
	var default_party: Array = BuddyCatalog.build_default_party()
	assert(default_party.size() == 6)
	assert(default_party[1] != null)
	assert(str(default_party[1].unit_name) == "Nova Cat")

	var s1: Dictionary = EncounterResolver.build_enemy_stats({"name": "Sparklet", "level": 3})
	assert(int(s1.get("max_health", 0)) > 0)
	assert(int(s1.get("attack_power", 0)) > 0)

	var s2: Dictionary = EncounterResolver.build_enemy_stats({"name": "UnknownBuddy", "level": 10})
	assert(s2.get("primary_color") is Color)

	var s3: Dictionary = EncounterResolver.build_enemy_stats({"name": "Red Rogue", "level": 2})
	assert(str(s3.get("name", "")) == "Red Rogue")

	var dino_moves: Array = BattleMoveCatalog.get_entries_for_unit("Dino Buddy")
	assert(dino_moves.size() == 3)
	assert(str((dino_moves[0] as Dictionary).get("id", "")) == "hype_tackle")

	var spark_moves: Array = BattleMoveCatalog.get_entries_for_unit("Sparklet")
	assert(spark_moves.size() == 2)

	var nova_moves: Array = BattleMoveCatalog.get_entries_for_unit("Nova Cat")
	assert(nova_moves.size() == 3)
	assert(str((nova_moves[0] as Dictionary).get("id", "")) == "midnight_pounce")

	var roar: Dictionary = BattleMoveCatalog.get_entry_by_id("Dino Buddy", "loyal_roar")
	assert(str(roar.get("kind", "")) == BattleMoveCatalog.KIND_BUFF_PARTNER_NEXT_ATTACK)

	var party_manager: Node = root.get_node_or_null("PartyManager")
	if party_manager == null:
		party_manager = PartyManagerScript.new()
		party_manager.name = "PartyManager"
		root.add_child(party_manager)
		if party_manager.has_method("_initialize_default_party"):
			party_manager.call("_initialize_default_party")
	assert(party_manager != null)
	var party_rows: Array[Dictionary] = party_manager.get_party_for_display()
	assert(party_rows.size() == 6)
	assert(party_rows[0].get("empty", true) == false)
	assert(party_rows[0].get("locked", false) == true)
	assert(party_rows[0].has("primary_color"))

	var battle_scene: PackedScene = load("res://scenes/battle/battle_arena.tscn")
	assert(battle_scene != null)
	var battle_instance := battle_scene.instantiate()
	assert(battle_instance.get_node_or_null("CaptureRhythmUI") != null)
	battle_instance.queue_free()

	var unit_scene: PackedScene = load("res://scenes/battle/battle_unit.tscn")
	assert(unit_scene != null)
	var unit_instance := unit_scene.instantiate()
	assert(unit_instance.get_node_or_null("Pivot/CaptureReadyLabel") != null)
	unit_instance.queue_free()

	print("validate_encounters: OK")
	quit(0)
