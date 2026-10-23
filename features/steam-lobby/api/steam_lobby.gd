# Steam lobby API and orchestration. Net transport, session, spawn, and sync
# details live in features/net/*.
extends Node

signal lobby_ready(lobby_id: int)
signal lobby_failed(reason: String)
signal players_updated(players: Array)

const NetSteamTransport := preload("res://features/net/transport/steam_transport.gd")
const NetSession := preload("res://features/net/session/net_session.gd")
const NetSpawner := preload("res://features/net/spawn/net_spawner.gd")
const NetDrops := preload("res://features/net/sync/net_drops.gd")
const LoadingScreenScene := preload("res://features/net/loading/loading_screen.tscn")

const LOBBY_TYPE_PUBLIC := 2
const RESULT_OK := 1
const HUB_SCENE := "res://screens/hub/ui/hub.tscn"
const RUNOUTS_MENU_SCENE := "res://screens/hub/ui/runouts-menu/RunoutsMenu.tscn"
const MISSION_SCENE := "res://screens/mission/ui/mission.tscn"
const HUB_PROFILE_SYNC_TIMEOUT_SECONDS := 6.0

var _steam_ready: bool = false
var _creating_lobby: bool = false
var _requested_lobby_id: int = 0
var _connection_deadline: int = 0

var lobby_id: int = 0
var peer: MultiplayerPeer
var is_host: bool = false
var is_joining: bool = false

var _transport := NetSteamTransport.new()
var _session := NetSession.new()
var _spawner := NetSpawner.new()
var _drops := NetDrops.new()

var _pending_hub: Node3D
var _pending_spawns: Array = []
var _hub_spawn_waiting: Dictionary = {}
var _pending_mission: Node3D
var _pending_mission_spawns: Array = []
var _hub_spawn_round: int = 0

var _loading_screen: NetworkLoadingScreen
var _mission_loading_transition_id: int = 0
var _mission_ready_waiting: Dictionary = {}
var _mission_completion_scheduled: bool = false
var _mission_spawn_waiting: Dictionary = {}

# Смена сетевой сцены проходит через prepare/commit. Пока все клиенты не
# отключили старые MultiplayerSynchronizer, сцена остаётся в дереве и может
# безопасно принять уже отправленные пакеты синхронизации.
var _scene_transition_id: int = 0
var _scene_transition_path: String = ""
var _scene_transition_waiting: Dictionary = {}
var _scene_transition_active: bool = false
var _scene_transition_commit_scheduled: bool = false
var _scene_load_started_waiting: Dictionary = {}
var _scene_load_retry_round: int = 0
var _threaded_load_transition_id: int = 0
var _threaded_load_path: String = ""


func _ready() -> void:
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
		lobby_failed.emit("Steam init failed")
		return

	await get_tree().process_frame

	print("Steam ID: ", Steam.getSteamID())
	SaveManager.load_profile()
	Steam.initRelayNetworkAccess()
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	print("Loaded hero: ", PlayerProfile.hero_scene)

	_steam_ready = true


func _process(_delta: float) -> void:
	if _steam_ready:
		Steam.run_callbacks()
	if _connection_deadline != 0 and Time.get_ticks_msec() >= _connection_deadline:
		disconnect_lobby()
		lobby_failed.emit("Время ожидания подключения истекло. Проверьте, что хост доступен и версии игры совпадают.")


func is_session_active() -> bool:
	return peer != null and multiplayer.has_multiplayer_peer()


func is_mission_loading() -> bool:
	return _mission_loading_transition_id != 0


func host_lobby() -> void:
	if _connection_deadline != 0:
		return
	if not is_steam_ready():
		lobby_failed.emit("Steam не инициализирован")
		return

	if lobby_id != 0:
		disconnect_lobby()

	_creating_lobby = true
	is_host = true
	_connection_deadline = Time.get_ticks_msec() + 30000
	Steam.createLobby(LOBBY_TYPE_PUBLIC, 4)


func join_lobby(id: int) -> void:
	if _connection_deadline != 0:
		return
	if id <= 0:
		lobby_failed.emit("Некорректный код лобби")
		return
	if not is_steam_ready():
		lobby_failed.emit("Steam не инициализирован")
		return

	if lobby_id != 0:
		disconnect_lobby()

	is_joining = true
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

	for connected_id in multiplayer.get_peers():
		if not _session.player_states.has(int(connected_id)):
			lobby_failed.emit("Дождитесь получения данных всех игроков")
			return

	for peer_id in _session.player_states:
		var state: PlayerState = _session.player_states[peer_id]
		if state.hero_scene.is_empty():
			push_warning("SteamLobby: игрок %d не выбрал героя" % peer_id)
			return

	# Мир принадлежит хосту; профили персонажей в этот файл не пишутся.
	SaveManager.save_world_progress(SaveManager.load_world_progress())
	_begin_network_scene_change(HUB_SCENE)


func leave_to_main_menu() -> void:
	if is_session_active() and multiplayer.is_server():
		_rpc_host_left.rpc()
	# Отложенный выход не удаляет текущую сцену внутри её обработчика GUI.
	_finish_leave_to_menu.call_deferred()


@rpc("authority", "call_remote", "reliable")
func _rpc_host_left() -> void:
	_finish_leave_to_menu.call_deferred()


func _finish_leave_to_menu() -> void:
	for node in get_tree().get_nodes_in_group("player"):
		if node is Player and node.owns_local_profile:
			SaveManager.save_player_state(node.inventory, node.equipment)
	disconnect_lobby()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://screens/main-menu/ui/main_menu.tscn")


func request_scene_change(scene_path: String) -> void:
	if not _is_allowed_gameplay_scene(scene_path):
		push_warning("SteamLobby: запрещён переход на сцену '%s'" % scene_path)
		return
	if not is_session_active():
		var hero := _hero_for_peer(1) as Player
		if hero != null and not SaveManager.save_player_state(hero.inventory, hero.equipment):
			return
		get_tree().change_scene_to_file(scene_path)
		return
	if multiplayer.is_server():
		_begin_network_scene_change(scene_path)
	else:
		_rpc_request_scene_change.rpc_id(1, scene_path)


@rpc("any_peer", "reliable")
func _rpc_request_scene_change(scene_path: String) -> void:
	if not multiplayer.is_server() or not _is_allowed_gameplay_scene(scene_path):
		return
	_begin_network_scene_change(scene_path)


func _begin_network_scene_change(scene_path: String) -> void:
	if not multiplayer.is_server() or is_gameplay_locked():
		return
	if not _is_allowed_gameplay_scene(scene_path):
		return

	# Поздний вход требует отдельной синхронизации мира и пока не поддерживается.
	peer.refuse_new_connections = true
	if _steam_ready and lobby_id != 0:
		Steam.setLobbyJoinable(lobby_id, false)
	_scene_transition_id += 1
	_scene_transition_path = scene_path
	_scene_transition_waiting = _connected_peer_set()
	_scene_transition_active = true
	_scene_transition_commit_scheduled = false
	if scene_path == MISSION_SCENE or scene_path == HUB_SCENE:
		_mission_loading_transition_id = _scene_transition_id
		_mission_ready_waiting = _connected_peer_set()
		_mission_completion_scheduled = false
		_rpc_show_mission_loading.rpc(_scene_transition_id, _mission_loading_roster(), "Загрузка хаба" if scene_path == HUB_SCENE else "Загрузка миссии")
	_rpc_prepare_scene_change.rpc(_scene_transition_id, scene_path)


func _mission_loading_roster() -> Array:
	var players := _session.player_list()
	var listed: Dictionary = {}
	for player_value in players:
		var player: Dictionary = player_value
		listed[int(player.get("peer_id", 0))] = true
	for peer_id_value in _connected_peer_set().keys():
		var peer_id := int(peer_id_value)
		if not listed.has(peer_id):
			players.append({
				"peer_id": peer_id,
				"character_name": "Игрок %d" % peer_id,
				"nickname": "",
			})
	return players


@rpc("authority", "call_local", "reliable")
func _rpc_show_mission_loading(transition_id: int, players: Array, title: String) -> void:
	_mission_loading_transition_id = transition_id
	_show_loading_screen(players)
	_loading_screen.title_label.text = title


func _show_loading_screen(players: Array) -> void:
	if is_instance_valid(_loading_screen):
		_loading_screen.queue_free()
	_loading_screen = LoadingScreenScene.instantiate() as NetworkLoadingScreen
	add_child(_loading_screen)
	_loading_screen.configure(players)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _reset_mission_loading() -> void:
	_mission_loading_transition_id = 0
	_mission_ready_waiting.clear()
	_mission_spawn_waiting.clear()
	_mission_completion_scheduled = false
	if is_instance_valid(_loading_screen):
		_loading_screen.queue_free()
	_loading_screen = null


@rpc("authority", "call_local", "reliable")
func _rpc_prepare_scene_change(transition_id: int, scene_path: String) -> void:
	if not _is_allowed_gameplay_scene(scene_path):
		return

	_scene_transition_id = transition_id
	_scene_transition_path = scene_path
	_scene_transition_active = true
	_disable_current_scene_synchronizers()

	var local_peer_id := multiplayer.get_unique_id()
	var hero := _hero_for_peer(local_peer_id) as Player
	if hero != null:
		while hero.inventory.network_pending:
			await get_tree().process_frame
		if not SaveManager.save_player_state(hero.inventory, hero.equipment):
			push_error("Не удалось сохранить персонажа перед переходом")
			return
	if multiplayer.is_server():
		_mark_scene_change_prepared(local_peer_id, transition_id)
	else:
		_rpc_scene_change_prepared.rpc_id(1, transition_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_scene_change_prepared(transition_id: int) -> void:
	if not multiplayer.is_server():
		return
	_mark_scene_change_prepared(multiplayer.get_remote_sender_id(), transition_id)


func _mark_scene_change_prepared(peer_id: int, transition_id: int) -> void:
	if not multiplayer.is_server() or transition_id != _scene_transition_id:
		return
	_scene_transition_waiting.erase(peer_id)
	if _scene_transition_waiting.is_empty() and not _scene_transition_commit_scheduled:
		_scene_transition_commit_scheduled = true
		_finish_scene_change_prepare(transition_id)


func _finish_scene_change_prepare(transition_id: int) -> void:
	# Даём старым ненадёжным sync-пакетам дойти, пока их узлы ещё существуют.
	await get_tree().create_timer(0.25, true).timeout
	if not multiplayer.is_server() or transition_id != _scene_transition_id:
		return
	_dispatch_scene_load(transition_id, _scene_transition_path)


func _dispatch_scene_load(transition_id: int, scene_path: String) -> void:
	# Сначала отдельно отправляем команду каждому клиенту и ждём короткого
	# подтверждения. Так хост не удаляет старую сцену в том же RPC-вызове,
	# из-за чего пакет перехода мог не успеть уйти одному из пиров.
	_scene_load_started_waiting.clear()
	_scene_load_retry_round = 0
	for peer_id in multiplayer.get_peers():
		var remote_peer_id := int(peer_id)
		_scene_load_started_waiting[remote_peer_id] = true
		_rpc_load_gameplay_scene.rpc_id(remote_peer_id, transition_id, scene_path)
	if _scene_load_started_waiting.is_empty():
		_start_threaded_scene_load(transition_id, scene_path)
	else:
		_retry_unacknowledged_scene_loads(transition_id, scene_path)


func _retry_unacknowledged_scene_loads(transition_id: int, scene_path: String) -> void:
	await get_tree().create_timer(2.0, true).timeout
	if not multiplayer.is_server() or transition_id != _scene_transition_id:
		return
	if _scene_load_started_waiting.is_empty():
		return
	_scene_load_retry_round += 1
	var connected_peers := multiplayer.get_peers()
	for peer_id_value in _scene_load_started_waiting.keys():
		var peer_id := int(peer_id_value)
		if connected_peers.has(peer_id):
			_rpc_load_gameplay_scene.rpc_id(peer_id, transition_id, scene_path)
		else:
			_scene_load_started_waiting.erase(peer_id)
	if _scene_load_started_waiting.is_empty():
		_start_threaded_scene_load(transition_id, scene_path)
		return
	if is_instance_valid(_loading_screen):
		_loading_screen.set_status("Ожидание ответа игроков…")
	_retry_unacknowledged_scene_loads(transition_id, scene_path)


@rpc("authority", "call_remote", "reliable")
func _rpc_load_gameplay_scene(transition_id: int, scene_path: String) -> void:
	if transition_id != _scene_transition_id:
		return
	if not _is_allowed_gameplay_scene(scene_path):
		return
	_rpc_scene_load_started.rpc_id(1, transition_id)
	_start_threaded_scene_load(transition_id, scene_path)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_scene_load_started(transition_id: int) -> void:
	if not multiplayer.is_server() or transition_id != _scene_transition_id:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	_scene_load_started_waiting.erase(peer_id)
	if _scene_load_started_waiting.is_empty():
		_start_threaded_scene_load(transition_id, _scene_transition_path)


func _start_threaded_scene_load(transition_id: int, scene_path: String) -> void:
	if transition_id != _scene_transition_id or not _is_allowed_gameplay_scene(scene_path):
		return
	if _threaded_load_transition_id == transition_id:
		return
	_threaded_load_transition_id = transition_id
	_threaded_load_path = scene_path
	if is_instance_valid(_loading_screen):
		_loading_screen.set_progress(0.0)

	var request_error := ResourceLoader.load_threaded_request(scene_path, "PackedScene", true)
	if request_error != OK:
		_threaded_load_transition_id = 0
		_threaded_load_path = ""
		_report_scene_load_failure(transition_id, "Не удалось начать загрузку сцены: %s" % error_string(request_error))
		return
	_poll_threaded_scene_load(transition_id, scene_path)


func _poll_threaded_scene_load(transition_id: int, scene_path: String) -> void:
	while transition_id == _threaded_load_transition_id and scene_path == _threaded_load_path:
		var progress: Array = []
		var status := ResourceLoader.load_threaded_get_status(scene_path, progress)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if is_instance_valid(_loading_screen) and not progress.is_empty():
				_loading_screen.set_progress(float(progress[0]))
			await get_tree().process_frame
			continue
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var packed_scene := ResourceLoader.load_threaded_get(scene_path) as PackedScene
			if packed_scene == null:
				_report_scene_load_failure(transition_id, "Загруженный ресурс не является сценой")
			else:
				_commit_loaded_scene(transition_id, scene_path, packed_scene)
			return
		_report_scene_load_failure(transition_id, "Ошибка фоновой загрузки сцены")
		return


func _commit_loaded_scene(transition_id: int, scene_path: String, packed_scene: PackedScene) -> void:
	if transition_id != _scene_transition_id or scene_path != _scene_transition_path:
		return
	_reset_pending_scene_spawns()
	_clear_autoload_spawns()
	_drops.clear()
	if is_instance_valid(_loading_screen):
		_loading_screen.set_progress(1.0)
	var change_error := get_tree().change_scene_to_packed(packed_scene)
	if change_error != OK:
		_report_scene_load_failure(transition_id, "Не удалось открыть сцену: %s" % error_string(change_error))
		return
	await get_tree().scene_changed
	if transition_id == _scene_transition_id:
		_reset_scene_transition()


func _report_scene_load_failure(transition_id: int, message: String) -> void:
	_threaded_load_transition_id = 0
	_threaded_load_path = ""
	push_error("SteamLobby: %s" % message)
	if is_instance_valid(_loading_screen):
		_loading_screen.set_status("Ошибка загрузки")
	if not multiplayer.is_server() and is_session_active():
		_rpc_scene_load_failed.rpc_id(1, transition_id, message)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_scene_load_failed(transition_id: int, message: String) -> void:
	if not multiplayer.is_server() or transition_id != _scene_transition_id:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	push_error("SteamLobby: peer %d не загрузил сцену: %s" % [peer_id, message])
	_rpc_mark_scene_load_failed.rpc(transition_id, peer_id)


@rpc("authority", "call_local", "reliable")
func _rpc_mark_scene_load_failed(transition_id: int, peer_id: int) -> void:
	if transition_id != _mission_loading_transition_id or not is_instance_valid(_loading_screen):
		return
	_loading_screen.set_player_error(peer_id)
	_loading_screen.set_status("Один из игроков не загрузил сцену")


func _disable_current_scene_synchronizers() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	for node in scene.find_children("*", "MultiplayerSynchronizer", true, false):
		var synchronizer := node as MultiplayerSynchronizer
		if synchronizer != null:
			synchronizer.public_visibility = false
			for peer_id in multiplayer.get_peers():
				synchronizer.set_visibility_for(int(peer_id), false)


func _reset_scene_transition() -> void:
	_scene_transition_path = ""
	_scene_transition_waiting.clear()
	_scene_load_started_waiting.clear()
	_scene_transition_active = false
	_scene_transition_commit_scheduled = false
	_scene_load_retry_round = 0
	_threaded_load_transition_id = 0
	_threaded_load_path = ""


func _is_allowed_gameplay_scene(scene_path: String) -> bool:
	return scene_path == HUB_SCENE or scene_path == MISSION_SCENE


func _connected_peer_set() -> Dictionary:
	var waiting := {multiplayer.get_unique_id(): true}
	for peer_id in multiplayer.get_peers():
		waiting[int(peer_id)] = true
	return waiting


func _reset_pending_scene_spawns() -> void:
	_hub_spawn_round += 1
	_pending_hub = null
	_pending_spawns = []
	_hub_spawn_waiting.clear()
	_pending_mission = null
	_pending_mission_spawns = []


func _resolve_disconnected_spawn_wait(peer_id: int) -> void:
	if _hub_spawn_waiting.has(peer_id):
		_hub_spawn_waiting.erase(peer_id)
		if _hub_spawn_waiting.is_empty():
			_finalize_hub_spawn()
	if _mission_loading_transition_id != 0 and multiplayer.is_server():
		var was_spawning := _mission_spawn_waiting.has(peer_id)
		_mission_spawn_waiting.erase(peer_id)
		if was_spawning and _mission_spawn_waiting.is_empty():
			_rpc_finish_mission_loading.rpc(_mission_loading_transition_id)
		_mission_ready_waiting.erase(peer_id)
		_rpc_remove_loading_player.rpc(_mission_loading_transition_id, peer_id)
		_try_complete_mission_loading()
	elif _mission_loading_transition_id != 0 and peer_id == 1 and is_instance_valid(_loading_screen):
		_loading_screen.set_status("Соединение с хостом потеряно")


func spawn_mission_players(mission: Node3D, spawn_points: Array) -> void:
	if not is_session_active():
		return
	if spawn_points.is_empty():
		push_error("SteamLobby: нет точек спавна в миссии")
		return

	mission.process_mode = Node.PROCESS_MODE_DISABLED
	SaveManager.ensure_starter_inventory_if_empty()
	var peer_id := multiplayer.get_unique_id()
	var state_data := _session.register_local_player(peer_id)
	if multiplayer.is_server():
		_pending_mission = mission
		_pending_mission_spawns = spawn_points
		_mark_mission_player_ready(peer_id, _mission_loading_transition_id, state_data)
	else:
		_rpc_mission_player_ready.rpc_id(1, _mission_loading_transition_id, state_data)


@rpc("any_peer", "reliable")
func _rpc_mission_player_ready(transition_id: int, state_data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	_mark_mission_player_ready(sender_id, transition_id, state_data)


func _mark_mission_player_ready(peer_id: int, transition_id: int, state_data: Dictionary) -> void:
	if not multiplayer.is_server() or transition_id != _mission_loading_transition_id:
		return
	if not _mission_ready_waiting.has(peer_id):
		return
	if peer_id != multiplayer.get_unique_id():
		_session.register_remote_player(peer_id, state_data)
	_mission_ready_waiting.erase(peer_id)
	_try_complete_mission_loading()


func _try_complete_mission_loading() -> void:
	if not multiplayer.is_server() or not _mission_ready_waiting.is_empty():
		return
	if not is_instance_valid(_pending_mission) or _pending_mission_spawns.is_empty():
		return
	if _mission_completion_scheduled:
		return
	_mission_completion_scheduled = true
	_finish_mission_loading(_mission_loading_transition_id)


func _finish_mission_loading(transition_id: int) -> void:
	# Даём последнему яркому имени отрисоваться перед общим запуском.
	await get_tree().create_timer(0.35, true).timeout
	if not multiplayer.is_server() or transition_id != _mission_loading_transition_id:
		return
	if not _mission_ready_waiting.is_empty():
		_mission_completion_scheduled = false
		return
	_finalize_mission_spawn(transition_id)


func _finalize_mission_spawn(transition_id: int) -> void:
	if not is_instance_valid(_pending_mission) or _pending_mission_spawns.is_empty():
		return
	if _pending_mission.scene_file_path == HUB_SCENE:
		_pending_mission.sync_world_progress_to_peers(SaveManager.load_world_progress())
		_pending_mission.spawn_test_dog_for_session()

	_mission_spawn_waiting = _connected_peer_set()
	for peer_id in _session.player_states:
		var state_data := _session.player_state_data(peer_id)
		var spawn_index := (maxi(1, int(peer_id)) - 1) % _pending_mission_spawns.size()
		var spawn_position: Vector3 = _pending_mission_spawns[spawn_index].global_position
		_rpc_spawn_mission_player.rpc(state_data, spawn_position)

	_pending_mission = null
	_pending_mission_spawns = []
	_rpc_confirm_mission_spawn.rpc(transition_id, _session.player_states.keys())


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_mission_player(state_data: Dictionary, spawn_position: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null or not scene.scene_file_path in [MISSION_SCENE, HUB_SCENE]:
		push_error("SteamLobby: получен спавн до готовности миссии")
		return
	_spawner.spawn_player(scene, state_data, spawn_position)


@rpc("authority", "call_local", "reliable")
func _rpc_set_loading_player_ready(transition_id: int, peer_id: int) -> void:
	if transition_id != _mission_loading_transition_id or not is_instance_valid(_loading_screen):
		return
	_loading_screen.set_player_ready(peer_id, true)


@rpc("authority", "call_local", "reliable")
func _rpc_remove_loading_player(transition_id: int, peer_id: int) -> void:
	if transition_id != _mission_loading_transition_id or not is_instance_valid(_loading_screen):
		return
	_loading_screen.remove_player(peer_id)


@rpc("authority", "call_local", "reliable")
func _rpc_finish_mission_loading(transition_id: int) -> void:
	if transition_id != _mission_loading_transition_id:
		return
	if is_instance_valid(_loading_screen):
		_loading_screen.set_status("Все игроки готовы")
	_hide_loading_after_spawn(transition_id)


func _hide_loading_after_spawn(transition_id: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if transition_id != _mission_loading_transition_id:
		return
	_reset_mission_loading()
	var scene := get_tree().current_scene
	if scene != null:
		scene.process_mode = Node.PROCESS_MODE_INHERIT
		for node in scene.find_children("*", "MultiplayerSynchronizer", true, false):
			node.public_visibility = true
		var local_player := scene.get_node_or_null(str(multiplayer.get_unique_id())) as Player
		if local_player != null:
			local_player.call_deferred("_activate_local_camera")


func spawn_hub_players(hub: Node3D, spawn_points: Array) -> void:
	# Хаб использует тот же барьер готовности сцены и героев, что и миссия.
	spawn_mission_players(hub, spawn_points)


func _wait_for_hub_profiles(spawn_round: int) -> void:
	await get_tree().create_timer(HUB_PROFILE_SYNC_TIMEOUT_SECONDS, true).timeout
	if spawn_round != _hub_spawn_round or not is_instance_valid(_pending_hub):
		return
	if _hub_spawn_waiting.is_empty():
		return
	push_warning("SteamLobby: хаб продолжает спавн без ответа от peer %s" % str(_hub_spawn_waiting.keys()))
	_hub_spawn_waiting.clear()
	_finalize_hub_spawn()


@rpc("authority", "call_local", "reliable")
func _rpc_sync_profile_before_spawn() -> void:
	SaveManager.ensure_starter_inventory_if_empty()
	var peer_id := multiplayer.get_unique_id()
	var state_data := _session.register_local_player(peer_id)

	if multiplayer.is_server():
		_on_spawn_profile_sync_done(peer_id)
	else:
		_rpc_spawn_profile_sync.rpc_id(1, state_data)


@rpc("any_peer", "reliable")
func _rpc_spawn_profile_sync(state_data: Dictionary) -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	_session.register_remote_player(sender_id, state_data)
	_on_spawn_profile_sync_done(sender_id)


func _on_spawn_profile_sync_done(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if not _hub_spawn_waiting.has(peer_id):
		return
	_hub_spawn_waiting.erase(peer_id)
	if not _hub_spawn_waiting.is_empty():
		return
	_finalize_hub_spawn()


func _finalize_hub_spawn() -> void:
	if _pending_hub == null or _pending_spawns.is_empty():
		return

	# Файл мира принадлежит хосту. Клиенты получают тот же снимок только по
	# сети и поэтому не могут случайно перезаписать локальный мир хоста.
	_pending_hub.sync_world_progress_to_peers(SaveManager.load_world_progress())
	_pending_hub.spawn_test_dog_for_session()

	for peer_id in _session.player_states:
		var state_data := _session.player_state_data(peer_id)
		var spawn_index := (maxi(1, int(peer_id)) - 1) % _pending_spawns.size()
		var spawn_pos: Vector3 = _pending_spawns[spawn_index].global_position
		_rpc_spawn_hub_player.rpc(state_data, spawn_pos)

	_pending_hub = null
	_pending_spawns = []


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_hub_player(state_data: Dictionary, spawn_position: Vector3) -> void:
	call_deferred("_deferred_spawn_hub_player", state_data, spawn_position)


func _deferred_spawn_hub_player(state_data: Dictionary, spawn_position: Vector3) -> void:
	for _frame in range(600):
		var hub := _get_hub_scene()
		if hub != null:
			_spawner.spawn_player(hub, state_data, spawn_position)
			return
		await get_tree().process_frame
	push_error("SteamLobby: не удалось заспавнить игрока — хаб не загружен")


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
		lobby_failed.emit("Failed to create lobby: %d" % result)
		push_error("SteamLobby: не удалось создать лобби: %d" % result)
		return

	lobby_id = id
	peer = _transport.create_steam_host(multiplayer)
	if peer == null:
		var reason := "Не удалось создать Steam-сервер: %s" % error_string(_transport.last_error)
		disconnect_lobby()
		lobby_failed.emit(reason)
		return
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	_session.register_local_player(1)
	lobby_ready.emit(lobby_id)
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
		lobby_failed.emit("Не удалось войти в Steam-лобби: %d" % response)
		return

	lobby_id = id
	var owner_id: int = Steam.getLobbyOwner(lobby_id)
	if owner_id == 0 or owner_id == Steam.getSteamID():
		disconnect_lobby()
		lobby_failed.emit("Хост лобби недоступен")
		return
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)
	# Подписываемся до установки peer в MultiplayerAPI.
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server, CONNECT_ONE_SHOT)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed, CONNECT_ONE_SHOT)
	peer = _transport.create_steam_client(multiplayer, owner_id)
	if peer == null:
		var reason := "Не удалось создать Steam-клиент: %s" % error_string(_transport.last_error)
		disconnect_lobby()
		lobby_failed.emit(reason)
		return
	is_joining = false

	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("SteamLobby: в лобби, ожидание P2P-подключения к хосту...")


func _on_connected_to_server() -> void:
	var state_data := _session.register_local_player(multiplayer.get_unique_id())
	_rpc_send_state.rpc_id(1, state_data)
	# Меню открывается после подтверждения профиля списком игроков от хоста.
	print("SteamLobby: P2P подключён, peer_id=", multiplayer.get_unique_id())


func _on_connection_failed() -> void:
	disconnect_lobby()
	lobby_failed.emit("Не удалось подключиться к хосту")


func _on_server_disconnected() -> void:
	# В том числе когда хост вышел через ворота: надёжный RPC о выходе
	# может не успеть дойти до закрытия транспорта.
	_finish_leave_to_menu.call_deferred()
	lobby_failed.emit("Соединение с хостом потеряно")


func _on_peer_connected(id: int) -> void:
	print("SteamLobby: подключился peer ", id)


func _on_peer_disconnected(id: int) -> void:
	print("SteamLobby: отключился peer ", id)
	_session.remove_player(id)
	_resolve_disconnected_spawn_wait(id)
	if multiplayer.is_server() and _scene_transition_waiting.has(id):
		_scene_transition_waiting.erase(id)
		if _scene_transition_waiting.is_empty() and not _scene_transition_commit_scheduled:
			_scene_transition_commit_scheduled = true
			_finish_scene_change_prepare(_scene_transition_id)
	if multiplayer.is_server() and _scene_load_started_waiting.has(id):
		_scene_load_started_waiting.erase(id)
		if _scene_load_started_waiting.is_empty() and _threaded_load_transition_id == 0:
			_start_threaded_scene_load(_scene_transition_id, _scene_transition_path)
	if multiplayer.is_server():
		_rpc_despawn_hub_player.rpc(id)
	else:
		# Клиент не имеет права вызывать authority RPC. При потере хоста
		# удаляем его копию локально, не создавая сетевую ошибку поверх разрыва.
		var scene := get_tree().current_scene
		if scene != null:
			_spawner.despawn_player(scene, id)


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
	if not multiplayer.is_server() and _connection_deadline != 0:
		for player_data in list:
			if int(player_data.get("peer_id", 0)) == multiplayer.get_unique_id():
				_connection_deadline = 0
				lobby_ready.emit(lobby_id)
				break
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


# ════════════════════════════════════════════════
# РАЗВИТИЕ ПЕРСОНАЖА
# Хост проверяет наличие реликвии и свободного очка, затем рассылает
# одинаковое состояние всем копиям героя.
# ════════════════════════════════════════════════
func request_spend_attribute(attribute_name: String) -> void:
	if not is_session_active():
		return
	if multiplayer.is_server():
		_server_spend_attribute(multiplayer.get_unique_id(), attribute_name)
	else:
		_rpc_request_spend_attribute.rpc_id(1, attribute_name)


@rpc("any_peer", "reliable")
func _rpc_request_spend_attribute(attribute_name: String) -> void:
	if multiplayer.is_server():
		_server_spend_attribute(multiplayer.get_remote_sender_id(), attribute_name)


func _server_spend_attribute(peer_id: int, attribute_name: String) -> void:
	var stats := _stats_for_peer(peer_id)
	if stats == null or not stats._apply_spent_attribute(attribute_name):
		return
	var progress := stats.get_progress_data()
	_session.update_progress(peer_id, progress)
	_rpc_apply_progress.rpc(peer_id, progress)


@rpc("authority", "call_local", "reliable")
func _rpc_apply_progress(peer_id: int, progress: Dictionary) -> void:
	var stats := _stats_for_peer(peer_id)
	if stats != null:
		stats.apply_progress_data(progress)
	_session.update_progress(peer_id, progress)


func _hero_for_peer(peer_id: int) -> Node:
	var scene := get_tree().current_scene
	return scene.get_node_or_null(str(peer_id)) if scene != null else null


func chat_player_name(peer_id: int) -> String:
	if not is_session_active():
		return PlayerProfile.character_name
	if _session.player_states.has(peer_id):
		var state: PlayerState = _session.player_states[peer_id]
		return state.character_name if not state.character_name.is_empty() else state.nickname
	return "Игрок %d" % peer_id


func execute_chat_command(peer_id: int, message: String) -> String:
	# Команды доступны всем игрокам для тестирования, но меняют только
	# их собственного героя. В сетевой игре выдачу выполняет хост.
	if is_session_active() and not multiplayer.is_server():
		return "Команду должен выполнить хост."
	if is_gameplay_locked():
		return "Дождитесь окончания загрузки."
	var hero := _hero_for_peer(peer_id) as Player
	if hero == null and not is_session_active():
		var scene := get_tree().current_scene
		if scene != null:
			for candidate in scene.find_children("*", "CharacterBody3D", true, false):
				if candidate is Player and candidate.is_multiplayer_authority():
					hero = candidate as Player
					break
	if hero == null:
		return "Команды выдачи доступны после появления героя в мире."
	if hero.inventory.network_pending:
		return "Дождитесь завершения операции с инвентарём."
	var separator := message.find(" ")
	var command := message.substr(0, separator) if separator >= 0 else message
	var argument := message.substr(separator + 1).strip_edges() if separator >= 0 else ""
	match command.to_lower():
		"/give":
			var selected: ItemData = null
			argument = argument.trim_prefix('"').trim_suffix('"')
			for item in ItemLibrary.all_items():
				if item.id.to_lower() == argument.to_lower() or item.item_name.to_lower() == argument.to_lower():
					selected = item
					break
			if selected == null:
				return "Предмет не найден. /items — список; /give <id или название>."
			if not hero.inventory.add_item(selected):
				return "Инвентарь заполнен."
			if is_session_active():
				hero.inventory.network_revision += 1
				_publish_inventory(peer_id)
			else:
				SaveManager.save_player_state(hero.inventory, hero.equipment)
			return "Выдан предмет: %s" % selected.item_name
		"/xp", "/exp":
			if not argument.is_valid_int() or int(argument) < 1 or int(argument) > 100000:
				return "Использование: /xp <число от 1 до 100000>."
			hero.stats.add_experience(int(argument))
			if is_session_active():
				var progress := hero.stats.get_progress_data()
				_session.update_progress(peer_id, progress)
				_rpc_apply_progress.rpc(peer_id, progress)
			return "Выдано опыта: %d" % int(argument)
	return "Неизвестная команда. /help — список команд."


func _inventory_for_peer(peer_id: int) -> InventoryComponent:
	var hero := _hero_for_peer(peer_id)
	return hero.get_node_or_null("InventoryComponent") as InventoryComponent if hero != null else null


func _stats_for_peer(peer_id: int) -> StatsComponent:
	var hero := _hero_for_peer(peer_id)
	return hero.get_node_or_null("StatsComponent") as StatsComponent if hero != null else null


# ════════════════════════════════════════════════════════
# ПРЕДМЕТЫ В МИРЕ
# Выбросить может любой игрок, но id предмету назначает и подбор
# подтверждает сервер — так один предмет не достанется двоим сразу.
# Работает и без сессии (соло): тогда всё происходит локально.
# ════════════════════════════════════════════════════════

# Выбросить предмет. position — точка старта, direction — куда бросать.
func request_drop(item_id: String, position: Vector3, direction: Vector3, thrower: Node3D = null) -> void:
	if item_id.is_empty():
		return

	if not is_session_active():
		var item: ItemData = ItemLibrary.get_item(item_id)
		if item == null:
			return
		var scene := get_tree().current_scene
		if scene != null:
			_drops.spawn(scene, _drops.allocate_id(), item, position, direction, thrower)
		return

	var inventory := _local_inventory()
	if inventory != null:
		var location := inventory.find_item_location(item_id)
		if not location.is_empty():
			inventory.network_request({"kind": "drop", "source": location.source, "index": location.slot_index})


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_drop(drop_id: int, item_id: String, position: Vector3, direction: Vector3, thrower_peer: int) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var item: ItemData = ItemLibrary.get_item(item_id)
	if item == null:
		return
	# Бросивший герой исключается из поиска земли, чтобы предмет не «встал» на него
	var thrower := scene.get_node_or_null(str(thrower_peer)) as Node3D
	_drops.spawn(scene, drop_id, item, position, direction, thrower)


# Игрок дошёл до предмета и просит его забрать.
# picker — инвентарь того, кто просит (нужен в соло-режиме).
func request_pickup(drop_id: int, picker: InventoryComponent) -> void:
	if not is_session_active():
		if _drops.has_drop(drop_id):
			var item_id := _drops.get_item_id(drop_id)
			_drops.remove(drop_id)
			_apply_pickup_grant(picker, item_id)
		return

	if multiplayer.is_server():
		_server_handle_pickup(multiplayer.get_unique_id(), drop_id)
	else:
		_rpc_request_pickup.rpc_id(1, drop_id)


@rpc("any_peer", "reliable")
func _rpc_request_pickup(drop_id: int) -> void:
	if not multiplayer.is_server():
		return
	_server_handle_pickup(multiplayer.get_remote_sender_id(), drop_id)


func _server_handle_pickup(picker_peer: int, drop_id: int) -> void:
	if is_gameplay_locked():
		return
	# Предмет уже забрал кто-то другой (или он давно исчез)
	if not _drops.has_drop(drop_id):
		return

	var item_id := _drops.get_item_id(drop_id)
	var server_inventory := _inventory_for_peer(picker_peer)
	var item := ItemLibrary.get_item(item_id)
	if server_inventory == null or item == null or not server_inventory.has_free_slot():
		return

	_rpc_remove_drop.rpc(drop_id)
	server_inventory.add_item(item)
	server_inventory.network_revision += 1
	_publish_inventory(picker_peer)


@rpc("authority", "call_local", "reliable")
func _rpc_remove_drop(drop_id: int) -> void:
	_drops.remove(drop_id)


func _apply_pickup_grant(inventory: InventoryComponent, item_id: String) -> void:
	var item: ItemData = ItemLibrary.get_item(item_id)
	if item == null or inventory == null:
		return

	if inventory.add_item(item):
		return

	# Редкая гонка: инвентарь заполнился между запросом и ответом сервера —
	# возвращаем предмет в мир, чтобы он не пропал.
	var hero := inventory.get_parent() as Node3D
	if hero == null:
		return
	var direction := Vector3(0, 0, -1)
	if hero.has_method("get_facing_direction"):
		direction = hero.call("get_facing_direction")
	request_drop(item_id, hero.global_position + Vector3(0, 1.0, 0), direction, hero)


func _local_inventory() -> InventoryComponent:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var hero := scene.get_node_or_null(str(multiplayer.get_unique_id()))
	if hero == null:
		return null
	return hero.get_node_or_null("InventoryComponent") as InventoryComponent


func _clear_autoload_spawns() -> void:
	for child in get_children():
		if child.name.is_valid_int():
			child.queue_free()


# true только если steamInit прошёл успешно и initRelayNetworkAccess вызван.
# Используй для отключения кнопки Host Game в главном меню.
func is_steam_ready() -> bool:
	return _steam_ready


func _steam_available() -> bool:
	return Engine.has_singleton("Steam")


func is_gameplay_locked() -> bool:
	return _scene_transition_active or is_mission_loading()


func request_inventory_operation(sequence: int, revision: int, command: Dictionary) -> void:
	if multiplayer.is_server():
		_server_inventory_operation(multiplayer.get_unique_id(), sequence, revision, command)
	else:
		_rpc_inventory_operation.rpc_id(1, sequence, revision, command)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_inventory_operation(sequence: int, revision: int, command: Dictionary) -> void:
	if multiplayer.is_server():
		_server_inventory_operation(multiplayer.get_remote_sender_id(), sequence, revision, command)


func _server_inventory_operation(peer_id: int, sequence: int, revision: int, command: Dictionary) -> void:
	var inv := _inventory_for_peer(peer_id)
	if inv == null:
		return
	if sequence <= inv.last_operation or revision != inv.network_revision or is_gameplay_locked():
		_publish_inventory(peer_id, sequence)
		return
	inv.last_operation = sequence
	var source := str(command.get("source", "inventory"))
	var index := int(command.get("index", -1))
	var item := inv.network_item(source, index)
	var hero := inv.get_parent() as Player
	match str(command.get("kind", "")):
		"move":
			var target := str(command.get("target", ""))
			var target_index := int(command.get("target_index", -1))
			var other := inv.network_item(target, target_index)
			if item != null and inv.accepts(target, target_index, item) and inv.accepts(source, index, other):
				inv.put_network_item(source, index, other)
				inv.put_network_item(target, target_index, item)
		"use":
			if item != null and source != "equipment":
				if item.experience_amount > 0:
					inv.consume_network_item(source, index, item.id)
					hero.stats.add_experience(item.experience_amount)
					_rpc_apply_progress.rpc(peer_id, hero.stats.get_progress_data())
				elif item.heal_hp > 0 or item.heal_mana > 0:
					# Only inventory ownership changes here; combat authority is unchanged.
					if item.is_consumable:
						inv.consume_network_item(source, index, item.id)
					_rpc_inventory_use_effect.rpc(peer_id, item.id)
		"drop":
			if item != null and source != "equipment":
				inv.consume_network_item(source, index, item.id)
				var direction := hero.get_facing_direction()
				_rpc_spawn_drop.rpc(_drops.allocate_id(), item.id, hero.global_position + direction * 0.6 + Vector3.UP, direction, peer_id)
		"chest_put", "chest_take":
			var chest := get_node_or_null(NodePath(str(command.get("chest", ""))))
			var scene := get_tree().current_scene
			if chest != null and scene != null and scene.is_ancestor_of(chest) and chest.has_method("_player_is_close") and chest.call("_player_is_close", hero):
				if str(command.kind) == "chest_put" and item != null:
					chest.call("_server_transfer_from_player", peer_id, index, item.id, [])
				elif str(command.kind) == "chest_take" and chest.call("get_item", index) != null and chest.call("get_item", index).id == str(command.get("expected", "")):
					chest.call("_server_transfer_to_player", peer_id, index, [])
	inv.network_revision += 1
	_publish_inventory(peer_id, sequence)


func _publish_inventory(peer_id: int, sequence: int = 0) -> void:
	var inv := _inventory_for_peer(peer_id)
	if inv == null:
		return
	_rpc_inventory_snapshot.rpc(peer_id, sequence, inv.network_revision, inv.get_data(), inv.get_quickslot_data(), inv.get_parent().equipment.to_dict())


@rpc("authority", "call_local", "reliable")
func _rpc_inventory_snapshot(peer_id: int, sequence: int, revision: int, items: Array, quick: Array, equipment_data: Dictionary) -> void:
	var inv := _inventory_for_peer(peer_id)
	if inv == null or revision < inv.network_revision:
		return
	inv.network_revision = revision
	if not multiplayer.is_server():
		inv.set_data(items)
		inv.set_quickslot_data(quick)
		inv.get_parent().equipment.load_from_dict(equipment_data)
		inv.changed.emit()
	if inv.get_parent().is_multiplayer_authority():
		if sequence == inv.operation_sequence:
			inv.network_pending = false
		SaveManager.save_player_state(inv, inv.get_parent().equipment)


@rpc("authority", "call_local", "reliable")
func _rpc_inventory_use_effect(peer_id: int, item_id: String) -> void:
	var hero := _hero_for_peer(peer_id)
	var item := ItemLibrary.get_item(item_id)
	if hero != null and item != null and hero.is_multiplayer_authority():
		item.use(hero)


@rpc("authority", "call_local", "reliable")
func _rpc_confirm_mission_spawn(transition_id: int, peer_ids: Array) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if transition_id != _mission_loading_transition_id:
		return
	for peer_id in peer_ids:
		var hero := _hero_for_peer(int(peer_id)) as Player
		if hero == null or not hero.is_node_ready() or hero.animation_tree == null or hero.camera_rig == null:
			return
	if multiplayer.is_server():
		_mark_spawn_ready(multiplayer.get_unique_id(), transition_id)
	else:
		_rpc_spawn_ready.rpc_id(1, transition_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_spawn_ready(transition_id: int) -> void:
	if multiplayer.is_server():
		_mark_spawn_ready(multiplayer.get_remote_sender_id(), transition_id)


func _mark_spawn_ready(peer_id: int, transition_id: int) -> void:
	if transition_id != _mission_loading_transition_id or not _mission_spawn_waiting.has(peer_id):
		return
	_mission_spawn_waiting.erase(peer_id)
	_rpc_set_loading_player_ready.rpc(transition_id, peer_id)
	if _mission_spawn_waiting.is_empty():
		_rpc_finish_mission_loading.rpc(transition_id)
