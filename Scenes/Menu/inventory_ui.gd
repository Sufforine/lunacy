# inventory_ui.gd
# Мини-инвентарь (6 слотов) — всегда виден на экране.
# По клавише I открывается/закрывается EquipmentPanel рядом.
#
# Структура сцены:
#   InventoryUI (Control)           ← этот скрипт
#   ├── Grid (GridContainer)        ← 6 слотов инвентаря
#   │   ├── Slot_1 (Button) → Icon (TextureRect)
#   │   └── ... Slot_6
#   └── EquipmentPanel (Panel)      ← скрыт по умолчанию
#       ├── Title (Label)
#       └── SlotsContainer (VBoxContainer)
#           ├── WeaponRow   (HBoxContainer) → Label + SlotWeapon   (Button → Icon)
#           ├── ArmorRow    (HBoxContainer) → Label + SlotArmor    (Button → Icon)
#           ├── Trinket1Row (HBoxContainer) → Label + SlotTrinket1 (Button → Icon)
#           └── Trinket2Row (HBoxContainer) → Label + SlotTrinket2 (Button → Icon)

extends Control
class_name InventoryUI

# ── ноды ────────────────────────────────────────────────
@onready var grid: GridContainer        = $Grid
@onready var equipment_panel: Panel     = $EquipmentPanel
@onready var slot_weapon: Button        = $EquipmentPanel/SlotsContainer/WeaponRow/SlotWeapon
@onready var slot_armor: Button         = $EquipmentPanel/SlotsContainer/ArmorRow/SlotArmor
@onready var slot_trinket1: Button      = $EquipmentPanel/SlotsContainer/Trinket1Row/SlotTrinket1
@onready var slot_trinket2: Button      = $EquipmentPanel/SlotsContainer/Trinket2Row/SlotTrinket2

# ── компоненты игрока ───────────────────────────────────
var _inventory:  InventoryComponent  = null
var _equipment:  EquipmentComponent  = null

# ── слоты инвентаря ─────────────────────────────────────
var _inv_buttons: Array[Button]      = []
var _inv_icons:   Array[TextureRect] = []

# ── слоты экипировки (порядок = ItemData.Slot enum) ─
var _eq_buttons:  Array[Button]      = []   # [WEAPON, ARMOR, TRINKET_1, TRINKET_2]
var _eq_icons:    Array[TextureRect] = []

# ── drag state ───────────────────────────────────────────
enum DragSource { NONE, INVENTORY, EQUIPMENT }
var _drag_source:    DragSource = DragSource.NONE
var _drag_from_idx:  int        = -1   # индекс в массиве источника
var _drag_preview:   Control    = null


# ════════════════════════════════════════════════════════
# READY
# ════════════════════════════════════════════════════════
func _ready() -> void:
	equipment_panel.visible = false
	_collect_inventory_slots()
	_collect_equipment_slots()


# ════════════════════════════════════════════════════════
# BIND — вызывается из player.gd
# ════════════════════════════════════════════════════════
func bind(inventory: InventoryComponent, equipment: EquipmentComponent) -> void:

	# инвентарь
	if _inventory != null and _inventory.changed.is_connected(_refresh_inventory):
		_inventory.changed.disconnect(_refresh_inventory)
	_inventory = inventory
	if _inventory != null:
		_inventory.changed.connect(_refresh_inventory)

	# экипировка
	if _equipment != null and _equipment.changed.is_connected(_refresh_equipment):
		_equipment.changed.disconnect(_refresh_equipment)
	_equipment = equipment
	if _equipment != null:
		_equipment.changed.connect(_refresh_equipment)

	_refresh_inventory()
	_refresh_equipment()


# ════════════════════════════════════════════════════════
# КЛАВИША I
# ════════════════════════════════════════════════════════
func _input(event: InputEvent) -> void:

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_I:
			equipment_panel.visible = not equipment_panel.visible

	# двигать призрак за курсором
	if _drag_preview != null and event is InputEventMouseMotion:
		_drag_preview.global_position = get_global_mouse_position() - _drag_preview.size * 0.5

	# отпустили мышь вне любого слота
	if _drag_source != DragSource.NONE and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			var inv_idx := _inv_slot_at_mouse()
			var eq_idx  := _eq_slot_at_mouse()
			if inv_idx >= 0:
				_drop_on_inventory(inv_idx)
			elif eq_idx >= 0:
				_drop_on_equipment(eq_idx)
			else:
				_cancel_drag()


# ════════════════════════════════════════════════════════
# COLLECT SLOTS
# ════════════════════════════════════════════════════════
func _collect_inventory_slots() -> void:

	_inv_buttons.clear()
	_inv_icons.clear()

	if grid == null:
		push_error("InventoryUI: нода Grid не найдена")
		return

	for child in grid.get_children():
		if not child is Button:
			continue
		var btn := child as Button
		var idx  := _inv_buttons.size()
		_inv_buttons.append(btn)

		var tex := _find_texture_rect(btn)
		_inv_icons.append(tex)
		if tex != null:
			_setup_icon(tex)

		btn.gui_input.connect(func(e: InputEvent): _on_inv_gui_input(e, idx))


func _collect_equipment_slots() -> void:

	_eq_buttons = [slot_weapon, slot_armor, slot_trinket1, slot_trinket2]
	_eq_icons.clear()

	var labels := ["Оружие", "Броня", "Тринкет 1", "Тринкет 2"]

	for i in _eq_buttons.size():
		var btn := _eq_buttons[i]
		if btn == null:
			push_error("InventoryUI: слот экипировки %d не найден" % i)
			_eq_icons.append(null)
			continue

		var tex := _find_texture_rect(btn)
		_eq_icons.append(tex)
		if tex != null:
			_setup_icon(tex)

		btn.tooltip_text = labels[i]
		btn.gui_input.connect(func(e: InputEvent): _on_eq_gui_input(e, i))


# ════════════════════════════════════════════════════════
# REFRESH
# ════════════════════════════════════════════════════════
func _refresh_inventory() -> void:
	for i in _inv_buttons.size():
		var item: ItemData = _inventory.get_item(i) if _inventory else null
		_set_icon(_inv_icons[i], item.icon if item and item.icon else null)


func _refresh_equipment() -> void:
	if _equipment == null:
		return
	var items := [
		_equipment.weapon,
		_equipment.armor,
		_equipment.trinket_1,
		_equipment.trinket_2,
	]
	for i in items.size():
		var eq: ItemData = items[i]
		_set_icon(_eq_icons[i], eq.icon if eq and eq.icon else null)


# ════════════════════════════════════════════════════════
# GUI INPUT — инвентарь
# ════════════════════════════════════════════════════════
func _on_inv_gui_input(event: InputEvent, idx: int) -> void:

	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return

	if mb.pressed:
		if _inventory and not _inventory.is_empty(idx):
			_start_drag_inventory(idx)
	else:
		if _drag_source != DragSource.NONE:
			_drop_on_inventory(idx)


# ════════════════════════════════════════════════════════
# GUI INPUT — экипировка
# ════════════════════════════════════════════════════════
func _on_eq_gui_input(event: InputEvent, idx: int) -> void:

	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return

	if mb.pressed:
		# начать drag с слота экипировки (снять предмет)
		if _equipment and _eq_slot_item(idx) != null:
			_start_drag_equipment(idx)
	else:
		if _drag_source != DragSource.NONE:
			_drop_on_equipment(idx)


# ════════════════════════════════════════════════════════
# DRAG — начало
# ════════════════════════════════════════════════════════
func _start_drag_inventory(idx: int) -> void:

	var item := _inventory.get_item(idx)
	if item == null:
		return

	_drag_source   = DragSource.INVENTORY
	_drag_from_idx = idx
	_create_preview(item.icon)

	if _inv_icons[idx]:
		_inv_icons[idx].modulate = Color(0.35, 0.35, 0.35, 0.5)


func _start_drag_equipment(idx: int) -> void:

	var item := _eq_slot_item(idx)
	if item == null:
		return

	_drag_source   = DragSource.EQUIPMENT
	_drag_from_idx = idx
	_create_preview(item.icon)

	if _eq_icons[idx]:
		_eq_icons[idx].modulate = Color(0.35, 0.35, 0.35, 0.5)


# ════════════════════════════════════════════════════════
# DROP — на слот инвентаря
# ════════════════════════════════════════════════════════
func _drop_on_inventory(to_idx: int) -> void:

	_destroy_preview()
	_restore_drag_icon()

	var from := _drag_from_idx
	var src   := _drag_source
	_drag_source   = DragSource.NONE
	_drag_from_idx = -1

	if src == DragSource.INVENTORY:
		# перекладываем внутри инвентаря
		if from != to_idx and _inventory:
			_inventory.move_item(from, to_idx)
		elif from == to_idx:
			_use_inventory_item(from)

	elif src == DragSource.EQUIPMENT:
		# снимаем экипировку → кладём в инвентарь
		var item := _eq_slot_item(from)
		if item == null:
			return
		if _inventory and _inventory.add_item_data_as_equipment(item, to_idx):
			_equipment.unequip(_eq_enum(from))


# ════════════════════════════════════════════════════════
# DROP — на слот экипировки
# ════════════════════════════════════════════════════════
func _drop_on_equipment(to_idx: int) -> void:

	_destroy_preview()
	_restore_drag_icon()

	var from := _drag_from_idx
	var src   := _drag_source
	_drag_source   = DragSource.NONE
	_drag_from_idx = -1

	if src == DragSource.INVENTORY:
		var item := _inventory.get_item(from)
		if item == null:
			return

		# Проверяем что предмет является снаряжением
		if not item.is_equipment():
			push_warning("InventoryUI: '%s' нельзя надеть — не снаряжение" % item.id)
			return

		# Проверяем что слот совпадает
		if item.slot != _eq_enum(to_idx):
			push_warning("InventoryUI: '%s' не подходит для этого слота" % item.id)
			return

		# Swap: текущий предмет из слота экипировки → в инвентарь
		var current := _eq_slot_item(to_idx)
		_inventory.slots[from] = current  # null если слот был пуст

		_equipment.equip(item)
		_inventory.changed.emit()

	elif src == DragSource.EQUIPMENT:
		# перекладываем между слотами экипировки — не имеет смысла, игнорируем
		pass


# ════════════════════════════════════════════════════════
# CANCEL
# ════════════════════════════════════════════════════════
func _cancel_drag() -> void:
	_destroy_preview()
	_restore_drag_icon()
	_drag_source   = DragSource.NONE
	_drag_from_idx = -1


func _restore_drag_icon() -> void:
	if _drag_source == DragSource.INVENTORY:
		if _drag_from_idx >= 0 and _drag_from_idx < _inv_icons.size():
			if _inv_icons[_drag_from_idx]:
				_inv_icons[_drag_from_idx].modulate = Color.WHITE
	elif _drag_source == DragSource.EQUIPMENT:
		if _drag_from_idx >= 0 and _drag_from_idx < _eq_icons.size():
			if _eq_icons[_drag_from_idx]:
				_eq_icons[_drag_from_idx].modulate = Color.WHITE


# ════════════════════════════════════════════════════════
# USE ITEM (клик без движения)
# ════════════════════════════════════════════════════════
func _use_inventory_item(slot_index: int) -> void:

	if _inventory == null or _inventory.is_empty(slot_index):
		return

	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		player = get_parent().get_parent()

	_inventory.use_item(slot_index, player)


# ════════════════════════════════════════════════════════
# HELPERS
# ════════════════════════════════════════════════════════
func _eq_slot_item(idx: int) -> ItemData:
	if _equipment == null:
		return null
	match idx:
		0: return _equipment.weapon
		1: return _equipment.armor
		2: return _equipment.trinket_1
		3: return _equipment.trinket_2
	return null


func _eq_enum(idx: int) -> ItemData.Slot:
	match idx:
		0: return ItemData.Slot.WEAPON
		1: return ItemData.Slot.ARMOR
		2: return ItemData.Slot.TRINKET_1
		3: return ItemData.Slot.TRINKET_2
	return ItemData.Slot.WEAPON


func _inv_slot_at_mouse() -> int:
	var mouse := get_global_mouse_position()
	for i in _inv_buttons.size():
		if _inv_buttons[i].get_global_rect().has_point(mouse):
			return i
	return -1


func _eq_slot_at_mouse() -> int:
	if not equipment_panel.visible:
		return -1
	var mouse := get_global_mouse_position()
	for i in _eq_buttons.size():
		if _eq_buttons[i] and _eq_buttons[i].get_global_rect().has_point(mouse):
			return i
	return -1


func _create_preview(icon: Texture2D) -> void:
	_drag_preview = Control.new()
	_drag_preview.size = Vector2(48, 48)
	_drag_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_preview.z_index = 200

	var tex := TextureRect.new()
	tex.texture = icon
	tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.modulate = Color(1, 1, 1, 0.8)
	_drag_preview.add_child(tex)

	add_child(_drag_preview)
	_drag_preview.global_position = get_global_mouse_position() - _drag_preview.size * 0.5


func _destroy_preview() -> void:
	if _drag_preview != null:
		_drag_preview.queue_free()
		_drag_preview = null


func _find_texture_rect(btn: Button) -> TextureRect:
	for c in btn.get_children():
		if c is TextureRect:
			return c as TextureRect
	push_error("InventoryUI: кнопка '%s' не имеет дочернего TextureRect" % btn.name)
	return null


func _setup_icon(tex: TextureRect) -> void:
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _set_icon(tex: TextureRect, icon: Texture2D) -> void:
	if tex == null:
		return
	tex.texture = icon
	tex.modulate = Color.WHITE
