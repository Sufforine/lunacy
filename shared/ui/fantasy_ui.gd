class_name FantasyUI
extends RefCounted

const FRAME_TEXTURE := preload("res://Assets/ui/kenney_fantasy_ui_borders/window_border.png")
const PANEL_TEXTURE := preload("res://Assets/ui/kenney_fantasy_ui_borders/panel_027.png")
const BUTTON_PANEL_TEXTURE := preload("res://Assets/ui/kenney_fantasy_ui_borders/button_panel_028.png")
const BUTTON_BORDER_TEXTURE := preload("res://Assets/ui/kenney_fantasy_ui_borders/button_border_028.png")
const INVENTORY_SLOT_TEXTURE := preload("res://Assets/ui/kenney_fantasy_ui_borders/inventory_slot.png")
const INVENTORY_SLOT_PRESSED_TEXTURE := preload("res://Assets/ui/kenney_fantasy_ui_borders/inventory_slot_pressed.png")
const INVENTORY_SLOT_BORDER_TEXTURE := preload("res://Assets/ui/kenney_fantasy_ui_borders/inventory_slot_border.png")
const INVENTORY_SLOT_BORDER_PRESSED_TEXTURE := preload("res://Assets/ui/kenney_fantasy_ui_borders/inventory_slot_border_pressed.png")
const INTERACTION_BORDER_TEXTURE := preload("res://Assets/ui/kenney_fantasy_ui_borders/interaction_border.png")
const PANEL_COLOR := Color("121418")
const BUTTON_PRESSED_COLOR := Color("ffffff")
const BUTTON_PRESSED_TEXT_COLOR := Color("101114")
const DANGER_BUTTON_TEXT_COLOR := Color("e04450")
const PANEL_PATCH_MARGIN := 16
const BUTTON_PATCH_MARGIN := 16
const BUTTON_BORDER_COLOR := PANEL_COLOR
const FRAME_NODE_NAME := &"FantasyFrame"
const BUTTON_FRAME_NODE_NAME := &"FantasyButtonFrame"
const BUTTON_UNDERLAY_NODE_NAME := &"FantasyButtonUnderlay"
const BUTTON_BACKGROUND_NODE_NAME := &"FantasyButtonBackground"
const BUTTON_BORDER_NODE_NAME := &"FantasyButtonBorder"
const SLOT_BORDER_NODE_NAME := &"FantasySlotBorder"
const PANEL_UNDERLAY_NODE_NAME := &"FantasyPanelUnderlay"


static func apply_root(control: Control, palette: Dictionary) -> void:
	control.theme = create_theme(palette)


static func create_theme(palette: Dictionary) -> Theme:
	var theme := Theme.new()
	var background: Color = palette.background
	var surface: Color = palette.surface
	var border: Color = palette.border
	var text: Color = palette.text
	var accent: Color = palette.accent

	theme.set_color(&"font_color", &"Label", text)
	theme.set_color(&"font_color", &"Button", text)
	theme.set_color(&"font_hover_color", &"Button", text)
	theme.set_color(&"font_pressed_color", &"Button", BUTTON_PRESSED_TEXT_COLOR)
	theme.set_color(&"font_focus_color", &"Button", text)
	theme.set_color(&"font_disabled_color", &"Button", text.darkened(0.45))
	theme.set_color(&"font_color", &"LineEdit", text)
	theme.set_color(&"font_placeholder_color", &"LineEdit", text.darkened(0.38))
	theme.set_color(&"font_color", &"OptionButton", text)
	theme.set_color(&"font_hover_color", &"OptionButton", text)
	theme.set_color(&"font_pressed_color", &"OptionButton", BUTTON_PRESSED_TEXT_COLOR)
	theme.set_color(&"font_selected_color", &"TabContainer", accent)
	theme.set_color(&"font_unselected_color", &"TabContainer", text.darkened(0.25))

	var panel := panel_style(background, border, 3)
	theme.set_stylebox(&"panel", &"Panel", panel)
	theme.set_stylebox(&"panel", &"PanelContainer", panel.duplicate())
	theme.set_stylebox(&"panel", &"PopupPanel", panel.duplicate())
	theme.set_stylebox(&"panel", &"TabContainer", panel_style(background.darkened(0.04), border, 2, false))

	theme.set_stylebox(&"normal", &"Button", button_style(surface, border, 2))
	theme.set_stylebox(&"hover", &"Button", button_style(surface, accent, 2))
	theme.set_stylebox(&"pressed", &"Button", button_style(BUTTON_PRESSED_COLOR, accent, 3))
	theme.set_stylebox(&"focus", &"Button", button_style(surface, accent, 2, false))
	theme.set_stylebox(&"disabled", &"Button", button_style(surface.darkened(0.18), border.darkened(0.25), 2))

	theme.set_stylebox(&"normal", &"LineEdit", field_style(surface, border, 2))
	theme.set_stylebox(&"focus", &"LineEdit", field_style(surface, accent, 3))
	theme.set_stylebox(&"read_only", &"LineEdit", field_style(surface.darkened(0.12), border, 2))
	for state in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		var source_state: StringName = state
		var option_style := theme.get_stylebox(source_state, &"Button")
		theme.set_stylebox(state, &"OptionButton", option_style.duplicate())

	theme.set_stylebox(&"slider", &"HSlider", bar_style(surface.darkened(0.18), border, 1))
	theme.set_stylebox(&"grabber_area", &"HSlider", bar_style(accent, border, 1))
	theme.set_stylebox(&"grabber_area_highlight", &"HSlider", bar_style(accent.lightened(0.12), accent, 1))
	theme.set_stylebox(&"background", &"ProgressBar", bar_style(surface.darkened(0.18), border, 1))
	theme.set_stylebox(&"fill", &"ProgressBar", bar_style(accent, border, 1))
	theme.set_color(&"font_color", &"ProgressBar", text)

	theme.set_constant(&"outline_size", &"Label", 2)
	theme.set_color(&"font_outline_color", &"Label", Color(0, 0, 0, 0.55))
	return theme


static func panel_style(_background: Color, _border: Color, _width: int = 3, _shadow: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	# The Kenney NinePatch is the visible border. A StyleBox border here would
	# create a second rectangular line outside the decorative frame.
	style.border_color = Color.TRANSPARENT
	style.set_border_width_all(0)
	style.set_corner_radius_all(1)
	style.content_margin_left = 8.0
	style.content_margin_top = 8.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 8.0
	return style


static func button_style(_background: Color, _border: Color, _width: int = 2, _fill: bool = true) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	# Button 028 and its separate border are rendered as NinePatch children.
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color.TRANSPARENT
	style.set_border_width_all(0)
	style.set_corner_radius_all(1)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style


static func field_style(background: Color, border: Color, width: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(1)
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	return style


static func bar_style(background: Color, border: Color, width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(1)
	return style


static func borderless_bar_style(background: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = Color.TRANSPARENT
	style.set_border_width_all(0)
	style.set_corner_radius_all(0)
	return style


static func decorate_panel(panel: Control, _border_color: Color, inset: float = 0.0) -> void:
	_decorate_control(panel, FRAME_NODE_NAME, PANEL_COLOR, inset, PANEL_PATCH_MARGIN, PANEL_TEXTURE, true)


static func decorate_filled_panel(panel: Control, panel_color: Color, _border_color: Color) -> void:
	# Panel 027 already contains both the center and its decorative edge.
	_decorate_control(panel, FRAME_NODE_NAME, PANEL_COLOR if panel_color.a > 0.0 else Color.TRANSPARENT, 0.0, PANEL_PATCH_MARGIN, PANEL_TEXTURE, true)
	var underlay := panel.get_node_or_null(NodePath(str(PANEL_UNDERLAY_NODE_NAME))) as ColorRect
	if underlay != null:
		underlay.queue_free()


static func decorate_interaction_prompt(panel: Control, border_color: Color) -> void:
	_decorate_control(panel, FRAME_NODE_NAME, border_color, -4.0, 12, INTERACTION_BORDER_TEXTURE)


static func decorate_button(button: Button, _panel_color: Color, _border_color: Color) -> void:
	# Ordinary buttons use panel 028 as the background and border 028 as an
	# independent overlay, so hover can affect the edge without changing fill.
	if button.has_meta(&"fantasy_inventory_slot"):
		return
	var underlay := button.get_node_or_null(NodePath(str(BUTTON_UNDERLAY_NODE_NAME))) as ColorRect
	if underlay != null:
		underlay.queue_free()
	var frame := button.get_node_or_null(NodePath(str(BUTTON_FRAME_NODE_NAME))) as NinePatchRect
	if frame != null:
		frame.queue_free()
	var background := button.get_node_or_null(NodePath(str(BUTTON_BACKGROUND_NODE_NAME))) as NinePatchRect
	if background == null:
		background = _create_button_nine_patch(button, BUTTON_BACKGROUND_NODE_NAME, BUTTON_PANEL_TEXTURE, true)
	var border := button.get_node_or_null(NodePath(str(BUTTON_BORDER_NODE_NAME))) as NinePatchRect
	if border == null:
		border = _create_button_nine_patch(button, BUTTON_BORDER_NODE_NAME, BUTTON_BORDER_TEXTURE, false)
	button.move_child(background, 0)
	button.move_child(border, 1)
	if not button.has_meta(&"fantasy_hover_connected"):
		button.set_meta(&"fantasy_hover_connected", true)
		button.mouse_entered.connect(_set_button_hovered.bind(button, true))
		button.mouse_exited.connect(_set_button_hovered.bind(button, false))
	if not button.has_meta(&"fantasy_pressed_connected"):
		button.set_meta(&"fantasy_pressed_connected", true)
		button.button_down.connect(_set_button_visual_pressed.bind(button, true))
		button.button_up.connect(_set_button_visual_pressed.bind(button, false))
		if button.toggle_mode:
			button.toggled.connect(func(toggled: bool): _set_button_visual_pressed(button, toggled))
	if button.has_meta(&"fantasy_danger_button"):
		_apply_danger_button_text(button)
	_set_button_hovered(button, button.is_hovered(), true)
	_set_button_visual_pressed(button, button.button_pressed if button.toggle_mode else false)


static func _create_button_nine_patch(button: Button, node_name: StringName, texture: Texture2D, draw_center: bool) -> NinePatchRect:
	var layer := NinePatchRect.new()
	layer.name = node_name
	layer.texture = texture
	layer.draw_center = draw_center
	layer.patch_margin_left = BUTTON_PATCH_MARGIN
	layer.patch_margin_top = BUTTON_PATCH_MARGIN
	layer.patch_margin_right = BUTTON_PATCH_MARGIN
	layer.patch_margin_bottom = BUTTON_PATCH_MARGIN
	layer.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	layer.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.show_behind_parent = true
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return layer


static func decorate_inventory_slot(button: Button, panel_color: Color, border_color: Color) -> void:
	button.set_meta(&"fantasy_inventory_slot", true)
	var underlay := button.get_node_or_null(NodePath(str(BUTTON_UNDERLAY_NODE_NAME))) as ColorRect
	if underlay == null:
		underlay = ColorRect.new()
		underlay.name = BUTTON_UNDERLAY_NODE_NAME
		underlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		underlay.show_behind_parent = true
		button.add_child(underlay)
	underlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	underlay.color = panel_color
	var frame := button.get_node_or_null(NodePath(str(BUTTON_FRAME_NODE_NAME))) as NinePatchRect
	if frame == null:
		frame = NinePatchRect.new()
		frame.name = BUTTON_FRAME_NODE_NAME
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.show_behind_parent = true
		frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		button.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.draw_center = true
	frame.modulate = panel_color
	frame.texture = INVENTORY_SLOT_TEXTURE
	frame.patch_margin_left = 12
	frame.patch_margin_top = 12
	frame.patch_margin_right = 12
	frame.patch_margin_bottom = 12
	_decorate_inventory_border(button, border_color)
	for state in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		button.add_theme_stylebox_override(state, button_style(Color.TRANSPARENT, Color.TRANSPARENT, 0))
	if not button.has_meta(&"fantasy_slot_press_connected"):
		button.set_meta(&"fantasy_slot_press_connected", true)
		button.button_down.connect(_set_inventory_slot_pressed.bind(button, true))
		button.button_up.connect(_set_inventory_slot_pressed.bind(button, false))


static func decorate_inventory_cell(cell: Control, panel_color: Color, border_color: Color) -> void:
	# Ability icons keep their existing size. Only the transparent edge of slot
	# 015 is drawn above the icon, while the slot's StyleBox supplies its fill.
	_decorate_inventory_border(cell, border_color)


static func _decorate_inventory_border(cell: Control, border_color: Color) -> void:
	_decorate_control(cell, SLOT_BORDER_NODE_NAME, border_color, 0.0, 12, INVENTORY_SLOT_BORDER_TEXTURE, false)
	var border := cell.get_node_or_null(NodePath(str(SLOT_BORDER_NODE_NAME))) as NinePatchRect
	if border != null:
		border.z_index = 1


static func _set_inventory_slot_pressed(button: Button, pressed: bool) -> void:
	var frame := button.get_node_or_null(NodePath(str(BUTTON_FRAME_NODE_NAME))) as NinePatchRect
	if frame != null:
		frame.texture = INVENTORY_SLOT_PRESSED_TEXTURE if pressed else INVENTORY_SLOT_TEXTURE
	var border := button.get_node_or_null(NodePath(str(SLOT_BORDER_NODE_NAME))) as NinePatchRect
	if border != null:
		border.texture = INVENTORY_SLOT_BORDER_PRESSED_TEXTURE if pressed else INVENTORY_SLOT_BORDER_TEXTURE


static func mark_danger_button(button: Button) -> void:
	button.set_meta(&"fantasy_danger_button", true)
	_apply_danger_button_text(button)


static func set_button_border_color(button: Button, color: Color) -> void:
	button.set_meta(&"fantasy_normal_border_color", color)
	_apply_button_visuals(button)


static func _apply_danger_button_text(button: Button) -> void:
	button.add_theme_color_override(&"font_color", DANGER_BUTTON_TEXT_COLOR)
	button.add_theme_color_override(&"font_hover_color", DANGER_BUTTON_TEXT_COLOR)
	button.add_theme_color_override(&"font_focus_color", DANGER_BUTTON_TEXT_COLOR)
	button.add_theme_color_override(&"font_pressed_color", BUTTON_PRESSED_TEXT_COLOR)


static func _set_button_hovered(button: Button, hovered: bool, immediate: bool = false) -> void:
	if button.has_meta(&"fantasy_inventory_slot"):
		return
	var previous: Variant = button.get_meta(&"fantasy_hover_tween") if button.has_meta(&"fantasy_hover_tween") else null
	if previous is Tween and (previous as Tween).is_valid():
		(previous as Tween).kill()
	button.pivot_offset = button.size * 0.5
	button.set_meta(&"fantasy_hovered", hovered)
	_apply_button_visuals(button)
	var target_scale := Vector2(1.06, 1.06) if hovered and not button.disabled else Vector2.ONE
	if immediate:
		button.scale = target_scale
		return
	var tween := button.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	button.set_meta(&"fantasy_hover_tween", tween)
	tween.tween_property(button, "scale", target_scale, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


static func _set_button_visual_pressed(button: Button, pressed: bool) -> void:
	button.set_meta(&"fantasy_visual_pressed", pressed or (button.toggle_mode and button.button_pressed))
	_apply_button_visuals(button)


static func _apply_button_visuals(button: Button) -> void:
	var background := button.get_node_or_null(NodePath(str(BUTTON_BACKGROUND_NODE_NAME))) as NinePatchRect
	var border := button.get_node_or_null(NodePath(str(BUTTON_BORDER_NODE_NAME))) as NinePatchRect
	var pressed := bool(button.get_meta(&"fantasy_visual_pressed")) if button.has_meta(&"fantasy_visual_pressed") else false
	var hovered := bool(button.get_meta(&"fantasy_hovered")) if button.has_meta(&"fantasy_hovered") else false
	var normal_border: Color = button.get_meta(&"fantasy_normal_border_color") if button.has_meta(&"fantasy_normal_border_color") else BUTTON_BORDER_COLOR
	if background != null:
		background.modulate = BUTTON_PRESSED_COLOR if pressed else PANEL_COLOR
	if border != null:
		border.modulate = Color.WHITE if hovered or pressed else normal_border


static func _decorate_control(
	control: Control,
	node_name: StringName,
	color: Color,
	inset: float,
	patch_margin: int,
	texture: Texture2D = FRAME_TEXTURE,
	draw_center: bool = false
) -> void:
	var frame := control.get_node_or_null(NodePath(str(node_name))) as NinePatchRect
	if frame == null:
		frame = NinePatchRect.new()
		frame.name = node_name
		frame.patch_margin_left = patch_margin
		frame.patch_margin_top = patch_margin
		frame.patch_margin_right = patch_margin
		frame.patch_margin_bottom = patch_margin
		frame.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
		frame.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		control.add_child(frame)
	frame.z_index = 0
	frame.z_as_relative = true
	frame.show_behind_parent = false
	frame.patch_margin_left = patch_margin
	frame.patch_margin_top = patch_margin
	frame.patch_margin_right = patch_margin
	frame.patch_margin_bottom = patch_margin
	frame.texture = texture
	frame.draw_center = draw_center
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = inset
	frame.offset_top = inset
	frame.offset_right = -inset
	frame.offset_bottom = -inset
	frame.modulate = color
	# Keep the frame above the panel background but below icons, labels and
	# inventory windows. A large relative z-index allowed HUD frames to escape
	# their parent's layer and cover unrelated UI.
	control.move_child(frame, 0)


static func decorate_panels(root: Node, border_color: Color, button_color: Color = Color.WHITE) -> void:
	if root is Panel or root is PanelContainer:
		decorate_panel(root as Control, border_color)
	elif root is Button and not (root as Button).has_meta(&"fantasy_inventory_slot"):
		decorate_button(root as Button, button_color, border_color)
	for child in root.get_children():
		if child.name in [FRAME_NODE_NAME, BUTTON_FRAME_NODE_NAME, BUTTON_UNDERLAY_NODE_NAME, BUTTON_BACKGROUND_NODE_NAME, BUTTON_BORDER_NODE_NAME, SLOT_BORDER_NODE_NAME, PANEL_UNDERLAY_NODE_NAME]:
			continue
		decorate_panels(child, border_color, button_color)
