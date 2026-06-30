extends Node3D

const NetSpawner := preload("res://features/net/spawn/net_spawner.gd")

@onready var spawns = $SpawnPoints.get_children()

var _spawner := NetSpawner.new()


func _ready() -> void:
	# Дождаться полной инициализации сцены после change_scene.
	await get_tree().process_frame
	await get_tree().process_frame

	if SteamLobby.is_session_active():
		SteamLobby.spawn_hub_players(self, spawns)
	else:
		_spawn_solo()


func _spawn_solo() -> void:
	if PlayerProfile.hero_scene.is_empty():
		push_warning("hub: герой не выбран")
		return

	var spawn_pos: Vector3 = spawns[0].global_position if not spawns.is_empty() else Vector3.ZERO
	var state_data := {
		"peer_id": 1,
		"hero_scene": PlayerProfile.hero_scene,
	}
	_spawner.spawn_player(self, state_data, spawn_pos)
