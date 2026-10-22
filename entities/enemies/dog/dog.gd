extends CharacterBody3D

enum State { IDLE, WALK }

const ANIM_IDLE := [&"idle", &"T"]
const ANIM_RUN := [&"walk", &"Run"]

@export var move_speed: float = 2.5
@export var turn_speed: float = 5.0
@export var idle_duration_min: float = 1.0
@export var idle_duration_max: float = 3.5
@export var walk_duration_min: float = 1.5
@export var walk_duration_max: float = 4.0
@export var wander_radius: float = 14.0

@onready var model: Node3D = $Model
@onready var stats: StatsComponent = $StatsComponent

var animation_player: AnimationPlayer
var _state: State = State.IDLE
var _state_timer: float = 0.0
var _move_direction := Vector3.ZERO
var _spawn_origin := Vector3.ZERO


func _ready() -> void:
	_spawn_origin = global_position
	animation_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_enter_idle()


func _physics_process(delta: float) -> void:
	if SteamLobby.is_gameplay_locked():
		return
	if SteamLobby.is_session_active() and not is_multiplayer_authority():
		_update_animation()
		return

	_state_timer -= delta

	match _state:
		State.WALK:
			_apply_walk(delta)
			if _state_timer <= 0.0 or _is_outside_wander():
				_enter_idle()
		State.IDLE:
			velocity.x = 0.0
			velocity.z = 0.0
			if _state_timer <= 0.0:
				_enter_walk()

	if not is_on_floor():
		velocity.y -= _get_gravity() * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	move_and_slide()
	_update_animation()


func _enter_idle() -> void:
	_state = State.IDLE
	_state_timer = randf_range(idle_duration_min, idle_duration_max)
	velocity.x = 0.0
	velocity.z = 0.0


func _enter_walk() -> void:
	_state = State.WALK
	_state_timer = randf_range(walk_duration_min, walk_duration_max)
	_move_direction = _pick_walk_direction()


func _pick_walk_direction() -> Vector3:
	var to_origin := _spawn_origin - global_position
	to_origin.y = 0.0

	if _is_outside_wander() and to_origin.length_squared() > 0.01:
		return to_origin.normalized()

	var angle := randf() * TAU
	return Vector3(cos(angle), 0.0, sin(angle))


func _apply_walk(delta: float) -> void:
	var actual_speed := stats.get_stat("move_speed") if stats != null else move_speed
	velocity.x = _move_direction.x * actual_speed
	velocity.z = _move_direction.z * actual_speed

	if _move_direction.length_squared() < 0.001:
		return

	var target_y := atan2(_move_direction.x, _move_direction.z)
	rotation.y = lerp_angle(rotation.y, target_y, turn_speed * delta)


func _is_outside_wander() -> bool:
	var offset := global_position - _spawn_origin
	offset.y = 0.0
	return offset.length() > wander_radius


func _update_animation() -> void:
	if animation_player == null:
		return

	var candidates: Array = ANIM_RUN if _state == State.WALK else ANIM_IDLE
	for animation_name in candidates:
		if animation_player.has_animation(animation_name):
			if animation_player.current_animation != animation_name:
				animation_player.play(animation_name)
			return


func _get_gravity() -> float:
	return ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
