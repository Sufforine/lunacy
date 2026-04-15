class_name Player
extends CharacterBody3D


@export var move_speed: float = 5.0
@export var ease_speed: float = 5.0
@onready var camera_rig = $CameraRig
@onready var Dullahan: Node3D = $Dullahan
@onready var animation_player: AnimationPlayer = $Dullahan/AnimationPlayer

enum AnimationState {IDLE, WALK}
var animation_state : int = AnimationState.IDLE

func _process(_delta : float) -> void:
	match(animation_state):
		AnimationState.WALK:
			animation_player.play('Armature|run_f')
			

func _physics_process(delta: float) -> void:
	_handle_movement()
	_handle_rotation(delta)

func _handle_movement() -> void:
	var input_dir = InputManager.get_input_direction()
	var velocity_vector = input_dir * move_speed
	velocity.x = velocity_vector.x
	velocity.z = velocity_vector.z
	animation_state = AnimationState.WALK
	move_and_slide()

func _handle_rotation(delta: float) -> void:
	if not camera_rig:
		printerr("Missing camera")
		return
	
	var camera: Camera3D = camera_rig.camera
	var viewport = get_viewport();
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
		var current_rot_y = rotation.y
		rotation.y = lerp_angle(current_rot_y, target_rot_y, 1.0 - pow(0.001, delta * ease_speed))
