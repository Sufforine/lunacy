extends Control

const SLOT_SIZE := Vector2(64.0, 64.0)
const SLOT_GAP := 6.0
const GROUP_GAP := 38.0
const PANEL_PADDING := 12.0
const COLUMN_GAP := 7.0
const BAR_HEIGHT := 20.0
const CONTENT_WIDTH := SLOT_SIZE.x * 6.0 + SLOT_GAP * 4.0 + GROUP_GAP
const PANEL_WIDTH := CONTENT_WIDTH + PANEL_PADDING * 2.0
const PANEL_HEIGHT := SLOT_SIZE.y + BAR_HEIGHT * 2.0 + COLUMN_GAP * 2.0 + PANEL_PADDING * 2.0

var combat: Node
var _hero: Player
var _inventory: InventoryComponent
var _stats: StatsComponent
var _panel: PanelContainer
var _ability_slots: Array[PanelContainer] = []
var _ability_icons: Array[TextureRect] = []
var _ability_cooldowns: Array[Label] = []
var _quick_slots: Array[Button] = []
var _quick_icons: Array[TextureRect] = []
var _key_labels: Array[Label] = []
var _health_track: PanelContainer
var _health_fill: ColorRect
var _shield_fill: ColorRect
var _health_label: Label
var _mana_track: PanelContainer
var _mana_fill: ColorRect
var _mana_label: Label
var _last_weapon: WeaponData


func _ready() -> void:
	_hero = combat.hero as Player
	_inventory = _hero.inventory
	_stats = _hero.stats
	z_index = -10
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -PANEL_WIDTH * 0.5
	offset_top = -PANEL_HEIGHT - 12.0
	offset_right = PANEL_WIDTH * 0.5
	offset_bottom = -12.0
	_build_interface()
	_inventory.changed.connect(_refresh_quickslots)
	_stats.stats_changed.connect(_refresh_bars)
	GameSettings.inventory_theme_changed.connect(_apply_theme)
	GameSettings.ui_scale_changed.connect(_apply_ui_scale)
	_apply_theme()
	_apply_ui_scale()
	_refresh_quickslots()
	_refresh_abilities()
	_refresh_bars()


func _build_interface() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, int(PANEL_PADDING))
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", int(COLUMN_GAP))
	margin.add_child(column)

	var slot_row := HBoxContainer.new()
	slot_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	slot_row.add_theme_constant_override("separation", int(GROUP_GAP))
	column.add_child(slot_row)

	var abilities := HBoxContainer.new()
	abilities.mouse_filter = Control.MOUSE_FILTER_IGNORE
	abilities.add_theme_constant_override("separation", int(SLOT_GAP))
	slot_row.add_child(abilities)
	for index in 3:
		_build_ability_slot(abilities, index)

	var quickslots := HBoxContainer.new()
	quickslots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quickslots.add_theme_constant_override("separation", int(SLOT_GAP))
	slot_row.add_child(quickslots)
	for index in 3:
		_build_quick_slot(quickslots, index)

	_health_track = _build_bar(column, Color("c63d3d"))
	_health_fill = _health_track.get_node("Content/Fill") as ColorRect
	_shield_fill = _health_track.get_node("Content/Shield") as ColorRect
	_health_label = _health_track.get_node("Content/Label") as Label
	_mana_track = _build_bar(column, Color("3971d6"), false)
	_mana_fill = _mana_track.get_node("Content/Fill") as ColorRect
	_mana_label = _mana_track.get_node("Content/Label") as Label


func _build_ability_slot(parent: Control, index: int) -> void:
	var slot := PanelContainer.new()
	slot.name = "Ability%d" % (index + 1)
	slot.custom_minimum_size = SLOT_SIZE
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(slot)
	_ability_slots.append(slot)
	var content := _build_slot_content(slot, combat.SKILL_ACTIONS[index])
	_ability_icons.append(content.icon)
	_ability_cooldowns.append(content.overlay)


func _build_quick_slot(parent: Control, index: int) -> void:
	var slot := Button.new()
	slot.name = "Quickslot%d" % (index + 1)
	slot.custom_minimum_size = SLOT_SIZE
	slot.clip_contents = true
	slot.focus_mode = Control.FOCUS_NONE
	slot.tooltip_text = "Клавиша %d" % (index + 1)
	slot.pressed.connect(_use_quickslot.bind(index))
	parent.add_child(slot)
	_quick_slots.append(slot)
	var content := _build_slot_content(slot, StringName(str(index + 1)))
	_quick_icons.append(content.icon)


func _build_slot_content(slot: Control, action: StringName) -> Dictionary:
	var content := Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot.add_child(content)
	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 4.0
	icon.offset_top = 4.0
	icon.offset_right = -4.0
	icon.offset_bottom = -4.0
	content.add_child(icon)
	var overlay := Label.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	overlay.add_theme_font_size_override("font_size", 22)
	overlay.add_theme_color_override("font_outline_color", Color.BLACK)
	overlay.add_theme_constant_override("outline_size", 5)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_child(overlay)
	var key := Label.new()
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key.text = _action_text(action)
	key.position = Vector2(3.0, 39.0)
	key.custom_minimum_size = Vector2(22.0, 22.0)
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key.add_theme_font_size_override("font_size", 12)
	content.add_child(key)
	_key_labels.append(key)
	return {"icon": icon, "overlay": overlay}


func _build_bar(parent: Control, fill_color: Color, with_shield: bool = true) -> PanelContainer:
	var track := PanelContainer.new()
	track.custom_minimum_size = Vector2(0.0, BAR_HEIGHT)
	track.clip_contents = true
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(track)
	var content := Control.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(content)
	var fill := ColorRect.new()
	fill.name = "Fill"
	fill.color = fill_color
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_child(fill)
	var shield := ColorRect.new()
	shield.name = "Shield"
	shield.color = Color(0.35, 0.82, 1.0, 0.58) if with_shield else Color.TRANSPARENT
	shield.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_child(shield)
	var label := Label.new()
	label.name = "Label"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_child(label)
	return track


func _process(_delta: float) -> void:
	if combat.weapon != _last_weapon:
		_refresh_abilities()
	for index in 3:
		var ability := _ability_at(index)
		var remaining: float = combat.remaining(index) if ability != null else 0.0
		_ability_icons[index].modulate = Color(0.38, 0.38, 0.38) if remaining > 0.0 else Color.WHITE
		_ability_cooldowns[index].text = str(ceili(remaining)) if remaining > 0.0 else ""
	_refresh_bars()


func _refresh_abilities() -> void:
	_last_weapon = combat.weapon as WeaponData
	for index in 3:
		var ability := _ability_at(index)
		_ability_icons[index].texture = ability.icon if ability != null else null
		_ability_icons[index].tooltip_text = ability.title if ability != null else ""


func _ability_at(index: int) -> AbilityDefinition:
	if _last_weapon == null or index >= _last_weapon.skills.size():
		return null
	return _last_weapon.skills[index]


func _refresh_quickslots() -> void:
	if _inventory == null:
		return
	for index in 3:
		var item: ItemData = _inventory.quickslots[index] if index < _inventory.quickslots.size() else null
		_quick_icons[index].texture = item.icon if item != null else null
		_quick_slots[index].tooltip_text = "%s — клавиша %d" % [item.item_name, index + 1] if item != null else "Клавиша %d" % (index + 1)


func _refresh_bars() -> void:
	if _stats == null or _health_fill == null:
		return
	var max_health := maxf(1.0, _stats.get_stat("health"))
	var max_mana := maxf(1.0, _stats.get_stat("mana"))
	_set_fill_ratio(_health_fill, clampf(float(_stats.current_health) / max_health, 0.0, 1.0))
	_set_fill_ratio(_shield_fill, clampf(_stats.current_shield / max_health, 0.0, 1.0))
	_set_fill_ratio(_mana_fill, clampf(float(_stats.current_mana) / max_mana, 0.0, 1.0))
	_health_label.text = "%d / %d" % [_stats.current_health, int(max_health)]
	if _stats.current_shield > 0.0:
		_health_label.text += "  (+%d)" % int(_stats.current_shield)
	_mana_label.text = "%d / %d" % [_stats.current_mana, int(max_mana)]


func _set_fill_ratio(fill: ColorRect, ratio: float) -> void:
	fill.anchor_right = ratio
	fill.offset_left = 0.0
	fill.offset_top = 0.0
	fill.offset_right = 0.0
	fill.offset_bottom = 0.0


func _use_quickslot(index: int) -> void:
	_inventory.use_quickslot(index, _hero)


func _apply_ui_scale() -> void:
	pivot_offset = Vector2(PANEL_WIDTH * 0.5, PANEL_HEIGHT)
	scale = Vector2.ONE * GameSettings.get_ui_scale()


func _apply_theme() -> void:
	var palette := GameSettings.get_inventory_theme_palette()
	var background: Color = palette.background
	var border: Color = palette.border
	var text_color: Color = palette.text
	var panel_style := _style(background, border, 4, 9)
	panel_style.shadow_color = Color(0, 0, 0, 0.5)
	panel_style.shadow_size = 10
	_panel.add_theme_stylebox_override("panel", panel_style)
	var slot_color := background.darkened(0.22)
	for slot in _ability_slots:
		slot.add_theme_stylebox_override("panel", _style(slot_color, border, 2, 5))
	for slot in _quick_slots:
		slot.add_theme_stylebox_override("normal", _style(slot_color, border, 2, 5))
		slot.add_theme_stylebox_override("hover", _style(slot_color.lightened(0.12), border, 2, 5))
		slot.add_theme_stylebox_override("pressed", _style(slot_color.darkened(0.1), border, 3, 5))
	for key in _key_labels:
		key.add_theme_color_override("font_color", text_color)
		key.add_theme_stylebox_override("normal", _style(background, border, 1, 3))
	var track_style := _style(Color(0.035, 0.04, 0.05, 0.92), border, 1, 3)
	_health_track.add_theme_stylebox_override("panel", track_style)
	_mana_track.add_theme_stylebox_override("panel", track_style.duplicate())


func _style(background: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	return style


func _action_text(action: StringName) -> String:
	if InputMap.has_action(action):
		var events := InputMap.action_get_events(action)
		if not events.is_empty():
			return events[0].as_text().replace(" (Physical)", "")
	return str(action)
