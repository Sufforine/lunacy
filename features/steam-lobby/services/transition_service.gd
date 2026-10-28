# Scene loading, readiness barrier and player spawning for hub and missions.
extends "res://features/steam-lobby/services/lobby_service.gd"

const LoadingScreenScene := preload("res://features/net/loading/loading_screen.tscn")
const HUB_SCENE := "res://screens/hub/ui/hub.tscn"
const RUNOUTS_MENU_SCENE := "res://screens/hub/ui/runouts-menu/RunoutsMenu.tscn"
const MISSION_SCENE := "res://screens/mission/ui/mission.tscn"
const HUB_PROFILE_SYNC_TIMEOUT_SECONDS := 6.0

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


var peer: MultiplayerPeer:
	get: return _lobby.peer
var lobby_id: int:
	get: return _lobby.lobby_id
var _steam_ready: bool:
	get: return _lobby.is_steam_ready()


func is_mission_loading() -> bool:
	return _mission_loading_transition_id != 0


func start_game() -> void:
	if not multiplayer.is_server():
		return

	if PlayerProfile.hero_scene.is_empty():
		push_warning("SteamLobby: хост не выбрал героя")
		return

	for connected_id in multiplayer.get_peers():
		if not _session.player_states.has(int(connected_id)):
			_lobby.lobby_failed.emit("Дождитесь получения данных всех игроков")
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
		_lobby._rpc_host_left.rpc()
	# Отложенный выход не удаляет текущую сцену внутри её обработчика GUI.
	_finish_leave_to_menu.call_deferred()


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
		_lobby._rpc_request_scene_change.rpc_id(1, scene_path)


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
		_lobby._rpc_show_mission_loading.rpc(_scene_transition_id, _mission_loading_roster(), "Загрузка хаба" if scene_path == HUB_SCENE else "Загрузка миссии")
	_lobby._rpc_prepare_scene_change.rpc(_scene_transition_id, scene_path)


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


func _rpc_show_mission_loading(transition_id: int, players: Array, title: String) -> void:
	_mission_loading_transition_id = transition_id
	_show_loading_screen(players)
	_loading_screen.title_label.text = title


func _show_loading_screen(players: Array) -> void:
	if is_instance_valid(_loading_screen):
		_loading_screen.queue_free()
	_loading_screen = LoadingScreenScene.instantiate() as NetworkLoadingScreen
	_lobby.add_child(_loading_screen)
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
		_lobby._rpc_scene_change_prepared.rpc_id(1, transition_id)


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
		_lobby._rpc_load_gameplay_scene.rpc_id(remote_peer_id, transition_id, scene_path)
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
			_lobby._rpc_load_gameplay_scene.rpc_id(peer_id, transition_id, scene_path)
		else:
			_scene_load_started_waiting.erase(peer_id)
	if _scene_load_started_waiting.is_empty():
		_start_threaded_scene_load(transition_id, scene_path)
		return
	if is_instance_valid(_loading_screen):
		_loading_screen.set_status("Ожидание ответа игроков…")
	_retry_unacknowledged_scene_loads(transition_id, scene_path)


func _rpc_load_gameplay_scene(transition_id: int, scene_path: String) -> void:
	if transition_id != _scene_transition_id:
		return
	if not _is_allowed_gameplay_scene(scene_path):
		return
	_lobby._rpc_scene_load_started.rpc_id(1, transition_id)
	_start_threaded_scene_load(transition_id, scene_path)


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
		_lobby._rpc_scene_load_failed.rpc_id(1, transition_id, message)


func _rpc_scene_load_failed(transition_id: int, message: String) -> void:
	if not multiplayer.is_server() or transition_id != _scene_transition_id:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	push_error("SteamLobby: peer %d не загрузил сцену: %s" % [peer_id, message])
	_lobby._rpc_mark_scene_load_failed.rpc(transition_id, peer_id)


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
			_lobby._rpc_finish_mission_loading.rpc(_mission_loading_transition_id)
		_mission_ready_waiting.erase(peer_id)
		_lobby._rpc_remove_loading_player.rpc(_mission_loading_transition_id, peer_id)
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
		_lobby._rpc_mission_player_ready.rpc_id(1, _mission_loading_transition_id, state_data)


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
		_lobby._rpc_spawn_mission_player.rpc(state_data, spawn_position)

	_pending_mission = null
	_pending_mission_spawns = []
	_lobby._rpc_confirm_mission_spawn.rpc(transition_id, _session.player_states.keys())


func _rpc_spawn_mission_player(state_data: Dictionary, spawn_position: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null or not scene.scene_file_path in [MISSION_SCENE, HUB_SCENE]:
		push_error("SteamLobby: получен спавн до готовности миссии")
		return
	_spawner.spawn_player(scene, state_data, spawn_position)


func _rpc_set_loading_player_ready(transition_id: int, peer_id: int) -> void:
	if transition_id != _mission_loading_transition_id or not is_instance_valid(_loading_screen):
		return
	_loading_screen.set_player_ready(peer_id, true)


func _rpc_remove_loading_player(transition_id: int, peer_id: int) -> void:
	if transition_id != _mission_loading_transition_id or not is_instance_valid(_loading_screen):
		return
	_loading_screen.remove_player(peer_id)


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


func _rpc_sync_profile_before_spawn() -> void:
	SaveManager.ensure_starter_inventory_if_empty()
	var peer_id := multiplayer.get_unique_id()
	var state_data := _session.register_local_player(peer_id)

	if multiplayer.is_server():
		_on_spawn_profile_sync_done(peer_id)
	else:
		_lobby._rpc_spawn_profile_sync.rpc_id(1, state_data)


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
		_lobby._rpc_spawn_hub_player.rpc(state_data, spawn_pos)

	_pending_hub = null
	_pending_spawns = []


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


func _rpc_despawn_hub_player(peer_id: int) -> void:
	var scene := get_tree().current_scene
	if scene:
		_spawner.despawn_player(scene, peer_id)
	_broadcast_player_list()


func is_gameplay_locked() -> bool:
	return _scene_transition_active or is_mission_loading()


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
		_lobby._rpc_spawn_ready.rpc_id(1, transition_id)


func _rpc_spawn_ready(transition_id: int) -> void:
	if multiplayer.is_server():
		_mark_spawn_ready(multiplayer.get_remote_sender_id(), transition_id)


func _mark_spawn_ready(peer_id: int, transition_id: int) -> void:
	if transition_id != _mission_loading_transition_id or not _mission_spawn_waiting.has(peer_id):
		return
	_mission_spawn_waiting.erase(peer_id)
	_lobby._rpc_set_loading_player_ready.rpc(transition_id, peer_id)
	if _mission_spawn_waiting.is_empty():
		_lobby._rpc_finish_mission_loading.rpc(transition_id)


func _handle_transition_peer_left(id: int) -> void:
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


# Calls into other services go through the facade.


func _broadcast_player_list() -> void:
	_lobby._broadcast_player_list()


func _clear_autoload_spawns() -> void:
	_lobby._clear_autoload_spawns()


func _hero_for_peer(peer_id: int) -> Node:
	return _lobby._hero_for_peer(peer_id)


func disconnect_lobby() -> void:
	_lobby.disconnect_lobby()


func is_session_active() -> bool:
	return _lobby.is_session_active()
