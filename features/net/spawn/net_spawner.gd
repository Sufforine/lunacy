class_name NetSpawner
extends RefCounted


func spawn_player(parent: Node, state_data: Dictionary, spawn_position: Vector3 = Vector3.ZERO) -> Node:
	var peer_id: int = state_data.get("peer_id", 0)
	var hero_path: String = state_data.get("hero_scene", "")

	if peer_id <= 0:
		push_error("NetSpawner: некорректный peer_id %d" % peer_id)
		return null

	var existing := parent.get_node_or_null(str(peer_id))
	if existing:
		return existing

	if hero_path.is_empty():
		push_error("NetSpawner: hero_scene пустой для peer %d" % peer_id)
		return null

	var hero_scene := load(hero_path)
	if hero_scene == null:
		push_error("NetSpawner: не удалось загрузить '%s'" % hero_path)
		return null

	var hero: Node = hero_scene.instantiate()
	hero.name = str(peer_id)
	hero.set_multiplayer_authority(peer_id)

	if not state_data.is_empty():
		hero.set_meta("network_state", state_data)

	parent.add_child(hero)

	if hero is Node3D and spawn_position != Vector3.ZERO:
		(hero as Node3D).global_position = spawn_position

	print("NetSpawner: заспавнен герой для peer ", peer_id, " @ ", spawn_position)
	return hero


func despawn_player(parent: Node, peer_id: int) -> void:
	var node := parent.get_node_or_null(str(peer_id))
	if node:
		node.queue_free()
