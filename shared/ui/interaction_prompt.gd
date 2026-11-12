class_name InteractionPrompt
extends Control

@onready var key_label: Label = %KeyLabel
@onready var key_panel: PanelContainer = $KeyPanel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	GameSettings.ui_scale_changed.connect(_apply_ui_scale)
	GameSettings.inventory_theme_changed.connect(_apply_theme)
	key_panel.resized.connect(_update_pivot)
	_apply_ui_scale()
	_apply_theme()


func _apply_ui_scale() -> void:
	key_panel.scale = Vector2.ONE * GameSettings.get_ui_scale()
	_update_pivot.call_deferred()


func _update_pivot() -> void:
	key_panel.pivot_offset = key_panel.size * 0.5


func _apply_theme() -> void:
	var palette := GameSettings.get_ui_theme_palette()
	FantasyUI.apply_root(self, palette)
	# The prompt uses a transparent-center Kenney frame, so it does not need a
	# second panel or rectangular shadow behind the key label.
	var style := FantasyUI.panel_style(Color.TRANSPARENT, palette.border, 0, false)
	key_panel.add_theme_stylebox_override("panel", style)
	FantasyUI.decorate_interaction_prompt(key_panel, palette.border)
	key_label.add_theme_color_override("font_color", palette.text)
	key_label.add_theme_color_override("font_outline_color", Color.TRANSPARENT)
	key_label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	key_label.add_theme_constant_override("outline_size", 0)
	key_label.add_theme_constant_override("shadow_offset_x", 0)
	key_label.add_theme_constant_override("shadow_offset_y", 0)
	key_label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())


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
