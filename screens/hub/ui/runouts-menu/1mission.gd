extends Button

const MISSION_SCENE := "res://screens/mission/ui/mission.tscn"


func _on_pressed() -> void:
	SteamLobby.request_scene_change(MISSION_SCENE)
