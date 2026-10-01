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
var _spawn_sync_remaining: int = 0


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
	_drops.clear()
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
	_drops.clear()
	_rpc_load_hub.rpc()


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
	_spawn_sync_remaining = _session.player_states.size()
	_rpc_sync_profile_before_spawn.rpc()


@rpc("authority", "call_local", "reliable")
func _rpc_sync_profile_before_spawn() -> void:
	SaveManager.ensure_starter_inventory_if_empty()
	var peer_id := multiplayer.get_unique_id()
	var state_data := _session.register_local_player(peer_id)

	if multiplayer.is_server():
		_on_spawn_profile_sync_done()
	else:
		_rpc_spawn_profile_sync.rpc_id(1, state_data)


@rpc("any_peer", "reliable")
func _rpc_spawn_profile_sync(state_data: Dictionary) -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	_session.register_remote_player(sender_id, state_data)
	_on_spawn_profile_sync_done()


func _on_spawn_profile_sync_done() -> void:
	if not multiplayer.is_server():
		return

	_spawn_sync_remaining -= 1
	if _spawn_sync_remaining > 0:
		return

	if _pending_hub == null or _pending_spawns.is_empty():
		return

	for peer_id in _session.player_states:
		var state_data := _session.player_state_data(peer_id)
		var spawn_index := int(peer_id) % _pending_spawns.size()
		var spawn_pos: Vector3 = _pending_spawns[spawn_index].global_position
		_rpc_spawn_hub_player.rpc(state_data, spawn_pos)

	_pending_hub = null
	_pending_spawns = []


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
	_rpc_remove_drop.rpc(drop_id)

	if picker_peer == multiplayer.get_unique_id():
		_apply_pickup_grant(_local_inventory(), item_id)
	else:
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


func _steam_available() -> bool:
	return Engine.has_singleton("Steam")
