extends Control

const MAIN_MENU_SCENE := "res://screens/main-menu/ui/main_menu.tscn"

@onready var pause_panel: Control = $CenterContainer
@onready var settings_panel: Control = $SettingsPanel

var _is_open: bool = false
var _used_tree_pause: bool = false
var _mouse_mode_before_open: int = Input.MOUSE_MODE_CAPTURED
var _player = null
var _player_was_processing_input: bool = true
var _player_was_processing_physics: bool = true
var _inventory_was_processing_input: bool = true


func _ready() -> void:
	# Меню должно получать Escape даже когда одиночная игра поставлена на паузу.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = _find_player()
	settings_panel.connect(&"close_requested", _on_settings_closed)
	_set_menu_visible(false)


func _unhandled_input(event: InputEvent) -> void:
	if _is_open:
		if _is_cancel_event(event):
			if settings_panel.visible:
				_show_pause_panel()
			else:
				resume()
		# Не пропускаем клавиши и мышь к взаимодействию с миром под меню.
		get_viewport().set_input_as_handled()
		return

	if not _is_cancel_event(event):
		return
	pause()
	get_viewport().set_input_as_handled()


func pause() -> void:
	if _is_open:
		return

	_is_open = true
	_mouse_mode_before_open = Input.mouse_mode
	_set_menu_visible(true)

	if SteamLobby.is_session_active():
		# Остановка SceneTree на одном клиенте прерывает его сетевую обработку.
		# В сетевой игре блокируем только управление локальным героем.
		_suspend_local_player()
	else:
		_used_tree_pause = true
		get_tree().paused = true

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func resume() -> void:
	_close_menu(true)


func _close_menu(restore_mouse: bool) -> void:
	if not _is_open:
		return

	_is_open = false
	if _used_tree_pause:
		get_tree().paused = false
		_used_tree_pause = false
	else:
		_restore_local_player()

	_set_menu_visible(false)
	if restore_mouse:
		Input.mouse_mode = _mouse_mode_before_open


func _set_menu_visible(value: bool) -> void:
	visible = value
	mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
	if value:
		_show_pause_panel()
	else:
		settings_panel.visible = false


func _suspend_local_player() -> void:
	if not is_instance_valid(_player):
		_player = _find_player()
	if not is_instance_valid(_player):
		return

	_player_was_processing_input = _player.is_processing_input()
	_player_was_processing_physics = _player.is_physics_processing()
	_player.set_process_input(false)
	# Блокируем ввод, но продолжаем падение и столкновения в сетевой игре.
	_player.velocity.x = 0.0
	_player.velocity.z = 0.0

	if is_instance_valid(_player.inventory_ui):
		_inventory_was_processing_input = _player.inventory_ui.is_processing_input()
		_player.inventory_ui.set_process_input(false)


func _restore_local_player() -> void:
	if not is_instance_valid(_player):
		return

	_player.set_process_input(_player_was_processing_input)
	_player.set_physics_process(_player_was_processing_physics)
	if is_instance_valid(_player.inventory_ui):
		_player.inventory_ui.set_process_input(_inventory_was_processing_input)


func _find_player() -> Node:
	var current: Node = get_parent()
	while current != null:
		if current.is_in_group("player"):
			return current
		current = current.get_parent()
	return null


func _is_cancel_event(event: InputEvent) -> bool:
	if not event.is_pressed() or event.is_echo():
		return false
	return event.is_action_pressed("esc") or event.is_action_pressed("ui_cancel")


func _on_resume_pressed() -> void:
	resume()


func _on_settings_pressed() -> void:
	pause_panel.visible = false
	settings_panel.visible = true


func _on_settings_closed() -> void:
	_show_pause_panel()


func _show_pause_panel() -> void:
	settings_panel.visible = false
	pause_panel.visible = true


func _on_restart_pressed() -> void:
	var current_scene := get_tree().current_scene
	if current_scene == null or current_scene.scene_file_path.is_empty():
		return

	var scene_path := current_scene.scene_file_path
	_close_menu(false)
	if SteamLobby.is_session_active():
		SteamLobby.request_scene_change(scene_path)
	else:
		get_tree().reload_current_scene()


func _on_quit_pressed() -> void:
	_close_menu(false)
	if SteamLobby.is_session_active():
		SteamLobby.disconnect_lobby()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _exit_tree() -> void:
	# Защита от зависшей паузы при смене сцены другим сетевым игроком.
	if _used_tree_pause:
		get_tree().paused = false
		_used_tree_pause = false
	elif _is_open:
		_restore_local_player()
