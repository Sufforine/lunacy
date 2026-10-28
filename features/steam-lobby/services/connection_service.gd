# Steam initialization, lobby membership, transport lifecycle and player roster.
extends "res://features/steam-lobby/services/lobby_service.gd"

const NetSteamTransport := preload("res://features/net/transport/steam_transport.gd")
const LOBBY_TYPE_PUBLIC := 2
const RESULT_OK := 1

var _steam_ready: bool = false
var _creating_lobby: bool = false
var _requested_lobby_id: int = 0
var _connection_deadline: int = 0
var _connection_stage: String = ""

var lobby_id: int = 0
var peer: MultiplayerPeer
var is_host: bool = false
var is_joining: bool = false

var _transport := NetSteamTransport.new()


func initialize() -> void:
	if not _steam_available():
		push_warning("SteamLobby: Steam singleton is not available")
		return

	var init_result: bool = Steam.steamInit(480, true)
	print("Steam initialized: ", init_result)

	# false — инициализация не удалась (Steam не запущен, нет
	# steam_appid.txt рядом с проектом/билдом, или не тот appid).
	# Любой дальнейший вызов Steam.* в этом случае падает с C++ ошибкой,
	# поэтому дальше идти нельзя.
	if not init_result:
		push_error("SteamLobby: Steam не инициализирован. Проверь что Steam запущен, ты залогинен, и рядом с проектом/билдом лежит steam_appid.txt с содержимым '480'.")
		_lobby.lobby_failed.emit("Steam init failed")
		return

	await get_tree().process_frame

	print("Steam ID: ", Steam.getSteamID())
	SaveManager.load_profile()
	if Steam.has_signal("relay_network_status"):
		Steam.connect("relay_network_status", _on_relay_network_status)
	if Steam.has_signal("network_authentication_status"):
		Steam.connect("network_authentication_status", _on_network_authentication_status)
	Steam.initRelayNetworkAccess()
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	print("Loaded hero: ", PlayerProfile.hero_scene)

	_steam_ready = true
	print("SteamLobby: Godot ", Engine.get_version_info().get("string", ""), "; AppID ", Steam.getAppID())


func _on_relay_network_status(available: int, _ping: int, config: int, relay: int, message: String) -> void:
	print("SteamNetwork: relay status=", available, " config=", config, " relay=", relay, " details=", message)


func _on_network_authentication_status(available: int, message: String) -> void:
	print("SteamNetwork: authentication status=", available, " details=", message)


func _process(_delta: float) -> void:
	if _steam_ready:
		Steam.run_callbacks()
	if _connection_deadline != 0 and Time.get_ticks_msec() >= _connection_deadline:
		var failed_stage := _connection_stage
		push_warning("SteamLobby: тайм-аут на этапе: %s" % failed_stage)
		if peer != null:
			print("SteamTransport: timeout status=", peer.get_connection_status(), " refuse_new_connections=", peer.refuse_new_connections)
		disconnect_lobby()
		_lobby.lobby_failed.emit("Время ожидания истекло. Этап: %s.\nПричину уточните в журнале Godot у обоих игроков." % failed_stage)


func is_session_active() -> bool:
	return peer != null and multiplayer.has_multiplayer_peer()


func host_lobby() -> void:
	if _connection_deadline != 0:
		return
	if not is_steam_ready():
		_lobby.lobby_failed.emit("Steam не инициализирован")
		return

	if lobby_id != 0:
		disconnect_lobby()

	_creating_lobby = true
	_connection_stage = "создание Steam-лобби"
	is_host = true
	_connection_deadline = Time.get_ticks_msec() + 30000
	Steam.createLobby(LOBBY_TYPE_PUBLIC, 4)


func join_lobby(id: int) -> void:
	if _connection_deadline != 0:
		return
	if id <= 0:
		_lobby.lobby_failed.emit("Некорректный код лобби")
		return
	if not is_steam_ready():
		_lobby.lobby_failed.emit("Steam не инициализирован")
		return

	if lobby_id != 0:
		disconnect_lobby()

	is_joining = true
	_connection_stage = "вход в Steam-лобби"
	_requested_lobby_id = id
	_connection_deadline = Time.get_ticks_msec() + 30000
	Steam.joinLobby(id)


func disconnect_lobby() -> void:
	_reset_pending_scene_spawns()
	_reset_mission_loading()
	_reset_scene_transition()
	_clear_autoload_spawns()
	_drops.clear()
	if _steam_ready and lobby_id != 0:
		Steam.leaveLobby(lobby_id)
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	if multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)
	if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.disconnect(_on_server_disconnected)
	_transport.close_connection(multiplayer)
	_creating_lobby = false
	_requested_lobby_id = 0
	_connection_deadline = 0
	_session.player_states.clear()
	_connection_stage = ""
	lobby_id = 0
	peer = null
	is_host = false
	is_joining = false


func _on_lobby_created(result: int, id: int) -> void:
	if not _creating_lobby:
		if result == RESULT_OK and id != lobby_id and _steam_ready:
			Steam.leaveLobby(id)
		return
	_creating_lobby = false
	_connection_deadline = 0
	if not _steam_available():
		return

	if result != RESULT_OK:
		is_host = false
		_lobby.lobby_failed.emit("Failed to create lobby: %d" % result)
		push_error("SteamLobby: не удалось создать лобби: %d" % result)
		return

	lobby_id = id
	peer = _transport.create_steam_host(multiplayer)
	if peer == null:
		var reason := "Не удалось создать Steam-сервер: %s" % error_string(_transport.last_error)
		disconnect_lobby()
		_lobby.lobby_failed.emit(reason)
		return
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	_session.register_local_player(1)
	_lobby.lobby_ready.emit(lobby_id)
	_broadcast_player_list()
	print("SteamLobby: лобби создано ", lobby_id)


func _on_lobby_joined(id: int, _permissions: int, _locked: bool, response: int) -> void:
	if not is_joining or id != _requested_lobby_id:
		if response == RESULT_OK and id != lobby_id and _steam_ready:
			Steam.leaveLobby(id)
		return

	if not _steam_available():
		return
	if response != RESULT_OK:
		disconnect_lobby()
		_lobby.lobby_failed.emit("Не удалось войти в Steam-лобби: %d" % response)
		return

	lobby_id = id
	var owner_id: int = Steam.getLobbyOwner(lobby_id)
	if owner_id == 0 or owner_id == Steam.getSteamID():
		disconnect_lobby()
		_lobby.lobby_failed.emit("Хост лобби недоступен")
		return
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)
	# Подписываемся до установки peer в MultiplayerAPI.
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server, CONNECT_ONE_SHOT)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed, CONNECT_ONE_SHOT)
	_connection_stage = "P2P-соединение с хостом"
	_connection_deadline = Time.get_ticks_msec() + 60000
	print("SteamLobby: соединение с владельцем лобби ", owner_id, "; Godot ", Engine.get_version_info().get("string", ""))
	peer = _transport.create_steam_client(multiplayer, owner_id)
	if peer == null:
		var reason := "Не удалось создать Steam-клиент: %s" % error_string(_transport.last_error)
		disconnect_lobby()
		_lobby.lobby_failed.emit(reason)
		return
	is_joining = false

	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("SteamLobby: в лобби, ожидание P2P-подключения к хосту...")


func _on_connected_to_server() -> void:
	_connection_stage = "подтверждение данных героя хостом"
	_connection_deadline = Time.get_ticks_msec() + 30000
	var state_data := _session.register_local_player(multiplayer.get_unique_id())
	_lobby._rpc_send_state.rpc_id(1, state_data)
	# Меню открывается после подтверждения профиля списком игроков от хоста.
	print("SteamLobby: P2P подключён, peer_id=", multiplayer.get_unique_id())


func _on_connection_failed() -> void:
	disconnect_lobby()
	_lobby.lobby_failed.emit("Не удалось подключиться к хосту")


func _on_server_disconnected() -> void:
	# В том числе когда хост вышел через ворота: надёжный RPC о выходе
	# может не успеть дойти до закрытия транспорта.
	_finish_leave_to_menu.call_deferred()
	_lobby.lobby_failed.emit("Соединение с хостом потеряно")


func _on_peer_connected(id: int) -> void:
	print("SteamLobby: подключился peer ", id)


func _on_peer_disconnected(id: int) -> void:
	print("SteamLobby: отключился peer ", id)
	_session.remove_player(id)
	_handle_transition_peer_left(id)
	if multiplayer.is_server():
		_lobby._rpc_despawn_hub_player.rpc(id)
	else:
		# Клиент не имеет права вызывать authority RPC. При потере хоста
		# удаляем его копию локально, не создавая сетевую ошибку поверх разрыва.
		var scene := get_tree().current_scene
		if scene != null:
			_spawner.despawn_player(scene, id)


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
	_lobby._rpc_player_list.rpc(_session.player_list())


func _rpc_player_list(list: Array) -> void:
	if not multiplayer.is_server() and _connection_deadline != 0:
		for player_data in list:
			if int(player_data.get("peer_id", 0)) == multiplayer.get_unique_id():
				_connection_deadline = 0
				_lobby.lobby_ready.emit(lobby_id)
				break
	_lobby.players_updated.emit(list)


func notify_hero_changed() -> void:
	if not is_session_active():
		return

	if multiplayer.is_server():
		var my_id := multiplayer.get_unique_id()
		_session.update_hero(my_id, PlayerProfile.hero_scene)
		_broadcast_player_list()
	else:
		_lobby._rpc_update_hero.rpc_id(1, PlayerProfile.hero_scene)


func _rpc_update_hero(hero_scene: String) -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	_session.update_hero(sender_id, hero_scene)
	_broadcast_player_list()


func is_steam_ready() -> bool:
	return _steam_ready


func _steam_available() -> bool:
	return Engine.has_singleton("Steam")


# Calls into other services go through the facade.


func _clear_autoload_spawns() -> void:
	_lobby._clear_autoload_spawns()


func _finish_leave_to_menu() -> void:
	_lobby._finish_leave_to_menu()


func _handle_transition_peer_left(id: int) -> void:
	_lobby._handle_transition_peer_left(id)


func _reset_mission_loading() -> void:
	_lobby._reset_mission_loading()


func _reset_pending_scene_spawns() -> void:
	_lobby._reset_pending_scene_spawns()


func _reset_scene_transition() -> void:
	_lobby._reset_scene_transition()
