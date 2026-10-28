# Host-authoritative attribute spending and progress replication.
extends "res://features/steam-lobby/services/lobby_service.gd"


func request_spend_attribute(attribute_name: String) -> void:
	if not is_session_active():
		return
	if multiplayer.is_server():
		_server_spend_attribute(multiplayer.get_unique_id(), attribute_name)
	else:
		_lobby._rpc_request_spend_attribute.rpc_id(1, attribute_name)


func _rpc_request_spend_attribute(attribute_name: String) -> void:
	if multiplayer.is_server():
		_server_spend_attribute(multiplayer.get_remote_sender_id(), attribute_name)


func _server_spend_attribute(peer_id: int, attribute_name: String) -> void:
	var stats := _stats_for_peer(peer_id)
	if stats == null or not stats._apply_spent_attribute(attribute_name):
		return
	var progress := stats.get_progress_data()
	_session.update_progress(peer_id, progress)
	_lobby._rpc_apply_progress.rpc(peer_id, progress)


func _rpc_apply_progress(peer_id: int, progress: Dictionary) -> void:
	var stats := _stats_for_peer(peer_id)
	if stats != null:
		stats.apply_progress_data(progress)
	_session.update_progress(peer_id, progress)


# Calls into other services go through the facade.


func _stats_for_peer(peer_id: int) -> StatsComponent:
	return _lobby._stats_for_peer(peer_id)


func is_session_active() -> bool:
	return _lobby.is_session_active()
