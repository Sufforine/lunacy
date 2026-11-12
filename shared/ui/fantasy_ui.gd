class_name FantasyUI
extends RefCounted

const FRAME_TEXTURE := preload("res://Assets/ui/kenney_fantasy_ui_borders/window_border.png")
const BUTTON_TEXTURE := preload("res://Assets/ui/kenney_fantasy_ui_borders/button_panel.png")
const INVENTORY_SLOT_TEXTURE := preload("res://Assets/ui/kenney_fantasy_ui_borders/inventory_slot.png")
const INVENTORY_SLOT_PRESSED_TEXTURE := preload("res://Assets/ui/kenney_fantasy_ui_borders/inventory_slot_pressed.png")
const INTERACTION_BORDER_TEXTURE := preload("res://Assets/ui/kenney_fantasy_ui_borders/interaction_border.png")
const FRAME_NODE_NAME := &"FantasyFrame"
const BUTTON_FRAME_NODE_NAME := &"FantasyButtonFrame"
const BUTTON_UNDERLAY_NODE_NAME := &"FantasyButtonUnderlay"
const PANEL_UNDERLAY_NODE_NAME := &"FantasyPanelUnderlay"


static func apply_root(control: Control, palette: Dictionary) -> void:
	control.theme = create_theme(palette)


static func create_theme(palette: Dictionary) -> Theme:
	var theme := Theme.new()
	var background: Color = palette.background
	var surface: Color = palette.surface
	var hover: Color = palette.surface_hover
	var border: Color = palette.border
	var text: Color = palette.text
	var accent: Color = palette.accent

	theme.set_color(&"font_color", &"Label", text)
	theme.set_color(&"font_color", &"Button", text)
	theme.set_color(&"font_hover_color", &"Button", text.lightened(0.12))
	theme.set_color(&"font_pressed_color", &"Button", text)
	theme.set_color(&"font_focus_color", &"Button", text)
	theme.set_color(&"font_disabled_color", &"Button", text.darkened(0.45))
	theme.set_color(&"font_color", &"LineEdit", text)
	theme.set_color(&"font_placeholder_color", &"LineEdit", text.darkened(0.38))
	theme.set_color(&"font_color", &"OptionButton", text)
	theme.set_color(&"font_selected_color", &"TabContainer", accent)
	theme.set_color(&"font_unselected_color", &"TabContainer", text.darkened(0.25))

	var panel := panel_style(background, border, 3)
	theme.set_stylebox(&"panel", &"Panel", panel)
	theme.set_stylebox(&"panel", &"PanelContainer", panel.duplicate())
	theme.set_stylebox(&"panel", &"PopupPanel", panel.duplicate())
	theme.set_stylebox(&"panel", &"TabContainer", panel_style(background.darkened(0.04), border, 2, false))

	theme.set_stylebox(&"normal", &"Button", button_style(surface, border, 2))
	theme.set_stylebox(&"hover", &"Button", button_style(hover, accent, 2))
	theme.set_stylebox(&"pressed", &"Button", button_style(surface.darkened(0.14), accent, 3))
	theme.set_stylebox(&"focus", &"Button", button_style(Color.TRANSPARENT, accent, 2, false))
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


static func panel_style(background: Color, _border: Color, _width: int = 3, shadow: bool = true) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	# The Kenney NinePatch is the visible border. A StyleBox border here would
	# create a second rectangular line outside the decorative frame.
	style.border_color = Color.TRANSPARENT
	style.set_border_width_all(0)
	style.set_corner_radius_all(1)
	style.content_margin_left = 8.0
	style.content_margin_top = 8.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 8.0
	if shadow:
		style.shadow_color = Color(0, 0, 0, 0.5)
		style.shadow_size = 10
	return style


static func button_style(_background: Color, _border: Color, _width: int = 2, _fill: bool = true) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	# The Kenney panel and its colored underlay are child controls rendered
	# behind Button, so the built-in style must stay transparent.
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
	var style := button_style(background, border, width)
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


static func decorate_panel(panel: Control, border_color: Color, inset: float = 0.0) -> void:
	_decorate_control(panel, FRAME_NODE_NAME, border_color, inset, 12)


static func decorate_filled_panel(panel: Control, panel_color: Color, border_color: Color) -> void:
	# One Kenney panel provides both the background and its visible edge. The
	# underlay only colors the transparent cuts in that same texture.
	_decorate_control(panel, FRAME_NODE_NAME, panel_color, 0.0, 12, BUTTON_TEXTURE, true)
	var underlay := panel.get_node_or_null(NodePath(str(PANEL_UNDERLAY_NODE_NAME))) as ColorRect
	if underlay == null:
		underlay = ColorRect.new()
		underlay.name = PANEL_UNDERLAY_NODE_NAME
		underlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(underlay)
	underlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	underlay.color = border_color
	panel.move_child(underlay, 0)
	var frame := panel.get_node_or_null(NodePath(str(FRAME_NODE_NAME)))
	if frame != null:
		panel.move_child(frame, 1)


static func decorate_interaction_prompt(panel: Control, border_color: Color) -> void:
	_decorate_control(panel, FRAME_NODE_NAME, border_color, -4.0, 12, INTERACTION_BORDER_TEXTURE)


static func decorate_button(button: Button, panel_color: Color, border_color: Color) -> void:
	var underlay := button.get_node_or_null(NodePath(str(BUTTON_UNDERLAY_NODE_NAME))) as ColorRect
	if underlay == null:
		underlay = ColorRect.new()
		underlay.name = BUTTON_UNDERLAY_NODE_NAME
		underlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		underlay.show_behind_parent = true
		button.add_child(underlay)
	underlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	underlay.color = border_color

	var frame := button.get_node_or_null(NodePath(str(BUTTON_FRAME_NODE_NAME))) as NinePatchRect
	if frame == null:
		frame = NinePatchRect.new()
		frame.name = BUTTON_FRAME_NODE_NAME
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.show_behind_parent = true
		frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		frame.patch_margin_left = 12
		frame.patch_margin_top = 12
		frame.patch_margin_right = 12
		frame.patch_margin_bottom = 12
		button.add_child(frame)
	frame.texture = BUTTON_TEXTURE
	frame.draw_center = true
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.set_meta(&"fantasy_panel_color", panel_color)
	button.set_meta(&"fantasy_border_color", border_color)
	if not button.has_meta(&"fantasy_hover_connected"):
		button.set_meta(&"fantasy_hover_connected", true)
		button.mouse_entered.connect(func(): _apply_button_hover(button, true))
		button.mouse_exited.connect(func(): _apply_button_hover(button, false))
	_apply_button_hover(button, button.is_hovered())


static func decorate_inventory_slot(button: Button, panel_color: Color, border_color: Color) -> void:
	decorate_button(button, panel_color, border_color)
	var frame := button.get_node_or_null(NodePath(str(BUTTON_FRAME_NODE_NAME))) as NinePatchRect
	if frame != null:
		frame.texture = INVENTORY_SLOT_TEXTURE
		frame.patch_margin_left = 12
		frame.patch_margin_top = 12
		frame.patch_margin_right = 12
		frame.patch_margin_bottom = 12
	if not button.has_meta(&"fantasy_slot_press_connected"):
		button.set_meta(&"fantasy_slot_press_connected", true)
		button.button_down.connect(_set_inventory_slot_pressed.bind(button, true))
		button.button_up.connect(_set_inventory_slot_pressed.bind(button, false))


static func decorate_inventory_cell(cell: Control, panel_color: Color) -> void:
	_decorate_control(cell, FRAME_NODE_NAME, panel_color, 0.0, 12, INVENTORY_SLOT_TEXTURE, true)


static func _set_inventory_slot_pressed(button: Button, pressed: bool) -> void:
	var frame := button.get_node_or_null(NodePath(str(BUTTON_FRAME_NODE_NAME))) as NinePatchRect
	if frame != null:
		frame.texture = INVENTORY_SLOT_PRESSED_TEXTURE if pressed else INVENTORY_SLOT_TEXTURE


static func _apply_button_hover(button: Button, hovered: bool) -> void:
	var frame := button.get_node_or_null(NodePath(str(BUTTON_FRAME_NODE_NAME))) as NinePatchRect
	var underlay := button.get_node_or_null(NodePath(str(BUTTON_UNDERLAY_NODE_NAME))) as ColorRect
	var panel_color: Color = button.get_meta(&"fantasy_panel_color", Color.WHITE)
	var border_color: Color = button.get_meta(&"fantasy_border_color", Color.WHITE)
	if frame != null:
		frame.modulate = panel_color.lightened(0.1) if hovered else panel_color
	if underlay != null:
		underlay.color = border_color.lightened(0.16) if hovered else border_color


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
	elif root is Button:
		decorate_button(root as Button, button_color, border_color)
	for child in root.get_children():
		if child.name in [FRAME_NODE_NAME, BUTTON_FRAME_NODE_NAME, BUTTON_UNDERLAY_NODE_NAME, PANEL_UNDERLAY_NODE_NAME]:
			continue
		decorate_panels(child, border_color, button_color)
