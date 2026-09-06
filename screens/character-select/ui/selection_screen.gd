extends Control


func _on_dullahan_pressed():
	PlayerProfile.hero_scene = "res://entities/characters/dullahan/Dullahan.tscn"
	SaveManager.save_profile()
	get_tree().change_scene_to_file("res://screens/hub/ui/hub.tscn")


func _on_slon_pressed():
	PlayerProfile.hero_scene = "res://entities/characters/slon/Slon.tscn"
	SaveManager.save_profile()
	get_tree().change_scene_to_file("res://screens/hub/ui/hub.tscn")


func _on_host_button_pressed() -> void:
	get_tree().change_scene_to_file("res://features/steam-lobby/ui/lobby_menu.tscn")
