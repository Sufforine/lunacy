extends CharacterBody3D
class_name Slon

@export var ease_speed: float = 5.0

@onready var camera_rig = $CameraRig
#@onready var dullahan: Node3D = $Slon
#@onready var animation_player: AnimationPlayer = $Dullahan/AnimationPlayer

@onready var stats: StatsComponent = $StatsComponent
@onready var stats_label: Label = $CanvasLayer/StatsLabel






func _process(_delta: float) -> void:



	stats_label.text = \
		"HP: " + str(stats.get_stat("health")) + "\n" + \
		"Mana: " + str(stats.get_stat("mana")) + "\n" + \
		"Phys Damage: " + str(stats.get_stat("physical_damage")) + "\n" + \
		"Magic Damage: " + str(stats.get_stat("magical_damage")) + "\n" + \
		"Phys Resist: " + str(stats.get_stat("physical_resistance")) + "\n" + \
		"Magic Resist: " + str(stats.get_stat("magical_resistance")) + "\n" + \
		"Move Speed: " + str(stats.get_stat("move_speed")) + "\n" + \
		"Attack Speed: " + str(stats.get_stat("attack_speed")) + "\n" + \
		"Crit Chance: " + str(stats.get_stat("crit_chance")) + "\n" + \
		"Crit Damage: " + str(stats.get_stat("crit_damage"))


func _physics_process(delta: float) -> void:
	_handle_movement()
	_handle_rotation(delta)


func _handle_movement() -> void:

	var input_dir = InputManager.get_input_direction()

	var current_move_speed = stats.get_stat("move_speed")

	var velocity_vector = input_dir * current_move_speed

	velocity.x = velocity_vector.x
	velocity.z = velocity_vector.z



	move_and_slide()


func _handle_rotation(delta: float) -> void:

	if not camera_rig:
		printerr("Missing camera rig")
		return

	var camera: Camera3D = camera_rig.camera

	var viewport = get_viewport()

	if not viewport:
		printerr("Missing viewport")
		return

	var mouse_pos = viewport.get_mouse_position()

	var from = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)

	var plane = Plane(Vector3.UP, position.y)

	var mouse_world_pos = plane.intersects_ray(from, dir)

	if mouse_world_pos != null:

		var target_dir = (position - mouse_world_pos).normalized()

		var target_rot_y = atan2(target_dir.x, target_dir.z)

		rotation.y = lerp_angle(
			rotation.y,
			target_rot_y,
			1.0 - pow(0.001, delta * ease_speed)
		)
