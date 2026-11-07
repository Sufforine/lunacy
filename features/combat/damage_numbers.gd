extends RefCounted

static func show_hit(scene: Node, point: Vector3, result: Dictionary) -> void:
	if scene.get_tree().get_nodes_in_group("damage_number").size() >= 64:
		return
	var entries: Array = []
	if int(result.physical) > 0:
		entries.append([str(result.physical), Color.WHITE])
	if int(result.magical) > 0:
		entries.append([str(result.magical), Color("559dff")])
	if entries.is_empty():
		entries.append(["Щит" if float(result.absorbed) > 0.0 else "Блок", Color.WHITE])
	for i in entries.size():
		var label := Label3D.new()
		label.text = entries[i][0]
		label.modulate = entries[i][1]
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 48
		label.outline_size = 10
		label.pixel_size = 0.008
		label.no_depth_test = false
		label.add_to_group("damage_number")
		scene.add_child(label)
		label.global_position = point + Vector3.UP * (0.35 * i + randf_range(0.0, 0.15))
		var tween := label.create_tween().set_parallel(true)
		tween.tween_property(label, "position:y", label.position.y + 0.8, 1.0)
		tween.tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.3)
		tween.chain().tween_callback(label.queue_free)
