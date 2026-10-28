# Shared session dependencies and access to the stable RPC endpoint.
# Services are children of SteamLobby and use the same MultiplayerAPI.
extends Node

const Session := preload("res://features/net/session/net_session.gd")
const Spawner := preload("res://features/net/spawn/net_spawner.gd")
const Drops := preload("res://features/net/sync/net_drops.gd")

var _lobby: Node
var _session: Session:
	get: return _lobby._session
var _spawner: Spawner:
	get: return _lobby._spawner
var _drops: Drops:
	get: return _lobby._drops


func configure(lobby: Node) -> void:
	_lobby = lobby
