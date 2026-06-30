extends StaticBody3D


var glow_ring: MeshInstance3D
var tween: Tween

func _ready():
	# Настраиваем обнаружение мыши
	var area = $Area3D
	area.mouse_entered.connect(_on_mouse_entered)
	area.mouse_exited.connect(_on_mouse_exited)
	area.input_event.connect(_on_input_event)
	
	# Находим круг свечения
	glow_ring = $GlowRing
	if glow_ring:
		glow_ring.visible = false

func _on_mouse_entered():
	if glow_ring:
		glow_ring.visible = true
		# Анимация появления
		if tween:
			tween.kill()
		tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_BACK)
		tween.tween_property(glow_ring, "scale", Vector3(2.7, 0.2, 2.7), 1.2)

func _on_mouse_exited():
	if glow_ring:
		if tween:
			tween.kill()
		tween = create_tween()
		tween.set_ease(Tween.EASE_IN)
		tween.tween_property(glow_ring, "scale", Vector3(2.5, 0.0, 2.5), 0.1)
		tween.tween_callback(func(): glow_ring.visible = false)

func _on_input_event(camera, event, position, normal, shape_idx):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		get_tree().change_scene_to_file("res://screens/main-menu/ui/main_menu.tscn")
