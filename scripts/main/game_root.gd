extends Node3D

const TITLE_SCENE := preload("res://scenes/main/title_screen.tscn")
const OVERWORLD_SCENE := preload("res://scenes/world/overworld.tscn")
const BATTLE_SCENE := preload("res://scenes/battle/battle_arena.tscn")
const INTRO_SCENE := preload("res://scenes/main/static_fall_intro.tscn")

@onready var active_container: Node3D = $ActiveScene

var current_scene: Node3D
var in_battle := false
var _transition_overlay: ColorRect
var _is_transitioning := false


func _ready() -> void:
	_create_transition_overlay()
	_load_scene(TITLE_SCENE)


func _create_transition_overlay() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	canvas.name = "TransitionLayer"
	add_child(canvas)

	_transition_overlay = ColorRect.new()
	_transition_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_transition_overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	_transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_transition_overlay)


func _load_scene(scene_resource: PackedScene) -> void:
	if current_scene:
		current_scene.queue_free()
		await get_tree().process_frame

	current_scene = scene_resource.instantiate()

	if current_scene.has_signal("battle_exit_requested"):
		current_scene.battle_exit_requested.connect(_on_battle_exit_requested)
	if current_scene.has_signal("battle_enter_requested"):
		current_scene.battle_enter_requested.connect(_on_battle_enter_requested)
	if current_scene.has_signal("start_game_requested"):
		current_scene.start_game_requested.connect(_on_start_game_requested)
	if current_scene.has_signal("continue_game_requested"):
		current_scene.continue_game_requested.connect(_on_continue_game_requested)
	if current_scene.has_signal("intro_finished"):
		current_scene.intro_finished.connect(_on_intro_finished)
	if current_scene.has_signal("quit_to_title_requested"):
		current_scene.quit_to_title_requested.connect(_on_quit_to_title_requested)

	active_container.add_child(current_scene)

	var chat_panel := get_node_or_null("DinoChatPanel")
	if chat_panel is CanvasLayer:
		(chat_panel as CanvasLayer).visible = (scene_resource != TITLE_SCENE)


func _transition_to(scene_resource: PackedScene, flash_color: Color = Color.BLACK, duration: float = 0.5, post_load: Callable = Callable()) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	_transition_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	_transition_overlay.color = Color(flash_color.r, flash_color.g, flash_color.b, 0.0)
	var fade_out := create_tween()
	fade_out.tween_property(_transition_overlay, "color:a", 1.0, duration).set_ease(Tween.EASE_IN)
	await fade_out.finished

	_load_scene(scene_resource)
	await get_tree().process_frame
	if post_load.is_valid():
		post_load.call()

	var fade_in := create_tween()
	fade_in.tween_property(_transition_overlay, "color:a", 0.0, duration).set_ease(Tween.EASE_OUT)
	await fade_in.finished

	_transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_is_transitioning = false


func _on_start_game_requested() -> void:
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null and save_manager.has_method("cancel_continue_request"):
		save_manager.call("cancel_continue_request")

	_reset_runtime_state()
	_transition_to(INTRO_SCENE, Color.BLACK, 0.9)


func _on_intro_finished() -> void:
	_transition_to(OVERWORLD_SCENE, Color.BLACK, 0.8)


func _on_quit_to_title_requested() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_transition_to(TITLE_SCENE, Color.BLACK, 0.8)


func _reset_runtime_state() -> void:
	var qm := get_node_or_null("/root/QuestManager")
	if qm != null and qm.has_method("reset"):
		qm.call("reset")
	var bm := get_node_or_null("/root/BondManager")
	if bm != null and bm.has_method("reset"):
		bm.call("reset")
	var em := get_node_or_null("/root/EchoManager")
	if em != null and em.has_method("reset"):
		em.call("reset")
	var im := get_node_or_null("/root/ItemManager")
	if im != null and im.has_method("reset"):
		im.call("reset")


func _on_continue_game_requested() -> void:
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager == null or not save_manager.has_method("request_continue"):
		return
	if not bool(save_manager.call("request_continue")):
		return
	_transition_to(OVERWORLD_SCENE, Color.BLACK, 0.9, Callable(self, "_apply_continue_after_load"))


func _on_battle_enter_requested() -> void:
	in_battle = true
	_transition_to(BATTLE_SCENE, Color.WHITE, 0.35)


func _on_battle_exit_requested() -> void:
	in_battle = false
	_transition_to(OVERWORLD_SCENE, Color.BLACK, 0.55, Callable(self, "_autosave_after_battle_return"))


func _apply_continue_after_load() -> void:
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager == null or current_scene == null:
		return
	if save_manager.has_method("consume_continue_request"):
		save_manager.call("consume_continue_request")
	if save_manager.has_method("apply_overworld_save"):
		save_manager.call("apply_overworld_save", current_scene)


func _autosave_after_battle_return() -> void:
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager == null or current_scene == null:
		return
	if save_manager.has_method("write_overworld_save"):
		save_manager.call("write_overworld_save", current_scene)
