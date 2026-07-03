extends Button

func _ready() -> void:
	pass

func _on_pressed() -> void:
		get_tree().change_scene_to_file("res://screens/mission/ui/mission.tscn")
