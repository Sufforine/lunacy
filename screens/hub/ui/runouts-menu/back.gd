extends Button

const HUB_SCENE := "res://screens/hub/ui/hub.tscn"


func _on_pressed() -> void:
	get_parent().close()
