# inventory_ui.gd
# Структура сцены:
#   InventoryUI (Control)
#   ├── MainPanel (Panel)                    ← открывается по I
#   │   ├── EquipmentSection (VBoxContainer)
#   │   │   ├── Row1 (HBoxContainer): Weapon, Helmet
#   │   │   ├── Row2 (HBoxContainer): Chestplate, Leggings
#   │   │   └── Row3 (HBoxContainer): Cloak, Trinket1, Scroll
#   │   └── InventorySection (VBoxContainer)
#   │       └── InvGrid (GridContainer)      ← 36 кнопок 9x4
#   ├── QuickBar (HBoxContainer)             ← всегда виден
#   │   ├── QSlot_1 (Button → Icon)
#   │   ├── QSlot_2 (Button → Icon)
#   │   └── QSlot_3 (Button → Icon)
extends Control
class_name InventoryUI

# ── ноды ────────────────────────────────────────────────
@onready var main_panel: Panel          = $MainPanel
@onready var inv_grid: GridContainer    = $MainPanel/InventorySection/InvGrid

# Экипировка
@onready var slot_weapon:     Button = $MainPanel/TopRow/EquipmentSection/Row1/SlotWeapon
@onready var slot_helmet:     Button = $MainPanel/TopRow/EquipmentSection/Row1/SlotHelmet
@onready var slot_chestplate: Button = $MainPanel/TopRow/EquipmentSection/Row1/SlotChestplate
@onready var slot_leggings:   Button = $MainPanel/TopRow/EquipmentSection/Row1/SlotLeggings
@onready var slot_cloak:      Button = $MainPanel/TopRow/EquipmentSection/Row2/SlotCloak
@onready var slot_trinket1:   Button = $MainPanel/TopRow/EquipmentSection/Row2/SlotTrinket1
@onready var slot_scroll:     Button = $MainPanel/TopRow/EquipmentSection/Row2/SlotScroll

# Быстрый доступ
@onready var qslot_1: Button = $MainPanel/TopRow/QuickSlotsSection/QRow/QSlot_1
@onready var qslot_2: Button = $MainPanel/TopRow/QuickSlotsSection/QRow/QSlot_2
@onready var qslot_3: Button = $MainPanel/TopRow/QuickSlotsSection/QRow/QSlot_3

# ── компоненты ───────────────────────────────────────────
var _inventory:  InventoryComponent = null
var _equipment:  EquipmentComponent = null

# ── слоты инвентаря ─────────────────────────────────────
var _inv_buttons: Array[Button]      = []
var _inv_icons:   Array[TextureRect] = []

# ── слоты экипировки ─────────────────────────────────────
# Порядок совпадает с _eq_enum(idx)
var _eq_buttons: Array[Button]       = []
var _eq_icons:   Array[TextureRect]  = []

# ── quickslots ───────────────────────────────────────────
var _qs_buttons: Array[Button]       = []
var _qs_icons:   Array[TextureRect]  = []

# ── drag ─────────────────────────────────────────────────
enum DragSource { NONE, INVENTORY, EQUIPMENT, QUICKSLOT }
var _drag_source:   DragSource = DragSource.NONE
var _drag_from_idx: int        = -1
var _drag_preview:  Control    = null


# ════════════════════════════════════════════════════════
# READY
# ════════════════════════════════════════════════════════
func _ready() -> void:
	main_panel.visible = false
	_collect_inventory_slots()
	_collect_equipment_slots()
	_collect_quickslots()


# ════════════════════════════════════════════════════════
# BIND
# ════════════════════════════════════════════════════════
func bind(inventory: InventoryComponent, equipment: EquipmentComponent) -> void:

	if _inventory != null and _inventory.changed.is_connected(_refresh_inventory):
		_inventory.changed.disconnect(_refresh_inventory)
	_inventory = inventory
	if _inventory != null:
		_inventory.changed.connect(_refresh_inventory)

	if _equipment != null and _equipment.changed.is_connected(_refresh_equipment):
		_equipment.changed.disconnect(_refresh_equipment)
	_equipment = equipment
	if _equipment != null:
		_equipment.changed.connect(_refresh_equipment)

	_refresh_inventory()
	_refresh_equipment()
	_refresh_quickslots()


# ════════════════════════════════════════════════════════
# INPUT
# ════════════════════════════════════════════════════════
func _input(event: InputEvent) -> void:

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_I:
			main_panel.visible = not main_panel.visible

	if _drag_preview != null and event is InputEventMouseMotion:
		_drag_preview.global_position = get_global_mouse_position() - _drag_preview.size * 0.5

	if _drag_source != DragSource.NONE and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			var inv_idx := _inv_slot_at_mouse()
			var eq_idx  := _eq_slot_at_mouse()
			var qs_idx  := _qs_slot_at_mouse()
			if qs_idx >= 0:
				_drop_on_quickslot(qs_idx)
			elif inv_idx >= 0:
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

	for child in inv_grid.get_children():
		if not child is Button:
			continue
		var btn := child as Button
		var idx  := _inv_buttons.size()
		_inv_buttons.append(btn)
		var tex := _find_texture_rect(btn)
		_inv_icons.append(tex)
		if tex:
			_setup_icon(tex)
		btn.gui_input.connect(func(e): _on_inv_gui_input(e, idx))


func _collect_equipment_slots() -> void:

	var btns: Array = [
		slot_weapon, slot_helmet, slot_chestplate,
		slot_leggings, slot_cloak, slot_trinket1, slot_scroll
	]
	var tips := ["Оружие", "Шлем", "Доспех", "Поножи", "Плащ", "Тринкет", "Свиток"]
	_eq_buttons.clear()
	_eq_icons.clear()

	for i in btns.size():
		var btn: Button = btns[i]
		if btn == null:
			push_error("InventoryUI: слот экипировки %d не найден" % i)
			_eq_buttons.append(null)
			_eq_icons.append(null)
			continue
		_eq_buttons.append(btn)
		var tex := _find_texture_rect(btn)
		_eq_icons.append(tex)
		if tex:
			_setup_icon(tex)
		btn.tooltip_text = tips[i]
		btn.gui_input.connect(func(e): _on_eq_gui_input(e, i))


func _collect_quickslots() -> void:

	_qs_buttons = [qslot_1, qslot_2, qslot_3]
	_qs_icons.clear()

	for i in _qs_buttons.size():
		var btn: Button = _qs_buttons[i]
		var tex := _find_texture_rect(btn)
		_qs_icons.append(tex)
		if tex:
			_setup_icon(tex)
		btn.tooltip_text = "Alt+%d" % (i + 1)
		btn.gui_input.connect(func(e): _on_qs_gui_input(e, i))


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
		_equipment.weapon, _equipment.helmet, _equipment.chestplate,
		_equipment.leggings, _equipment.cloak, _equipment.trinket_1, _equipment.scroll
	]
	for i in items.size():
		var eq: ItemData = items[i]
		_set_icon(_eq_icons[i], eq.icon if eq and eq.icon else null)


func _refresh_quickslots() -> void:
	if _inventory == null:
		return
	for i in _inventory.quickslots.size():
		var item: ItemData = _inventory.quickslots[i]
		_set_icon(_qs_icons[i], item.icon if item and item.icon else null)


# ════════════════════════════════════════════════════════
# GUI INPUT
# ════════════════════════════════════════════════════════
func _on_inv_gui_input(event: InputEvent, idx: int) -> void:
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		if _inventory and not _inventory.is_empty(idx):
			_drag_source = DragSource.INVENTORY
			_drag_from_idx = idx
			_create_preview(_inventory.get_item(idx).icon)
			if _inv_icons[idx]:
				_inv_icons[idx].modulate = Color(0.35, 0.35, 0.35, 0.5)
	else:
		if _drag_source != DragSource.NONE:
			_drop_on_inventory(idx)


func _on_eq_gui_input(event: InputEvent, idx: int) -> void:
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		if _equipment and _eq_slot_item(idx) != null:
			_drag_source = DragSource.EQUIPMENT
			_drag_from_idx = idx
			_create_preview(_eq_slot_item(idx).icon)
			if _eq_icons[idx]:
				_eq_icons[idx].modulate = Color(0.35, 0.35, 0.35, 0.5)
	else:
		if _drag_source != DragSource.NONE:
			_drop_on_equipment(idx)


func _on_qs_gui_input(event: InputEvent, idx: int) -> void:
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		if _inventory and _inventory.quickslots[idx] != null:
			_drag_source = DragSource.QUICKSLOT
			_drag_from_idx = idx
			_create_preview(_inventory.quickslots[idx].icon)
			if _qs_icons[idx]:
				_qs_icons[idx].modulate = Color(0.35, 0.35, 0.35, 0.5)
	else:
		if _drag_source != DragSource.NONE:
			_drop_on_quickslot(idx)


# ════════════════════════════════════════════════════════
# DROP
# ════════════════════════════════════════════════════════
func _drop_on_inventory(to_idx: int) -> void:

	_destroy_preview()
	_restore_drag_icon()
	var from := _drag_from_idx
	var src  := _drag_source
	_drag_source   = DragSource.NONE
	_drag_from_idx = -1

	match src:
		DragSource.INVENTORY:
			if from != to_idx and _inventory:
				_inventory.move_item(from, to_idx)
			elif from == to_idx:
				_use_inventory_item(from)

		DragSource.EQUIPMENT:
			var item := _eq_slot_item(from)
			if item == null or _inventory == null:
				return
			var displaced: ItemData = _inventory.get_item(to_idx)
			_inventory.slots[to_idx] = item
			_equipment.unequip(_eq_enum(from))
			if displaced != null:
				_inventory.add_item(displaced)
			_inventory.changed.emit()

		DragSource.QUICKSLOT:
			if _inventory:
				_inventory.move_to_quickslot(to_idx, from)  # swap inv↔qs


func _drop_on_equipment(to_idx: int) -> void:

	_destroy_preview()
	_restore_drag_icon()
	var from := _drag_from_idx
	var src  := _drag_source
	_drag_source   = DragSource.NONE
	_drag_from_idx = -1

	if src == DragSource.INVENTORY:
		var item := _inventory.get_item(from)
		if item == null or not item.is_equipment():
			return
		if item.slot != _eq_enum(to_idx):
			push_warning("InventoryUI: '%s' не подходит для этого слота" % item.id)
			return
		var current := _eq_slot_item(to_idx)
		_inventory.slots[from] = current
		_equipment.equip(item)
		_inventory.changed.emit()


func _drop_on_quickslot(to_idx: int) -> void:

	_destroy_preview()
	_restore_drag_icon()
	var from := _drag_from_idx
	var src  := _drag_source
	_drag_source   = DragSource.NONE
	_drag_from_idx = -1

	match src:
		DragSource.INVENTORY:
			if _inventory:
				_inventory.move_to_quickslot(from, to_idx)
		DragSource.QUICKSLOT:
			# swap между quickslots
			if _inventory and from != to_idx:
				var tmp: ItemData = _inventory.quickslots[to_idx]
				_inventory.quickslots[to_idx] = _inventory.quickslots[from]
				_inventory.quickslots[from] = tmp
				_inventory.changed.emit()


# ════════════════════════════════════════════════════════
# CANCEL / RESTORE
# ════════════════════════════════════════════════════════
func _cancel_drag() -> void:
	_destroy_preview()
	_restore_drag_icon()
	_drag_source   = DragSource.NONE
	_drag_from_idx = -1


func _restore_drag_icon() -> void:
	match _drag_source:
		DragSource.INVENTORY:
			if _drag_from_idx >= 0 and _drag_from_idx < _inv_icons.size():
				if _inv_icons[_drag_from_idx]:
					_inv_icons[_drag_from_idx].modulate = Color.WHITE
		DragSource.EQUIPMENT:
			if _drag_from_idx >= 0 and _drag_from_idx < _eq_icons.size():
				if _eq_icons[_drag_from_idx]:
					_eq_icons[_drag_from_idx].modulate = Color.WHITE
		DragSource.QUICKSLOT:
			if _drag_from_idx >= 0 and _drag_from_idx < _qs_icons.size():
				if _qs_icons[_drag_from_idx]:
					_qs_icons[_drag_from_idx].modulate = Color.WHITE


# ════════════════════════════════════════════════════════
# USE
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
		1: return _equipment.helmet
		2: return _equipment.chestplate
		3: return _equipment.leggings
		4: return _equipment.cloak
		5: return _equipment.trinket_1
		6: return _equipment.scroll
	return null


func _eq_enum(idx: int) -> ItemData.Slot:
	match idx:
		0: return ItemData.Slot.WEAPON
		1: return ItemData.Slot.HELMET
		2: return ItemData.Slot.CHESTPLATE
		3: return ItemData.Slot.LEGGINGS
		4: return ItemData.Slot.CLOAK
		5: return ItemData.Slot.TRINKET_1
		6: return ItemData.Slot.SCROLL
	return ItemData.Slot.NONE


func _inv_slot_at_mouse() -> int:
	if not main_panel.visible:
		return -1
	var mouse := get_global_mouse_position()
	for i in _inv_buttons.size():
		if _inv_buttons[i].get_global_rect().has_point(mouse):
			return i
	return -1


func _eq_slot_at_mouse() -> int:
	if not main_panel.visible:
		return -1
	var mouse := get_global_mouse_position()
	for i in _eq_buttons.size():
		if _eq_buttons[i] and _eq_buttons[i].get_global_rect().has_point(mouse):
			return i
	return -1


func _qs_slot_at_mouse() -> int:
	var mouse := get_global_mouse_position()
	for i in _qs_buttons.size():
		if _qs_buttons[i] and _qs_buttons[i].get_global_rect().has_point(mouse):
			return i
	return -1


func _create_preview(icon: Texture2D) -> void:
	_drag_preview = Control.new()
	_drag_preview.size = Vector2(44, 44)
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
	push_error("InventoryUI: кнопка '%s' не имеет TextureRect" % btn.name)
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
