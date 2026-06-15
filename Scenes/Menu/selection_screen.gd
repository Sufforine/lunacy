extends Control


func _on_dullahan_pressed():
	PlayerProfile.hero_scene = "res://Scenes/Chars/Dullahan.tscn"
	SaveManager.save_profile()
	get_tree().change_scene_to_file("res://Scenes/Hub/hub.tscn")


func _on_slon_pressed():
	PlayerProfile.hero_scene = "res://Scenes/Chars/Slon.tscn"
	SaveManager.save_profile()
	get_tree().change_scene_to_file("res://Scenes/Hub/hub.tscn")
