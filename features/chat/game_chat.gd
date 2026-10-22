extends CanvasLayer

const HELP := "/give <id или название предмета> — выдать предмет; /xp <число> — опыт; /items — список предметов; /help — команды."
var is_typing := false
var _panel: PanelContainer
var _history: RichTextLabel
var _entry: LineEdit
var _messages: Array[String] = []
var _previous_mouse_mode: int = Input.MOUSE_MODE_VISIBLE
var _last_sent: Dictionary = {}
var _typing_style := StyleBoxFlat.new()
var _transparent_style := StyleBoxEmpty.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 80
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.offset_left = 20
	_panel.offset_right = 580
	_panel.offset_top = -285
	_panel.offset_bottom = -25
	add_child(_panel)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(column)
	_history = RichTextLabel.new()
	_history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history.bbcode_enabled = false
	_history.scroll_following = true
	_history.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_history)
	_entry = LineEdit.new()
	_entry.placeholder_text = "Сообщение или /help"
	_entry.max_length = 256
	column.add_child(_entry)
	_entry.hide()
	_typing_style.bg_color = Color(0.04, 0.05, 0.07, 0.88)
	_typing_style.corner_radius_top_left = 8
	_typing_style.corner_radius_top_right = 8
	_typing_style.corner_radius_bottom_left = 8
	_typing_style.corner_radius_bottom_right = 8
	_typing_style.content_margin_left = 10
	_typing_style.content_margin_top = 10
	_typing_style.content_margin_right = 10
	_typing_style.content_margin_bottom = 10
	_set_typing_visual(false)
	get_tree().scene_changed.connect(_on_scene_changed)
	multiplayer.peer_disconnected.connect(func(id: int): _last_sent.erase(id))


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if is_typing:
		if event.keycode == KEY_ESCAPE:
			_close()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			var message := _entry.text.strip_edges()
			_close()
			get_viewport().set_input_as_handled()
			if not message.is_empty():
				_submit(message)
	elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		if get_tree().get_first_node_in_group("mission_selection") != null:
			return
		if get_viewport().gui_get_focus_owner() is LineEdit or SteamLobby.is_gameplay_locked():
			return
		is_typing = true
		_previous_mouse_mode = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_set_typing_visual(true)
		_entry.show()
		_entry.clear()
		_entry.grab_focus()
		get_viewport().set_input_as_handled()


func _close() -> void:
	is_typing = false
	_entry.release_focus()
	_entry.hide()
	_set_typing_visual(false)
	Input.mouse_mode = _previous_mouse_mode


func _on_scene_changed() -> void:
	# Не восстанавливаем режим мыши от уже удалённой сцены.
	is_typing = false
	_entry.release_focus()
	_entry.hide()
	_set_typing_visual(false)
	_last_sent.clear()


func _set_typing_visual(typing: bool) -> void:
	# Закрытый чат показывает только текст и полностью пропускает мышь к UI
	# под ним. Фон и перехват кликов включаются лишь на время ввода.
	_panel.add_theme_stylebox_override("panel", _typing_style if typing else _transparent_style)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP if typing else Control.MOUSE_FILTER_IGNORE


func _submit(message: String) -> void:
	if not SteamLobby.is_session_active():
		_handle_message(1, message)
	elif multiplayer.is_server():
		_handle_message(multiplayer.get_unique_id(), message)
	else:
		_request_message.rpc_id(1, message)


@rpc("any_peer", "call_remote", "reliable")
func _request_message(message: String) -> void:
	if multiplayer.is_server():
		_handle_message(multiplayer.get_remote_sender_id(), message)


func _handle_message(sender: int, message: String) -> void:
	message = message.strip_edges().left(256).replace("\n", " ").replace("\r", " ")
	if message.is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_sent.get(sender, -1000)) < 300:
		return
	_last_sent[sender] = now
	if message.begins_with("/"):
		var reply: String
		if message == "/help":
			reply = HELP
		elif message == "/items":
			var items: PackedStringArray = []
			for item in ItemLibrary.all_items():
				items.append("%s (%s)" % [item.id, item.item_name])
			reply = "; ".join(items)
		else:
			reply = SteamLobby.execute_chat_command(sender, message)
		if not SteamLobby.is_session_active() or sender == multiplayer.get_unique_id():
			_receive_message("Система", reply)
		else:
			_receive_message.rpc_id(sender, "Система", reply)
	else:
		var author := SteamLobby.chat_player_name(sender)
		if SteamLobby.is_session_active():
			_receive_message.rpc(author, message)
		else:
			_receive_message(author, message)


@rpc("authority", "call_local", "reliable")
func _receive_message(author: String, message: String) -> void:
	_messages.append("%s: %s" % [author, message])
	if _messages.size() > 100:
		_messages.pop_front()
	_history.text = "\n".join(_messages)
