extends Control


func _on_dullahan_pressed():
	_select_hero("dullahan")


func _on_slon_pressed():
	_select_hero("slon")


func _select_hero(hero_id: String) -> void:
	var hero: HeroDefinition = HeroLibrary.get_hero(hero_id)
	if hero == null or hero.scene == null:
		push_error("selection_screen: hero '%s' has no scene" % hero_id)
		return

	PlayerProfile.hero_scene = hero.scene.resource_path
	SaveManager.save_profile()
	get_tree().change_scene_to_file("res://screens/hub/ui/hub.tscn")


func _on_host_button_pressed() -> void:
	get_tree().change_scene_to_file("res://features/steam-lobby/ui/lobby_menu.tscn")
