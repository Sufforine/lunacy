class_name Player
extends CharacterBody3D

## Player move speed
@export var move_speed: float = 5.0

## Rotation ease speed
@export var ease_speed: float = 5.0

## Camera rig
@onready var camera_rig = $CameraRig

@onready var mission_inventory: Inventory = get_node_or_null("Inventory")
@onready var storage_inventory: Inventory = get_node_or_null("Storage")

var _storage_open := false

func _physics_process(delta: float) -> void:
	_handle_movement()
	_handle_rotation(delta)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_storage"):
		_toggle_storage()

func _toggle_storage() -> void:
	if not storage_inventory:
		return

	_storage_open = not _storage_open
	storage_inventory.visible = _storage_open

	if _storage_open:
		if PlayerStorage.slots_state.is_empty():
			PlayerStorage.slots_state.resize(storage_inventory.rows * storage_inventory.cols)
		storage_inventory.import_state(PlayerStorage.slots_state)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		PlayerStorage.slots_state = storage_inventory.export_state()
		Inventory.selected_item = null
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Handle player movement
func _handle_movement() -> void:
	var input_dir = InputManager.get_input_direction()
	var velocity_vector = input_dir * move_speed
	velocity.x = velocity_vector.x
	velocity.z = velocity_vector.z
	move_and_slide()

## Handle player rotation
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
