extends CanvasLayer

const InputLabelHelper := preload("res://scripts/ui/input_label_helper.gd")

signal capture_succeeded(buddy_name: String)
signal capture_failed(reason: String)

const BuddyCatalog := preload("res://scripts/buddies/buddy_catalog.gd")
const PENDING_COLOR := Color(0.18, 0.22, 0.29, 0.95)
const READY_COLOR := Color(0.3, 0.9, 1.0, 0.95)
const GOOD_COLOR := Color(0.47, 0.95, 0.62, 1.0)
const PERFECT_COLOR := Color(1.0, 0.92, 0.4, 1.0)
const MISS_COLOR := Color(0.92, 0.35, 0.4, 1.0)

@export var min_beats_total := 3
@export var max_beats_total := 5
@export var bpm := 112.0
@export var perfect_window_ms := 60.0
@export var great_window_ms := 100.0
@export var good_window_ms := 145.0
@export var miss_grace_after_beat_ms := 180.0
@export var max_misses := 2
@export var success_quality_threshold := 0.52

@onready var root_panel: PanelContainer = $Margin/Panel
@onready var title_label: Label = $Margin/Panel/VBox/TitleLabel
@onready var instruction_label: Label = $Margin/Panel/VBox/InstructionLabel
@onready var beat_label: Label = $Margin/Panel/VBox/BeatLabel
@onready var timing_label: Label = $Margin/Panel/VBox/TimingLabel
@onready var beat_track: HBoxContainer = $Margin/Panel/VBox/BeatTrack
@onready var pulse_ring: Control = $Margin/Panel/VBox/PulseRing
@onready var beat_marker: ColorRect = $Margin/Panel/VBox/PulseRing/BeatMarker
@onready var success_label: Label = $Margin/Panel/VBox/SuccessLabel
@onready var particles: GPUParticles2D = $Margin/Panel/VBox/Particles
@onready var capture_flash: ColorRect = $CaptureFlash

var rng := RandomNumberGenerator.new()
var active := false
var buddy_name := "Wild Buddy"
var beats_total := 4
var beat_interval := 0.0
var beat_times: Array[float] = []
var beat_index := 0
var start_time := 0.0
var hits: Array[String] = []
var miss_count := 0
var consumed_beats := 0
var beat_indicators: Array[ColorRect] = []


func _ready() -> void:
	rng.randomize()
	hide_capture()


func start_capture(display_name: String) -> void:
	buddy_name = display_name
	active = true
	visible = true
	root_panel.visible = true
	success_label.visible = false
	particles.emitting = false
	capture_flash.color = Color(1.0, 1.0, 1.0, 0.0)

	var clamped_min: int = clampi(min_beats_total, 3, 5)
	var clamped_max: int = clampi(max_beats_total, clamped_min, 5)
	beats_total = rng.randi_range(clamped_min, clamped_max)
	beat_interval = 60.0 / maxf(bpm, 1.0)
	beat_times.clear()
	for index: int in range(beats_total):
		beat_times.append((index + 1) * beat_interval)

	beat_index = 0
	hits.clear()
	miss_count = 0
	consumed_beats = 0
	_rebuild_beat_track(beats_total)
	_refresh_beat_track(0.0)

	title_label.text = "Capture %s" % buddy_name
	var jump_hint := InputLabelHelper.action_pretty("jump")
	instruction_label.text = "Press %s when the beat flashes.\nSync %d beats to digitize %s." % [jump_hint, beats_total, buddy_name]
	timing_label.text = "Timing: Wait for the pulse..."
	beat_label.text = "Beat: 0 / %d" % beats_total

	start_time = Time.get_ticks_msec() / 1000.0
	set_process(true)
	set_process_input(true)


func hide_capture() -> void:
	active = false
	visible = false
	if root_panel:
		root_panel.visible = false
	success_label.visible = false
	particles.emitting = false
	capture_flash.color = Color(1.0, 1.0, 1.0, 0.0)
	set_process(false)
	set_process_input(false)


func _process(delta: float) -> void:
	if not active:
		return

	var now: float = Time.get_ticks_msec() / 1000.0 - start_time
	_update_visuals(now, delta)
	_check_misses(now)


func _input(event: InputEvent) -> void:
	if not active:
		return

	if event.is_action_pressed("jump"):
		var now: float = Time.get_ticks_msec() / 1000.0 - start_time
		_try_hit(now)


func _try_hit(now: float) -> void:
	if beat_index >= beat_times.size():
		return

	var target_time: float = beat_times[beat_index]
	var delta_ms: float = absf(now - target_time) * 1000.0

	if delta_ms <= perfect_window_ms:
		_register_hit("Perfect", delta_ms)
	elif delta_ms <= great_window_ms:
		_register_hit("Great", delta_ms)
	elif delta_ms <= good_window_ms:
		_register_hit("Good", delta_ms)
	else:
		_register_offbeat()


func _register_hit(label: String, delta_ms: float) -> void:
	hits.append(label)
	consumed_beats += 1
	beat_index += 1
	timing_label.text = "Timing: %s (%.0f ms)" % [label, delta_ms]
	beat_label.text = "Beat: %d / %d" % [consumed_beats, beats_total]
	_refresh_beat_track(0.0)

	if consumed_beats >= beats_total and active:
		_finish_capture()


func _register_miss(reason: String) -> void:
	miss_count += 1
	timing_label.text = "Timing: Miss (%s)" % reason
	_refresh_beat_track(0.0)
	if miss_count >= max_misses:
		_fail_capture("too_many_misses")


func _check_misses(now: float) -> void:
	if beat_index >= beat_times.size():
		return

	var target_time: float = beat_times[beat_index]
	if now > target_time + (miss_grace_after_beat_ms / 1000.0):
		hits.append("Miss")
		consumed_beats += 1
		beat_index += 1
		beat_label.text = "Beat: %d / %d" % [consumed_beats, beats_total]
		_register_miss("late")
		if not active:
			return

		if consumed_beats >= beats_total:
			_finish_capture()


func _register_offbeat() -> void:
	hits.append("OffBeat")
	consumed_beats += 1
	beat_index += 1
	timing_label.text = "Timing: Off beat"
	beat_label.text = "Beat: %d / %d" % [consumed_beats, beats_total]
	_refresh_beat_track(0.0)
	miss_count += 1
	if miss_count >= max_misses:
		_fail_capture("too_many_misses")
		return

	if consumed_beats >= beats_total and active:
		_finish_capture()


func _finish_capture() -> void:
	var weighted_sum: float = 0.0
	for hit_label: String in hits:
		weighted_sum += _quality_for_label(hit_label)

	var average_quality: float = weighted_sum / float(maxi(beats_total, 1))
	var success := average_quality >= success_quality_threshold and miss_count < max_misses

	if not success:
		_fail_capture("low_sync_quality")
		return

	var party_manager: Node = get_node_or_null("/root/PartyManager")
	if party_manager == null or not party_manager.has_method("try_add_captured_buddy"):
		_fail_capture("no_party_manager")
		return

	var added_index: int = int(party_manager.try_add_captured_buddy(_build_captured_member()))
	if added_index < 0:
		_fail_capture("party_full")
		return

	active = false
	set_process(false)
	set_process_input(false)
	success_label.text = "%s Captured!" % buddy_name
	success_label.visible = true
	particles.restart()
	particles.emitting = true
	_play_capture_flash()

	await get_tree().create_timer(1.0).timeout
	hide_capture()
	emit_signal("capture_succeeded", buddy_name)


func _fail_capture(reason: String) -> void:
	active = false
	set_process(false)
	set_process_input(false)
	hide_capture()
	emit_signal("capture_failed", reason)


func _build_captured_member():
	return BuddyCatalog.build_captured_member(buddy_name)


func _quality_for_label(label: String) -> float:
	match label:
		"Perfect":
			return 1.0
		"Great":
			return 0.85
		"Good":
			return 0.65
		"OffBeat":
			return 0.0
		"Miss":
			return 0.0
		_:
			return 0.0


func _update_visuals(now: float, _delta: float) -> void:
	if beat_times.is_empty() or beat_interval <= 0.0:
		return

	var phase := fmod(now, beat_interval) / beat_interval
	var pulse := 0.78 + 0.28 * sin(phase * TAU)
	pulse_ring.scale = Vector2.ONE * pulse

	var safe_index: int = mini(beat_index, beat_times.size() - 1)
	var next_beat: float = beat_times[safe_index]
	var proximity: float = clampf(1.0 - absf(now - next_beat) / beat_interval, 0.0, 1.0)
	beat_marker.color = Color(0.2 + proximity * 0.8, 0.55 + proximity * 0.35, 1.0, 0.22 + proximity * 0.62)
	_refresh_beat_track(proximity)


func _rebuild_beat_track(count: int) -> void:
	for child: Node in beat_track.get_children():
		child.queue_free()

	beat_indicators.clear()
	for _index: int in range(count):
		var indicator := ColorRect.new()
		indicator.custom_minimum_size = Vector2(44.0, 18.0)
		indicator.color = PENDING_COLOR
		beat_track.add_child(indicator)
		beat_indicators.append(indicator)


func _refresh_beat_track(proximity: float) -> void:
	for index: int in range(beat_indicators.size()):
		var indicator: ColorRect = beat_indicators[index]
		if index < hits.size():
			indicator.color = _color_for_label(hits[index])
		elif index == beat_index and active:
			indicator.color = READY_COLOR.lerp(PERFECT_COLOR, proximity)
		else:
			indicator.color = PENDING_COLOR


func _color_for_label(label: String) -> Color:
	match label:
		"Perfect":
			return PERFECT_COLOR
		"Great":
			return Color(0.72, 1.0, 0.55, 1.0)
		"Good":
			return GOOD_COLOR
		"OffBeat":
			return MISS_COLOR
		"Miss":
			return MISS_COLOR
		_:
			return PENDING_COLOR


func _play_capture_flash() -> void:
	capture_flash.color = Color(0.9, 1.0, 1.0, 0.55)
	var tween: Tween = create_tween()
	tween.tween_property(capture_flash, "color", Color(0.9, 1.0, 1.0, 0.0), 0.35)
