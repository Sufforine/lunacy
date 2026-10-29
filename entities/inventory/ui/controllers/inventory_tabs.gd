extends RefCounted

const INVENTORY_ICON := preload("res://Assets/Icons/WoW Icon Pack/Miscellaneous/Bag_01.png")
const STATS_ICON := preload("res://Assets/Icons/WoW Icon Pack/Miscellaneous/Book_01.png")
const ATTRIBUTES_ICON := preload("res://Assets/Icons/WoW Icon Pack/Spells/Strength.png")
const SKILL_TREE_ICON := preload("res://Assets/Icons/WoW Icon Pack/Abilities/TreeofLife.png")

const CHARACTERISTIC_LABELS := {
	"strength": "Сила",
	"agility": "Ловкость",
	"wisdom": "Мудрость",
	"intellect": "Интеллект",
}

const STAT_LABELS := {
	"health": "Здоровье",
	"mana": "Мана",
	"armor": "Броня",
	"magic_resistance": "Магическое сопротивление",
	"attack_speed": "Скорость атаки",
	"physical_damage_bonus": "Увеличение физ. урона",
	"magical_damage_bonus": "Увеличение маг. урона",
	"move_speed": "Скорость передвижения",
	"morale": "Боевой дух",
	"crit_chance": "Шанс крита",
	"crit_multiplier": "Множитель крита",
	"duration": "Длительность эффектов",
	"radius": "Радиус способностей",
}

var _main_panel: Panel
var _stats: StatsComponent
var _equipment: EquipmentComponent
var _tab_bar: Control
var _inventory_button: Button
var _stats_button: Button
var _attributes_button: Button
var _stats_tab: Control
var _stats_scroll: ScrollContainer
var _attributes_tab: Control
var _skill_tree_panel: PanelContainer
var _value_labels: Dictionary = {}
var _attribute_buttons: Dictionary = {}
var _level_label: Label
var _attribute_points_label: Label


func build(main_panel: Panel) -> void:
	_main_panel = main_panel
	_build_tab_buttons()
	_build_stats_tab()
	_build_attributes_tab()
	show_inventory()


func bind(stats: StatsComponent, equipment: EquipmentComponent) -> void:
	_stats = stats
	_equipment = equipment
	refresh()


func show_inventory() -> void:
	_set_buttons(true, false, false)
	_stats_tab.visible = false
	_attributes_tab.visible = false
	_set_inventory_content_visible(true)


func show_stats() -> void:
	_set_buttons(false, true, false)
	_stats_tab.visible = true
	_attributes_tab.visible = false
	_set_inventory_content_visible(false)
	refresh()


func show_attributes() -> void:
	_set_buttons(false, false, true)
	_stats_tab.visible = false
	_attributes_tab.visible = true
	_set_inventory_content_visible(false)
	refresh()


func hide_for_chest() -> void:
	_stats_tab.visible = false
	_attributes_tab.visible = false
	if _tab_bar != null:
		_tab_bar.visible = false


func leave_chest_mode() -> void:
	if _tab_bar != null:
		_tab_bar.visible = true
	show_inventory()


func is_stats_visible() -> bool:
	return _stats_tab != null and _stats_tab.visible


func is_mouse_wheel(event: InputEventMouseButton) -> bool:
	return event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN


func scroll_stats(event: InputEventMouseButton) -> void:
	if _stats_scroll == null:
		return
	var scroll_bar := _stats_scroll.get_v_scroll_bar()
	var amount := maxf(scroll_bar.page * 0.18, 36.0) * maxf(event.factor, 1.0)
	scroll_bar.value += -amount if event.button_index == MOUSE_BUTTON_WHEEL_UP else amount


func refresh() -> void:
	if _stats == null or _level_label == null:
		return
	_level_label.text = "Уровень: %d   Опыт: %d/%d" % [
		_stats.level, _stats.experience, StatsComponent.EXPERIENCE_PER_LEVEL]
	_attribute_points_label.text = "Свободные очки: %d" % _stats.attribute_points
	for button in _attribute_buttons.values():
		(button as Button).disabled = _stats.attribute_points <= 0
	for key in CHARACTERISTIC_LABELS:
		_value_labels[key].text = "%.1f" % _stats.get_characteristic(key)
	for key in STAT_LABELS:
		_value_labels[key].text = _format_stat(key, _stats.get_stat(key))
	var weapon: ItemData = _equipment.weapon if _equipment else null
	if weapon is WeaponData:
		_value_labels["weapon_physical"].text = "%.1f" % weapon.get_physical_damage(_stats)
		_value_labels["weapon_magical"].text = "%.1f" % weapon.get_magical_damage(_stats)
	else:
		_value_labels["weapon_physical"].text = "— (нет оружия)"
		_value_labels["weapon_magical"].text = "— (нет оружия)"


func apply_theme() -> void:
	if _main_panel == null:
		return
	var night := GameSettings.inventory_theme == GameSettings.InventoryTheme.NIGHT
	var palette := GameSettings.get_inventory_theme_palette()
	var background: Color = palette.background
	var border: Color = palette.border
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(4)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 12
	_main_panel.add_theme_stylebox_override("panel", style)
	if _skill_tree_panel != null:
		var tree_style := StyleBoxFlat.new()
		tree_style.bg_color = background.darkened(0.08) if night else background.lightened(0.12)
		tree_style.border_color = border
		tree_style.set_border_width_all(2)
		tree_style.set_corner_radius_all(6)
		_skill_tree_panel.add_theme_stylebox_override("panel", tree_style)
	_apply_label_color(_main_panel, palette.text)
	for button in [_inventory_button, _stats_button, _attributes_button]:
		_style_tab_button(button, background, border)


func _build_tab_buttons() -> void:
	var bar := VBoxContainer.new()
	bar.name = "TabBar"
	bar.position = Vector2(-56, 36)
	bar.size = Vector2(50, 172)
	bar.add_theme_constant_override("separation", 8)
	_tab_bar = bar
	_inventory_button = _make_tab_button(INVENTORY_ICON, "Инвентарь")
	_stats_button = _make_tab_button(STATS_ICON, "Характеристики")
	_attributes_button = _make_tab_button(ATTRIBUTES_ICON, "Атрибуты")
	_inventory_button.pressed.connect(show_inventory)
	_stats_button.pressed.connect(show_stats)
	_attributes_button.pressed.connect(show_attributes)
	bar.add_child(_inventory_button)
	bar.add_child(_stats_button)
	bar.add_child(_attributes_button)
	_main_panel.add_child(bar)


func _make_tab_button(icon_texture: Texture2D, hint: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(50, 50)
	button.icon = icon_texture
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.expand_icon = true
	button.toggle_mode = true
	button.tooltip_text = hint
	return button


func _build_stats_tab() -> void:
	_stats_tab = Control.new()
	_stats_tab.name = "StatsTab"
	_stats_tab.position = Vector2(16, 36)
	_stats_tab.size = Vector2(736, 468)
	_stats_tab.visible = false
	_main_panel.add_child(_stats_tab)
	_stats_scroll = ScrollContainer.new()
	_stats_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stats_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_stats_tab.add_child(_stats_scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_scroll.add_child(column)
	var title := Label.new()
	title.text = "Характеристики"
	title.add_theme_font_size_override("font_size", 16)
	column.add_child(title)
	for key in STAT_LABELS:
		column.add_child(_make_stat_row(key, STAT_LABELS[key]))
	column.add_child(HSeparator.new())
	var weapon_title := Label.new()
	weapon_title.text = "Урон оружия"
	weapon_title.add_theme_font_size_override("font_size", 16)
	column.add_child(weapon_title)
	column.add_child(_make_stat_row("weapon_physical", "Физический урон"))
	column.add_child(_make_stat_row("weapon_magical", "Магический урон"))


func _build_attributes_tab() -> void:
	_attributes_tab = Control.new()
	_attributes_tab.name = "AttributesTab"
	_attributes_tab.position = Vector2(24, 40)
	_attributes_tab.size = Vector2(720, 450)
	_attributes_tab.visible = false
	_main_panel.add_child(_attributes_tab)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 8)
	_attributes_tab.add_child(column)
	var heading := Label.new()
	heading.text = "Атрибуты героя"
	heading.add_theme_font_size_override("font_size", 22)
	column.add_child(heading)
	_level_label = Label.new()
	column.add_child(_level_label)
	_attribute_points_label = Label.new()
	column.add_child(_attribute_points_label)
	column.add_child(HSeparator.new())
	for key in CHARACTERISTIC_LABELS:
		column.add_child(_make_stat_row(key, CHARACTERISTIC_LABELS[key], true))
	_skill_tree_panel = PanelContainer.new()
	_skill_tree_panel.name = "SkillTreePanel"
	_skill_tree_panel.custom_minimum_size = Vector2(0, 150)
	_skill_tree_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_skill_tree_panel)
	var tree_content := CenterContainer.new()
	_skill_tree_panel.add_child(tree_content)
	var tree_column := VBoxContainer.new()
	tree_column.alignment = BoxContainer.ALIGNMENT_CENTER
	tree_content.add_child(tree_column)
	var tree_icon := TextureRect.new()
	tree_icon.texture = SKILL_TREE_ICON
	tree_icon.custom_minimum_size = Vector2(72, 72)
	tree_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	tree_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tree_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tree_column.add_child(tree_icon)
	var tree_label := Label.new()
	tree_label.text = "Дерево прокачки"
	tree_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tree_label.add_theme_font_size_override("font_size", 18)
	tree_column.add_child(tree_label)


func _make_stat_row(key: String, display_name: String, can_increase: bool = false) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = display_name
	name_label.custom_minimum_size = Vector2(260, 0)
	row.add_child(name_label)
	var value_label := Label.new()
	value_label.text = "—"
	_value_labels[key] = value_label
	row.add_child(value_label)
	if can_increase:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		var increase_button := Button.new()
		increase_button.text = "+"
		increase_button.tooltip_text = "Вложить одно очко"
		increase_button.pressed.connect(func(): _stats.request_spend_attribute(key) if _stats != null else null)
		_attribute_buttons[key] = increase_button
		row.add_child(increase_button)
	return row


func _set_buttons(inventory: bool, stats: bool, attributes: bool) -> void:
	_inventory_button.button_pressed = inventory
	_stats_button.button_pressed = stats
	_attributes_button.button_pressed = attributes


func _set_inventory_content_visible(visible: bool) -> void:
	var top_row := _main_panel.get_node_or_null("TopRow")
	var inventory_section := _main_panel.get_node_or_null("InventorySection")
	if top_row != null:
		top_row.visible = visible
	if inventory_section != null:
		inventory_section.visible = visible


func _apply_label_color(node: Node, color: Color) -> void:
	if node is Label:
		(node as Label).add_theme_color_override("font_color", color)
	for child in node.get_children():
		_apply_label_color(child, color)


func _style_tab_button(button: Button, background: Color, border: Color) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = background.lightened(0.16) if state in ["hover", "hover_pressed"] else background
		style.border_color = border
		style.set_border_width_all(3 if state in ["pressed", "hover_pressed"] else 2)
		style.set_corner_radius_all(6)
		button.add_theme_stylebox_override(state, style)


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
