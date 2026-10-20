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

# Режим мыши до открытия инвентаря — чтобы вернуть при закрытии именно его
# (например MOUSE_MODE_CAPTURED для камеры за плечом во время боя)
var _mouse_mode_before_open: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
@onready var inv_grid: GridContainer    = $MainPanel/InventorySection/InvGrid

# Экипировка
# Экипировка
@onready var slot_weapon:     Button = $MainPanel/TopRow/EquipmentSection/Row2/SlotWeapon
@onready var slot_helmet:     Button = $MainPanel/TopRow/EquipmentSection/Row1/SlotHelmet
@onready var slot_chestplate: Button = $MainPanel/TopRow/EquipmentSection/Row1/SlotChestplate
@onready var slot_leggings:   Button = $MainPanel/TopRow/EquipmentSection/Row1/SlotLeggings
@onready var slot_cloak:      Button = $MainPanel/TopRow/EquipmentSection/Row1/SlotCloak
@onready var slot_trinket1:   Button = $MainPanel/TopRow/EquipmentSection/Row2/SlotTrinket1
@onready var slot_trinket2:     Button = $MainPanel/TopRow/EquipmentSection/Row2/SlotTrinket2

# QuickSlots в MainPanel (для drag & drop)
@onready var qslot_1: Button = $MainPanel/TopRow/QuickSlotsSection/QRow/QSlot_1
@onready var qslot_2: Button = $MainPanel/TopRow/QuickSlotsSection/QRow/QSlot_2
@onready var qslot_3: Button = $MainPanel/TopRow/QuickSlotsSection/QRow/QSlot_3

# QuickSlots HUD (всегда видны, дублируют отображение)
@onready var qhud_1: Button = $QuickBarHUD/QSlot_1
@onready var qhud_2: Button = $QuickBarHUD/QSlot_2
@onready var qhud_3: Button = $QuickBarHUD/QSlot_3

# ── компоненты ───────────────────────────────────────────
var _inventory:  InventoryComponent = null
var _equipment:  EquipmentComponent = null
var _stats:      StatsComponent     = null

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

# ── сундук ──────────────────────────────────────────────
var _open_chest: Node = null
var _chest_section: Control = null
var _chest_grid: GridContainer = null
var _chest_buttons: Array[Button] = []
var _chest_icons: Array[TextureRect] = []
var _player_inventory_label: Label = null
var _inventory_section_default_position := Vector2.ZERO


# ════════════════════════════════════════════════════════
# READY
# ════════════════════════════════════════════════════════
func _ready() -> void:
	# Control по умолчанию — mouse_filter STOP, то есть этот полноэкранный
	# узел перехватывал бы мышь ВСЕГДА (даже когда MainPanel скрыт, из-за
	# постоянно видимого QuickBarHUD), и camera_rig._unhandled_input()
	# никогда не получал бы движение мыши. IGNORE пропускает её дальше;
	# кнопки внутри сами по себе интерактивны и не страдают от этого.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var quick_bar_hud := get_node_or_null("QuickBarHUD")
	if quick_bar_hud is Control:
		(quick_bar_hud as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

	main_panel.visible = false
	_collect_inventory_slots()
	_collect_equipment_slots()
	_collect_quickslots()
	_build_tab_buttons()
	_build_stats_tab()
	_build_chest_section()
	_show_inventory_tab()


# ════════════════════════════════════════════════════════
# BIND
# ════════════════════════════════════════════════════════
func bind(inventory: InventoryComponent, equipment: EquipmentComponent, stats: StatsComponent = null) -> void:

	if _inventory != null and _inventory.changed.is_connected(_refresh_inventory):
		_inventory.changed.disconnect(_refresh_inventory)
	_inventory = inventory
	if _inventory != null:
		_inventory.changed.connect(_refresh_inventory)
		_inventory.changed.connect(_refresh_quickslots)

	if _equipment != null and _equipment.changed.is_connected(_refresh_equipment):
		_equipment.changed.disconnect(_refresh_equipment)
	_equipment = equipment
	if _equipment != null:
		_equipment.changed.connect(_refresh_equipment)
		_equipment.changed.connect(_refresh_stats_tab)

	if _stats != null and _stats.stats_changed.is_connected(_refresh_stats_tab):
		_stats.stats_changed.disconnect(_refresh_stats_tab)
	_stats = stats
	if _stats != null:
		_stats.stats_changed.connect(_refresh_stats_tab)

	_refresh_inventory()
	_refresh_equipment()
	_refresh_quickslots()
	_refresh_stats_tab()


# ════════════════════════════════════════════════════════
# INPUT
# ════════════════════════════════════════════════════════
func _input(event: InputEvent) -> void:
	# В мультиплеере у каждого героя есть свой InventoryUI, но глобальный
	# режим мыши один на всё окно. Управлять им может только локальный герой.
	var owner_player := _find_owner_player()
	if owner_player != null and not owner_player.is_multiplayer_authority():
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("interact") and _open_chest != null:
			_close_main_panel()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_I:
			if main_panel.visible:
				_close_main_panel()
			else:
				_open_main_panel()
		elif event.keycode == KEY_ESCAPE and main_panel.visible:
			_close_main_panel()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_DELETE:
			_drop_hovered_item()

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
			elif main_panel.visible and not main_panel.get_global_rect().has_point(get_global_mouse_position()):
				# Отпустили за пределами окна инвентаря — выбросить в мир
				_drop_dragged_item_in_world()
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
		slot_leggings, slot_cloak, slot_trinket1, slot_trinket2
	]
	var tips := ["Оружие", "Шлем", "Доспех", "Поножи", "Плащ", "Тринкет", "Тринкет 2"]
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


# HUD иконки (дублируют quickslots, только отображение)
var _qs_hud_icons: Array[TextureRect] = []

func _collect_quickslots() -> void:

	_qs_buttons = [qslot_1, qslot_2, qslot_3]
	_qs_icons.clear()
	_qs_hud_icons.clear()

	var hud_btns := [qhud_1, qhud_2, qhud_3]

	for i in _qs_buttons.size():
		# Слоты внутри MainPanel — drag & drop
		var btn: Button = _qs_buttons[i]
		var tex := _find_texture_rect(btn)
		_qs_icons.append(tex)
		if tex:
			_setup_icon(tex)
		btn.tooltip_text = "Клавиша %d" % (i + 1)
		btn.gui_input.connect(func(e): _on_qs_gui_input(e, i))

		# HUD кнопки — только отображение, клик = использовать
		var hud_btn: Button = hud_btns[i]
		var hud_tex := _find_texture_rect(hud_btn)
		_qs_hud_icons.append(hud_tex)
		if hud_tex:
			_setup_icon(hud_tex)
		hud_btn.tooltip_text = "Клавиша %d" % (i + 1)
		hud_btn.pressed.connect(func(): _use_quickslot_item(i))


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
		_equipment.leggings, _equipment.cloak, _equipment.trinket_1, _equipment.trinket_2
	]
	for i in items.size():
		var eq: ItemData = items[i]
		_set_icon(_eq_icons[i], eq.icon if eq and eq.icon else null)


func _refresh_quickslots() -> void:
	if _inventory == null:
		return
	for i in _inventory.quickslots.size():
		var item: ItemData = _inventory.quickslots[i]
		var icon: Texture2D = item.icon if item and item.icon else null
		# Обновить иконку в MainPanel
		if i < _qs_icons.size():
			_set_icon(_qs_icons[i], icon)
		# Обновить иконку в HUD
		if i < _qs_hud_icons.size():
			_set_icon(_qs_hud_icons[i], icon)


# ════════════════════════════════════════════════════════
# GUI INPUT
# ════════════════════════════════════════════════════════
func _on_inv_gui_input(event: InputEvent, idx: int) -> void:
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		if mb.pressed:
			_use_inventory_item(idx)
			accept_event()
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		if _inventory and not _inventory.is_empty(idx):
			# При открытом сундуке Ctrl+клик переносит предмет в него.
			if mb.ctrl_pressed:
				if _open_chest != null and _open_chest.has_method("request_transfer_from_player"):
					_open_chest.call("request_transfer_from_player", idx, _inventory)
				else:
					_quick_equip(idx)
				return
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
			# Ctrl+клик — быстро снять в первый свободный слот инвентаря
			if mb.ctrl_pressed:
				_quick_unequip(idx)
				return
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
		var target_slot := _eq_enum(to_idx)
		if item.slot != target_slot:
			push_warning("InventoryUI: '%s' не подходит для этого слота" % item.id)
			return
		var current := _eq_slot_item(to_idx)
		_inventory.slots[from] = current
		_equipment.equip_to_slot(item, to_idx)
		_inventory.changed.emit()

	elif src == DragSource.EQUIPMENT:
		# Перекладываем между слотами экипировки
		if from == to_idx:
			return
		var item_from := _eq_slot_item(from)
		var item_to   := _eq_slot_item(to_idx)
		# Проверяем совместимость: тринкет → тринкет, остальные строго по типу
		var slot_from := _eq_enum(from)
		var slot_to   := _eq_enum(to_idx)
		if slot_from != slot_to:
			push_warning("InventoryUI: нельзя переложить '%s' в этот слот" % (item_from.id if item_from else "?"))
			return
		# Swap
		_equipment.equip_to_slot(item_from, to_idx)
		_equipment.equip_to_slot(item_to,   from)
		_equipment.changed.emit()


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
	var player := _find_owner_player()
	if player == null:
		return
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
		6: return _equipment.trinket_2
	return null


func _eq_enum(idx: int) -> ItemData.Slot:
	match idx:
		0: return ItemData.Slot.WEAPON
		1: return ItemData.Slot.HELMET
		2: return ItemData.Slot.CHESTPLATE
		3: return ItemData.Slot.LEGGINGS
		4: return ItemData.Slot.CLOAK
		5: return ItemData.Slot.TRINKET
		6: return ItemData.Slot.TRINKET
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
	# Проверяем слоты в MainPanel (если открыт)
	if main_panel.visible:
		for i in _qs_buttons.size():
			if _qs_buttons[i] and _qs_buttons[i].get_global_rect().has_point(mouse):
				return i
	# Проверяем HUD слоты (всегда видны)
	var hud_btns := [qhud_1, qhud_2, qhud_3]
	for i in hud_btns.size():
		if hud_btns[i] and hud_btns[i].get_global_rect().has_point(mouse):
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


func _build_chest_section() -> void:
	_chest_section = Control.new()
	_chest_section.name = "ChestSection"
	_chest_section.position = Vector2(8, 34)
	_chest_section.size = Vector2(624, 166)
	_chest_section.visible = false
	main_panel.add_child(_chest_section)

	var chest_title := Label.new()
	chest_title.text = "Сундук"
	chest_title.position = Vector2(0, 0)
	chest_title.size = Vector2(624, 24)
	chest_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chest_title.add_theme_font_size_override("font_size", 18)
	_chest_section.add_child(chest_title)

	var grid_center := CenterContainer.new()
	grid_center.position = Vector2(0, 28)
	grid_center.size = Vector2(624, 124)
	_chest_section.add_child(grid_center)

	_chest_grid = GridContainer.new()
	_chest_grid.columns = 6
	_chest_grid.add_theme_constant_override("h_separation", 6)
	_chest_grid.add_theme_constant_override("v_separation", 6)
	grid_center.add_child(_chest_grid)

	for index in 12:
		var button := Button.new()
		button.custom_minimum_size = Vector2(52, 52)
		button.tooltip_text = "Ctrl + ЛКМ — забрать"
		_chest_grid.add_child(button)
		var icon := TextureRect.new()
		_setup_icon(icon)
		button.add_child(icon)
		button.gui_input.connect(func(event: InputEvent) -> void: _on_chest_gui_input(event, index))
		_chest_buttons.append(button)
		_chest_icons.append(icon)

	_player_inventory_label = Label.new()
	_player_inventory_label.text = "Инвентарь"
	_player_inventory_label.position = Vector2(8, 202)
	_player_inventory_label.size = Vector2(624, 24)
	_player_inventory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_player_inventory_label.add_theme_font_size_override("font_size", 18)
	_player_inventory_label.visible = false
	main_panel.add_child(_player_inventory_label)

	var inventory_section := main_panel.get_node_or_null("InventorySection") as Control
	if inventory_section != null:
		_inventory_section_default_position = inventory_section.position


func _on_chest_gui_input(event: InputEvent, slot_index: int) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.ctrl_pressed:
		if _open_chest != null and _open_chest.has_method("request_transfer_to_player"):
			_open_chest.call("request_transfer_to_player", slot_index, _inventory)
		accept_event()


func _refresh_chest() -> void:
	for index in _chest_icons.size():
		var item: ItemData = null
		if _open_chest != null and _open_chest.has_method("get_item"):
			item = _open_chest.call("get_item", index) as ItemData
		_set_icon(_chest_icons[index], item.icon if item != null and item.icon != null else null)


func open_chest(chest: Node) -> void:
	if chest == null:
		return
	if _open_chest == chest and main_panel.visible:
		_close_main_panel()
		return
	_disconnect_chest()
	_open_chest = chest
	if _open_chest.has_signal("contents_changed"):
		_open_chest.connect("contents_changed", _refresh_chest)

	_mouse_mode_before_open = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	main_panel.visible = true
	var title := main_panel.get_node("Title") as Label
	title.text = "Хранилище"
	main_panel.get_node("TopRow").visible = false
	main_panel.get_node("TabBar").visible = false
	_stats_tab.visible = false
	_chest_section.visible = true
	_player_inventory_label.visible = true
	var inventory_section := main_panel.get_node("InventorySection") as Control
	inventory_section.visible = true
	inventory_section.position = Vector2(_inventory_section_default_position.x, 230.0)
	_refresh_chest()
	_refresh_inventory()


func is_chest_open(chest: Node = null) -> bool:
	if chest == null:
		return _open_chest != null and main_panel.visible
	return _open_chest == chest and main_panel.visible


func close_chest() -> void:
	if _open_chest != null:
		_close_main_panel()


func _disconnect_chest() -> void:
	if _open_chest == null:
		return
	if _open_chest.has_signal("contents_changed") and _open_chest.is_connected("contents_changed", _refresh_chest):
		_open_chest.disconnect("contents_changed", _refresh_chest)
	if _open_chest.has_method("set_open_visual"):
		_open_chest.call("set_open_visual", false)
	_open_chest = null


func _leave_chest_layout() -> void:
	_disconnect_chest()
	if _chest_section != null:
		_chest_section.visible = false
	if _player_inventory_label != null:
		_player_inventory_label.visible = false
	if main_panel != null:
		var title := main_panel.get_node("Title") as Label
		title.text = "Инвентарь  [I]"
		main_panel.get_node("TabBar").visible = true
		var inventory_section := main_panel.get_node("InventorySection") as Control
		inventory_section.position = _inventory_section_default_position
	_show_inventory_tab()

func _use_quickslot_item(slot_index: int) -> void:
	if _inventory == null:
		return
	var player := _find_owner_player()
	if player == null:
		return
	_inventory.use_quickslot(slot_index, player)
	_refresh_quickslots()

# ════════════════════════════════════════════════════════
# QUICK EQUIP — Ctrl+клик
# Надевает предмет в подходящий слот экипировки.
# Если слот занят — вытесненный предмет возвращается в
# тот же слот инвентаря.
# ════════════════════════════════════════════════════════
func _quick_equip(inv_idx: int) -> void:

	if _inventory == null or _equipment == null:
		return

	var item := _inventory.get_item(inv_idx)
	if item == null or not item.is_equipment():
		return

	# Найти индекс слота экипировки для этого типа предмета
	var eq_idx := _find_eq_slot_for(item)
	if eq_idx < 0:
		return

	# Вытеснить текущий предмет обратно в инвентарь
	var current := _eq_slot_item(eq_idx)
	_inventory.slots[inv_idx] = current

	_equipment.equip_to_slot(item, eq_idx)
	_inventory.changed.emit()


# Вернуть индекс UI-слота экипировки для данного предмета.
# Для TRINKET: предпочитаем пустой слот, иначе trinket_1 (idx 5).
func _find_eq_slot_for(item: ItemData) -> int:

	match item.slot:
		ItemData.Slot.WEAPON:     return 0
		ItemData.Slot.HELMET:     return 1
		ItemData.Slot.CHESTPLATE: return 2
		ItemData.Slot.LEGGINGS:   return 3
		ItemData.Slot.CLOAK:      return 4
		ItemData.Slot.TRINKET:
			# Предпочесть пустой слот
			if _equipment.trinket_1 == null:
				return 5
			if _equipment.trinket_2 == null:
				return 6
			# Оба заняты — вытесняем trinket_1
			return 5

	return -1

# Ctrl+клик на слот экипировки — снять предмет в первый свободный слот инвентаря
func _quick_unequip(eq_idx: int) -> void:

	if _inventory == null or _equipment == null:
		return

	var item := _eq_slot_item(eq_idx)
	if item == null:
		return

	# Найти первый свободный слот инвентаря
	var free_slot := -1
	for i in _inventory.slots.size():
		if _inventory.slots[i] == null:
			free_slot = i
			break

	if free_slot < 0:
		push_warning("InventoryUI: нет свободных слотов в инвентаре")
		return

	_inventory.slots[free_slot] = item
	_equipment.equip_to_slot(null, eq_idx)
	_inventory.changed.emit()


# ════════════════════════════════════════════════════════
# ВКЛАДКИ: Инвентарь / Характеристики
# Строятся программно поверх существующей раскладки MainPanel,
# поэтому не требуют правок .tscn.
# ════════════════════════════════════════════════════════

var _tab_inventory_btn: Button = null
var _tab_stats_btn:     Button = null
var _stats_tab:         Control = null
var _stats_value_labels: Dictionary = {}  # stat_name → Label
var _attribute_buttons: Dictionary = {}
var _level_label: Label = null
var _attribute_points_label: Label = null

# Отображаемые названия характеристик и показателей
const CHARACTERISTIC_LABELS := {
	"strength":  "Сила",
	"agility":   "Ловкость",
	"intellect": "Интеллект",
	"wisdom":    "Мудрость",
}

const STAT_LABELS := {
	"health":                 "Здоровье",
	"mana":                   "Мана",
	"armor":                  "Броня",
	"magic_resistance":       "Магическое сопротивление",
	"attack_speed":           "Скорость атаки",
	"physical_damage_bonus":  "Увеличение физ. урона",
	"magical_damage_bonus":   "Увеличение маг. урона",
	"move_speed":             "Скорость передвижения",
	"morale":                 "Боевой дух",
	"crit_chance":            "Шанс крита",
	"crit_multiplier":        "Множитель крита",
	"duration":               "Длительность эффектов",
	"radius":                 "Радиус способностей",
}


func _build_tab_buttons() -> void:

	var bar := HBoxContainer.new()
	bar.name = "TabBar"
	bar.position = Vector2(8, 28)
	bar.size = Vector2(624, 28)

	_tab_inventory_btn = Button.new()
	_tab_inventory_btn.text = "Инвентарь"
	_tab_inventory_btn.toggle_mode = true
	_tab_inventory_btn.button_pressed = true
	_tab_inventory_btn.pressed.connect(_show_inventory_tab)
	bar.add_child(_tab_inventory_btn)

	_tab_stats_btn = Button.new()
	_tab_stats_btn.text = "Характеристики"
	_tab_stats_btn.toggle_mode = true
	_tab_stats_btn.pressed.connect(_show_stats_tab)
	bar.add_child(_tab_stats_btn)

	main_panel.add_child(bar)

	# Сдвинуть существующий контент (TopRow, InventorySection) вниз,
	# чтобы освободить место под панель вкладок
	var top_row := main_panel.get_node_or_null("TopRow")
	if top_row:
		top_row.position.y += 28
	var inv_section := main_panel.get_node_or_null("InventorySection")
	if inv_section:
		inv_section.position.y += 28


func _build_stats_tab() -> void:

	_stats_tab = Control.new()
	_stats_tab.name = "StatsTab"
	_stats_tab.position = Vector2(8, 64)
	_stats_tab.size = Vector2(624, 440)
	_stats_tab.visible = false
	main_panel.add_child(_stats_tab)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stats_tab.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	_level_label = Label.new()
	vbox.add_child(_level_label)
	_attribute_points_label = Label.new()
	vbox.add_child(_attribute_points_label)
	vbox.add_child(HSeparator.new())

	var char_title := Label.new()
	char_title.text = "Характеристики"
	char_title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(char_title)

	for key in CHARACTERISTIC_LABELS:
		vbox.add_child(_make_stat_row(key, CHARACTERISTIC_LABELS[key], true))

	vbox.add_child(HSeparator.new())

	var stat_title := Label.new()
	stat_title.text = "Показатели"
	stat_title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(stat_title)

	for key in STAT_LABELS:
		vbox.add_child(_make_stat_row(key, STAT_LABELS[key]))

	vbox.add_child(HSeparator.new())

	var weapon_title := Label.new()
	weapon_title.text = "Урон оружия"
	weapon_title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(weapon_title)

	vbox.add_child(_make_stat_row("weapon_physical", "Физический урон"))
	vbox.add_child(_make_stat_row("weapon_magical",  "Магический урон"))


func _make_stat_row(key: String, display_name: String, can_increase: bool = false) -> HBoxContainer:

	var row := HBoxContainer.new()

	var name_label := Label.new()
	name_label.text = display_name
	name_label.custom_minimum_size = Vector2(260, 0)
	row.add_child(name_label)

	var value_label := Label.new()
	value_label.text = "—"
	_stats_value_labels[key] = value_label
	row.add_child(value_label)

	if can_increase:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		var increase_button := Button.new()
		increase_button.text = "+"
		increase_button.tooltip_text = "Вложить одно очко"
		increase_button.pressed.connect(func(): _on_attribute_increased(key))
		_attribute_buttons[key] = increase_button
		row.add_child(increase_button)

	return row


func _show_inventory_tab() -> void:
	_tab_inventory_btn.button_pressed = true
	_tab_stats_btn.button_pressed = false
	_stats_tab.visible = false
	var top_row := main_panel.get_node_or_null("TopRow")
	var inv_section := main_panel.get_node_or_null("InventorySection")
	if top_row:
		top_row.visible = true
	if inv_section:
		inv_section.visible = true


func _show_stats_tab() -> void:
	_tab_inventory_btn.button_pressed = false
	_tab_stats_btn.button_pressed = true
	_stats_tab.visible = true
	var top_row := main_panel.get_node_or_null("TopRow")
	var inv_section := main_panel.get_node_or_null("InventorySection")
	if top_row:
		top_row.visible = false
	if inv_section:
		inv_section.visible = false
	_refresh_stats_tab()


# ════════════════════════════════════════════════════════
# ОБНОВЛЕНИЕ ЗНАЧЕНИЙ
# ════════════════════════════════════════════════════════
func _refresh_stats_tab() -> void:

	if _stats == null:
		return
	_level_label.text = "Уровень: %d   Опыт: %d/%d" % [
		_stats.level, _stats.experience, StatsComponent.EXPERIENCE_PER_LEVEL]
	_attribute_points_label.text = "Свободные очки: %d" % _stats.attribute_points
	for button in _attribute_buttons.values():
		(button as Button).disabled = _stats.attribute_points <= 0

	for key in CHARACTERISTIC_LABELS:
		if _stats_value_labels.has(key):
			_stats_value_labels[key].text = "%.1f" % _stats.get_characteristic(key)
	for key in STAT_LABELS:
		if not _stats_value_labels.has(key):
			continue
		var value: float = _stats.get_stat(key)
		_stats_value_labels[key].text = _format_stat(key, value)

	# Урон оружия — берём из надетого WeaponData, если есть
	var weapon: ItemData = _equipment.weapon if _equipment else null
	if weapon != null and weapon is WeaponData:
		var w := weapon as WeaponData
		_stats_value_labels["weapon_physical"].text = "%.1f" % w.get_physical_damage(_stats)
		_stats_value_labels["weapon_magical"].text  = "%.1f" % w.get_magical_damage(_stats)
	else:
		_stats_value_labels["weapon_physical"].text = "— (нет оружия)"
		_stats_value_labels["weapon_magical"].text  = "— (нет оружия)"


func _on_attribute_increased(attribute_name: String) -> void:
	if _stats != null:
		_stats.request_spend_attribute(attribute_name)


func _format_stat(key: String, value: float) -> String:
	match key:
		"physical_damage_bonus", "magical_damage_bonus", "duration":
			return "%.1f%%" % value
		"crit_chance":
			return "%.1f%%" % (value * 100.0)
		"crit_multiplier":
			return "x%.2f" % value
		"attack_speed":
			return "%.2f" % value
		_:
			return "%d" % int(value)


# ════════════════════════════════════════════════════════
# ВЫБРАСЫВАНИЕ ПРЕДМЕТОВ В МИР
# ════════════════════════════════════════════════════════

# Delete над слотом: выбросить предмет из слота инвентаря или быстрого доступа.
# Слоты экипировки намеренно не трогаем — чтобы не выбросить надетое случайно.
func _drop_hovered_item() -> void:

	if _inventory == null:
		return

	var inv_idx := _inv_slot_at_mouse()
	if inv_idx >= 0 and not _inventory.is_empty(inv_idx):
		var item: ItemData = _inventory.get_item(inv_idx)
		_inventory.slots[inv_idx] = null
		_inventory.changed.emit()
		_spawn_world_drop(item)
		return

	var qs_idx := _qs_slot_at_mouse()
	if qs_idx >= 0 and _inventory.quickslots[qs_idx] != null:
		var q_item: ItemData = _inventory.quickslots[qs_idx]
		_inventory.quickslots[qs_idx] = null
		_inventory.changed.emit()
		_spawn_world_drop(q_item)


# Перетащили предмет за пределы окна — выбросить его
func _drop_dragged_item_in_world() -> void:

	var from := _drag_from_idx
	var src  := _drag_source

	# Надетое снаряжение за пределы окна не выбрасываем — возвращаем на место
	if src == DragSource.EQUIPMENT or _inventory == null:
		_cancel_drag()
		return

	_destroy_preview()
	_restore_drag_icon()
	_drag_source   = DragSource.NONE
	_drag_from_idx = -1

	var item: ItemData = null
	match src:
		DragSource.INVENTORY:
			item = _inventory.get_item(from)
			_inventory.slots[from] = null
		DragSource.QUICKSLOT:
			item = _inventory.quickslots[from]
			_inventory.quickslots[from] = null

	if item == null:
		return

	_inventory.changed.emit()
	_spawn_world_drop(item)


# Попросить SteamLobby создать предмет в мире перед героем.
# В соло это происходит немедленно локально, в сети — сервер сам
# разошлёт появление всем игрокам (см. steam_lobby.gd).
func _spawn_world_drop(item: ItemData) -> void:

	if item == null:
		return

	var player := _find_owner_player()
	if player == null:
		push_warning("InventoryUI: герой-владелец не найден, предмет не выброшен")
		return

	var direction := Vector3(0, 0, -1)
	if player.has_method("get_facing_direction"):
		direction = player.get_facing_direction()

	var spawn_position: Vector3 = player.global_position + direction * 0.6 + Vector3(0, 1.0, 0)

	SteamLobby.request_drop(item.id, spawn_position, direction, player)

	print("InventoryUI: выброшен '%s'" % item.id)


# Герой которому принадлежит этот интерфейс: идём вверх по дереву
# (InventoryUI → CanvasLayer → Player). Так в мультиплеере предмет
# выбрасывается у своего героя, а не у первого попавшегося.
func _find_owner_player() -> Node3D:
	var node: Node = get_parent()
	while node != null:
		if node is CharacterBody3D:
			return node as Node3D
		node = node.get_parent()
	return null


# ════════════════════════════════════════════════════════
# ОТКРЫТИЕ / ЗАКРЫТИЕ ПАНЕЛИ
# Мышь нужно освобождать: пока камера захватывает курсор для обзора
# (MOUSE_MODE_CAPTURED), в UI нельзя ни увидеть курсор, ни кликнуть
# по слотам. При закрытии возвращаем тот режим, что был до открытия.
# ════════════════════════════════════════════════════════
func _open_main_panel() -> void:
	_leave_chest_layout()
	_mouse_mode_before_open = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	main_panel.visible = true


func is_main_panel_open() -> bool:
	return main_panel != null and main_panel.visible


func _close_main_panel() -> void:
	main_panel.visible = false
	_leave_chest_layout()
	var owner_player := _find_owner_player()
	var camera_rig: CameraRig = null
	if owner_player != null:
		camera_rig = owner_player.get_node_or_null("CameraRig") as CameraRig
	if camera_rig != null and camera_rig.enabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = _mouse_mode_before_open
