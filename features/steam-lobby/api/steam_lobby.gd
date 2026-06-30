# Steam lobby API and orchestration. Net transport, session, spawn, and sync
# details live in features/net/*.
extends Node

signal lobby_ready(lobby_id: int)
signal lobby_failed(reason: String)
signal players_updated(players: Array)

const NetSteamTransport := preload("res://features/net/transport/steam_transport.gd")
const NetSession := preload("res://features/net/session/net_session.gd")
const NetSpawner := preload("res://features/net/spawn/net_spawner.gd")

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


func is_session_active() -> bool:
	return peer != null and multiplayer.has_multiplayer_peer()


func host_lobby() -> void:
	if not _steam_available():
		lobby_failed.emit("Steam singleton is not available")
		return

	if lobby_id != 0:
		disconnect_lobby()

	Steam.createLobby(LOBBY_TYPE_PUBLIC, 4)
	is_host = true


func join_lobby(id: int) -> void:
	if not _steam_available():
		lobby_failed.emit("Steam singleton is not available")
		return

	if lobby_id != 0:
		disconnect_lobby()

	is_joining = true
	Steam.joinLobby(id)


func disconnect_lobby() -> void:
	_clear_autoload_spawns()
	_transport.close_connection(multiplayer)
	_session.player_states.clear()
	lobby_id = 0
	peer = null
	is_host = false
	is_joining = false


func start_game() -> void:
	if not multiplayer.is_server():
		return

	if PlayerProfile.hero_scene.is_empty():
		push_warning("SteamLobby: хост не выбрал героя")
		return

	for peer_id in _session.player_states:
		var state: PlayerState = _session.player_states[peer_id]
		if state.hero_scene.is_empty():
			push_warning("SteamLobby: игрок %d не выбрал героя" % peer_id)
			return

	_clear_autoload_spawns()
	_rpc_load_hub.rpc()


func spawn_hub_players(hub: Node3D, spawn_points: Array) -> void:
	if not is_session_active():
		return

	if not multiplayer.is_server():
		return

	if spawn_points.is_empty():
		push_error("SteamLobby: нет точек спавна в хабе")
		return

	for peer_id in _session.player_states:
		var state_data := _session.player_state_data(peer_id)
		var spawn_index := int(peer_id) % spawn_points.size()
		var spawn_pos: Vector3 = spawn_points[spawn_index].global_position
		_rpc_spawn_hub_player.rpc(state_data, spawn_pos)


@rpc("authority", "call_local", "reliable")
func _rpc_load_hub() -> void:
	get_tree().change_scene_to_file("res://screens/hub/ui/hub.tscn")


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_hub_player(state_data: Dictionary, spawn_position: Vector3) -> void:
	call_deferred("_deferred_spawn_hub_player", state_data, spawn_position)


func _deferred_spawn_hub_player(state_data: Dictionary, spawn_position: Vector3) -> void:
	var hub := _get_hub_scene()
	if hub == null:
		# Клиент может ещё загружать хаб — повторить на следующем кадре.
		await get_tree().process_frame
		hub = _get_hub_scene()

	if hub == null:
		push_error("SteamLobby: не удалось заспавнить игрока — хаб не загружен")
		return

	_spawner.spawn_player(hub, state_data, spawn_position)


func _get_hub_scene() -> Node:
	var scene := get_tree().current_scene
	if scene != null and scene.name == "Hub":
		return scene
	return null


@rpc("authority", "call_local", "reliable")
func _rpc_despawn_hub_player(peer_id: int) -> void:
	var scene := get_tree().current_scene
	if scene:
		_spawner.despawn_player(scene, peer_id)
	_broadcast_player_list()


func _on_lobby_created(result: int, id: int) -> void:
	if not _steam_available():
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
		return

	lobby_id = id
	peer = _transport.create_steam_client(multiplayer, Steam.getLobbyOwner(lobby_id))
	is_joining = false

	multiplayer.connected_to_server.connect(_on_connected_to_server, CONNECT_ONE_SHOT)
	multiplayer.connection_failed.connect(_on_connection_failed, CONNECT_ONE_SHOT)
	print("SteamLobby: в лобби, ожидание P2P-подключения к хосту...")


func _on_connected_to_server() -> void:
	var state_data := _session.register_local_player(multiplayer.get_unique_id())
	_rpc_send_state.rpc_id(1, state_data)
	lobby_ready.emit(lobby_id)
	print("SteamLobby: P2P подключён, peer_id=", multiplayer.get_unique_id())


func _on_connection_failed() -> void:
	lobby_failed.emit("Не удалось подключиться к хосту")
	disconnect_lobby()


func _on_peer_connected(id: int) -> void:
	print("SteamLobby: подключился peer ", id)


func _on_peer_disconnected(id: int) -> void:
	print("SteamLobby: отключился peer ", id)
	_session.remove_player(id)
	_rpc_despawn_hub_player.rpc(id)


@rpc("any_peer", "reliable")
func _rpc_send_state(state_data: Dictionary) -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	_session.register_remote_player(sender_id, state_data)
	print("SteamLobby: получен PlayerState от peer ", sender_id)
	_broadcast_player_list()


func _broadcast_player_list() -> void:
	if not multiplayer.is_server():
		return
	_rpc_player_list.rpc(_session.player_list())


@rpc("authority", "call_local", "reliable")
func _rpc_player_list(list: Array) -> void:
	players_updated.emit(list)


func notify_hero_changed() -> void:
	if not is_session_active():
		return

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


func _clear_autoload_spawns() -> void:
	for child in get_children():
		if child.name.is_valid_int():
			child.queue_free()


func _steam_available() -> bool:
	return Engine.has_singleton("Steam")
