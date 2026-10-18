extends StaticBody3D

var glow_ring: MeshInstance3D
var tween: Tween


func _ready() -> void:
	add_to_group("hub_interactable")
	glow_ring = $GlowRing
	glow_ring.visible = false


func set_interaction_focus(focused: bool) -> void:
	if tween != null:
		tween.kill()
	if focused:
		glow_ring.visible = true
		tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.tween_property(glow_ring, "scale", Vector3(2.2, 0.2, 2.2), 0.2)
	else:
		tween = create_tween().set_ease(Tween.EASE_IN)
		tween.tween_property(glow_ring, "scale", Vector3(2.0, 0.0, 2.0), 0.1)
		tween.tween_callback(func() -> void: glow_ring.visible = false)


func interact(_player: Player) -> void:
	get_tree().change_scene_to_file("res://screens/character-select/ui/character_select.tscn")
