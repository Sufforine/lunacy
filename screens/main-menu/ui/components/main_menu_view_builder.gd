extends RefCounted

var _host


func build(host: Node3D) -> void:
	_host = host
	var layer := CanvasLayer.new()
	_host.add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ignore_mouse(root)
	layer.add_child(root)
	_host._title_ui = _build_title()
	_host._stage_ui = _build_stage()
	_host._edit_ui = _build_editor()
	_host._mode_ui = _build_mode_select()
	_host._world_ui = _build_world_select()
	_host._confirm_ui = _build_delete_confirmation()
	for screen in [_host._title_ui, _host._stage_ui, _host._edit_ui, _host._mode_ui, _host._world_ui, _host._confirm_ui]:
		root.add_child(screen)


func make_label(text: String, font_size: int = 18) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label


func make_button(text: String, callback: Callable, min_width: float = 220.0) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(min_width, 48.0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(callback)
	return button


func ignore_mouse(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _build_title() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ignore_mouse(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	center.add_child(column)
	var title := make_label(_host.game_title, 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 40.0)
	column.add_child(gap)
	column.add_child(make_button("Играть", _host._on_play_pressed))
	column.add_child(make_button("Настройки", _host._on_options_pressed))
	column.add_child(make_button("Выход", _host._on_quit_pressed))
	return center


func _build_stage() -> Control:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ignore_mouse(column)
	var top_gap := Control.new()
	top_gap.custom_minimum_size = Vector2(0.0, 36.0)
	ignore_mouse(top_gap)
	column.add_child(top_gap)
	_host._character_label = make_label("", 30)
	_host._character_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_host._character_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ignore_mouse(spacer)
	column.add_child(spacer)
	var bar_center := CenterContainer.new()
	ignore_mouse(bar_center)
	column.add_child(bar_center)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	bar_center.add_child(bar)
	_host._back_button = make_button("Назад", _host._on_back_pressed, 140.0)
	_host._select_button = make_button("Выбрать", _host._on_select_pressed)
	_host._delete_button = make_button("Удалить", _host._on_delete_pressed, 140.0)
	_host._delete_button.modulate = Color(1.0, 0.6, 0.6)
	_host._create_button = make_button("Создать персонажа", _host._on_create_pressed, 260.0)
	_host._cancel_choice_button = make_button("Отмена", _host._on_cancel_choice_pressed, 140.0)
	for button in [_host._back_button, _host._select_button, _host._delete_button, _host._create_button, _host._cancel_choice_button]:
		bar.add_child(button)
	for entry in CharacterModels.BODY_TYPES:
		var body_def: Dictionary = entry
		var body_id := str(body_def["id"])
		var button := make_button(str(body_def["label"]), func(): _host._on_body_chosen(body_id), 200.0)
		bar.add_child(button)
		_host._body_buttons.append(button)
	var bottom_gap := Control.new()
	bottom_gap.custom_minimum_size = Vector2(0.0, 36.0)
	ignore_mouse(bottom_gap)
	column.add_child(bottom_gap)
	return column


func _build_editor() -> Control:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	ignore_mouse(margin)
	var row := HBoxContainer.new()
	ignore_mouse(row)
	margin.add_child(row)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ignore_mouse(spacer)
	row.add_child(spacer)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320.0, 0.0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(panel)
	var inner := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(inner)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	inner.add_child(column)
	column.add_child(make_label("Новый персонаж", 24))
	_host._name_input = LineEdit.new()
	_host._name_input.placeholder_text = "Имя персонажа"
	_host._name_input.max_length = _host.NAME_MAX_LENGTH
	_host._name_input.custom_minimum_size = Vector2(0.0, 36.0)
	column.add_child(_host._name_input)
	column.add_child(make_label("Цвет кожи", 18))
	var swatches := GridContainer.new()
	swatches.columns = 6
	column.add_child(swatches)
	for swatch_color in _host._skin_swatches:
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(44.0, 32.0)
		for state_name in ["normal", "hover", "pressed"]:
			var style := StyleBoxFlat.new()
			style.bg_color = swatch_color
			style.set_corner_radius_all(4)
			swatch.add_theme_stylebox_override(state_name, style)
		swatch.pressed.connect(func(): _host._set_edit_skin(swatch_color, true))
		swatches.add_child(swatch)
	var custom_row := HBoxContainer.new()
	custom_row.add_theme_constant_override("separation", 10)
	column.add_child(custom_row)
	custom_row.add_child(make_label("Свой цвет:", 16))
	_host._color_picker = ColorPickerButton.new()
	_host._color_picker.custom_minimum_size = Vector2(80.0, 32.0)
	_host._color_picker.edit_alpha = false
	_host._color_picker.color = _host._edit_skin
	_host._color_picker.color_changed.connect(_host._on_custom_skin_changed)
	custom_row.add_child(_host._color_picker)
	column.add_child(make_label("Причёска", 18))
	_host._hair_container = GridContainer.new()
	_host._hair_container.columns = 2
	_host._hair_container.add_theme_constant_override("h_separation", 6)
	_host._hair_container.add_theme_constant_override("v_separation", 6)
	column.add_child(_host._hair_container)
	_host._error_label = make_label("", 16)
	_host._error_label.modulate = Color(1.0, 0.45, 0.45)
	_host._error_label.visible = false
	column.add_child(_host._error_label)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)
	buttons.add_child(make_button("Отмена", _host._on_cancel_edit_pressed, 130.0))
	buttons.add_child(make_button("Сохранить", _host._on_save_pressed, 150.0))
	return margin


func _build_mode_select() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ignore_mouse(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var inner := _padded_margin(28, 24)
	panel.add_child(inner)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	inner.add_child(column)
	var title := make_label("Режим игры", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_host._solo_button = make_button("Одиночная игра", _host._on_solo_pressed, 280.0)
	_host._multiplayer_button = make_button("Мультиплеер", _host._on_multiplayer_pressed, 280.0)
	column.add_child(_host._solo_button)
	column.add_child(_host._multiplayer_button)
	column.add_child(make_button("Назад", _host._on_mode_back_pressed, 280.0))
	return center


func _build_world_select() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ignore_mouse(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(540.0, 0.0)
	center.add_child(panel)
	var inner := _padded_margin(28, 24)
	panel.add_child(inner)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	inner.add_child(column)
	var title := make_label("Выбор мира", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var hint := make_label("Персонаж сохраняется отдельно и может заходить в разные миры.", 15)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 180.0)
	column.add_child(scroll)
	_host._world_list = VBoxContainer.new()
	_host._world_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_host._world_list)
	column.add_child(HSeparator.new())
	column.add_child(make_label("Создать новый мир", 18))
	var create_row := HBoxContainer.new()
	create_row.add_theme_constant_override("separation", 8)
	column.add_child(create_row)
	_host._world_name_input = LineEdit.new()
	_host._world_name_input.placeholder_text = "Название мира"
	_host._world_name_input.max_length = _host.NAME_MAX_LENGTH
	_host._world_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host._world_name_input.text_submitted.connect(func(_text: String): _host._on_world_create_pressed())
	create_row.add_child(_host._world_name_input)
	create_row.add_child(make_button("Создать", _host._on_world_create_pressed, 130.0))
	_host._world_error_label = make_label("", 15)
	_host._world_error_label.modulate = Color(1.0, 0.45, 0.45)
	_host._world_error_label.visible = false
	column.add_child(_host._world_error_label)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	column.add_child(actions)
	actions.add_child(make_button("Назад", _host._on_world_back_pressed, 150.0))
	_host._world_start_button = make_button("Играть", _host._on_world_start_pressed, 180.0)
	_host._world_start_button.disabled = true
	actions.add_child(_host._world_start_button)
	return center


func _build_delete_confirmation() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ignore_mouse(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var inner := _padded_margin(28, 24)
	panel.add_child(inner)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	inner.add_child(column)
	var title := make_label("Удалить персонажа?", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_host._confirm_label = make_label("", 20)
	_host._confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_host._confirm_label)
	var warning := make_label("Инвентарь, снаряжение и прогресс будут потеряны.\nЭто нельзя отменить.", 16)
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.modulate = Color(1.0, 0.7, 0.7)
	column.add_child(warning)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(buttons)
	buttons.add_child(make_button("Отмена", _host._on_delete_cancelled, 150.0))
	var confirm := make_button("Удалить", _host._on_delete_confirmed, 150.0)
	confirm.modulate = Color(1.0, 0.5, 0.5)
	buttons.add_child(confirm)
	return center


func _padded_margin(horizontal: int, vertical: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", horizontal)
	margin.add_theme_constant_override("margin_right", horizontal)
	margin.add_theme_constant_override("margin_top", vertical)
	margin.add_theme_constant_override("margin_bottom", vertical)
	return margin
