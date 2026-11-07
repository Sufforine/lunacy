extends Node

const Resolver = preload("res://features/combat/damage_resolver.gd")
const Numbers = preload("res://features/combat/damage_numbers.gd")
var _event_id := 0
var _received_event := -1
var _epoch := -1
var _sync_left := 0.0

func is_authority() -> bool:
	return not SteamLobby.is_session_active() or multiplayer.is_server()

func _process(delta: float) -> void:
	var epoch: int = SteamLobby.combat_scene_epoch()
	if epoch != _epoch:
		_epoch = epoch
		_received_event = -1
	_sync_left -= delta
	if _sync_left > 0.0 or not SteamLobby.is_session_active() or not multiplayer.is_server() or SteamLobby.is_gameplay_locked():
		return
	_sync_left = 0.5
	# Small full snapshots also initialize late joiners / newly spawned targets.
	_publish_state()

func apply_hit(source: Node, target: Node, physical: int, magical: int) -> Dictionary:
	if not is_authority() or SteamLobby.is_gameplay_locked() or not is_instance_valid(target):
		return {}
	var stats := target.get_node_or_null("StatsComponent") as StatsComponent
	if stats == null or stats.is_dead or (physical <= 0 and magical <= 0):
		return {}
	var result: Dictionary = Resolver.resolve(stats, physical, magical)
	stats.current_health = result.health
	stats.current_shield = result.shield
	if stats.current_health == 0 and not stats.is_downed and not stats.training_target:
		stats._trigger_down()
	stats.stats_changed.emit()
	if int(result.physical) > 0:
		stats.damage_received.emit(int(result.physical), false)
	if int(result.magical) > 0:
		stats.damage_received.emit(int(result.magical), true)
	var owner_id := source.get_multiplayer_authority() if is_instance_valid(source) else 0
	var point: Vector3 = target.global_position + Vector3.UP * 2.2
	_event_id += 1
	if SteamLobby.is_session_active():
		sync_stats(stats)
		_hit_event.rpc(SteamLobby.combat_scene_epoch(), _event_id, owner_id, stats.get_path(), point, result)
	else:
		Numbers.show_hit(get_tree().current_scene, point, result)
	return result

func sync_stats(stats: StatsComponent) -> void:
	if SteamLobby.is_session_active() and multiplayer.is_server() and not SteamLobby.is_gameplay_locked():
		_state_snapshot.rpc(SteamLobby.combat_scene_epoch(), {str(stats.get_path()): _state(stats)})

func _state(stats: StatsComponent) -> Array:
	return [stats.current_health, stats.current_shield, stats.current_morale, stats.is_downed, stats.is_dead, stats._agony_timer]

func _publish_state() -> void:
	var states: Dictionary = {}
	for stats in get_tree().get_nodes_in_group("combat_stats"):
		states[str(stats.get_path())] = _state(stats)
	_state_snapshot.rpc(SteamLobby.combat_scene_epoch(), states)

@rpc("authority", "call_remote", "reliable", 1)
func _state_snapshot(epoch: int, states: Dictionary) -> void:
	if epoch != SteamLobby.combat_scene_epoch() or SteamLobby.is_gameplay_locked():
		return
	for path in states:
		var stats := get_node_or_null(NodePath(path)) as StatsComponent
		if stats == null:
			continue
		var state: Array = states[path]
		var was_downed := stats.is_downed
		var was_dead := stats.is_dead
		stats.current_health = state[0]
		stats.current_shield = state[1]
		stats.current_morale = state[2]
		stats.is_downed = state[3]
		stats.is_dead = state[4]
		stats._agony_timer = state[5]
		if stats.is_dead and not was_dead:
			stats.died.emit()
		elif stats.is_downed and not was_downed:
			stats.downed.emit()
		elif was_downed and not stats.is_downed and not stats.is_dead:
			stats.revived.emit()
		stats.stats_changed.emit()

@rpc("authority", "call_local", "reliable", 1)
func _hit_event(epoch: int, event_id: int, owner_id: int, target_path: NodePath, point: Vector3, result: Dictionary) -> void:
	if epoch != SteamLobby.combat_scene_epoch() or SteamLobby.is_gameplay_locked():
		return
	if _epoch != epoch:
		_epoch = epoch
		_received_event = -1
	if event_id <= _received_event:
		return
	_received_event = event_id
	if not multiplayer.is_server():
		var stats := get_node_or_null(target_path) as StatsComponent
		if stats != null:
			if int(result.physical) > 0:
				stats.damage_received.emit(int(result.physical), false)
			if int(result.magical) > 0:
				stats.damage_received.emit(int(result.magical), true)
	if owner_id == multiplayer.get_unique_id() and get_tree().current_scene != null:
		Numbers.show_hit(get_tree().current_scene, point, result)
