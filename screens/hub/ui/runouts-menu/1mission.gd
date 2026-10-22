extends Button

const MISSION_SCENE := "res://screens/mission/ui/mission.tscn"


func _on_pressed() -> void:
	get_parent().select_mission()
