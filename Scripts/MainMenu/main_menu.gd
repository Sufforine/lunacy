extends Control


func _on_debug_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/Missions/mission.tscn") # Replace with function body.


func _on_start_pressed() -> void:
		get_tree().change_scene_to_file("res://Scenes/Menu/character_select.tscn") # Replace with function body.
 # Replace with function body.


func _on_host_game_pressed() -> void:
		get_tree().change_scene_to_file("res://Scenes/Menu/lobby_menu.tscn")
