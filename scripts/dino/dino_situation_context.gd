extends RefCounted

## Builds a compact "where we are" blurb for Dino's system prompt so replies feel grounded in the live scene.

const POND_POS := Vector3(14.0, 0.0, -9.0)
const RIFT_POS := Vector3(-6.0, 0.0, 4.0)
const DINO_HOME_POS := Vector3(18.0, 0.0, -18.0)
const PATH_HINT_RADIUS := 14.0
const LANDMARK_NEAR := 9.0
const LANDMARK_KINDA := 16.0


func build(game_root: Node) -> String:
	if game_root == null:
		return "Location unknown (no game root)."

	var active: Node = game_root.get_node_or_null("ActiveScene")
	if active == null or active.get_child_count() == 0:
		return "In a transition or loading state."

	var scene_root: Node = active.get_child(0)
	var path := str(scene_root.scene_file_path)

	if path.contains("title_screen"):
		return (
			"Title screen of Legacy of Nexus. The player has not entered Greenbelt Park yet. "
			+ "You exist as their companion in spirit here; keep it brief and welcoming."
		)

	if path.contains("battle_arena"):
		return (
			"Battle arena — combat focus. You (Dino) are with them in spirit; cheer them on briefly if you speak. "
			+ "Do not describe park landmarks."
		)

	if path.contains("overworld") or scene_root.is_in_group("overworld"):
		return _overworld_situation(scene_root)

	return "Inside: %s. Stay in character as Dino Buddy." % scene_root.name


func _overworld_situation(overworld: Node) -> String:
	var chunks: PackedStringArray = ["Greenbelt Park — Nexus overworld."]

	var cycle: Node = overworld.get_node_or_null("DayNightCycle")
	if cycle != null and cycle.has_method("get_time_of_day"):
		var tod: float = float(cycle.call("get_time_of_day"))
		chunks.append(_time_phrase(tod))

	var player: Node3D = _first_in_group("player")
	if player == null:
		chunks.append("Player position unavailable.")
		return " ".join(chunks)

	var p := player.global_position
	chunks.append(_compass_from(p))
	chunks.append(_zone_from_position(p))
	chunks.append(_landmark_distances(p))

	var dino: Node = player.get_node_or_null("DinoBuddy")
	if dino != null and dino.has_method("get_activity_blurb"):
		chunks.append("Dino right now: %s" % str(dino.call("get_activity_blurb")))

	return " ".join(chunks)


func _time_phrase(tod: float) -> String:
	if tod < 0.22:
		return "Time: deep night."
	if tod < 0.35:
		return "Time: dawn."
	if tod < 0.65:
		return "Time: daytime."
	if tod < 0.78:
		return "Time: dusk."
	return "Time: night (lampposts and fireflies likely visible)."


func _compass_from(pos: Vector3) -> String:
	var deg := fposmod(rad_to_deg(atan2(pos.x, pos.z)), 360.0)
	return "Rough map position: bearing ~%d° from park center (flavor only)." % int(deg)


func _zone_from_position(pos: Vector3) -> String:
	var ax := absf(pos.x)
	var az := absf(pos.z)
	if ax < PATH_HINT_RADIUS and az < PATH_HINT_RADIUS:
		return "Near the main crossing dirt path."
	if pos.x > 8.0 and pos.z < -4.0:
		if pos.x > 12.0 and pos.z < -12.0:
			return "By Dino Home, the little house on the southeast side of the park."
		return "Eastern side of the park, pond quarter."
	if pos.x < -4.0:
		return "Western side of the park."
	if pos.z > 8.0:
		return "Northern meadow area."
	if pos.z < -8.0:
		return "Southern grassy edge."
	return "Open grass away from the central path."


func _landmark_distances(pos: Vector3) -> String:
	var d_pond := Vector2(pos.x, pos.z).distance_to(Vector2(POND_POS.x, POND_POS.z))
	var d_rift := Vector2(pos.x, pos.z).distance_to(Vector2(RIFT_POS.x, RIFT_POS.z))
	var d_home := Vector2(pos.x, pos.z).distance_to(Vector2(DINO_HOME_POS.x, DINO_HOME_POS.z))

	var bits: PackedStringArray = []
	if d_home < LANDMARK_NEAR:
		bits.append("Very close to Dino Home, the cozy little house you share.")
	elif d_home < LANDMARK_KINDA:
		bits.append("Dino Home is nearby.")

	if d_pond < LANDMARK_NEAR:
		bits.append("Very close to the pond.")
	elif d_pond < LANDMARK_KINDA:
		bits.append("Pond is nearby.")

	if d_rift < LANDMARK_NEAR:
		bits.append("Very close to the unstable rift (purple anomaly).")
	elif d_rift < LANDMARK_KINDA:
		bits.append("Rift energy is somewhere nearby.")

	if bits.is_empty():
		bits.append("No major anomaly in immediate sight (rift/pond are farther).")

	return " ".join(bits)


func _first_in_group(group_name: StringName) -> Node3D:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var nodes := tree.get_nodes_in_group(group_name)
	if nodes.is_empty():
		return null
	return nodes[0] as Node3D
