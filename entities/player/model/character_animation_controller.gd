extends Node

const MOVEMENT_PARAMETER := "parameters/Alive/Base/Grounded/Movement/blend_position"
const STRIDE_PARAMETER := "parameters/Alive/Base/Grounded/Stride/scale"
const UPPER_WEIGHT_PARAMETER := "parameters/Alive/UpperBlend/blend_amount"
const JUMP_RATE_PARAMETER := "parameters/Alive/Base/JumpStart/Rate/scale"
const LAND_RATE_PARAMETER := "parameters/Alive/Base/Land/Rate/scale"
const FULL_BODY_STATES := [&"ActionA", &"ActionB", &"Guard"]

var hero: Player
var animation_player: AnimationPlayer
var animation_tree: AnimationTree
var _animation_playback: AnimationNodeStateMachinePlayback
var _base_playback: AnimationNodeStateMachinePlayback
var _upper_playback: AnimationNodeStateMachinePlayback
var _base: AnimationNodeStateMachine
var _upper: AnimationNodeStateMachine
var _movement: AnimationNodeBlendSpace1D
var _library: AnimationLibrary
var _action_locked := false
var _action_time_left := 0.0
var _holding := false
var _upper_body_action := false
var _use_full_b := false
var _use_upper_b := false
var _allow_air := false
var _clips: Dictionary = {}
var _default_idle: StringName
var _smoothed_speed := 0.0
var _movement_blend := 0.0
var _stride_scale := 1.0
var _upper_weight := 0.0


func _ready() -> void:
	hero = get_parent() as Player
	animation_player = hero.animation_player
	animation_tree = hero.animation_tree
	if animation_player == null or animation_tree == null:
		push_error("CharacterAnimationController: missing AnimationPlayer or AnimationTree")
		return
	animation_tree.active = false
	animation_tree.tree_root = animation_tree.tree_root.duplicate(true)
	var root := animation_tree.tree_root as AnimationNodeStateMachine
	var layers := root.get_node(&"Alive") as AnimationNodeBlendTree if root != null else null
	if layers == null:
		push_error("CharacterAnimationController: Alive must be an AnimationNodeBlendTree")
		return
	_base = layers.get_node(&"Base") as AnimationNodeStateMachine
	_upper = layers.get_node(&"UpperActions") as AnimationNodeStateMachine
	var grounded := _base.get_node(&"Grounded") as AnimationNodeBlendTree if _base != null else null
	_movement = grounded.get_node(&"Movement") as AnimationNodeBlendSpace1D if grounded != null else null
	if _movement == null or _upper == null:
		push_error("CharacterAnimationController: missing locomotion or upper-body layer")
		return
	# Each hero owns the tree and equipment clips; shared imported resources stay immutable.
	_library = AnimationLibrary.new()
	animation_player.add_animation_library(&"equipment", _library)
	_default_idle = (_movement.get_blend_point_node(0) as AnimationNodeAnimation).animation
	_animation_playback = animation_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	_base_playback = animation_tree.get("parameters/Alive/Base/playback") as AnimationNodeStateMachinePlayback
	_upper_playback = animation_tree.get("parameters/Alive/UpperActions/playback") as AnimationNodeStateMachinePlayback
	animation_tree.set(MOVEMENT_PARAMETER, 0.0)
	animation_tree.set(STRIDE_PARAMETER, 1.0)
	animation_tree.set(UPPER_WEIGHT_PARAMETER, 0.0)
	_configure_phase_rate(&"JumpStart", hero.animation_jump_start_duration, JUMP_RATE_PARAMETER)
	_configure_phase_rate(&"Land", hero.animation_land_duration, LAND_RATE_PARAMETER)
	animation_tree.active = true
	_base_playback.start(&"Grounded")
	_upper_playback.start(&"Guard")
	_animation_playback.start(&"Alive")


func configure_weapon(weapon: WeaponData) -> void:
	if _movement == null or _library == null:
		return
	cancel_action()
	# Keep old clips until this hero is freed so a fading action can finish safely.
	var idle := _movement.get_blend_point_node(0) as AnimationNodeAnimation
	idle.animation = _default_idle
	if weapon == null:
		return
	if weapon.idle_animation != null:
		idle.animation = _register_clip(weapon.idle_animation, true)
	for index in [-2, -1, 0, 1, 2]:
		var ability := weapon.get_ability(index)
		if ability != null and ability.animation != null:
			_register_clip(ability.animation, ability.held)


func _register_clip(source: Animation, loop: bool) -> StringName:
	var key := "%s_%s" % [source.get_instance_id(), loop]
	if _clips.has(key):
		return _clips[key]
	var clip := source.duplicate() as Animation
	clip.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var clip_name := StringName("clip_%d" % _clips.size())
	_library.add_animation(clip_name, clip)
	var path := StringName("equipment/" + str(clip_name))
	_clips[key] = path
	return path


func play_action(ability: AbilityDefinition, elapsed: float = 0.0) -> void:
	if _base_playback == null or _library == null:
		return
	cancel_action()
	if ability.animation == null:
		return
	_upper_body_action = ability.animation_layer == AbilityDefinition.AnimationLayer.UPPER_BODY
	_allow_air = not ability.requires_grounded
	_action_time_left = maxf(0.0, ability.get_duration() - elapsed)
	_action_locked = _action_time_left > 0.0
	# Each layer alternates its own two slots, including consecutive identical attacks.
	var state: StringName
	if _upper_body_action:
		_use_upper_b = not _use_upper_b
		state = &"ActionB" if _use_upper_b else &"ActionA"
	else:
		_use_full_b = not _use_full_b
		state = &"ActionB" if _use_full_b else &"ActionA"
	var machine := _upper if _upper_body_action else _base
	var playback := _upper_playback if _upper_body_action else _base_playback
	var action_tree := machine.get_node(state) as AnimationNodeBlendTree
	(action_tree.get_node(&"Clip") as AnimationNodeAnimation).animation = _register_clip(ability.animation, false)
	var parameter_root := "parameters/Alive/%s/%s" % ["UpperActions" if _upper_body_action else "Base", state]
	animation_tree.set(parameter_root + "/Rate/scale", ability.get_animation_speed())
	animation_tree.set(parameter_root + "/Seek/seek_request", -1.0)
	playback.travel(state)
	if elapsed > 0.0 and _action_locked:
		animation_tree.set(parameter_root + "/Seek/seek_request", elapsed * ability.get_animation_speed())
	_interrupt_landing_for_action()


func play_hold(ability: AbilityDefinition, _elapsed: float = 0.0) -> void:
	if _base_playback == null or _library == null:
		return
	cancel_action()
	_upper_body_action = ability.animation_layer == AbilityDefinition.AnimationLayer.UPPER_BODY
	_allow_air = not ability.requires_grounded
	_holding = true
	var clip := _register_clip(ability.animation, true) if ability.animation != null else _default_idle
	var machine := _upper if _upper_body_action else _base
	var playback := _upper_playback if _upper_body_action else _base_playback
	(machine.get_node(&"Guard") as AnimationNodeAnimation).animation = clip
	playback.travel(&"Guard")
	_interrupt_landing_for_action()


func _configure_phase_rate(state: StringName, duration: float, parameter: String) -> void:
	var phase := _base.get_node(state) as AnimationNodeBlendTree
	if phase == null:
		return
	var clip_node := phase.get_node(&"Clip") as AnimationNodeAnimation
	if clip_node == null or not animation_player.has_animation(clip_node.animation):
		return
	var clip := animation_player.get_animation(clip_node.animation)
	animation_tree.set(parameter, clip.length / maxf(duration, 0.01))


func _interrupt_landing_for_action() -> void:
	# An upper-body action also interrupts a landing, without replacing leg movement.
	if _upper_body_action and _base_playback.get_current_node() == &"Land":
		_travel_base(&"Grounded")


func cancel_action() -> void:
	_allow_air = false
	_action_locked = false
	_holding = false
	_action_time_left = 0.0
	if _base_playback != null and _base_playback.get_current_node() in FULL_BODY_STATES:
		_travel_base(&"Air" if _is_airborne() else &"Grounded")


func _process(delta: float) -> void:
	if _animation_playback == null or _base_playback == null:
		return
	if _action_locked:
		_action_time_left = maxf(0.0, _action_time_left - delta)
		_action_locked = _action_time_left > 0.0
	if _holding and (hero.weapon_combat == null or not hero.weapon_combat.blocking):
		_holding = false
	_update_locomotion(delta)
	_update_animation()
	var target_weight := 1.0 if _upper_body_action and (_action_locked or _holding) else 0.0
	_upper_weight = move_toward(_upper_weight, target_weight, delta / 0.12)
	animation_tree.set(UPPER_WEIGHT_PARAMETER, _upper_weight)


func _update_locomotion(delta: float) -> void:
	# The owner publishes real controlled speed. Remote peers do not differentiate
	# interpolated positions or include external impulses in their gait.
	var speed := hero.locomotion_speed
	if not is_finite(speed) or SteamLobby.is_gameplay_locked() or _is_airborne() \
		or hero.animation_state in [Player.AnimationState.DOWNED, Player.AnimationState.DEAD]:
		speed = 0.0
	speed = clampf(speed, 0.0, 60.0)
	var response := 1.0 - exp(-hero.animation_blend_response * delta)
	_smoothed_speed = lerpf(_smoothed_speed, speed, response)
	if _smoothed_speed < 0.04:
		_smoothed_speed = 0.0
	var walk_speed := maxf(0.1, hero.animation_walk_speed)
	var run_speed := maxf(walk_speed + 0.1, hero.animation_sprint_speed)
	var target_blend := 0.0
	if _smoothed_speed > 0.08:
		# Fade out idle early; slower movement then uses a slower walking cycle.
		target_blend = minf(1.0, _smoothed_speed / (walk_speed * 0.25))
		if _smoothed_speed > walk_speed:
			target_blend = 1.0 + clampf((_smoothed_speed - walk_speed) / (run_speed - walk_speed), 0.0, 1.0)
	_movement_blend = lerpf(_movement_blend, target_blend, response)
	if _smoothed_speed == 0.0 and _movement_blend < 0.01:
		_movement_blend = 0.0
	var reference_speed := lerpf(walk_speed, run_speed, clampf(_movement_blend - 1.0, 0.0, 1.0))
	var gait_rate := clampf(_smoothed_speed / reference_speed, 0.3, 2.5)
	# Idle keeps its normal tempo. Stride only scales Grounded, never attack clips.
	var target_rate := lerpf(1.0, gait_rate, minf(1.0, _movement_blend))
	_stride_scale = lerpf(_stride_scale, target_rate, response)
	animation_tree.set(MOVEMENT_PARAMETER, _movement_blend)
	animation_tree.set(STRIDE_PARAMETER, _stride_scale)


func _update_animation() -> void:
	if hero.animation_state in [Player.AnimationState.DOWNED, Player.AnimationState.DEAD]:
		_action_locked = false
		_holding = false
		_upper_weight = 0.0
		var root_state := &"Dead" if hero.animation_state == Player.AnimationState.DEAD else &"Downed"
		if _animation_playback.get_current_node() != root_state:
			_animation_playback.travel(root_state)
		return
	if _animation_playback.get_current_node() != &"Alive":
		_animation_playback.travel(&"Alive")
		_base_playback.start(&"Grounded")
	if _is_airborne() and not _allow_air:
		_action_locked = false
		_holding = false
	# Full-body actions own the base pose. Upper-body actions keep legs updating.
	if not _upper_body_action and (_action_locked or _holding):
		return
	var current := _base_playback.get_current_node()
	if _is_airborne():
		if hero.animation_state == Player.AnimationState.FALL:
			_travel_base(&"Air")
		elif current not in [&"JumpStart", &"Air"]:
			_travel_base(&"JumpStart")
		return
	if current in [&"JumpStart", &"Air"]:
		if hero.locomotion_speed > 0.08 or _action_locked or _holding:
			_travel_base(&"Grounded")
		else:
			_travel_base(&"Land")
		return
	if current == &"Land" and hero.locomotion_speed <= 0.08 and not _action_locked and not _holding \
		and _base_playback.get_current_play_position() < _base_playback.get_current_length() - 0.12:
		return
	_travel_base(&"Grounded")


func _is_airborne() -> bool:
	return hero.animation_state in [Player.AnimationState.JUMP, Player.AnimationState.FALL]


func _travel_base(state: StringName) -> void:
	if _base_playback.get_current_node() != state:
		_base_playback.travel(state)
