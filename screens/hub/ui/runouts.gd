extends StaticBody3D

const RUNOUTS_MENU_SCENE := "res://screens/hub/ui/runouts-menu/RunoutsMenu.tscn"

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
	if get_tree().get_first_node_in_group("mission_selection") != null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 60
	get_tree().current_scene.add_child(layer)
	var menu: Control = load(RUNOUTS_MENU_SCENE).instantiate()
	layer.add_child(menu)
	menu.connect("mission_selected", func(): get_tree().current_scene.get_node("Wagon").request_departure())
