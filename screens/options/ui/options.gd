extends Control

const MAIN_MENU_SCENE := "res://screens/main-menu/ui/main_menu.tscn"


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("esc"):
		_return_to_main_menu()
		get_viewport().set_input_as_handled()


func _on_settings_closed() -> void:
	_return_to_main_menu()


func _return_to_main_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
