# Steam lobby API and orchestration. Net transport, session, spawn, and sync
# details live in features/net/*.
extends Node

signal lobby_ready(lobby_id: int)
signal lobby_failed(reason: String)
signal players_updated(players: Array)

const NetSteamTransport := preload("res://features/net/transport/steam_transport.gd")
const NetSession := preload("res://features/net/session/net_session.gd")
const NetSpawner := preload("res://features/net/spawn/net_spawner.gd")

# GodotSteam matchmaking constants (LobbyType / Result live on the class, not the singleton instance).
const LOBBY_TYPE_PUBLIC := 2
const RESULT_OK := 1

var lobby_id: int = 0
var peer: MultiplayerPeer
var is_host: bool = false
var is_joining: bool = false

var _transport := NetSteamTransport.new()
var _session := NetSession.new()
var _spawner := NetSpawner.new()


func _ready() -> void:
	if not _steam_available():
		push_warning("SteamLobby: Steam singleton is not available")
		return

	var init_result := Steam.steamInit(480, true)
	print("Steam initialized: ", init_result)

	await get_tree().process_frame

	print("Steam ID: ", Steam.getSteamID())
	SaveManager.load_profile()
	Steam.initRelayNetworkAccess()
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	print("Loaded hero: ", PlayerProfile.hero_scene)


func _process(_delta: float) -> void:
	if _steam_available():
		Steam.run_callbacks()


func host_lobby() -> void:
	if not _steam_available():
		lobby_failed.emit("Steam singleton is not available")
		push_warning("SteamLobby: Steam singleton is not available")
		return

	Steam.createLobby(LOBBY_TYPE_PUBLIC, 4)
	is_host = true


func join_lobby(id: int) -> void:
	if not _steam_available():
		lobby_failed.emit("Steam singleton is not available")
		push_warning("SteamLobby: Steam singleton is not available")
		return

	is_joining = true
	Steam.joinLobby(id)


func disconnect_lobby() -> void:
	_transport.close_connection(multiplayer)
	_session.player_states.clear()
	lobby_id = 0
	peer = null
	is_host = false
	is_joining = false


func _on_lobby_created(result: int, id: int) -> void:
	if not _steam_available():
		push_warning("SteamLobby: Steam singleton is not available")
		return

	if result != RESULT_OK:
		lobby_failed.emit("Failed to create lobby: %d" % result)
		push_error("SteamLobby: не удалось создать лобби: %d" % result)
		return

	lobby_id = id
	peer = _transport.create_steam_host(multiplayer)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	_session.register_local_player(1)
	lobby_ready.emit(lobby_id)
	_broadcast_player_list()
	print("SteamLobby: лобби создано ", lobby_id)


func _on_lobby_joined(id: int, _permissions: int, _locked: bool, _response: int) -> void:
	if not is_joining:
		return

	if not _steam_available():
		push_warning("SteamLobby: Steam singleton is not available")
		return

	lobby_id = id
	peer = _transport.create_steam_client(multiplayer, Steam.getLobbyOwner(lobby_id))
	is_joining = false
	lobby_ready.emit(lobby_id)

	multiplayer.connected_to_server.connect(_on_connected_to_server, CONNECT_ONE_SHOT)


func _on_connected_to_server() -> void:
	var state_data := _session.register_local_player(multiplayer.get_unique_id())
	_rpc_send_state.rpc_id(1, state_data)
	print("SteamLobby: отправлен PlayerState хосту")


func _on_peer_connected(id: int) -> void:
	print("SteamLobby: подключился peer ", id)


func _on_peer_disconnected(id: int) -> void:
	print("SteamLobby: отключился peer ", id)
	_session.remove_player(id)
	_spawner.despawn_player(self, id)
	_rpc_despawn_player.rpc(id)
	_broadcast_player_list()


@rpc("any_peer", "reliable")
func _rpc_send_state(state_data: Dictionary) -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	var normalized_state := _session.register_remote_player(sender_id, state_data)

	_rpc_spawn_player.rpc(normalized_state)
	print("SteamLobby: получен PlayerState от peer ", sender_id)

	for existing_id in _session.player_states:
		if existing_id == sender_id:
			continue
		var existing_data := _session.player_state_data(existing_id)
		if not existing_data.is_empty():
			_rpc_spawn_player.rpc_id(sender_id, existing_data)

	_broadcast_player_list()


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_player(state_data: Dictionary) -> void:
	_spawner.spawn_player(self, state_data)


@rpc("authority", "call_local", "reliable")
func _rpc_despawn_player(peer_id: int) -> void:
	_spawner.despawn_player(self, peer_id)


func _spawn_local_player(peer_id: int) -> void:
	if PlayerProfile.hero_scene.is_empty():
		push_error("SteamLobby: hero_scene не выбран")
		return

	var state_data := _session.register_local_player(peer_id)
	_rpc_spawn_player.rpc(state_data)
	_broadcast_player_list()


func _broadcast_player_list() -> void:
	_rpc_player_list.rpc(_session.player_list())


@rpc("authority", "call_local", "reliable")
func _rpc_player_list(list: Array) -> void:
	players_updated.emit(list)


func notify_hero_changed() -> void:
	if multiplayer.is_server():
		var my_id := multiplayer.get_unique_id()
		_session.update_hero(my_id, PlayerProfile.hero_scene)
		_broadcast_player_list()
	else:
		_rpc_update_hero.rpc_id(1, PlayerProfile.hero_scene)


@rpc("any_peer", "reliable")
func _rpc_update_hero(hero_scene: String) -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	_session.update_hero(sender_id, hero_scene)
	_broadcast_player_list()


func _steam_available() -> bool:
	return Engine.has_singleton("Steam")
