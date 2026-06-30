class_name PlayerStateCodec
extends RefCounted


static func from_profile(peer_id: int) -> Dictionary:
	var state := PlayerState.new()
	state.from_profile(PlayerProfile)
	state.peer_id = peer_id
	return to_dict(state)


static func to_dict(state: PlayerState) -> Dictionary:
	return {
		"peer_id": state.peer_id,
		"steam_id": state.steam_id,
		"nickname": state.nickname,
		"hero_scene": state.hero_scene,
		"level": state.level,
		"experience": state.experience,
		"inventory": state.inventory.duplicate(),
		"equipment": state.equipment.duplicate(),
	}


static func apply_dict(data: Dictionary, state: PlayerState) -> void:
	state.peer_id = data.get("peer_id", 0)
	state.steam_id = data.get("steam_id", 0)
	state.nickname = data.get("nickname", "Игрок")
	state.hero_scene = data.get("hero_scene", "")
	state.level = data.get("level", 1)
	state.experience = data.get("experience", 0)
	state.inventory = data.get("inventory", [])
	state.equipment = data.get("equipment", {})


static func to_state(data: Dictionary) -> PlayerState:
	var state := PlayerState.new()
	apply_dict(data, state)
	return state
