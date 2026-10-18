extends Button

const HUB_SCENE := "res://screens/hub/ui/hub.tscn"


func _on_pressed() -> void:
	SteamLobby.request_scene_change(HUB_SCENE)
