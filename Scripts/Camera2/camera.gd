extends Node3D

@export var sensitivity: float = 0.005

func _ready():
	# Capture the mouse to allow infinite rotation without hitting screen edges
	top_level = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent):
	if event is InputEventMouseMotion:
		# Rotate the pivot (and thus the camera) based on horizontal mouse movement
		# This "turns the world" around the player
		rotate_y(-event.relative.x * sensitivity)
		
		# Optional: Add vertical rotation to the CameraArm child
		# var arm = $CameraArm
		# arm.rotate_x(-event.relative.y * sensitivity)
		# arm.rotation.x = clamp(arm.rotation.x, deg_to_rad(-60), deg_to_rad(-20))

func _process(_delta):
	# Keep the pivot exactly at the player's position
	# This prevents the camera from inheriting the player's rotation
	global_position = get_parent().global_position
