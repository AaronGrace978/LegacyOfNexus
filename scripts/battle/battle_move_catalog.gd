extends RefCounted
class_name BattleMoveCatalog

const BuddyCatalog := preload("res://scripts/buddies/buddy_catalog.gd")

## Move entry keys: id, label, kind, power_mult, status_chance (0-1), requires_partner (bool)

const KIND_SINGLE := "single"
const KIND_ALL_ENEMIES := "all_enemies"
const KIND_BUFF_PARTNER_NEXT_ATTACK := "buff_partner_next_attack"
const KIND_ALL_ENEMIES_STATUS := "all_enemies_status"


static func get_entries_for_unit(unit_name: String) -> Array:
	return BuddyCatalog.get_move_entries(unit_name)


static func get_entry_by_id(unit_name: String, move_id: String) -> Dictionary:
	return BuddyCatalog.get_move_entry_by_id(unit_name, move_id)
