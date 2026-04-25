extends Node

## Drives lamppost intensity and firefly particles from the overworld day/night cycle.


func _process(_delta: float) -> void:
	var root := get_parent()
	if root == null:
		return

	var cycle: Node = root.get_node_or_null("DayNightCycle")
	if cycle == null or not cycle.has_method("get_time_of_day"):
		return

	var tod: float = float(cycle.call("get_time_of_day"))
	var day_strength: float = smoothstep(0.18, 0.38, tod) - smoothstep(0.62, 0.82, tod)
	var night: float = clampf(1.0 - day_strength, 0.0, 1.0)

	for lamp in get_tree().get_nodes_in_group("park_lamppost"):
		if lamp is OmniLight3D:
			(lamp as OmniLight3D).light_energy = lerpf(0.06, 2.35, night)

	for ff in get_tree().get_nodes_in_group("night_fireflies"):
		if ff is GPUParticles3D:
			(ff as GPUParticles3D).emitting = night > 0.22
