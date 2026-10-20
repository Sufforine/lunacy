class_name InteractionPrompt
extends Control

@onready var key_label: Label = %KeyLabel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func show_action(action: StringName = &"interact") -> void:
	key_label.text = _action_key_text(action)
	visible = true


func hide_prompt() -> void:
	visible = false


func _action_key_text(action: StringName) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key_event := event as InputEventKey
			var code := key_event.physical_keycode
			if code == KEY_NONE:
				code = key_event.keycode
			var key_text := OS.get_keycode_string(code)
			if not key_text.is_empty():
				return key_text
	return "F"
