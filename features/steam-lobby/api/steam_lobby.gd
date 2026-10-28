# Stable public API and RPC endpoint at /root/SteamLobby.
# State and implementation live in services; RPC names/annotations stay here
# so existing scenes and network node paths remain compatible.
extends Node

signal lobby_ready(lobby_id: int)
signal lobby_failed(reason: String)
signal players_updated(players: Array)

const NetSession := preload("res://features/net/session/net_session.gd")
const NetSpawner := preload("res://features/net/spawn/net_spawner.gd")
const NetDrops := preload("res://features/net/sync/net_drops.gd")
const HUB_SCENE := "res://screens/hub/ui/hub.tscn"
const RUNOUTS_MENU_SCENE := "res://screens/hub/ui/runouts-menu/RunoutsMenu.tscn"
const MISSION_SCENE := "res://screens/mission/ui/mission.tscn"

var _session := NetSession.new()
var _spawner := NetSpawner.new()
var _drops := NetDrops.new()
var _connection_service := preload("res://features/steam-lobby/services/connection_service.gd").new()
var _transition_service := preload("res://features/steam-lobby/services/transition_service.gd").new()
var _inventory_service := preload("res://features/steam-lobby/services/inventory_service.gd").new()
var _drops_service := preload("res://features/steam-lobby/services/drops_service.gd").new()
var _progression_service := preload("res://features/steam-lobby/services/progression_service.gd").new()
var _chat_service := preload("res://features/steam-lobby/services/chat_service.gd").new()

var lobby_id: int:
	get: return _connection_service.lobby_id
	set(value): _connection_service.lobby_id = value

var peer: MultiplayerPeer:
	get: return _connection_service.peer
	set(value): _connection_service.peer = value

var is_host: bool:
	get: return _connection_service.is_host
	set(value): _connection_service.is_host = value

var is_joining: bool:
	get: return _connection_service.is_joining
	set(value): _connection_service.is_joining = value


func _ready() -> void:
	var services := {
		"Connection": _connection_service,
		"Transitions": _transition_service,
		"Inventory": _inventory_service,
		"Drops": _drops_service,
		"Progression": _progression_service,
		"ChatCommands": _chat_service,
	}
	for service_name in services:
		var service: Node = services[service_name]
		service.name = service_name
		service.configure(self)
		add_child(service)
	_connection_service.initialize()


func is_session_active() -> bool:
	return _connection_service.is_session_active()


func is_mission_loading() -> bool:
	return _transition_service.is_mission_loading()


func host_lobby() -> void:
	_connection_service.host_lobby()


func join_lobby(id: int) -> void:
	_connection_service.join_lobby(id)


func disconnect_lobby() -> void:
	_connection_service.disconnect_lobby()


func start_game() -> void:
	_transition_service.start_game()


func leave_to_main_menu() -> void:
	_transition_service.leave_to_main_menu()


@rpc("authority", "call_remote", "reliable")
func _rpc_host_left() -> void:
	_transition_service._rpc_host_left()


func _finish_leave_to_menu() -> void:
	_transition_service._finish_leave_to_menu()


func request_scene_change(scene_path: String) -> void:
	_transition_service.request_scene_change(scene_path)


@rpc("any_peer", "reliable")
func _rpc_request_scene_change(scene_path: String) -> void:
	_transition_service._rpc_request_scene_change(scene_path)


@rpc("authority", "call_local", "reliable")
func _rpc_show_mission_loading(transition_id: int, players: Array, title: String) -> void:
	_transition_service._rpc_show_mission_loading(transition_id, players, title)


func _reset_mission_loading() -> void:
	_transition_service._reset_mission_loading()


@rpc("authority", "call_local", "reliable")
func _rpc_prepare_scene_change(transition_id: int, scene_path: String) -> void:
	_transition_service._rpc_prepare_scene_change(transition_id, scene_path)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_scene_change_prepared(transition_id: int) -> void:
	_transition_service._rpc_scene_change_prepared(transition_id)


@rpc("authority", "call_remote", "reliable")
func _rpc_load_gameplay_scene(transition_id: int, scene_path: String) -> void:
	_transition_service._rpc_load_gameplay_scene(transition_id, scene_path)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_scene_load_started(transition_id: int) -> void:
	_transition_service._rpc_scene_load_started(transition_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_scene_load_failed(transition_id: int, message: String) -> void:
	_transition_service._rpc_scene_load_failed(transition_id, message)


@rpc("authority", "call_local", "reliable")
func _rpc_mark_scene_load_failed(transition_id: int, peer_id: int) -> void:
	_transition_service._rpc_mark_scene_load_failed(transition_id, peer_id)


func _reset_scene_transition() -> void:
	_transition_service._reset_scene_transition()


func _reset_pending_scene_spawns() -> void:
	_transition_service._reset_pending_scene_spawns()


func spawn_mission_players(mission: Node3D, spawn_points: Array) -> void:
	_transition_service.spawn_mission_players(mission, spawn_points)


@rpc("any_peer", "reliable")
func _rpc_mission_player_ready(transition_id: int, state_data: Dictionary) -> void:
	_transition_service._rpc_mission_player_ready(transition_id, state_data)


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_mission_player(state_data: Dictionary, spawn_position: Vector3) -> void:
	_transition_service._rpc_spawn_mission_player(state_data, spawn_position)


@rpc("authority", "call_local", "reliable")
func _rpc_set_loading_player_ready(transition_id: int, peer_id: int) -> void:
	_transition_service._rpc_set_loading_player_ready(transition_id, peer_id)


@rpc("authority", "call_local", "reliable")
func _rpc_remove_loading_player(transition_id: int, peer_id: int) -> void:
	_transition_service._rpc_remove_loading_player(transition_id, peer_id)


@rpc("authority", "call_local", "reliable")
func _rpc_finish_mission_loading(transition_id: int) -> void:
	_transition_service._rpc_finish_mission_loading(transition_id)


func spawn_hub_players(hub: Node3D, spawn_points: Array) -> void:
	_transition_service.spawn_hub_players(hub, spawn_points)


@rpc("authority", "call_local", "reliable")
func _rpc_sync_profile_before_spawn() -> void:
	_transition_service._rpc_sync_profile_before_spawn()


@rpc("any_peer", "reliable")
func _rpc_spawn_profile_sync(state_data: Dictionary) -> void:
	_transition_service._rpc_spawn_profile_sync(state_data)


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_hub_player(state_data: Dictionary, spawn_position: Vector3) -> void:
	_transition_service._rpc_spawn_hub_player(state_data, spawn_position)


@rpc("authority", "call_local", "reliable")
func _rpc_despawn_hub_player(peer_id: int) -> void:
	_transition_service._rpc_despawn_hub_player(peer_id)


@rpc("any_peer", "reliable")
func _rpc_send_state(state_data: Dictionary) -> void:
	_connection_service._rpc_send_state(state_data)


func _broadcast_player_list() -> void:
	_connection_service._broadcast_player_list()


@rpc("authority", "call_local", "reliable")
func _rpc_player_list(list: Array) -> void:
	_connection_service._rpc_player_list(list)


func notify_hero_changed() -> void:
	_connection_service.notify_hero_changed()


@rpc("any_peer", "reliable")
func _rpc_update_hero(hero_scene: String) -> void:
	_connection_service._rpc_update_hero(hero_scene)


func request_spend_attribute(attribute_name: String) -> void:
	_progression_service.request_spend_attribute(attribute_name)


@rpc("any_peer", "reliable")
func _rpc_request_spend_attribute(attribute_name: String) -> void:
	_progression_service._rpc_request_spend_attribute(attribute_name)


@rpc("authority", "call_local", "reliable")
func _rpc_apply_progress(peer_id: int, progress: Dictionary) -> void:
	_progression_service._rpc_apply_progress(peer_id, progress)


func _hero_for_peer(peer_id: int) -> Node:
	var scene := get_tree().current_scene
	return scene.get_node_or_null(str(peer_id)) if scene != null else null


func chat_player_name(peer_id: int) -> String:
	return _chat_service.chat_player_name(peer_id)


func execute_chat_command(peer_id: int, message: String) -> String:
	return _chat_service.execute_chat_command(peer_id, message)


func _inventory_for_peer(peer_id: int) -> InventoryComponent:
	var hero := _hero_for_peer(peer_id)
	return hero.get_node_or_null("InventoryComponent") as InventoryComponent if hero != null else null


func _stats_for_peer(peer_id: int) -> StatsComponent:
	var hero := _hero_for_peer(peer_id)
	return hero.get_node_or_null("StatsComponent") as StatsComponent if hero != null else null


func request_drop(item_id: String, position: Vector3, direction: Vector3, thrower: Node3D = null) -> void:
	_drops_service.request_drop(item_id, position, direction, thrower)


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_drop(drop_id: int, item_id: String, position: Vector3, direction: Vector3, thrower_peer: int) -> void:
	_drops_service._rpc_spawn_drop(drop_id, item_id, position, direction, thrower_peer)


func request_pickup(drop_id: int, picker: InventoryComponent) -> void:
	_drops_service.request_pickup(drop_id, picker)


@rpc("any_peer", "reliable")
func _rpc_request_pickup(drop_id: int) -> void:
	_drops_service._rpc_request_pickup(drop_id)


@rpc("authority", "call_local", "reliable")
func _rpc_remove_drop(drop_id: int) -> void:
	_drops_service._rpc_remove_drop(drop_id)


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


func is_steam_ready() -> bool:
	return _connection_service.is_steam_ready()


func is_gameplay_locked() -> bool:
	return _transition_service.is_gameplay_locked()


func request_inventory_operation(sequence: int, revision: int, command: Dictionary) -> void:
	_inventory_service.request_inventory_operation(sequence, revision, command)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_inventory_operation(sequence: int, revision: int, command: Dictionary) -> void:
	_inventory_service._rpc_inventory_operation(sequence, revision, command)


func _publish_inventory(peer_id: int, sequence: int = 0) -> void:
	_inventory_service._publish_inventory(peer_id, sequence)


@rpc("authority", "call_local", "reliable")
func _rpc_inventory_snapshot(peer_id: int, sequence: int, revision: int, items: Array, quick: Array, equipment_data: Dictionary) -> void:
	_inventory_service._rpc_inventory_snapshot(peer_id, sequence, revision, items, quick, equipment_data)


@rpc("authority", "call_local", "reliable")
func _rpc_inventory_use_effect(peer_id: int, item_id: String) -> void:
	_inventory_service._rpc_inventory_use_effect(peer_id, item_id)


@rpc("authority", "call_local", "reliable")
func _rpc_confirm_mission_spawn(transition_id: int, peer_ids: Array) -> void:
	_transition_service._rpc_confirm_mission_spawn(transition_id, peer_ids)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_spawn_ready(transition_id: int) -> void:
	_transition_service._rpc_spawn_ready(transition_id)


func _handle_transition_peer_left(id: int) -> void:
	_transition_service._handle_transition_peer_left(id)
