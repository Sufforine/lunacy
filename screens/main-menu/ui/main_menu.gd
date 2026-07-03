extends Control


func _on_debug_pressed() -> void:
	get_tree().change_scene_to_file("res://screens/mission/ui/mission.tscn")


func _on_start_pressed() -> void:
		get_tree().change_scene_to_file("res://screens/character-select/ui/character_select.tscn")



func _on_host_game_pressed() -> void:
		get_tree().change_scene_to_file("res://features/steam-lobby/ui/lobby_menu.tscn")
