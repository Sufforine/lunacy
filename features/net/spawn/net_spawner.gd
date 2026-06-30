class_name NetSpawner
extends RefCounted


func spawn_player(parent: Node, state_data: Dictionary) -> void:
	var peer_id: int = state_data.get("peer_id", 0)
	var hero_path: String = state_data.get("hero_scene", "")

	if hero_path.is_empty():
		push_error("NetSpawner: hero_scene пустой для peer %d" % peer_id)
		return

	var hero_scene = load(hero_path)
	if hero_scene == null:
		push_error("NetSpawner: не удалось загрузить '%s'" % hero_path)
		return

	var hero = hero_scene.instantiate()
	hero.name = str(peer_id)
	hero.set_multiplayer_authority(peer_id)
	parent.add_child(hero)

	print("NetSpawner: заспавнен герой для peer ", peer_id)


func despawn_player(parent: Node, peer_id: int) -> void:
	var node = parent.get_node_or_null(str(peer_id))
	if node:
		node.queue_free()
