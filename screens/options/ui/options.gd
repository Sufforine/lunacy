extends Control


func _ready() -> void:
	pass


func _process(delta: float) -> void:
	pass

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://screens/main-menu/ui/main_menu.tscn")


func _on_button_pressed() -> void:
		get_tree().change_scene_to_file("res://screens/main-menu/ui/main_menu.tscn")
