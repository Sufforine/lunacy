extends CanvasLayer

const HELP := "/give <id или название предмета> — выдать предмет; /xp <число> — опыт; /items — список предметов; /help — команды."
var is_typing := false
var _panel: PanelContainer
var _history: RichTextLabel
var _entry: LineEdit
var _messages: Array[String] = []
var _hide_at := 0
var _previous_mouse_mode: int = Input.MOUSE_MODE_VISIBLE
var _last_sent: Dictionary = {}


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
	_panel.add_child(column)
	_history = RichTextLabel.new()
	_history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history.bbcode_enabled = false
	_history.scroll_following = true
	column.add_child(_history)
	_entry = LineEdit.new()
	_entry.placeholder_text = "Сообщение или /help"
	_entry.max_length = 256
	column.add_child(_entry)
	_entry.hide()
	_panel.hide()
	get_tree().scene_changed.connect(_on_scene_changed)
	multiplayer.peer_disconnected.connect(func(id: int): _last_sent.erase(id))


func _process(_delta: float) -> void:
	if not is_typing and Time.get_ticks_msec() > _hide_at:
		_panel.hide()


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
		_panel.show()
		_entry.show()
		_entry.clear()
		_entry.grab_focus()
		get_viewport().set_input_as_handled()


func _close() -> void:
	is_typing = false
	_entry.release_focus()
	_entry.hide()
	Input.mouse_mode = _previous_mouse_mode
	_hide_at = Time.get_ticks_msec() + 8000


func _on_scene_changed() -> void:
	# Не восстанавливаем режим мыши от уже удалённой сцены.
	is_typing = false
	_entry.release_focus()
	_entry.hide()
	_panel.hide()
	_hide_at = 0
	_last_sent.clear()


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
	_panel.show()
	_hide_at = Time.get_ticks_msec() + 8000
