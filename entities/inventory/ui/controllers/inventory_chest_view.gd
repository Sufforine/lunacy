extends RefCounted

var _host
var _main_panel: Panel
var _tabs
var _inventory: InventoryComponent
var _chest: Node
var _section: Control
var _icons: Array[TextureRect] = []
var _player_inventory_label: Label
var _inventory_default_position := Vector2.ZERO


func build(host, main_panel: Panel, tabs) -> void:
	_host = host
	_main_panel = main_panel
	_tabs = tabs
	_section = Control.new()
	_section.name = "ChestSection"
	_section.position = Vector2(8, 34)
	_section.size = Vector2(752, 166)
	_section.visible = false
	_main_panel.add_child(_section)
	var title := Label.new()
	title.text = "Сундук"
	title.size = Vector2(752, 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	_section.add_child(title)
	var grid_center := CenterContainer.new()
	grid_center.position = Vector2(0, 28)
	grid_center.size = Vector2(752, 124)
	_section.add_child(grid_center)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid_center.add_child(grid)
	for index in 12:
		var button := Button.new()
		button.custom_minimum_size = Vector2(52, 52)
		button.tooltip_text = "Ctrl + ЛКМ — забрать"
		grid.add_child(button)
		var icon := TextureRect.new()
		_host._setup_icon(icon)
		button.add_child(icon)
		button.gui_input.connect(func(event: InputEvent): _on_slot_input(event, index))
		_icons.append(icon)
	_player_inventory_label = Label.new()
	_player_inventory_label.text = "Инвентарь"
	_player_inventory_label.position = Vector2(8, 202)
	_player_inventory_label.size = Vector2(752, 24)
	_player_inventory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_player_inventory_label.add_theme_font_size_override("font_size", 18)
	_player_inventory_label.visible = false
	_main_panel.add_child(_player_inventory_label)
	var inventory_section := _main_panel.get_node_or_null("InventorySection") as Control
	if inventory_section != null:
		_inventory_default_position = inventory_section.position


func bind(inventory: InventoryComponent) -> void:
	_inventory = inventory


func open(chest: Node) -> void:
	if chest == null:
		return
	if _chest == chest and _main_panel.visible:
		_host._close_main_panel()
		return
	disconnect_chest()
	_chest = chest
	if _chest.has_signal("contents_changed"):
		_chest.connect("contents_changed", refresh)
	_host._mouse_mode_before_open = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_main_panel.visible = true
	(_main_panel.get_node("Title") as Label).text = "Хранилище"
	_tabs.hide_for_chest()
	_section.visible = true
	_player_inventory_label.visible = true
	var inventory_section := _main_panel.get_node("InventorySection") as Control
	inventory_section.visible = true
	inventory_section.position = Vector2(_inventory_default_position.x, 230.0)
	refresh()
	_host._refresh_inventory()


func is_open(chest: Node = null) -> bool:
	if chest == null:
		return _chest != null and _main_panel.visible
	return _chest == chest and _main_panel.visible


func has_chest() -> bool:
	return _chest != null


func transfer_from_player(slot_index: int) -> void:
	if _chest != null and _chest.has_method("request_transfer_from_player"):
		_chest.call("request_transfer_from_player", slot_index, _inventory)


func close() -> void:
	if _chest != null:
		_host._close_main_panel()


func leave_layout() -> void:
	disconnect_chest()
	_section.visible = false
	_player_inventory_label.visible = false
	(_main_panel.get_node("Title") as Label).text = "Инвентарь  [I]"
	var inventory_section := _main_panel.get_node("InventorySection") as Control
	inventory_section.position = _inventory_default_position
	_tabs.leave_chest_mode()


func disconnect_chest() -> void:
	if _chest == null:
		return
	if _chest.has_signal("contents_changed") and _chest.is_connected("contents_changed", refresh):
		_chest.disconnect("contents_changed", refresh)
	if _chest.has_method("set_open_visual"):
		_chest.call("set_open_visual", false)
	_chest = null


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
