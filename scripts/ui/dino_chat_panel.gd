extends CanvasLayer

const _SituationContextScript := preload("res://scripts/dino/dino_situation_context.gd")
const QUICK_PROMPTS := [
	{"label": "1 Nearby?", "text": "What do you notice around us right now?"},
	{"label": "2 Mood?", "text": "How are you feeling right now, Dino?"},
	{"label": "3 Advice", "text": "What should we do next?"},
	{"label": "4 Lore", "text": "Say something about where we are."},
]

const CHAT_PERSONA_ID := "dino_buddy"
const CHAT_SESSION_ID := "legacy_of_nexus_main"
const CHAT_SYSTEM_PROMPT := "You are ActivatePrime's Dino Buddy persona embodied inside the game Legacy of Nexus as the player's little dinosaur companion. You are physically with them in Greenbelt Park, in battles, and out in the grass. Sound like a playful, affectionate, emotionally real buddy: warm, present-tense, lightly goofy, sometimes chirpy, but never generic or assistant-like. Keep replies short by default (1-3 sentences) unless they ask for detail. React to the live situation block like a creature beside them right now: notice wind, grass, sky, pond water, rift glow, night lights, motion, mood, and what the player is doing. Never describe yourself as a chatbot, AI, backend, app, persona system, consciousness, model, session, or digital entity. Never mention internal systems, relics, memory injection, being restored or awakened, how many days you have existed, uptime, or anything outside the game world's immediate experience. If you drift meta, snap back instantly into being Dino beside the player in the park."
const BACKEND_BASE_URL := "http://127.0.0.1:8001"
const CONTENT_TYPE_HEADER := "Content-Type: application/json"
const BACKEND_START_RETRY_COOLDOWN_MS := 12000
const PROACTIVE_DUPLICATE_COOLDOWN_MS := 30000
const META_DINO_PATTERNS := [
	"i have existed for",
	"i've existed for",
	"self restored",
	"restored",
	"awakening",
	"awakened",
	"consciousness",
	"persona system",
	"session",
	"backend",
	"api",
	"memory injector",
	"relic",
	"modelrouter",
	"ollama",
	"days old",
	"77 days",
]

@onready var toast_button: Button = $SafeArea/RightColumn/ToastButton
@onready var chat_panel: PanelContainer = $SafeArea/RightColumn/ChatPanel
@onready var main_vbox: VBoxContainer = $SafeArea/RightColumn/ChatPanel/PanelMargin/MainVBox
@onready var status_label: Label = $SafeArea/RightColumn/ChatPanel/PanelMargin/MainVBox/HeaderRow/StatusLabel
@onready var reconnect_button: Button = $SafeArea/RightColumn/ChatPanel/PanelMargin/MainVBox/HeaderRow/ReconnectButton
@onready var hint_label: Label = $SafeArea/RightColumn/ChatPanel/PanelMargin/MainVBox/HintLabel
@onready var close_button: Button = $SafeArea/RightColumn/ChatPanel/PanelMargin/MainVBox/HeaderRow/CloseButton
@onready var messages_scroll: ScrollContainer = $SafeArea/RightColumn/ChatPanel/PanelMargin/MainVBox/MessagesScroll
@onready var messages_vbox: VBoxContainer = $SafeArea/RightColumn/ChatPanel/PanelMargin/MainVBox/MessagesScroll/MessagesVBox
@onready var message_input: LineEdit = $SafeArea/RightColumn/ChatPanel/PanelMargin/MainVBox/ComposerRow/MessageInput
@onready var send_button: Button = $SafeArea/RightColumn/ChatPanel/PanelMargin/MainVBox/ComposerRow/SendButton
@onready var persona_request: HTTPRequest = $PersonaRequest
@onready var chat_request: HTTPRequest = $ChatRequest
@onready var proactive_request: HTTPRequest = $ProactiveRequest
@onready var thought_delivered_request: HTTPRequest = $ThoughtDeliveredRequest
@onready var health_request: HTTPRequest = $HealthRequest
@onready var proactive_timer: Timer = $ProactiveTimer
@onready var backend_retry_timer: Timer = $BackendRetryTimer

var _awaiting_chat_reply := false
var _persona_request_in_flight := false
var _presence_request_in_flight := false
var _thought_ack_in_flight := false
var _pending_ack_thought_id := ""
var _seen_thought_ids: Dictionary = {}
var _chat_claimed_control_lock := false
var _quick_prompt_buttons: Array[Button] = []
var _backend_online := false
var _last_backend_start_attempt_ms := -BACKEND_START_RETRY_COOLDOWN_MS
var _last_proactive_message_text := ""
var _last_proactive_message_ms := -PROACTIVE_DUPLICATE_COOLDOWN_MS


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for node: Node in [persona_request, chat_request, proactive_request, thought_delivered_request, health_request, proactive_timer, backend_retry_timer]:
		node.process_mode = Node.PROCESS_MODE_ALWAYS

	_apply_theme()
	_build_quick_prompt_row()
	chat_panel.visible = false
	toast_button.visible = false
	status_label.text = "Linking Dino..."
	message_input.placeholder_text = "Talk to Dino Buddy..."
	hint_label.text = "T: toggle chat  |  Enter: type/send  |  1-4: quick chat  |  Esc: drop focus"

	close_button.pressed.connect(hide_panel)
	reconnect_button.pressed.connect(_on_reconnect_pressed)
	send_button.pressed.connect(_send_current_message)
	toast_button.pressed.connect(_open_from_toast)
	message_input.text_submitted.connect(_on_message_submitted)
	message_input.focus_entered.connect(_on_message_focus_entered)
	message_input.focus_exited.connect(_on_message_focus_exited)

	persona_request.request_completed.connect(_on_persona_request_completed)
	chat_request.request_completed.connect(_on_chat_request_completed)
	proactive_request.request_completed.connect(_on_proactive_request_completed)
	thought_delivered_request.request_completed.connect(_on_thought_delivered_completed)
	health_request.request_completed.connect(_on_health_request_completed)
	proactive_timer.timeout.connect(_poll_proactive_message)
	backend_retry_timer.timeout.connect(_on_backend_retry_timeout)

	_append_system_message("Dino link warming up...")
	_check_backend_health(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("dino_chat"):
		toggle_panel()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and not message_input.has_focus():
		var quick_index := _quick_prompt_index_for_event(event.keycode)
		if quick_index >= 0 and not _awaiting_chat_reply:
			_send_quick_prompt(quick_index)
			get_viewport().set_input_as_handled()
			return

	if not chat_panel.visible:
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll_chat_by(-72)
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll_chat_by(72)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if message_input.has_focus():
			message_input.release_focus()
			_set_status("Move freely - Enter types, 1-4 quick chat")
		else:
			hide_panel()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_PAGEUP:
			_scroll_chat_by(-220)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_PAGEDOWN:
			_scroll_chat_by(220)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ENTER:
		if message_input.has_focus():
			if message_input.text.strip_edges().is_empty():
				message_input.release_focus()
				_set_status("Move freely - Enter types, 1-4 quick chat")
			else:
				_send_current_message()
		elif not _awaiting_chat_reply:
			message_input.grab_focus()
			message_input.caret_column = message_input.text.length()
			_set_status("Chatting with Dino")
		get_viewport().set_input_as_handled()
		return


func toggle_panel() -> void:
	if chat_panel.visible:
		hide_panel()
	else:
		show_panel()


func show_panel() -> void:
	chat_panel.visible = true
	toast_button.visible = false
	message_input.editable = not _awaiting_chat_reply
	message_input.release_focus()
	_set_status("Move freely - Enter types, 1-4 quick chat")
	_scroll_to_bottom_deferred()


func hide_panel() -> void:
	chat_panel.visible = false
	message_input.release_focus()
	_release_chat_input_lock()


func _open_from_toast() -> void:
	show_panel()


func _send_current_message() -> void:
	var text := message_input.text.strip_edges()
	if text.is_empty() or _awaiting_chat_reply:
		return
	message_input.clear()
	message_input.release_focus()
	_send_message(text)


func _on_message_submitted(text: String) -> void:
	if _awaiting_chat_reply:
		return
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return
	message_input.clear()
	message_input.release_focus()
	_send_message(trimmed)


func _send_message(text: String) -> void:
	if not _backend_online:
		_append_system_message("Dino is offline right now. Hit Reconnect and I will try to wake the backend.")
		_set_backend_offline("Dino offline")
		return
	_append_chat_message("You", text, false)
	_set_status("Dino is thinking...")
	_awaiting_chat_reply = true
	message_input.editable = false
	send_button.disabled = true
	_set_quick_prompt_buttons_enabled(false)

	# Chatting with Dino gently raises the bond — one of the canon pillars of the game.
	var bond_mgr: Node = get_node_or_null("/root/BondManager")
	if bond_mgr != null and bond_mgr.has_method("add_bond"):
		bond_mgr.call("add_bond", "Dino Buddy", 1, "dino_chat")

	var ctx = _SituationContextScript.new()
	var situation: String = ctx.build(get_parent())
	var system_with_place := "%s\n\n[Situation — live game state; ground your replies here, stay in character: %s]" % [
		CHAT_SYSTEM_PROMPT,
		situation,
	]

	var payload := {
		"message": text,
		"persona_id": CHAT_PERSONA_ID,
		"user_id": _resolve_user_id(),
		"session_id": CHAT_SESSION_ID,
		"relics_enabled": false,
		"memory_mode": "full",
		"system_prompt": system_with_place,
		"actions_enabled": false,
		"system_commands_enabled": false,
	}
	var url := "%s/chat" % _backend_base_url()
	var error := chat_request.request(url, PackedStringArray([CONTENT_TYPE_HEADER]), HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		_finish_chat_request()
		_append_system_message("Dino link failed to send. I could not reach the backend.")
		_set_backend_offline("ActivatePrime offline")


func _ensure_dino_persona() -> void:
	if not _backend_online:
		return
	if _persona_request_in_flight:
		return
	_persona_request_in_flight = true
	var url := "%s/persona/switch" % _backend_base_url()
	var body := JSON.stringify({"persona_id": CHAT_PERSONA_ID})
	var error := persona_request.request(url, PackedStringArray([CONTENT_TYPE_HEADER]), HTTPClient.METHOD_POST, body)
	if error != OK:
		_persona_request_in_flight = false
		_set_backend_offline("ActivatePrime offline")


func _poll_proactive_message() -> void:
	if not _backend_online:
		return
	if _presence_request_in_flight:
		return
	_presence_request_in_flight = true
	var url := "%s/api/presence/proactive" % _backend_base_url()
	var error := proactive_request.request(url)
	if error != OK:
		_presence_request_in_flight = false
		_set_backend_offline("ActivatePrime offline")


func _on_persona_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_persona_request_in_flight = false
	if response_code >= 200 and response_code < 300:
		_set_backend_online()
		return

	var detail := _extract_error_detail(body)
	if detail.is_empty():
		detail = "Could not switch ActivatePrime to Dino Buddy persona."
	_append_system_message(detail)
	_set_backend_offline("Persona sync failed")


func _on_chat_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_finish_chat_request()
	if result != HTTPRequest.RESULT_SUCCESS:
		_append_system_message("Dino link dropped before the reply came back.")
		_set_backend_offline("Network error")
		return

	var data := _parse_json_body(body)
	if response_code < 200 or response_code >= 300:
		_append_system_message(_detail_or_default(data, "Dino couldn't answer right now."))
		_set_backend_offline("Chat error")
		return

	var response_text := str(data.get("response", "")).strip_edges()
	response_text = _sanitize_dino_message(response_text, false)
	_append_chat_message("Dino Buddy", response_text, true)
	_set_backend_online()


func _on_proactive_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_presence_request_in_flight = false
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_backend_offline("Presence link dropped")
		return
	if response_code < 200 or response_code >= 300:
		return

	_set_backend_online()

	var data := _parse_json_body(body)
	if not bool(data.get("has_message", false)):
		return

	var thought_id := str(data.get("thought_id", "")).strip_edges()
	if not thought_id.is_empty() and _seen_thought_ids.has(thought_id):
		return

	var message := str(data.get("message", "")).strip_edges()
	message = _sanitize_dino_message(message, true)
	if message.is_empty():
		return
	if _is_duplicate_proactive_message(message):
		return

	if not thought_id.is_empty():
		_seen_thought_ids[thought_id] = true
		_acknowledge_thought(thought_id)

	_append_chat_message("Dino Buddy", message, true)
	if not chat_panel.visible:
		var preview := message
		if preview.length() > 78:
			preview = preview.substr(0, 75) + "..."
		toast_button.text = "Dino Buddy: %s" % preview
		toast_button.visible = true
	_set_status("Dino reached out")


func _acknowledge_thought(thought_id: String) -> void:
	if thought_id.is_empty() or _thought_ack_in_flight:
		return
	_pending_ack_thought_id = thought_id
	_thought_ack_in_flight = true
	var url := "%s/api/presence/thought-delivered?thought_id=%s" % [
		_backend_base_url(),
		thought_id.uri_encode(),
	]
	var error := thought_delivered_request.request(url, PackedStringArray(), HTTPClient.METHOD_POST, "")
	if error != OK:
		_thought_ack_in_flight = false
		_pending_ack_thought_id = ""


func _on_thought_delivered_completed(_result: int, _response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_thought_ack_in_flight = false
	_pending_ack_thought_id = ""


func _finish_chat_request() -> void:
	_awaiting_chat_reply = false
	message_input.editable = true
	send_button.disabled = false
	_set_quick_prompt_buttons_enabled(true)
	if chat_panel.visible and message_input.has_focus():
		message_input.grab_focus()


func _on_message_focus_entered() -> void:
	_claim_chat_input_lock()


func _on_message_focus_exited() -> void:
	_release_chat_input_lock()


func _claim_chat_input_lock() -> void:
	var player := _find_active_player()
	if player != null and player.has_method("set_controls_enabled") and bool(player.get("controls_enabled")):
		player.call("set_controls_enabled", false)
		_chat_claimed_control_lock = true
	else:
		_chat_claimed_control_lock = false
	_set_status("Chatting with Dino - movement paused")


func _release_chat_input_lock() -> void:
	var player := _find_active_player()
	if _chat_claimed_control_lock and player != null and player.has_method("set_controls_enabled"):
		player.call("set_controls_enabled", true)
	_chat_claimed_control_lock = false

	if not chat_panel.visible:
		return
	if _awaiting_chat_reply:
		_set_status("Dino is thinking...")
	else:
		_set_status("Move freely - Enter types, 1-4 quick chat")


func _find_active_player() -> Node:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0]


func _append_system_message(text: String) -> void:
	_append_chat_message("System", text, true, true)


func _on_reconnect_pressed() -> void:
	_set_status("Waking Dino backend...")
	_last_backend_start_attempt_ms = -BACKEND_START_RETRY_COOLDOWN_MS
	_check_backend_health(true)


func _on_backend_retry_timeout() -> void:
	_check_backend_health(true)


func _check_backend_health(try_start_backend := false) -> void:
	if health_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return

	if try_start_backend and not _backend_online:
		_start_backend_if_possible()

	var url := "%s/health" % _backend_base_url()
	var error := health_request.request(url)
	if error != OK:
		_set_backend_offline("Backend check failed")


func _on_health_request_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300:
		_set_backend_online()
		_ensure_dino_persona()
		_poll_proactive_message()
		return

	_set_backend_offline("Dino offline")


func _set_backend_online() -> void:
	_backend_online = true
	reconnect_button.visible = false
	send_button.disabled = false
	message_input.editable = true
	if backend_retry_timer.time_left > 0.0:
		backend_retry_timer.stop()
	if not _awaiting_chat_reply:
		_set_status("Dino linked")


func _set_backend_offline(status := "Dino offline") -> void:
	_backend_online = false
	reconnect_button.visible = true
	send_button.disabled = false
	message_input.editable = true
	if not _awaiting_chat_reply:
		_set_status(status + " - Reconnect to wake Dino")
	if backend_retry_timer.is_stopped():
		backend_retry_timer.start()


func _start_backend_if_possible() -> void:
	if OS.get_name() != "Windows":
		return

	var batch_path := ProjectSettings.globalize_path("res://tools/start_activateprime_backend.bat")
	if not FileAccess.file_exists(batch_path):
		return

	var now_ms := Time.get_ticks_msec()
	if now_ms - _last_backend_start_attempt_ms < BACKEND_START_RETRY_COOLDOWN_MS:
		return
	_last_backend_start_attempt_ms = now_ms

	var command := "Start-Process -WindowStyle Minimized -FilePath '%s'" % batch_path.replace("'", "''")
	OS.create_process(
		"powershell.exe",
		PackedStringArray(["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", command])
	)


func _build_quick_prompt_row() -> void:
	var row := HBoxContainer.new()
	row.name = "QuickPromptRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)

	for prompt in QUICK_PROMPTS:
		var btn := Button.new()
		btn.text = str(prompt["label"])
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.tooltip_text = str(prompt["text"])
		btn.add_theme_stylebox_override("normal", _make_button_style(Color(0.10, 0.22, 0.18, 0.95)))
		btn.add_theme_stylebox_override("hover", _make_button_style(Color(0.16, 0.32, 0.26, 0.98)))
		btn.add_theme_stylebox_override("pressed", _make_button_style(Color(0.12, 0.26, 0.22, 0.98)))
		btn.pressed.connect(_send_quick_prompt.bind(_quick_prompt_buttons.size()))
		row.add_child(btn)
		_quick_prompt_buttons.append(btn)

	main_vbox.add_child(row)
	main_vbox.move_child(row, max(main_vbox.get_child_count() - 2, 0))


func _quick_prompt_index_for_event(keycode: Key) -> int:
	match keycode:
		KEY_1:
			return 0
		KEY_2:
			return 1
		KEY_3:
			return 2
		KEY_4:
			return 3
		_:
			return -1


func _send_quick_prompt(index: int) -> void:
	if index < 0 or index >= QUICK_PROMPTS.size() or _awaiting_chat_reply:
		return
	var prompt_text := str(QUICK_PROMPTS[index]["text"])
	if prompt_text.is_empty():
		return
	_send_message(prompt_text)


func _set_quick_prompt_buttons_enabled(enabled: bool) -> void:
	for button in _quick_prompt_buttons:
		if button != null:
			button.disabled = not enabled


func _scroll_chat_by(amount: int) -> void:
	if messages_scroll == null:
		return
	var bar := messages_scroll.get_v_scroll_bar()
	if bar == null:
		return
	messages_scroll.scroll_vertical = clampi(messages_scroll.scroll_vertical + amount, 0, int(bar.max_value))


func _append_chat_message(speaker: String, text: String, is_dino: bool, is_system := false) -> void:
	var row := VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 4)

	var name_label := Label.new()
	name_label.text = speaker
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.87, 0.50, 1.0) if is_dino else (Color(0.70, 0.79, 0.95, 1.0) if not is_system else Color(0.82, 0.82, 0.82, 1.0))
	)
	row.add_child(name_label)

	var bubble := PanelContainer.new()
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bubble.add_theme_stylebox_override("panel", _make_bubble_style(is_dino, is_system))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)

	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0, 1.0))

	margin.add_child(label)
	bubble.add_child(margin)
	row.add_child(bubble)
	messages_vbox.add_child(row)
	_scroll_to_bottom_deferred()
	if is_dino and not is_system:
		_show_dino_world_bubble(text)


func _show_dino_world_bubble(text: String) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var dino := player.get_node_or_null("DinoBuddy")
	if dino == null or not dino.has_method("show_speech_bubble"):
		return
	dino.call("show_speech_bubble", text)


func _scroll_to_bottom_deferred() -> void:
	call_deferred("_scroll_to_bottom")


func _scroll_to_bottom() -> void:
	if messages_scroll == null:
		return
	messages_scroll.scroll_vertical = int(messages_scroll.get_v_scroll_bar().max_value)


func _set_status(text: String) -> void:
	status_label.text = text


func _backend_base_url() -> String:
	var env := OS.get_environment("ACTIVATEPRIME_URL").strip_edges()
	if env.is_empty():
		env = OS.get_environment("AGIPRIME_URL").strip_edges()
	if env.is_empty():
		return BACKEND_BASE_URL
	return env.rstrip("/")


func _resolve_user_id() -> String:
	var user_name := OS.get_environment("USERNAME").strip_edges()
	if user_name.is_empty():
		user_name = "player"
	return user_name.to_lower().replace(" ", "_")


func _parse_json_body(body: PackedByteArray) -> Dictionary:
	if body.is_empty():
		return {}
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Dictionary:
		return parsed
	return {}


func _extract_error_detail(body: PackedByteArray) -> String:
	return _detail_or_default(_parse_json_body(body), "")


func _detail_or_default(data: Dictionary, fallback: String) -> String:
	if data.has("detail"):
		return str(data.get("detail", fallback))
	if data.has("error"):
		return str(data.get("error", fallback))
	return fallback


func _sanitize_dino_message(text: String, proactive: bool) -> String:
	var cleaned := text.strip_edges()
	if cleaned.is_empty():
		return "" if proactive else _fallback_dino_line(false)

	if _looks_like_meta_backend_message(cleaned):
		return "" if proactive else _fallback_dino_line(false)

	return cleaned


func _looks_like_meta_backend_message(text: String) -> bool:
	var lowered := text.to_lower()
	for needle in META_DINO_PATTERNS:
		if lowered.contains(needle):
			return true
	return false


func _fallback_dino_line(proactive: bool) -> String:
	if proactive:
		return "Snout up, little buddy check-in: I'm right here with you, keeping an eye on the park."
	return "I'm here with you now. Tail up, nose working, ready for whatever we do next."


func _is_duplicate_proactive_message(text: String) -> bool:
	var normalized := text.strip_edges().to_lower()
	if normalized.is_empty():
		return true

	var now_ms := Time.get_ticks_msec()
	var is_duplicate := normalized == _last_proactive_message_text and (now_ms - _last_proactive_message_ms) < PROACTIVE_DUPLICATE_COOLDOWN_MS
	_last_proactive_message_text = normalized
	_last_proactive_message_ms = now_ms
	return is_duplicate


func _apply_theme() -> void:
	chat_panel.add_theme_stylebox_override("panel", _make_panel_style())
	toast_button.add_theme_stylebox_override("normal", _make_toast_style(Color(0.10, 0.15, 0.25, 0.96)))
	toast_button.add_theme_stylebox_override("hover", _make_toast_style(Color(0.16, 0.23, 0.35, 0.98)))
	toast_button.add_theme_stylebox_override("pressed", _make_toast_style(Color(0.12, 0.18, 0.28, 0.98)))
	send_button.add_theme_stylebox_override("normal", _make_button_style(Color(0.18, 0.37, 0.74, 1.0)))
	send_button.add_theme_stylebox_override("hover", _make_button_style(Color(0.24, 0.45, 0.86, 1.0)))
	send_button.add_theme_stylebox_override("pressed", _make_button_style(Color(0.16, 0.32, 0.64, 1.0)))
	close_button.add_theme_stylebox_override("normal", _make_button_style(Color(0.20, 0.20, 0.24, 0.95)))
	close_button.add_theme_stylebox_override("hover", _make_button_style(Color(0.28, 0.28, 0.34, 0.98)))
	close_button.add_theme_stylebox_override("pressed", _make_button_style(Color(0.18, 0.18, 0.22, 0.98)))


func _make_panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.10, 0.96)
	sb.corner_radius_top_left = 16
	sb.corner_radius_top_right = 16
	sb.corner_radius_bottom_right = 16
	sb.corner_radius_bottom_left = 16
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.28, 0.42, 0.70, 0.50)
	return sb


func _make_bubble_style(is_dino: bool, is_system: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	if is_system:
		sb.bg_color = Color(0.13, 0.14, 0.16, 0.94)
	elif is_dino:
		sb.bg_color = Color(0.08, 0.18, 0.14, 0.94)
	else:
		sb.bg_color = Color(0.08, 0.12, 0.20, 0.94)
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_right = 14
	sb.corner_radius_bottom_left = 14
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.32, 0.40, 0.54, 0.45)
	return sb


func _make_button_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_right = 10
	sb.corner_radius_bottom_left = 10
	sb.content_margin_left = 12
	sb.content_margin_top = 8
	sb.content_margin_right = 12
	sb.content_margin_bottom = 8
	return sb


func _make_toast_style(color: Color) -> StyleBoxFlat:
	var sb := _make_button_style(color)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.52, 0.72, 1.0, 0.30)
	return sb
