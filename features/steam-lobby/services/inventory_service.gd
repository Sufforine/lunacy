# Host-authoritative inventory operations and snapshots.
extends "res://features/steam-lobby/services/lobby_service.gd"


func request_inventory_operation(sequence: int, revision: int, command: Dictionary) -> void:
	if multiplayer.is_server():
		_server_inventory_operation(multiplayer.get_unique_id(), sequence, revision, command)
	else:
		_lobby._rpc_inventory_operation.rpc_id(1, sequence, revision, command)


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
					_lobby._rpc_apply_progress.rpc(peer_id, hero.stats.get_progress_data())
				elif item.heal_hp > 0 or item.heal_mana > 0:
					# Only inventory ownership changes here; combat authority is unchanged.
					if item.is_consumable:
						inv.consume_network_item(source, index, item.id)
					_lobby._rpc_inventory_use_effect.rpc(peer_id, item.id)
		"drop":
			if item != null and source != "equipment":
				inv.consume_network_item(source, index, item.id)
				var direction := hero.get_facing_direction()
				_lobby._rpc_spawn_drop.rpc(_drops.allocate_id(), item.id, hero.global_position + direction * 0.6 + Vector3.UP, direction, peer_id)
		"chest_put", "chest_take":
			# Resolve relative paths from the original RPC endpoint as before.
			var chest := _lobby.get_node_or_null(NodePath(str(command.get("chest", ""))))
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
	_lobby._rpc_inventory_snapshot.rpc(peer_id, sequence, inv.network_revision, inv.get_data(), inv.get_quickslot_data(), inv.get_parent().equipment.to_dict())


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


func _rpc_inventory_use_effect(peer_id: int, item_id: String) -> void:
	var hero := _hero_for_peer(peer_id)
	var item := ItemLibrary.get_item(item_id)
	if hero != null and item != null and hero.is_multiplayer_authority():
		item.use(hero)
	elif hero != null and item != null and item.heal_mana > 0:
		# Ability costs are validated on the host; keep its mana copy in sync
		# with this already-authorized potion use (without applying HP twice).
		hero.stats.restore_mana(item.heal_mana)


# Calls into other services go through the facade.


func _hero_for_peer(peer_id: int) -> Node:
	return _lobby._hero_for_peer(peer_id)


func _inventory_for_peer(peer_id: int) -> InventoryComponent:
	return _lobby._inventory_for_peer(peer_id)


func is_gameplay_locked() -> bool:
	return _lobby.is_gameplay_locked()
