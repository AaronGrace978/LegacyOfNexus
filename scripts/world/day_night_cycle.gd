extends Node3D

@export var cycle_duration := 180.0
@export var time_scale := 1.0
@export var start_time := 0.30

var _time_of_day: float
var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _world_env: WorldEnvironment
var _sky_material: ProceduralSkyMaterial


func _ready() -> void:
	_sun = get_parent().get_node_or_null("Sun") as DirectionalLight3D
	_world_env = get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if _world_env and _world_env.environment and _world_env.environment.sky:
		_sky_material = _world_env.environment.sky.sky_material as ProceduralSkyMaterial
	_setup_moon()
	set_time_of_day(start_time)


func _setup_moon() -> void:
	if get_parent() == null:
		return
	_moon = DirectionalLight3D.new()
	_moon.name = "MoonLight"
	_moon.light_color = Color(0.42, 0.52, 0.88, 1.0)
	_moon.shadow_enabled = false
	_moon.light_energy = 0.0
	get_parent().add_child.call_deferred(_moon)


func _process(delta: float) -> void:
	_time_of_day = fmod(_time_of_day + (delta * time_scale / cycle_duration), 1.0)
	_update_sun()
	_update_moon()
	_update_sky()
	_update_fog()


func get_time_of_day() -> float:
	return _time_of_day


func set_time_of_day(value: float) -> void:
	_time_of_day = fposmod(value, 1.0)
	_update_sun()
	_update_moon()
	_update_sky()
	_update_fog()


func _update_sun() -> void:
	if _sun == null:
		return

	var sun_pitch := (_time_of_day - 0.25) * TAU
	_sun.rotation.x = sun_pitch
	_sun.rotation.y = 0.65

	var sun_color: Color
	var sun_energy: float

	if _time_of_day < 0.22:
		var t := _time_of_day / 0.22
		sun_color = Color(0.18, 0.18, 0.32).lerp(Color(0.95, 0.55, 0.28), t)
		sun_energy = lerpf(0.08, 0.7, t)
	elif _time_of_day < 0.5:
		var t := (_time_of_day - 0.22) / 0.28
		sun_color = Color(0.95, 0.55, 0.28).lerp(Color(1.0, 0.96, 0.88), t)
		sun_energy = lerpf(0.7, 1.8, t)
	elif _time_of_day < 0.72:
		var t := (_time_of_day - 0.5) / 0.22
		sun_color = Color(1.0, 0.96, 0.88).lerp(Color(1.0, 0.48, 0.22), t)
		sun_energy = lerpf(1.8, 0.7, t)
	else:
		var t := (_time_of_day - 0.72) / 0.28
		sun_color = Color(1.0, 0.48, 0.22).lerp(Color(0.18, 0.18, 0.32), t)
		sun_energy = lerpf(0.7, 0.08, t)

	_sun.light_color = sun_color
	_sun.light_energy = sun_energy


func _update_moon() -> void:
	if _moon == null:
		return

	var sun_pitch := (_time_of_day - 0.25) * TAU
	_moon.rotation.x = sun_pitch + PI * 0.92
	_moon.rotation.y = -0.72

	var daytime := smoothstep(0.18, 0.35, _time_of_day) - smoothstep(0.65, 0.82, _time_of_day)
	var night := clampf(1.0 - daytime, 0.0, 1.0)
	_moon.light_energy = lerpf(0.0, 0.32, night * night)


func _update_sky() -> void:
	if _sky_material == null:
		return

	var day_top := Color(0.30, 0.50, 0.85)
	var day_hz := Color(0.62, 0.73, 0.88)
	var night_top := Color(0.03, 0.05, 0.12)
	var night_hz := Color(0.06, 0.09, 0.18)
	var dawn_top := Color(0.35, 0.28, 0.48)
	var dawn_hz := Color(0.88, 0.52, 0.32)
	var dusk_top := Color(0.25, 0.14, 0.38)
	var dusk_hz := Color(0.92, 0.38, 0.22)

	var top: Color
	var hz: Color

	if _time_of_day < 0.22:
		var t := _time_of_day / 0.22
		top = night_top.lerp(dawn_top, t)
		hz = night_hz.lerp(dawn_hz, t)
	elif _time_of_day < 0.5:
		var t := (_time_of_day - 0.22) / 0.28
		top = dawn_top.lerp(day_top, t)
		hz = dawn_hz.lerp(day_hz, t)
	elif _time_of_day < 0.72:
		var t := (_time_of_day - 0.5) / 0.22
		top = day_top.lerp(dusk_top, t)
		hz = day_hz.lerp(dusk_hz, t)
	else:
		var t := (_time_of_day - 0.72) / 0.28
		top = dusk_top.lerp(night_top, t)
		hz = dusk_hz.lerp(night_hz, t)

	_sky_material.sky_top_color = top
	_sky_material.sky_horizon_color = hz


func _update_fog() -> void:
	if _world_env == null or _world_env.environment == null:
		return

	var env := _world_env.environment
	var day_fog := Color(0.68, 0.78, 0.62)
	var night_fog := Color(0.05, 0.07, 0.12)
	var daytime := smoothstep(0.18, 0.35, _time_of_day) - smoothstep(0.65, 0.82, _time_of_day)
	env.fog_light_color = night_fog.lerp(day_fog, daytime)
	env.ambient_light_energy = lerpf(0.1, 0.45, daytime)
