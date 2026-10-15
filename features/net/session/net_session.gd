class_name NetSession
extends RefCounted

const PlayerStateCodec := preload("res://features/net/sync/player_state_codec.gd")

var player_states: Dictionary = {}


func register_local_player(peer_id: int) -> Dictionary:
	var state_data := PlayerStateCodec.from_profile(peer_id)
	player_states[peer_id] = PlayerStateCodec.to_state(state_data)
	return state_data


func register_remote_player(peer_id: int, state_data: Dictionary) -> Dictionary:
	var normalized := state_data.duplicate(true)
	normalized["peer_id"] = peer_id
	player_states[peer_id] = PlayerStateCodec.to_state(normalized)
	return normalized


func remove_player(peer_id: int) -> void:
	player_states.erase(peer_id)


func update_hero(peer_id: int, hero_scene: String) -> void:
	if player_states.has(peer_id):
		player_states[peer_id].hero_scene = hero_scene


func update_progress(peer_id: int, progress: Dictionary) -> void:
	if not player_states.has(peer_id):
		return
	var state: PlayerState = player_states[peer_id]
	state.level = int(progress.get("level", state.level))
	state.experience = int(progress.get("experience", state.experience))
	state.attributes = progress.get("attributes", state.attributes).duplicate(true)
	state.attribute_points = int(progress.get("attribute_points", state.attribute_points))


func player_state_data(peer_id: int) -> Dictionary:
	if not player_states.has(peer_id):
		return {}
	return PlayerStateCodec.to_dict(player_states[peer_id])


func player_list() -> Array:
	var list: Array = []
	for peer_id in player_states:
		var state: PlayerState = player_states[peer_id]
		list.append({
			"peer_id": state.peer_id,
			"nickname": state.nickname,
			"character_name": state.character_name,
			"hero_scene": state.hero_scene,
		})
	return list
