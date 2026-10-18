
extends Node3D

const NetSpawner := preload("res://features/net/spawn/net_spawner.gd")

var _spawner := NetSpawner.new()
var _spawn_points: Array = []


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	var spawn_root := get_node_or_null("SpawnPoints")
	if spawn_root == null:
		push_error("mission: нода SpawnPoints не найдена")
		return
	_spawn_points = spawn_root.get_children()

	if SteamLobby.is_session_active():
		SteamLobby.spawn_mission_players(self, _spawn_points)
	else:
		_spawn_solo_player()


func _spawn_solo_player() -> void:
	if PlayerProfile.hero_scene.is_empty():
		push_warning("mission: герой не выбран")
		return

	var spawn_position: Vector3 = _spawn_points[0].global_position if not _spawn_points.is_empty() else Vector3.ZERO
	var state_data := {
		"peer_id": 1,
		"hero_scene": PlayerProfile.hero_scene,
		"inventory": PlayerProfile.inventory,
		"quickslots": PlayerProfile.quickslots,
		"equipment": PlayerProfile.equipment,
	}
	_spawner.spawn_player(self, state_data, spawn_position)
