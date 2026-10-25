extends Node

var hero: Player
var animation_player: AnimationPlayer
var animation_tree: AnimationTree
var _animation_playback: AnimationNodeStateMachinePlayback
var _alive_playback: AnimationNodeStateMachinePlayback
var _alive: AnimationNodeStateMachine
var _library: AnimationLibrary
var _action_locked := false
var _action_time_left := 0.0
var _use_action_b := false
var _allow_air := false
var _clips: Dictionary = {}
var _default_idle: StringName


func _ready() -> void:
	hero = get_parent() as Player
	animation_player = hero.animation_player
	animation_tree = hero.animation_tree
	if animation_player == null or animation_tree == null:
		return
	animation_tree.active = false
	animation_tree.tree_root = animation_tree.tree_root.duplicate(true)
	var root := animation_tree.tree_root as AnimationNodeStateMachine
	_alive = root.get_node(&"Alive") as AnimationNodeStateMachine
	# Separate action library per hero. Imported animations are never modified.
	_library = AnimationLibrary.new()
	animation_player.add_animation_library(&"equipment", _library)
	var grounded := _alive.get_node(&"Grounded") as AnimationNodeBlendSpace1D
	_default_idle = (grounded.get_blend_point_node(0) as AnimationNodeAnimation).animation
	_animation_playback = animation_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	_alive_playback = animation_tree.get("parameters/Alive/playback") as AnimationNodeStateMachinePlayback
	animation_tree.active = true
	_alive_playback.start(&"Grounded")
	_animation_playback.start(&"Alive")


func configure_weapon(weapon: WeaponData) -> void:
	if _alive == null:
		return
	cancel_action()
	# Cache clips across equipment switches so a crossfade can finish safely.
	var grounded := _alive.get_node(&"Grounded") as AnimationNodeBlendSpace1D
	var idle := grounded.get_blend_point_node(0) as AnimationNodeAnimation
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


func play_action(ability: AbilityDefinition) -> void:
	if _alive == null or ability.animation == null:
		return
	# Alternate two generic slots so consecutive uses restart and crossfade.
	_use_action_b = not _use_action_b
	var state: StringName = &"ActionB" if _use_action_b else &"ActionA"
	(_alive.get_node(state) as AnimationNodeAnimation).animation = _register_clip(ability.animation, false)
	_allow_air = not ability.requires_grounded
	_action_locked = true
	_action_time_left = ability.get_duration()
	_travel_animation(state)


func play_hold(ability: AbilityDefinition) -> void:
	if _alive == null:
		return
	_allow_air = not ability.requires_grounded
	var clip := _register_clip(ability.animation, true) if ability.animation != null else _default_idle
	(_alive.get_node(&"Guard") as AnimationNodeAnimation).animation = clip
	_travel_animation(&"Guard")


func cancel_action() -> void:
	_allow_air = false
	_action_locked = false
	_action_time_left = 0.0
	if _alive_playback != null:
		_travel_animation(&"Grounded")


func _process(delta: float) -> void:
	if _action_locked:
		_action_time_left = maxf(0.0, _action_time_left - delta)
		_action_locked = _action_time_left > 0.0
	_update_animation()


func _update_animation() -> void:
	if _animation_playback == null or _alive_playback == null:
		return
	if hero.animation_state in [Player.AnimationState.DOWNED, Player.AnimationState.DEAD]:
		_action_locked = false
		var root_state := &"Dead" if hero.animation_state == Player.AnimationState.DEAD else &"Downed"
		if _animation_playback.get_current_node() != root_state:
			_animation_playback.travel(root_state)
		return
	if _animation_playback.get_current_node() != &"Alive":
		_animation_playback.travel(&"Alive")
		_alive_playback.start(&"Grounded")
	if _allow_air and (_action_locked or (hero.weapon_combat != null and hero.weapon_combat.blocking)):
		return
	var current := _alive_playback.get_current_node()
	if hero.animation_state in [Player.AnimationState.JUMP, Player.AnimationState.FALL]:
		_action_locked = false
		if hero.animation_state == Player.AnimationState.FALL:
			_travel_animation(&"Air")
		elif current not in [&"JumpStart", &"Air"]:
			_travel_animation(&"JumpStart")
		return
	if current in [&"JumpStart", &"Air"]:
		_travel_animation(&"Land")
		return
	if _action_locked:
		return
	if hero.weapon_combat != null and hero.weapon_combat.blocking:
		_travel_animation(&"Guard")
		return
	# В покое даём приземлению закончиться. Движение сразу прерывает Land;
	# способность переводит дерево напрямую через play_action().
	if current == &"Land" and hero.animation_state == Player.AnimationState.IDLE \
			and _alive_playback.get_current_play_position() < _alive_playback.get_current_length() - 0.12:
		return
	var movement_blend := 0.0
	match hero.animation_state:
		Player.AnimationState.WALK:
			movement_blend = 1.0
		Player.AnimationState.SPRINT:
			movement_blend = 2.0
	animation_tree.set("parameters/Alive/Grounded/blend_position", movement_blend)
	_travel_animation(&"Grounded")


func _travel_animation(state: StringName) -> void:
	if _alive_playback.get_current_node() != state:
		_alive_playback.travel(state)


