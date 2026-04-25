class_name BattlePartyMember
extends RefCounted

var party_index := 0
var unit_name := "Buddy"
var max_health := 20
var current_health := 20
var attack_power := 4
var primary_color := Color(1.0, 1.0, 1.0, 1.0)
var accent_color := Color(0.9, 0.9, 0.9, 1.0)
var locked := false
var level := 5


func _init(
	index: int,
	display_name: String,
	health: int,
	power: int,
	body_tint: Color,
	head_tint: Color,
	is_locked: bool = false,
	unit_level: int = 5
) -> void:
	party_index = index
	unit_name = display_name
	max_health = health
	current_health = health
	attack_power = power
	primary_color = body_tint
	accent_color = head_tint
	locked = is_locked
	level = unit_level
