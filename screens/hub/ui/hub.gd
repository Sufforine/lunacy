extends Node3D

const NetSpawner := preload("res://features/net/spawn/net_spawner.gd")
const DogScene := preload("res://entities/enemies/dog/dog.tscn")

@export_range(0.5, 10.0, 0.1) var interaction_distance: float = 2.5

var spawns: Array = []
var world_progress: Dictionary = {}
var _owns_world_save: bool = false
var _focused_interactable: Node3D = null

var _spawner := NetSpawner.new()


func _ready() -> void:
	# В одиночной игре и у хоста мир читается из одного и того же выбранного
	# файла. Клиент получает снимок мира от хоста и локальный файл не трогает.
	_owns_world_save = not SteamLobby.is_session_active() or multiplayer.is_server()
	if _owns_world_save:
		world_progress = SaveManager.load_world_progress()

	# Дождаться полной инициализации сцены после change_scene.
	await get_tree().process_frame
	await get_tree().process_frame

	var spawn_node := get_node_or_null("SpawnPoints")
	if spawn_node == null:
		push_error("hub: нода SpawnPoints не найдена")
		return
	spawns = spawn_node.get_children()

	if SteamLobby.is_session_active():
		SteamLobby.spawn_hub_players(self, spawns)
	else:
		_spawn_solo()

	if not SteamLobby.is_session_active():
		_spawn_test_dog()


func _process(_delta: float) -> void:
	_update_interaction_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or event.is_echo():
		return

	var local_player := _get_local_player()
	if local_player == null or not _player_can_interact(local_player):
		return
	if _focused_interactable == null or not is_instance_valid(_focused_interactable):
		return
	if not _focused_interactable.has_method("interact"):
		return

	get_viewport().set_input_as_handled()
	# interact() может синхронно сменить сцену и удалить Hub, поэтому после
	# него обращаться к viewport уже нельзя.
	_focused_interactable.call("interact", local_player)


func _update_interaction_focus() -> void:
	var local_player := _get_local_player()
	var closest: Node3D = null
	var closest_distance_squared := interaction_distance * interaction_distance

	if local_player != null and _player_can_interact(local_player):
		for node in get_tree().get_nodes_in_group("hub_interactable"):
			if not node is Node3D or not node.has_method("interact"):
				continue
			var interactable := node as Node3D
			var distance_squared := local_player.global_position.distance_squared_to(interactable.global_position)
			if distance_squared <= closest_distance_squared:
				closest = interactable
				closest_distance_squared = distance_squared

	_set_focused_interactable(closest)


func _set_focused_interactable(interactable: Node3D) -> void:
	if _focused_interactable == interactable:
		return
	if is_instance_valid(_focused_interactable) and _focused_interactable.has_method("set_interaction_focus"):
		_focused_interactable.call("set_interaction_focus", false)
	_focused_interactable = interactable
	if is_instance_valid(_focused_interactable) and _focused_interactable.has_method("set_interaction_focus"):
		_focused_interactable.call("set_interaction_focus", true)


func _get_local_player() -> Player:
	for node in get_tree().get_nodes_in_group("player"):
		if node is Player:
			var candidate := node as Player
			if candidate.is_multiplayer_authority():
				return candidate
	return null


func _player_can_interact(player: Player) -> bool:
	if player.stats.is_dead or player.stats.is_downed:
		return false
	return player.inventory_ui == null or not player.inventory_ui.is_main_panel_open()


func _exit_tree() -> void:
	_save_authoritative_world()


func get_world_progress() -> Dictionary:
	return world_progress.duplicate(true)


# Точка входа для систем мира: изменение сразу сохраняется, а хост также
# отправляет новый снимок всем клиентам.
func set_world_progress_value(key: String, value: Variant) -> void:
	if not _owns_world_save:
		return
	world_progress[key] = value
	_save_authoritative_world()
	if SteamLobby.is_session_active():
		_rpc_apply_world_progress.rpc(world_progress)


func sync_world_progress_to_peers(progress: Dictionary) -> void:
	if not SteamLobby.is_session_active() or not multiplayer.is_server():
		return
	_rpc_apply_world_progress.rpc(progress)


@rpc("authority", "call_local", "reliable")
func _rpc_apply_world_progress(progress: Dictionary) -> void:
	world_progress = progress.duplicate(true)


func _save_authoritative_world() -> void:
	if not _owns_world_save:
		return
	SaveManager.save_world_progress(world_progress)


func _spawn_solo() -> void:
	if PlayerProfile.hero_scene.is_empty():
		push_warning("hub: герой не выбран")
		return

	SaveManager.ensure_starter_inventory_if_empty()

	var spawn_pos: Vector3 = spawns[0].global_position if not spawns.is_empty() else Vector3.ZERO
	var state_data := {
		"peer_id": 1,
		"hero_scene": PlayerProfile.hero_scene,
		"inventory": PlayerProfile.inventory,
		"equipment": PlayerProfile.equipment,
	}
	_spawner.spawn_player(self, state_data, spawn_pos)


func _spawn_test_dog() -> void:
	_spawn_test_dog_at(_test_dog_spawn_position())


func spawn_test_dog_for_session() -> void:
	if not SteamLobby.is_session_active() or not multiplayer.is_server():
		return
	_rpc_spawn_test_dog.rpc(_test_dog_spawn_position())


func _test_dog_spawn_position() -> Vector3:
	var spawn_pos: Vector3 = spawns[0].global_position if not spawns.is_empty() else Vector3.ZERO
	spawn_pos += Vector3(-2.0, 0.0, 1.5)
	return spawn_pos


@rpc("authority", "call_local", "reliable")
func _rpc_spawn_test_dog(spawn_pos: Vector3) -> void:
	_spawn_test_dog_at(spawn_pos)


func _spawn_test_dog_at(spawn_pos: Vector3) -> void:
	if get_node_or_null("Dog") != null:
		return
	var dog: Node3D = DogScene.instantiate()
	add_child(dog)
	dog.global_position = spawn_pos
