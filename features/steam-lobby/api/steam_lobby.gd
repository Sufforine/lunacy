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

const LOBBY_TYPE_PUBLIC := 2
const RESULT_OK := 1
const HUB_SCENE := "res://screens/hub/ui/hub.tscn"
const RUNOUTS_MENU_SCENE := "res://screens/hub/ui/runouts-menu/RunoutsMenu.tscn"
const MISSION_SCENE := "res://screens/mission/ui/mission.tscn"

var _steam_ready: bool = false

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
var _mission_spawn_waiting: Dictionary = {}

# Смена сетевой сцены проходит через prepare/commit. Пока все клиенты не
# отключили старые MultiplayerSynchronizer, сцена остаётся в дереве и может
# безопасно принять уже отправленные пакеты синхронизации.
var _scene_transition_id: int = 0
var _scene_transition_path: String = ""
var _scene_transition_waiting: Dictionary = {}
var _scene_transition_active: bool = false
var _scene_transition_commit_scheduled: bool = false


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
	if _steam_available():
		Steam.run_callbacks()


func is_session_active() -> bool:
	return peer != null and multiplayer.has_multiplayer_peer()


func host_lobby() -> void:
	if not is_steam_ready():
		lobby_failed.emit("Steam не инициализирован")
		return

	if lobby_id != 0:
		disconnect_lobby()

	Steam.createLobby(LOBBY_TYPE_PUBLIC, 4)
	is_host = true


func join_lobby(id: int) -> void:
	if not is_steam_ready():
		lobby_failed.emit("Steam не инициализирован")
		return

	if lobby_id != 0:
		disconnect_lobby()

	is_joining = true
	Steam.joinLobby(id)


func disconnect_lobby() -> void:
	_reset_pending_scene_spawns()
	_reset_scene_transition()
	_clear_autoload_spawns()
	_drops.clear()
	if _steam_ready and lobby_id != 0:
		Steam.leaveLobby(lobby_id)
	_transport.close_connection(multiplayer)
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
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

	# Мир принадлежит хосту; профили персонажей в этот файл не пишутся.
	SaveManager.save_world_progress(SaveManager.load_world_progress())
	_begin_network_scene_change(HUB_SCENE)


func request_scene_change(scene_path: String) -> void:
	if not _is_allowed_gameplay_scene(scene_path):
		push_warning("SteamLobby: запрещён переход на сцену '%s'" % scene_path)
		return
	if not is_session_active():
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
	if not multiplayer.is_server() or _scene_transition_active:
		return
	if not _is_allowed_gameplay_scene(scene_path):
		return

	_scene_transition_id += 1
	_scene_transition_path = scene_path
	_scene_transition_waiting = _connected_peer_set()
	_scene_transition_active = true
	_scene_transition_commit_scheduled = false
	_rpc_prepare_scene_change.rpc(_scene_transition_id, scene_path)


@rpc("authority", "call_local", "reliable")
func _rpc_prepare_scene_change(transition_id: int, scene_path: String) -> void:
	if not _is_allowed_gameplay_scene(scene_path):
		return

	_scene_transition_id = transition_id
	_scene_transition_path = scene_path
	_scene_transition_active = true
	_disable_current_scene_synchronizers()

	var local_peer_id := multiplayer.get_unique_id()
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
	_rpc_load_gameplay_scene.rpc(transition_id, _scene_transition_path)


@rpc("authority", "call_local", "reliable")
func _rpc_load_gameplay_scene(transition_id: int, scene_path: String) -> void:
	if transition_id != _scene_transition_id:
		return
	if not _is_allowed_gameplay_scene(scene_path):
		return
	_reset_pending_scene_spawns()
	_clear_autoload_spawns()
	_drops.clear()
	_reset_scene_transition()
	get_tree().change_scene_to_file(scene_path)


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
	_scene_transition_active = false
	_scene_transition_commit_scheduled = false


func _is_allowed_gameplay_scene(scene_path: String) -> bool:
	return scene_path == HUB_SCENE or scene_path == RUNOUTS_MENU_SCENE or scene_path == MISSION_SCENE


func _connected_peer_set() -> Dictionary:
	var waiting := {multiplayer.get_unique_id(): true}
	for peer_id in multiplayer.get_peers():
		waiting[int(peer_id)] = true
	return waiting


func _reset_pending_scene_spawns() -> void:
	_pending_hub = null
	_pending_spawns = []
	_hub_spawn_waiting.clear()
	_pending_mission = null
	_pending_mission_spawns = []
	_mission_spawn_waiting.clear()


func _resolve_disconnected_spawn_wait(peer_id: int) -> void:
	if _hub_spawn_waiting.has(peer_id):
		_hub_spawn_waiting.erase(peer_id)
		if _hub_spawn_waiting.is_empty():
			_finalize_hub_spawn()
	if _mission_spawn_waiting.has(peer_id):
		_mission_spawn_waiting.erase(peer_id)
		if _mission_spawn_waiting.is_empty():
			_finalize_mission_spawn()


func spawn_mission_players(mission: Node3D, spawn_points: Array) -> void:
	if not is_session_active() or not multiplayer.is_server():
		return
	if spawn_points.is_empty():
		push_error("SteamLobby: нет точек спавна в миссии")
		return

	_pending_mission = mission
	_pending_mission_spawns = spawn_points
	_mission_spawn_waiting = _connected_peer_set()
	_rpc_sync_mission_profile_before_spawn.rpc()


@rpc("authority", "call_local", "reliable")
func _rpc_sync_mission_profile_before_spawn() -> void:
	SaveManager.ensure_starter_inventory_if_empty()
	var peer_id := multiplayer.get_unique_id()
	var state_data := _session.register_local_player(peer_id)
	if multiplayer.is_server():
		_on_mission_spawn_profile_sync_done(peer_id)
	else:
		_rpc_mission_spawn_profile_sync.rpc_id(1, state_data)


@rpc("any_peer", "reliable")
func _rpc_mission_spawn_profile_sync(state_data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	_session.register_remote_player(sender_id, state_data)
	_on_mission_spawn_profile_sync_done(sender_id)


func _on_mission_spawn_profile_sync_done(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if not _mission_spawn_waiting.has(peer_id):
		return
	_mission_spawn_waiting.erase(peer_id)
	if not _mission_spawn_waiting.is_empty():
		return
	_finalize_mission_spawn()


func _finalize_mission_spawn() -> void:
	if not is_instance_valid(_pending_mission) or _pending_mission_spawns.is_empty():
		return

	for peer_id in _session.player_states:
		var state_data := _session.player_state_data(peer_id)
		var spawn_index := (maxi(1, int(peer_id)) - 1) % _pending_mission_spawns.size()
		var spawn_position: Vector3 = _pending_mission_spawns[spawn_index].global_position
		_rpc_spawn_mission_player.rpc(state_data, spawn_position)

	_pending_mission = null
	_pending_mission_spawns = []


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_mission_player(state_data: Dictionary, spawn_position: Vector3) -> void:
	call_deferred("_deferred_spawn_mission_player", state_data, spawn_position)


func _deferred_spawn_mission_player(state_data: Dictionary, spawn_position: Vector3) -> void:
	for _frame in range(600):
		var scene := get_tree().current_scene
		if scene != null and scene.scene_file_path == MISSION_SCENE:
			_spawner.spawn_player(scene, state_data, spawn_position)
			return
		await get_tree().process_frame
	push_error("SteamLobby: не удалось заспавнить игрока — миссия не загружена")


func spawn_hub_players(hub: Node3D, spawn_points: Array) -> void:
	if not is_session_active():
		return

	if not multiplayer.is_server():
		return

	if spawn_points.is_empty():
		push_error("SteamLobby: нет точек спавна в хабе")
		return

	_pending_hub = hub
	_pending_spawns = spawn_points
	_hub_spawn_waiting = _connected_peer_set()
	_rpc_sync_profile_before_spawn.rpc()


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
	if not _steam_available():
		return

	if result != RESULT_OK:
		is_host = false
		lobby_failed.emit("Failed to create lobby: %d" % result)
		push_error("SteamLobby: не удалось создать лобби: %d" % result)
		return

	lobby_id = id
	peer = _transport.create_steam_host(multiplayer)
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	_session.register_local_player(1)
	lobby_ready.emit(lobby_id)
	_broadcast_player_list()
	print("SteamLobby: лобби создано ", lobby_id)


func _on_lobby_joined(id: int, _permissions: int, _locked: bool, response: int) -> void:
	if not is_joining:
		return

	if not _steam_available():
		return
	if response != RESULT_OK:
		is_joining = false
		lobby_failed.emit("Не удалось войти в Steam-лобби: %d" % response)
		return

	lobby_id = id
	peer = _transport.create_steam_client(multiplayer, Steam.getLobbyOwner(lobby_id))
	is_joining = false

	multiplayer.connected_to_server.connect(_on_connected_to_server, CONNECT_ONE_SHOT)
	multiplayer.connection_failed.connect(_on_connection_failed, CONNECT_ONE_SHOT)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
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
	_resolve_disconnected_spawn_wait(id)
	if multiplayer.is_server() and _scene_transition_waiting.has(id):
		_scene_transition_waiting.erase(id)
		if _scene_transition_waiting.is_empty() and not _scene_transition_commit_scheduled:
			_scene_transition_commit_scheduled = true
			_finish_scene_change_prepare(_scene_transition_id)
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


func request_use_experience_relic(source: String, slot_index: int, item_id: String) -> void:
	if not is_session_active():
		return
	if multiplayer.is_server():
		_server_use_experience_relic(multiplayer.get_unique_id(), source, slot_index, item_id)
	else:
		_rpc_request_experience_relic.rpc_id(1, source, slot_index, item_id)


@rpc("any_peer", "reliable")
func _rpc_request_experience_relic(source: String, slot_index: int, item_id: String) -> void:
	if multiplayer.is_server():
		_server_use_experience_relic(multiplayer.get_remote_sender_id(), source, slot_index, item_id)


func _server_use_experience_relic(peer_id: int, source: String, slot_index: int, item_id: String) -> void:
	var inventory := _inventory_for_peer(peer_id)
	var stats := _stats_for_peer(peer_id)
	if inventory == null or stats == null:
		return
	var item := inventory.get_source_item(source, slot_index)
	var authoritative_source := source
	var authoritative_slot := slot_index
	if item == null or item.id != item_id:
		var location := inventory.find_item_location(item_id)
		if not location.is_empty():
			authoritative_source = str(location["source"])
			authoritative_slot = int(location["slot_index"])
			item = inventory.get_source_item(authoritative_source, authoritative_slot)
	if item == null or item.id != item_id or item.experience_amount <= 0:
		push_warning("SteamLobby: peer %d попытался использовать отсутствующую реликвию" % peer_id)
		return
	# Сразу убираем авторитетную копию: повторный RPC не сможет выдать ещё один уровень.
	inventory.consume_network_item(authoritative_source, authoritative_slot, item_id)
	stats.add_experience(item.experience_amount)
	var progress := stats.get_progress_data()
	_session.update_progress(peer_id, progress)
	_rpc_commit_experience_relic.rpc(peer_id, source, slot_index, item_id, progress)


@rpc("authority", "call_local", "reliable")
func _rpc_commit_experience_relic(peer_id: int, source: String, slot_index: int, item_id: String, progress: Dictionary) -> void:
	var inventory := _inventory_for_peer(peer_id)
	if inventory != null:
		inventory.consume_network_item(source, slot_index, item_id)
	var stats := _stats_for_peer(peer_id)
	if stats != null:
		stats.apply_progress_data(progress)
	var hero := _hero_for_peer(peer_id)
	if hero != null and hero.is_multiplayer_authority() and inventory != null:
		PlayerProfile.inventory = inventory.get_data()
		PlayerProfile.quickslots = inventory.get_quickslot_data()
		SaveManager.save_profile()
	_session.update_progress(peer_id, progress)


@rpc("authority", "call_local", "reliable")
func _rpc_apply_progress(peer_id: int, progress: Dictionary) -> void:
	var stats := _stats_for_peer(peer_id)
	if stats != null:
		stats.apply_progress_data(progress)
	_session.update_progress(peer_id, progress)


func _hero_for_peer(peer_id: int) -> Node:
	var scene := get_tree().current_scene
	return scene.get_node_or_null(str(peer_id)) if scene != null else null


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

	if multiplayer.is_server():
		_server_spawn_drop(item_id, position, direction, multiplayer.get_unique_id())
	else:
		_rpc_request_drop.rpc_id(1, item_id, position, direction)


@rpc("any_peer", "reliable")
func _rpc_request_drop(item_id: String, position: Vector3, direction: Vector3) -> void:
	if not multiplayer.is_server():
		return
	_server_spawn_drop(item_id, position, direction, multiplayer.get_remote_sender_id())


func _server_spawn_drop(item_id: String, position: Vector3, direction: Vector3, thrower_peer: int) -> void:
	if not ItemLibrary.has_item(item_id):
		push_warning("SteamLobby: неизвестный предмет '%s' в запросе на выброс" % item_id)
		return
	# У хоста UI и серверная копия совпадают, поэтому предмет уже удалён до
	# запроса. Для удалённого игрока сервер хранит отдельную копию инвентаря:
	# удаляем предмет и отклоняем поддельный либо повторный запрос.
	if thrower_peer != multiplayer.get_unique_id():
		var inventory := _inventory_for_peer(thrower_peer)
		if inventory == null:
			return
		var location := inventory.find_item_location(item_id)
		if location.is_empty():
			push_warning("SteamLobby: peer %d попытался выбросить отсутствующий '%s'" % [thrower_peer, item_id])
			return
		inventory.consume_network_item(
			str(location["source"]),
			int(location["slot_index"]),
			item_id
		)
	_rpc_spawn_drop.rpc(_drops.allocate_id(), item_id, position, direction, thrower_peer)


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
	if picker_peer != multiplayer.get_unique_id():
		_rpc_grant_pickup.rpc_id(picker_peer, item_id)


@rpc("authority", "call_local", "reliable")
func _rpc_remove_drop(drop_id: int) -> void:
	_drops.remove(drop_id)


@rpc("authority", "reliable")
func _rpc_grant_pickup(item_id: String) -> void:
	_apply_pickup_grant(_local_inventory(), item_id)


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


# ════════════════════════════════════════════════════════
# СНАРЯЖЕНИЕ — чтобы остальные видели что надето (и пассивки вроде щита)
# Вызывается героем-владельцем при каждой смене снаряжения.
# ════════════════════════════════════════════════════════
func sync_equipment(equipment_data: Dictionary) -> void:
	if not is_session_active():
		return

	if multiplayer.is_server():
		_rpc_equipment_changed.rpc(multiplayer.get_unique_id(), equipment_data)
	else:
		_rpc_equipment_to_server.rpc_id(1, equipment_data)


@rpc("any_peer", "reliable")
func _rpc_equipment_to_server(equipment_data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	_apply_remote_equipment(sender_id, equipment_data)  # копия героя на хосте
	_rpc_equipment_changed.rpc(sender_id, equipment_data)


# call_remote: на самом сервере не выполняется (он применил снаряжение выше)
@rpc("authority", "call_remote", "reliable")
func _rpc_equipment_changed(peer_id: int, equipment_data: Dictionary) -> void:
	_apply_remote_equipment(peer_id, equipment_data)


func _apply_remote_equipment(peer_id: int, equipment_data: Dictionary) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var hero := scene.get_node_or_null(str(peer_id))
	# Своего героя не трогаем — его снаряжение уже актуально
	if hero == null or hero.is_multiplayer_authority():
		return
	var eq := hero.get_node_or_null("EquipmentComponent") as EquipmentComponent
	if eq != null:
		eq.load_from_dict(equipment_data)


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
