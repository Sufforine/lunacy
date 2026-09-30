class_name CameraRig
extends Node3D

const WORLD_LAYER := 1 << 0
const CAMERA_LAYER := 1 << 9

@onready var camera: Camera3D = $Camera3D

@export var player: Player
@export var enabled := false

@export_group("Composition")
@export var target_height := 1.25
@export var shoulder_offset := 1.15
@export var base_camera_height := 0.8
@export var look_ahead_distance := 1.75

@export_group("Orbit")
@export_range(0.01, 1.0, 0.01) var mouse_sensitivity := 0.15
@export_range(-45.0, 45.0, 1.0) var default_pitch_degrees := 18.0
@export_range(-60.0, 0.0, 1.0) var minimum_pitch_degrees := -10.0
@export_range(0.0, 85.0, 1.0) var maximum_pitch_degrees := 55.0

@export_group("Zoom")
@export_range(1.0, 20.0, 0.1) var default_distance := 5.5
@export_range(0.5, 10.0, 0.1) var minimum_distance := 2.5
@export_range(2.0, 30.0, 0.1) var maximum_distance := 10.0
@export_range(0.1, 5.0, 0.1) var zoom_step := 0.75
@export_range(1.0, 30.0, 0.5) var zoom_smoothing := 12.0

@export_group("Collision")
@export_flags_3d_physics var collision_mask := WORLD_LAYER | CAMERA_LAYER
@export_range(0.05, 1.0, 0.01) var collision_radius := 0.2

var _target_distance := 5.5
var _current_distance := 5.5
var _yaw := 0.0
var _pitch := 0.0
var _collision_shape := SphereShape3D.new()


func _ready() -> void:
	_target_distance = clampf(default_distance, minimum_distance, maximum_distance)
	_current_distance = _target_distance
	_pitch = deg_to_rad(clampf(
		default_pitch_degrees,
		minimum_pitch_degrees,
		maximum_pitch_degrees
	))
	_collision_shape.radius = collision_radius

	if player == null and get_parent() is Player:
		player = get_parent() as Player

	call_deferred("_activate_if_local")


func _activate_if_local() -> void:
	if player != null and player.is_multiplayer_authority():
		activate_for_local_player()
	else:
		deactivate()


func activate_for_local_player() -> void:
	if player == null:
		return

	enabled = true
	global_position = _focus_position()
	camera.position = _camera_offset(_current_distance)
	camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func deactivate() -> void:
	enabled = false
	if camera != null:
		var was_current := camera.current
		camera.current = false
		if was_current and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_apply_orbit_motion(motion.relative)
		return

	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return

	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_target_distance = maxf(minimum_distance, _target_distance - zoom_step)
		get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_target_distance = minf(maximum_distance, _target_distance + zoom_step)
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if not enabled or player == null or not is_instance_valid(player):
		return

	global_position = _focus_position()

	var zoom_weight := 1.0 - exp(-zoom_smoothing * delta)
	_current_distance = lerpf(_current_distance, _target_distance, zoom_weight)

	var desired_position := global_position + _camera_offset(_current_distance)
	var safe_position := _resolve_camera_collision(desired_position)
	var is_obstructed := not safe_position.is_equal_approx(desired_position)
	var camera_weight := 1.0 if is_obstructed else zoom_weight
	camera.global_position = camera.global_position.lerp(safe_position, camera_weight)
	camera.look_at(global_position + get_aim_direction() * look_ahead_distance, Vector3.UP)


func _focus_position() -> Vector3:
	return player.global_position + Vector3.UP * target_height


func _camera_offset(distance: float) -> Vector3:
	var orbit_basis := Basis(Vector3.UP, _yaw)
	return orbit_basis * Vector3(
		shoulder_offset,
		base_camera_height + sin(_pitch) * distance,
		cos(_pitch) * distance
	)


func get_aim_direction() -> Vector3:
	return Basis(Vector3.UP, _yaw) * Vector3.FORWARD


func get_camera_relative_direction(input_direction: Vector3) -> Vector3:
	var direction := Basis(Vector3.UP, _yaw) * input_direction
	direction.y = 0.0
	return direction.normalized()


func _apply_orbit_motion(relative: Vector2) -> void:
	_yaw -= deg_to_rad(relative.x * mouse_sensitivity)
	_pitch = clampf(
		_pitch + deg_to_rad(relative.y * mouse_sensitivity),
		deg_to_rad(minimum_pitch_degrees),
		deg_to_rad(maximum_pitch_degrees)
	)


func _resolve_camera_collision(desired_position: Vector3) -> Vector3:
	var motion := desired_position - global_position
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _collision_shape
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	query.motion = motion
	query.collision_mask = collision_mask
	query.exclude = [player.get_rid()]
	query.collide_with_areas = false

	var travel := get_world_3d().direct_space_state.cast_motion(query)
	if travel.is_empty() or is_equal_approx(travel[0], 1.0):
		return desired_position

	return global_position + motion * travel[0]
