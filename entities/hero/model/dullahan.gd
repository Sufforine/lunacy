extends Player

const ANIM_IDLE := "T"
const ANIM_RUN := "Run"
const ANIM_CRAWL := "Crawl"
const ANIM_SLASH := "Slash"
const ANIM_FIREBALLS := "Fireballs"
const ANIM_JUMP := "Jump"

var _action_locked := false


func _ready() -> void:
	super._ready()
	_resolve_animation_player()
	if animation_player != null:
		animation_player.animation_finished.connect(_on_action_animation_finished)


func _resolve_animation_player() -> void:
	if animation_player != null:
		return
	if model == null:
		return
	animation_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer


func _input(event: InputEvent) -> void:
	super._input(event)

	if not is_multiplayer_authority() or stats.is_downed or stats.is_dead:
		return

	if not event.is_pressed() or event.is_echo():
		return

	if event.is_action_pressed("attack"):
		_play_action(ANIM_SLASH)
	elif event.is_action_pressed("ability"):
		_play_action(ANIM_FIREBALLS)
	elif event.is_action_pressed("jump"):
		_play_action(ANIM_JUMP)


func _update_animation() -> void:
	if animation_player == null or _action_locked:
		return

	match animation_state:
		AnimationState.IDLE:
			_play_loop(ANIM_IDLE)
		AnimationState.WALK:
			_play_loop(ANIM_RUN)
		AnimationState.DOWNED:
			_play_loop(ANIM_CRAWL)
		AnimationState.DEAD:
			_play_loop(ANIM_IDLE)


func _play_loop(anim_name: String) -> void:
	if not animation_player.has_animation(anim_name):
		return
	if animation_player.current_animation != anim_name:
		animation_player.play(anim_name)


func _play_action(anim_name: String) -> void:
	if animation_player == null or _action_locked:
		return
	if not animation_player.has_animation(anim_name):
		return
	_action_locked = true
	animation_player.play(anim_name)


func _on_action_animation_finished(_anim_name: StringName) -> void:
	if not _action_locked:
		return
	_action_locked = false
	_update_animation()
