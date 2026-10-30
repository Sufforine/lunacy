extends RefCounted

const MAIN_PANEL_SIZE := Vector2(708, 428)
const INVENTORY_ONLY_PANEL_SIZE := Vector2(428, 428)
const CHEST_PANEL_SIZE := Vector2(438, 174)
const PANEL_GAP := 12.0
const SCREEN_MARGIN := 24.0
const SLOT_SIZE := Vector2(64, 64)
const INVENTORY_DEFAULT_POSITION := Vector2(292, 12)
const INVENTORY_CHEST_POSITION := Vector2(12, 12)
const INVENTORY_SECTION_SIZE := Vector2(404, 404)

var _host
var _main_panel: Panel
var _tabs
var _inventory: InventoryComponent
var _chest: Node
var _panel: Panel
var _icons: Array[TextureRect] = []


func build(host, main_panel: Panel, tabs) -> void:
	_host = host
	_main_panel = main_panel
	_tabs = tabs
	_panel = Panel.new()
	_panel.name = "ChestPanel"
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -CHEST_PANEL_SIZE.x * 0.5
	_panel.offset_top = -MAIN_PANEL_SIZE.y * 0.5 - PANEL_GAP - CHEST_PANEL_SIZE.y
	_panel.offset_right = CHEST_PANEL_SIZE.x * 0.5
	_panel.offset_bottom = -MAIN_PANEL_SIZE.y * 0.5 - PANEL_GAP
	_panel.visible = false
	_host.add_child(_panel)
	var title := Label.new()
	title.text = "Сундук"
	title.position = Vector2(8, 6)
	title.size = Vector2(422, 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	_panel.add_child(title)
	var grid_center := CenterContainer.new()
	grid_center.position = Vector2(12, 32)
	grid_center.size = Vector2(414, 134)
	_panel.add_child(grid_center)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid_center.add_child(grid)
	for index in 12:
		var button := Button.new()
		button.custom_minimum_size = SLOT_SIZE
		button.tooltip_text = "Ctrl + ЛКМ — забрать"
		grid.add_child(button)
		var icon := TextureRect.new()
		_host._setup_icon(icon)
		button.add_child(icon)
		button.gui_input.connect(func(event: InputEvent): _on_slot_input(event, index))
		_icons.append(icon)
	apply_theme()


func bind(inventory: InventoryComponent) -> void:
	_inventory = inventory


func open(chest: Node) -> void:
	if chest == null:
		return
	if _chest == chest and _main_panel.visible and _panel.visible:
		_host._close_main_panel()
		return
	disconnect_chest()
	_chest = chest
	if _chest.has_signal("contents_changed"):
		_chest.connect("contents_changed", refresh)
	_host._mouse_mode_before_open = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_main_panel.visible = true
	_tabs.show_inventory()
	_tabs.hide_for_chest()
	_set_chest_inventory_layout()
	_panel.visible = true
	_host._apply_ui_scale()
	refresh()
	_host._refresh_inventory()


func is_open(chest: Node = null) -> bool:
	if chest == null:
		return _chest != null and _main_panel.visible and _panel.visible
	return _chest == chest and _main_panel.visible and _panel.visible


func has_chest() -> bool:
	return _chest != null


func transfer_from_player(slot_index: int) -> void:
	if _chest != null and _chest.has_method("request_transfer_from_player"):
		_chest.call("request_transfer_from_player", slot_index, _inventory)


func close() -> void:
	if _chest != null:
		_host._close_main_panel()


func leave_layout() -> void:
	var was_chest_layout := _panel.visible
	disconnect_chest()
	_panel.visible = false
	if was_chest_layout:
		_restore_inventory_layout()
	_host._apply_ui_scale()


func apply_theme() -> void:
	if _panel == null:
		return
	var palette := GameSettings.get_inventory_theme_palette()
	var style := StyleBoxFlat.new()
	style.bg_color = palette.background
	style.border_color = palette.border
	style.set_border_width_all(4)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 12
	_panel.add_theme_stylebox_override("panel", style)
	_apply_label_color(_panel, palette.text)


func apply_layout(scale_factor: float, viewport_size: Vector2) -> void:
	if _panel == null:
		return
	if not _panel.visible:
		_set_centered_main_panel(scale_factor)
		_panel.scale = Vector2.ONE * scale_factor
		return

	var combined_height := CHEST_PANEL_SIZE.y + PANEL_GAP + INVENTORY_ONLY_PANEL_SIZE.y
	var layout_width := maxf(INVENTORY_ONLY_PANEL_SIZE.x, CHEST_PANEL_SIZE.x)
	var width_scale := (viewport_size.x - SCREEN_MARGIN) / layout_width
	var height_scale := (viewport_size.y - SCREEN_MARGIN) / combined_height
	var fitted_scale := minf(scale_factor, minf(width_scale, height_scale))
	var layout_top := -combined_height * 0.5
	var main_top := layout_top + CHEST_PANEL_SIZE.y + PANEL_GAP

	_main_panel.offset_left = -INVENTORY_ONLY_PANEL_SIZE.x * 0.5
	_main_panel.offset_top = main_top
	_main_panel.offset_right = INVENTORY_ONLY_PANEL_SIZE.x * 0.5
	_main_panel.offset_bottom = main_top + INVENTORY_ONLY_PANEL_SIZE.y
	_main_panel.pivot_offset = Vector2(INVENTORY_ONLY_PANEL_SIZE.x * 0.5, -main_top)
	_main_panel.scale = Vector2.ONE * fitted_scale

	_panel.offset_left = -CHEST_PANEL_SIZE.x * 0.5
	_panel.offset_top = layout_top
	_panel.offset_right = CHEST_PANEL_SIZE.x * 0.5
	_panel.offset_bottom = layout_top + CHEST_PANEL_SIZE.y
	_panel.pivot_offset = Vector2(CHEST_PANEL_SIZE.x * 0.5, -layout_top)
	_panel.scale = Vector2.ONE * fitted_scale


func _set_centered_main_panel(scale_factor: float) -> void:
	_main_panel.offset_left = -MAIN_PANEL_SIZE.x * 0.5
	_main_panel.offset_top = -MAIN_PANEL_SIZE.y * 0.5
	_main_panel.offset_right = MAIN_PANEL_SIZE.x * 0.5
	_main_panel.offset_bottom = MAIN_PANEL_SIZE.y * 0.5
	_main_panel.pivot_offset = MAIN_PANEL_SIZE * 0.5
	_main_panel.scale = Vector2.ONE * scale_factor


func _set_chest_inventory_layout() -> void:
	var top_row := _main_panel.get_node_or_null("TopRow") as Control
	var inventory_section := _main_panel.get_node_or_null("InventorySection") as Control
	if top_row != null:
		top_row.visible = false
	if inventory_section != null:
		inventory_section.position = INVENTORY_CHEST_POSITION
		inventory_section.size = INVENTORY_SECTION_SIZE


func _restore_inventory_layout() -> void:
	var top_row := _main_panel.get_node_or_null("TopRow") as Control
	var inventory_section := _main_panel.get_node_or_null("InventorySection") as Control
	if top_row != null:
		top_row.visible = true
	if inventory_section != null:
		inventory_section.position = INVENTORY_DEFAULT_POSITION
		inventory_section.size = INVENTORY_SECTION_SIZE
	_tabs.leave_chest_mode()


func contains_global_point(point: Vector2) -> bool:
	return _panel != null and _panel.visible and _panel.get_global_rect().has_point(point)


func disconnect_chest() -> void:
	if _chest == null:
		return
	if _chest.has_signal("contents_changed") and _chest.is_connected("contents_changed", refresh):
		_chest.disconnect("contents_changed", refresh)
	if _chest.has_method("set_open_visual"):
		_chest.call("set_open_visual", false)
	_chest = null


func _apply_label_color(node: Node, color: Color) -> void:
	if node is Label:
		(node as Label).add_theme_color_override("font_color", color)
	for child in node.get_children():
		_apply_label_color(child, color)


func refresh() -> void:
	for index in _icons.size():
		var item: ItemData = null
		if _chest != null and _chest.has_method("get_item"):
			item = _chest.call("get_item", index) as ItemData
		_host._set_icon(_icons[index], item.icon if item != null and item.icon != null else null)


func _on_slot_input(event: InputEvent, slot_index: int) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.ctrl_pressed:
			if _chest != null and _chest.has_method("request_transfer_to_player"):
				_chest.call("request_transfer_to_player", slot_index, _inventory)
			_host.accept_event()
