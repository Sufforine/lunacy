extends Control

var combat: Node
var _icons: Array[TextureRect] = []
var _cooldowns: Array[Label] = []
var _slots: Array[PanelContainer] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -126
	offset_top = -88
	offset_right = 126
	offset_bottom = -12
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	for i in 3:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(76, 76)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color("17202b")
		style.border_color = Color("d2b77c")
		style.set_border_width_all(2)
		panel.add_theme_stylebox_override("panel", style)
		row.add_child(panel)
		_slots.append(panel)
		var content := Control.new()
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(content)
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		content.add_child(icon)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_icons.append(icon)
		var cooldown := Label.new()
		cooldown.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cooldown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cooldown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cooldown.add_theme_font_size_override("font_size", 24)
		content.add_child(cooldown)
		cooldown.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_cooldowns.append(cooldown)
		var key := Label.new()
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		key.text = InputMap.action_get_events(combat.SKILL_ACTIONS[i])[0].as_text().replace(" (Physical)", "")
		key.position = Vector2(3, 48)
		key.custom_minimum_size = Vector2(24, 24)
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var key_style := StyleBoxFlat.new()
		key_style.bg_color = Color("101721")
		key_style.border_color = Color("d2b77c")
		key_style.set_border_width_all(1)
		key_style.set_corner_radius_all(3)
		key.add_theme_stylebox_override("normal", key_style)
		key.add_theme_color_override("font_outline_color", Color.BLACK)
		key.add_theme_constant_override("outline_size", 6)
		content.add_child(key)
func _process(_delta: float) -> void:
	var weapon := combat.weapon as WeaponData
	visible = weapon != null
	if weapon == null:
		return
	for i in 3:
		var skill := weapon.skills[i] if i < weapon.skills.size() else null
		_slots[i].visible = skill != null
		if skill == null:
			continue
		_icons[i].texture = skill.icon
		var remaining: float = combat.remaining(i)
		_icons[i].modulate = Color(0.4, 0.4, 0.4) if remaining > 0.0 else Color.WHITE
		_cooldowns[i].text = str(ceili(remaining)) if remaining > 0.0 else ""
