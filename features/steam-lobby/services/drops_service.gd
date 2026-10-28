# World item spawning, pickup arbitration and local pickup fallback.
extends "res://features/steam-lobby/services/lobby_service.gd"


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
		_lobby._rpc_request_pickup.rpc_id(1, drop_id)


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

	_lobby._rpc_remove_drop.rpc(drop_id)
	server_inventory.add_item(item)
	server_inventory.network_revision += 1
	_publish_inventory(picker_peer)


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


# Calls into other services go through the facade.


func _inventory_for_peer(peer_id: int) -> InventoryComponent:
	return _lobby._inventory_for_peer(peer_id)


func _local_inventory() -> InventoryComponent:
	return _lobby._local_inventory()


func _publish_inventory(peer_id: int, sequence: int = 0) -> void:
	_lobby._publish_inventory(peer_id, sequence)


func is_gameplay_locked() -> bool:
	return _lobby.is_gameplay_locked()


func is_session_active() -> bool:
	return _lobby.is_session_active()
