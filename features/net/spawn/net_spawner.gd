class_name NetSpawner
extends RefCounted

const PLAYER_SCENE_PATH := "res://entities/characters/model/Player.tscn"
const PLAYER_SCENE: PackedScene = preload(PLAYER_SCENE_PATH)

func spawn_player(parent: Node, state_data: Dictionary, spawn_position: Vector3 = Vector3.ZERO) -> Node:
	var peer_id: int = state_data.get("peer_id", 0)

	if peer_id <= 0:
		push_error("NetSpawner: некорректный peer_id %d" % peer_id)
		return null

	var existing := parent.get_node_or_null(str(peer_id))
	if existing:
		return existing

	var requested_path := str(state_data.get("hero_scene", ""))
	if not requested_path.is_empty() and requested_path != PLAYER_SCENE_PATH:
		push_warning("NetSpawner: устаревшая сцена '%s' для peer %d заменена на Player" % [requested_path, peer_id])

	var normalized_state := state_data.duplicate(true)
	normalized_state["hero_scene"] = PLAYER_SCENE_PATH

	var hero: Node = PLAYER_SCENE.instantiate()
	hero.name = str(peer_id)
	hero.set_multiplayer_authority(peer_id)

	if not normalized_state.is_empty():
		hero.set_meta("network_state", normalized_state)

	parent.add_child(hero)

	if hero is Node3D:
		(hero as Node3D).global_position = spawn_position

	print("NetSpawner: заспавнен герой для peer ", peer_id, " @ ", spawn_position)
	return hero


func despawn_player(parent: Node, peer_id: int) -> void:
	var node := parent.get_node_or_null(str(peer_id))
	if node:
		node.queue_free()
