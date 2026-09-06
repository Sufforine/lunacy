extends Player

const ANIM_SLASH: StringName = &"Slash"
const ANIM_FIREBALLS: StringName = &"Fireballs"
const ANIM_JUMP: StringName = &"Jump"


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
