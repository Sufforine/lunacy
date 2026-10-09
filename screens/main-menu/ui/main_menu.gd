# main_menu.gd
# Главное меню в 3D. Корневая нода сцены — Node3D с этим скриптом;
# камера, свет, декорации и CanvasLayer с кнопками строятся кодом.
#
# Поток:
#   TITLE       → кнопки «Играть» / «Выход»
#   MOVING      → камера плавно уезжает влево к постаменту
#   STAGE       → снизу по центру «Создать персонажа»; если персонаж уже есть,
#                 на постаменте стоит последний созданный + кнопка «Выбрать»
#   EDITING     → имя, цвет куба, причёска (второй куб сверху), «Сохранить»
#   MODE_SELECT → одиночная игра или мультиплеер
extends Node3D

const SOLO_SCENE  := "res://screens/hub/ui/hub.tscn"
const LOBBY_SCENE := "res://features/steam-lobby/ui/lobby_menu.tscn"

const NAME_MAX_LENGTH := 24

# Причёски — дополнительный куб на верхней части. size == ZERO → без причёски.
const HAIR_STYLES := [
	{"label": "Без причёски", "size": Vector3.ZERO},
	{"label": "Ёжик",         "size": Vector3(1.0, 0.18, 1.0)},
	{"label": "Башня",        "size": Vector3(0.6, 0.7, 0.6)},
	{"label": "Шляпа",        "size": Vector3(1.45, 0.2, 1.45)},
	{"label": "Гребень",      "size": Vector3(0.2, 0.45, 1.0)},
]

const BODY_TOP_Y := 1.1  # верх основного куба: центр 0.6 + половина высоты 0.5

enum State { TITLE, MOVING, STAGE, EDITING, MODE_SELECT, CONFIRM_DELETE }

@export var game_title: String = "НАЗВАНИЕ ИГРЫ"
@export var title_camera_position: Vector3 = Vector3(0.0, 1.8, 7.0)
@export var stage_camera_position: Vector3 = Vector3(-10.0, 1.5, 3.4)
@export var stage_center: Vector3 = Vector3(-10.0, 0.0, 0.0)
@export var camera_pitch_degrees: float = -6.0
@export var camera_move_time: float = 1.4
@export var figure_spin_speed: float = 0.6

var _state: State = State.TITLE

var _camera: Camera3D
var _figure: Node3D
var _body: CSGBox3D
var _hair: CSGBox3D
var _body_material: StandardMaterial3D
var _hair_material: StandardMaterial3D

var _title_ui: Control
var _stage_ui: Control
var _edit_ui: Control
var _mode_ui: Control
var _confirm_ui: Control

var _character_label: Label
var _back_button: Button
var _select_button: Button
var _delete_button: Button
var _confirm_label: Label
var _create_button: Button

var _name_input: LineEdit
var _error_label: Label
var _color_picker: ColorPickerButton
var _hair_buttons: Array[Button] = []

var _multiplayer_button: Button

var _last_character: Dictionary = {}
var _edit_color: Color = Color8(52, 152, 219)
var _edit_hair: int = 0

var _swatch_colors: Array[Color] = [
	Color8(231, 76, 60),
	Color8(230, 126, 34),
	Color8(241, 196, 15),
	Color8(46, 204, 113),
	Color8(26, 188, 156),
	Color8(52, 152, 219),
	Color8(155, 89, 182),
	Color8(236, 240, 241),
]


# ════════════════════════════════════════════════════════
# READY
# ════════════════════════════════════════════════════════
func _ready() -> void:
	# Предыдущая сцена (миссия) могла оставить мышь захваченной камерой
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_build_world()
	_build_ui()
	_set_state(State.TITLE)


func _process(delta: float) -> void:
	if _figure.visible:
		_figure.rotate_y(figure_spin_speed * delta)


# ════════════════════════════════════════════════════════
# 3D-МИР
# ════════════════════════════════════════════════════════
func _build_world() -> void:

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.07, 0.08, 0.12)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.6, 0.75)
	environment.ambient_light_energy = 0.5

	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)

	var floor_box := CSGBox3D.new()
	floor_box.size = Vector3(80.0, 0.2, 60.0)
	floor_box.position = Vector3(-5.0, -0.1, 0.0)
	floor_box.material = _make_material(Color(0.14, 0.15, 0.2))
	add_child(floor_box)

	# Постамент для персонажа
	var platform := CSGCylinder3D.new()
	platform.radius = 1.6
	platform.height = 0.2
	platform.sides = 32
	platform.position = stage_center
	platform.material = _make_material(Color(0.3, 0.32, 0.4))
	add_child(platform)

	# Простые колонны на заднем плане титульного экрана
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(8):
		var pillar_height: float = rng.randf_range(1.5, 4.0)
		var pillar := CSGBox3D.new()
		pillar.size = Vector3(1.0, pillar_height, 1.0)
		pillar.position = Vector3(
			rng.randf_range(-6.0, 6.0),
			pillar_height * 0.5,
			rng.randf_range(-9.0, -3.0)
		)
		pillar.material = _make_material(Color(0.2, 0.22, 0.3))
		add_child(pillar)

	_camera = Camera3D.new()
	_camera.position = title_camera_position
	_camera.rotation_degrees = Vector3(camera_pitch_degrees, 0.0, 0.0)
	add_child(_camera)
	_camera.make_current()

	# Фигура персонажа: куб + куб-причёска сверху
	_figure = Node3D.new()
	_figure.position = stage_center
	_figure.visible = false
	add_child(_figure)

	_body_material = _make_material(Color.WHITE)
	_hair_material = _make_material(Color.WHITE)

	_body = CSGBox3D.new()
	_body.size = Vector3.ONE
	_body.position = Vector3(0.0, 0.6, 0.0)
	_body.material = _body_material
	_figure.add_child(_body)

	_hair = CSGBox3D.new()
	_hair.material = _hair_material
	_figure.add_child(_hair)


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material


# Показать на фигуре внешность: цвет куба и индекс причёски
func _apply_appearance(color: Color, hair_index: int) -> void:

	_body_material.albedo_color = color
	_hair_material.albedo_color = color.darkened(0.45)

	var index: int = clampi(hair_index, 0, HAIR_STYLES.size() - 1)
	var hair_style: Dictionary = HAIR_STYLES[index]
	var hair_size: Vector3 = hair_style["size"]

	if hair_size == Vector3.ZERO:
		_hair.visible = false
		return

	_hair.visible = true
	_hair.size = hair_size
	_hair.position = Vector3(0.0, BODY_TOP_Y + hair_size.y * 0.5 - 0.02, 0.0)


func _appearance_color(appearance: Dictionary) -> Color:
	return Color.html(str(appearance.get("color", "3498db")))


# ════════════════════════════════════════════════════════
# UI
# ════════════════════════════════════════════════════════
func _build_ui() -> void:

	var layer := CanvasLayer.new()
	add_child(layer)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ignore_mouse(root)
	layer.add_child(root)

	_title_ui = _build_title_ui()
	root.add_child(_title_ui)

	_stage_ui = _build_stage_ui()
	root.add_child(_stage_ui)

	_edit_ui = _build_edit_ui()
	root.add_child(_edit_ui)

	_mode_ui = _build_mode_ui()
	root.add_child(_mode_ui)

	_confirm_ui = _build_confirm_ui()
	root.add_child(_confirm_ui)


func _build_title_ui() -> Control:

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ignore_mouse(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var title := _make_label(game_title, 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 40.0)
	box.add_child(gap)

	box.add_child(_make_button("Играть", _on_play_pressed))
	box.add_child(_make_button("Выход", _on_quit_pressed))

	return center


func _build_stage_ui() -> Control:

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ignore_mouse(column)

	var top_gap := Control.new()
	top_gap.custom_minimum_size = Vector2(0.0, 36.0)
	_ignore_mouse(top_gap)
	column.add_child(top_gap)

	_character_label = _make_label("", 30)
	_character_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_character_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ignore_mouse(spacer)
	column.add_child(spacer)

	# Нижняя панель кнопок — CenterContainer сам держит её по центру
	var bar_center := CenterContainer.new()
	_ignore_mouse(bar_center)
	column.add_child(bar_center)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	bar_center.add_child(bar)

	_back_button = _make_button("Назад", _on_back_pressed, 140.0)
	bar.add_child(_back_button)

	_select_button = _make_button("Выбрать", _on_select_pressed)
	bar.add_child(_select_button)

	_delete_button = _make_button("Удалить", _on_delete_pressed, 140.0)
	_delete_button.modulate = Color(1.0, 0.6, 0.6)
	bar.add_child(_delete_button)

	_create_button = _make_button("Создать персонажа", _on_create_pressed, 260.0)
	bar.add_child(_create_button)

	var bottom_gap := Control.new()
	bottom_gap.custom_minimum_size = Vector2(0.0, 36.0)
	_ignore_mouse(bottom_gap)
	column.add_child(bottom_gap)

	return column


func _build_edit_ui() -> Control:

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	_ignore_mouse(margin)

	var row := HBoxContainer.new()
	_ignore_mouse(row)
	margin.add_child(row)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ignore_mouse(spacer)
	row.add_child(spacer)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320.0, 0.0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(panel)

	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 16)
	inner.add_theme_constant_override("margin_right", 16)
	inner.add_theme_constant_override("margin_top", 16)
	inner.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(inner)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	inner.add_child(column)

	column.add_child(_make_label("Новый персонаж", 24))

	_name_input = LineEdit.new()
	_name_input.placeholder_text = "Имя персонажа"
	_name_input.max_length = NAME_MAX_LENGTH
	_name_input.custom_minimum_size = Vector2(0.0, 36.0)
	column.add_child(_name_input)

	# ── Цвет ──────────────────────────────────────────────
	column.add_child(_make_label("Цвет", 18))

	var swatches := GridContainer.new()
	swatches.columns = 4
	column.add_child(swatches)

	for swatch_color in _swatch_colors:
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(44.0, 32.0)
		for state_name in ["normal", "hover", "pressed"]:
			var box_style := StyleBoxFlat.new()
			box_style.bg_color = swatch_color
			box_style.set_corner_radius_all(4)
			swatch.add_theme_stylebox_override(state_name, box_style)
		swatch.pressed.connect(func(): _set_edit_color(swatch_color, true))
		swatches.add_child(swatch)

	var custom_row := HBoxContainer.new()
	custom_row.add_theme_constant_override("separation", 10)
	column.add_child(custom_row)
	custom_row.add_child(_make_label("Свой цвет:", 16))

	_color_picker = ColorPickerButton.new()
	_color_picker.custom_minimum_size = Vector2(80.0, 32.0)
	_color_picker.edit_alpha = false
	_color_picker.color = _edit_color
	_color_picker.color_changed.connect(_on_custom_color_changed)
	custom_row.add_child(_color_picker)

	# ── Причёска ──────────────────────────────────────────
	column.add_child(_make_label("Причёска", 18))

	var hair_group := ButtonGroup.new()
	_hair_buttons.clear()
	for i in range(HAIR_STYLES.size()):
		var hair_style: Dictionary = HAIR_STYLES[i]
		var hair_button := Button.new()
		hair_button.text = str(hair_style["label"])
		hair_button.toggle_mode = true
		hair_button.button_group = hair_group
		hair_button.custom_minimum_size = Vector2(0.0, 34.0)
		hair_button.pressed.connect(func(): _set_edit_hair(i))
		column.add_child(hair_button)
		_hair_buttons.append(hair_button)

	_error_label = _make_label("", 16)
	_error_label.modulate = Color(1.0, 0.45, 0.45)
	_error_label.visible = false
	column.add_child(_error_label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)

	var cancel_button := _make_button("Отмена", _on_cancel_edit_pressed, 130.0)
	buttons.add_child(cancel_button)

	var save_button := _make_button("Сохранить", _on_save_pressed, 150.0)
	buttons.add_child(save_button)

	return margin


func _build_confirm_ui() -> Control:

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ignore_mouse(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 28)
	inner.add_theme_constant_override("margin_right", 28)
	inner.add_theme_constant_override("margin_top", 24)
	inner.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(inner)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	inner.add_child(column)

	var title := _make_label("Удалить персонажа?", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	_confirm_label = _make_label("", 20)
	_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_confirm_label)

	var warning := _make_label("Инвентарь, снаряжение и прогресс будут потеряны.\nЭто нельзя отменить.", 16)
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.modulate = Color(1.0, 0.7, 0.7)
	column.add_child(warning)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(buttons)

	buttons.add_child(_make_button("Отмена", _on_delete_cancelled, 150.0))

	var confirm_button := _make_button("Удалить", _on_delete_confirmed, 150.0)
	confirm_button.modulate = Color(1.0, 0.5, 0.5)
	buttons.add_child(confirm_button)

	return center


func _build_mode_ui() -> Control:

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ignore_mouse(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 28)
	inner.add_theme_constant_override("margin_right", 28)
	inner.add_theme_constant_override("margin_top", 24)
	inner.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(inner)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	inner.add_child(column)

	var title := _make_label("Режим игры", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	column.add_child(_make_button("Одиночная игра", _on_solo_pressed, 280.0))

	_multiplayer_button = _make_button("Мультиплеер", _on_multiplayer_pressed, 280.0)
	column.add_child(_multiplayer_button)

	column.add_child(_make_button("Назад", _on_mode_back_pressed, 280.0))

	return center


# ── Мелкие помощники для UI ──────────────────────────────
func _ignore_mouse(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _make_label(text: String, font_size: int = 18) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _make_button(text: String, callback: Callable, min_width: float = 220.0) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(min_width, 48.0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(callback)
	return button


# ════════════════════════════════════════════════════════
# СОСТОЯНИЯ
# ════════════════════════════════════════════════════════
func _set_state(new_state: State) -> void:
	_state = new_state
	_title_ui.visible = new_state == State.TITLE
	_stage_ui.visible = new_state == State.STAGE
	_edit_ui.visible  = new_state == State.EDITING
	_mode_ui.visible  = new_state == State.MODE_SELECT
	_confirm_ui.visible = new_state == State.CONFIRM_DELETE


func _move_camera(target: Vector3) -> void:
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_camera, "position", target, camera_move_time)
	await tween.finished


# Экран с постаментом: последний созданный персонаж или пустой постамент
func _show_stage() -> void:

	_last_character = SaveManager.get_last_character()
	var has_character: bool = not _last_character.is_empty()

	if has_character:
		var appearance: Dictionary = _last_character.get("appearance", {})
		_apply_appearance(_appearance_color(appearance), int(appearance.get("hair", 0)))
		_character_label.text = str(_last_character.get("character_name", ""))
	else:
		_character_label.text = ""

	_figure.visible = has_character
	_select_button.visible = has_character
	_delete_button.visible = has_character
	_back_button.visible = true
	_create_button.text = "Создать нового" if has_character else "Создать персонажа"

	_set_state(State.STAGE)


# ════════════════════════════════════════════════════════
# ОБРАБОТЧИКИ КНОПОК
# ════════════════════════════════════════════════════════
func _on_play_pressed() -> void:
	if _state != State.TITLE:
		return
	_set_state(State.MOVING)
	await _move_camera(stage_camera_position)
	_show_stage()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_back_pressed() -> void:
	if _state != State.STAGE:
		return
	_figure.visible = false
	_set_state(State.MOVING)
	await _move_camera(title_camera_position)
	_set_state(State.TITLE)


func _on_create_pressed() -> void:

	if _state != State.STAGE:
		return

	_edit_color = Color8(52, 152, 219)
	_edit_hair = 0
	_name_input.text = ""
	_error_label.visible = false
	_color_picker.color = _edit_color
	_refresh_hair_buttons()

	_apply_appearance(_edit_color, _edit_hair)
	_figure.visible = true

	_set_state(State.EDITING)
	_name_input.grab_focus()


func _on_cancel_edit_pressed() -> void:
	if _state != State.EDITING:
		return
	_show_stage()


func _on_save_pressed() -> void:

	if _state != State.EDITING:
		return

	var character_name: String = _name_input.text.strip_edges()
	if character_name.is_empty():
		_show_error("Введи имя персонажа")
		return

	var appearance: Dictionary = {
		"color": _edit_color.to_html(false),
		"hair":  _edit_hair,
	}

	if not SaveManager.create_character(character_name, appearance):
		_show_error("Не удалось сохранить персонажа")
		return

	# Возвращаемся на постамент: теперь там только что созданный персонаж
	# и доступна кнопка «Выбрать»
	_show_stage()


func _on_select_pressed() -> void:

	if _state != State.STAGE or _last_character.is_empty():
		return

	SaveManager.select_save(_last_character)

	var steam_ready: bool = SteamLobby.is_steam_ready()
	_multiplayer_button.disabled = not steam_ready
	_multiplayer_button.tooltip_text = "" if steam_ready else "Steam недоступен. Запусти Steam, залогинься и перезапусти игру."

	_set_state(State.MODE_SELECT)


func _on_delete_pressed() -> void:

	if _state != State.STAGE or _last_character.is_empty():
		return

	_confirm_label.text = "«%s»" % str(_last_character.get("character_name", ""))
	_set_state(State.CONFIRM_DELETE)


func _on_delete_confirmed() -> void:

	if _state != State.CONFIRM_DELETE:
		return

	if not SaveManager.delete_character(_last_character):
		push_warning("main_menu: не удалось удалить персонажа")

	# Постамент покажет следующего по дате персонажа или опустеет
	_show_stage()


func _on_delete_cancelled() -> void:
	if _state != State.CONFIRM_DELETE:
		return
	_set_state(State.STAGE)


func _on_solo_pressed() -> void:
	get_tree().change_scene_to_file(SOLO_SCENE)


func _on_multiplayer_pressed() -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_mode_back_pressed() -> void:
	if _state != State.MODE_SELECT:
		return
	_set_state(State.STAGE)


# ── Редактор внешности ───────────────────────────────────
# update_picker == false, когда цвет пришёл из самого пикера —
# иначе мы бы заново выставляли ему тот же цвет.
func _set_edit_color(color: Color, update_picker: bool) -> void:
	_edit_color = color
	if update_picker:
		_color_picker.color = color
	_apply_appearance(_edit_color, _edit_hair)


func _on_custom_color_changed(color: Color) -> void:
	_set_edit_color(color, false)


func _set_edit_hair(index: int) -> void:
	_edit_hair = index
	_apply_appearance(_edit_color, _edit_hair)


func _refresh_hair_buttons() -> void:
	for i in range(_hair_buttons.size()):
		_hair_buttons[i].button_pressed = (i == _edit_hair)


func _show_error(text: String) -> void:
	_error_label.text = text
	_error_label.visible = true
