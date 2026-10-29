# main_menu.gd
# Главное меню в 3D. Корневая нода сцены — Node3D с этим скриптом;
# камера, свет, декорации и CanvasLayer с кнопками строятся кодом.
#
# Поток:
#   TITLE          → «Играть» / «Выход»
#   MOVING         → камера плавно переезжает (кнопок нет)
#   STAGE          → на сцене последний созданный персонаж (если есть);
#                    «Выбрать», «Удалить», «Создать персонажа»
#   CHOOSE_BODY    → на сцене два тела рядом, выбираешь мужское или женское
#   EDITING        → камера приближена к выбранному телу: имя, цвет кожи, причёска
#   MODE_SELECT    → одиночная игра или мультиплеер
#   WORLD_SELECT   → выбор/создание мира перед одиночным хабом
#   CONFIRM_DELETE → подтверждение удаления
#
# Модели и применение внешности — в character_models.gd.
extends Node3D

const SOLO_SCENE  := "res://screens/hub/ui/hub.tscn"
const LOBBY_SCENE := "res://features/steam-lobby/ui/lobby_menu.tscn"
const OPTIONS_SCENE := "res://screens/options/ui/options.tscn"
const MainMenuWorld := preload("res://screens/main-menu/ui/components/main_menu_world.gd")
const MainMenuViewBuilder := preload("res://screens/main-menu/ui/components/main_menu_view_builder.gd")

const NAME_MAX_LENGTH := 24

const STAGE_FLOOR_Y := 0.1  # верх постамента: на этой высоте стоят ноги фигур

enum State { TITLE, MOVING, STAGE, CHOOSE_BODY, EDITING, MODE_SELECT, WORLD_SELECT, CONFIRM_DELETE }

# Сцена игрока (корень с player.gd и всеми компонентами). Перетащи её сюда
# в инспекторе: так она используется для любого созданного персонажа.
# Модель внутри неё подменяется моделью персонажа при спавне (см. player.gd).
@export var hero_scene: PackedScene
@export var start_in_character_editor: bool = false
@export_file("*.tscn") var return_scene_after_character_select: String = ""

@export var game_title: String = "Lunacy"
@export var title_camera_position: Vector3 = Vector3(0.0, 1.8, 7.0)
@export var stage_camera_position: Vector3 = Vector3(-10.0, 1.6, 4.0)
@export var stage_center: Vector3 = Vector3(-10.0, 0.0, 0.0)
# Положение камеры при редактировании относительно выбранной фигуры.
# Смещение по X сдвигает фигуру влево от центра, чтобы её не закрывала панель.
@export var edit_camera_offset: Vector3 = Vector3(0.9, 1.25, 2.4)
@export var figure_spacing: float = 3.4
@export var camera_pitch_degrees: float = -6.0
@export var camera_move_time: float = 1.4
@export var figure_spin_speed: float = 0.6

var _state: State = State.TITLE
var _world_view := MainMenuWorld.new()
var _view_builder := MainMenuViewBuilder.new()

var _camera: Camera3D
var _figures: Dictionary = {}   # id тела → Node3D (позиция и вращение)
var _models: Dictionary = {}    # id тела → Node3D (сама модель внутри фигуры)

var _title_ui: Control
var _stage_ui: Control
var _edit_ui: Control
var _mode_ui: Control
var _world_ui: Control
var _confirm_ui: Control

var _character_label: Label
var _back_button: Button
var _select_button: Button
var _delete_button: Button
var _create_button: Button
var _cancel_choice_button: Button
var _body_buttons: Array[Button] = []
var _confirm_label: Label

var _name_input: LineEdit
var _error_label: Label
var _color_picker: ColorPickerButton
var _hair_container: GridContainer
var _hair_buttons: Array[Button] = []

var _solo_button: Button
var _multiplayer_button: Button

var _world_list: VBoxContainer
var _world_name_input: LineEdit
var _world_error_label: Label
var _world_start_button: Button
var _selected_world_name: String = ""

var _last_character: Dictionary = {}

var _edit_body: String = CharacterModels.DEFAULT_BODY
var _edit_skin: Color = Color.html(CharacterModels.DEFAULT_SKIN)
var _edit_hair: int = 0

var _skin_swatches: Array[Color] = [
	Color8(255, 224, 196),
	Color8(241, 194, 125),
	Color8(224, 172, 105),
	Color8(198, 134, 66),
	Color8(141, 85, 36),
	Color8(104, 66, 38),
	Color8(84, 52, 30),
	Color8(60, 38, 24),
	Color8(125, 85, 170),
	Color8(175, 130, 205),
	Color8(70, 105, 145),
	Color8(75, 135, 65),
	Color8(125, 160, 85),
	Color8(170, 65, 55),
	Color8(115, 40, 45),
]


# ════════════════════════════════════════════════════════
# READY
# ════════════════════════════════════════════════════════
func _ready() -> void:
	# Предыдущая сцена (миссия) могла оставить мышь захваченной камерой
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if hero_scene != null:
		SaveManager.default_hero_scene = hero_scene.resource_path
	elif SaveManager.default_hero_scene.is_empty():
		push_warning("main_menu: не задан Hero Scene — «Одиночная игра» будет недоступна. Перетащи сцену игрока в инспекторе корневого узла меню.")

	_world_view.build(self)
	_view_builder.build(self)
	if start_in_character_editor:
		_camera.position = stage_camera_position
		_show_stage()
	else:
		_set_state(State.TITLE)


func _process(delta: float) -> void:
	# Крутим фигуры только в показе и редактировании; при выборе тела
	# они стоят лицом к камере
	if _state != State.STAGE and _state != State.EDITING:
		return
	for body_id in _figures:
		var figure: Node3D = _figures[body_id]
		if figure.visible:
			figure.rotate_y(figure_spin_speed * delta)


func _place_figure(body_id: String, x_offset: float) -> void:
	_world_view.place_figure(body_id, x_offset)


func _hide_all_figures() -> void:
	_world_view.hide_all_figures()


func _body_id_of(appearance: Dictionary) -> String:
	return _world_view.body_id_of(appearance)


func _make_label(text: String, font_size: int = 18) -> Label:
	return _view_builder.make_label(text, font_size)


# ════════════════════════════════════════════════════════
# СОСТОЯНИЯ И ПЕРЕХОДЫ МЕНЮ
# ════════════════════════════════════════════════════════
func _set_state(new_state: State) -> void:
	_state = new_state
	_title_ui.visible   = new_state == State.TITLE
	_stage_ui.visible   = new_state == State.STAGE or new_state == State.CHOOSE_BODY
	_edit_ui.visible    = new_state == State.EDITING
	_mode_ui.visible    = new_state == State.MODE_SELECT
	_world_ui.visible   = new_state == State.WORLD_SELECT
	_confirm_ui.visible = new_state == State.CONFIRM_DELETE


# Какие кнопки нижней панели показывать: обычные или выбор тела
func _set_bar_mode(has_character: bool, choosing: bool) -> void:
	_back_button.visible          = not choosing
	_select_button.visible        = has_character and not choosing
	_delete_button.visible        = has_character and not choosing
	_create_button.visible        = not choosing
	_cancel_choice_button.visible = choosing
	for body_button in _body_buttons:
		body_button.visible = choosing


func _move_camera(target: Vector3) -> void:
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_camera, "position", target, camera_move_time)
	await tween.finished


# Экран с постаментом: последний созданный персонаж по центру или пустой постамент
func _show_stage() -> void:

	_last_character = SaveManager.get_last_character()
	var has_character: bool = not _last_character.is_empty()

	_hide_all_figures()

	if has_character:
		var appearance: Dictionary = _last_character.get("appearance", {})
		var body_id: String = _body_id_of(appearance)
		var model: Node3D = _models[body_id]
		CharacterModels.apply_appearance(model, appearance)
		_place_figure(body_id, 0.0)
		var figure: Node3D = _figures[body_id]
		figure.visible = true
		_character_label.text = str(_last_character.get("character_name", ""))
	else:
		_character_label.text = ""

	_create_button.text = "Создать нового" if has_character else "Создать персонажа"
	_set_bar_mode(has_character, false)
	_set_state(State.STAGE)


# Оба тела рядом, слева направо в порядке BODY_TYPES
func _show_choose_body() -> void:

	_hide_all_figures()

	var count: int = CharacterModels.BODY_TYPES.size()
	for index in range(count):
		var body_def: Dictionary = CharacterModels.BODY_TYPES[index]
		var body_id: String = str(body_def["id"])

		var preview: Dictionary = {
			"body": body_id,
			"skin": CharacterModels.DEFAULT_SKIN,
			"hair": 1,
		}
		var model: Node3D = _models[body_id]
		CharacterModels.apply_appearance(model, preview)

		_place_figure(body_id, (index - (count - 1) * 0.5) * figure_spacing)
		var figure: Node3D = _figures[body_id]
		figure.visible = true

	_character_label.text = "Выбери модель"
	_set_bar_mode(false, true)
	_set_state(State.CHOOSE_BODY)


# Камера уже рядом с выбранной фигурой — готовим редактор
func _begin_editing() -> void:

	_edit_skin = Color.html(CharacterModels.DEFAULT_SKIN)
	_color_picker.color = _edit_skin
	_name_input.text = ""
	_error_label.visible = false

	_rebuild_hair_buttons()
	# Первая причёска, если она есть: фигура сразу выглядит живее
	_edit_hair = 1 if _hair_buttons.size() > 1 else 0
	_refresh_hair_buttons()
	_apply_edit_preview()

	_set_state(State.EDITING)
	_name_input.grab_focus()


# ════════════════════════════════════════════════════════
# ОБРАБОТЧИКИ КНОПОК
# ════════════════════════════════════════════════════════
func _on_play_pressed() -> void:
	if _state != State.TITLE:
		return
	_set_state(State.MOVING)
	await _move_camera(stage_camera_position)
	_show_stage()


func _on_options_pressed() -> void:
	if _state != State.TITLE:
		return
	get_tree().change_scene_to_file(OPTIONS_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_back_pressed() -> void:
	if _state != State.STAGE:
		return
	if start_in_character_editor and not return_scene_after_character_select.is_empty():
		_leave_character_editor()
		return
	_hide_all_figures()
	_set_state(State.MOVING)
	await _move_camera(title_camera_position)
	_set_state(State.TITLE)


func _on_create_pressed() -> void:
	if _state != State.STAGE:
		return
	_show_choose_body()


func _on_cancel_choice_pressed() -> void:
	if _state != State.CHOOSE_BODY:
		return
	_show_stage()


# Выбрали тело: камера приближается к нему, затем открывается редактор
func _on_body_chosen(body_id: String) -> void:

	if _state != State.CHOOSE_BODY:
		return

	_edit_body = body_id
	_set_state(State.MOVING)

	var chosen: Node3D = _figures[body_id]
	await _move_camera(chosen.position + edit_camera_offset)

	# Второе тело больше не нужно
	for other_id in _figures:
		if str(other_id) != body_id:
			var other: Node3D = _figures[other_id]
			other.visible = false

	_begin_editing()


# Отмена в редакторе: камера отъезжает, снова выбор тела
func _on_cancel_edit_pressed() -> void:
	if _state != State.EDITING:
		return
	_set_state(State.MOVING)
	await _move_camera(stage_camera_position)
	_show_choose_body()


func _on_save_pressed() -> void:

	if _state != State.EDITING:
		return

	var character_name: String = _name_input.text.strip_edges()
	if character_name.is_empty():
		_show_error("Введи имя персонажа")
		return

	var appearance: Dictionary = {
		"body": _edit_body,
		"skin": _edit_skin.to_html(false),
		"hair": _edit_hair,
	}

	if not SaveManager.create_character(character_name, appearance):
		_show_error("Не удалось сохранить персонажа")
		return

	# Камера возвращается, на постаменте стоит новый персонаж и есть «Выбрать»
	_set_state(State.MOVING)
	await _move_camera(stage_camera_position)
	_show_stage()


func _on_select_pressed() -> void:

	if _state != State.STAGE or _last_character.is_empty():
		return

	SaveManager.select_save(_last_character)
	if start_in_character_editor and not return_scene_after_character_select.is_empty():
		_leave_character_editor()
		return

	# Без сцены героя хаб останется пустым — лучше сказать об этом сразу
	var hero_ready: bool = SaveManager.has_valid_hero_scene()
	var hero_hint: String = "Не задана сцена героя: перетащи сцену игрока в поле Hero Scene у корневого узла меню."

	_solo_button.disabled = not hero_ready
	_solo_button.tooltip_text = "" if hero_ready else hero_hint

	var steam_ready: bool = SteamLobby.is_steam_ready()
	_multiplayer_button.disabled = not (steam_ready and hero_ready)
	if not hero_ready:
		_multiplayer_button.tooltip_text = hero_hint
	elif not steam_ready:
		_multiplayer_button.tooltip_text = "Steam недоступен. Запусти Steam, залогинься и перезапусти игру."
	else:
		_multiplayer_button.tooltip_text = ""

	_set_state(State.MODE_SELECT)


func _leave_character_editor() -> void:
	if SteamLobby.is_session_active():
		SteamLobby.request_scene_change(return_scene_after_character_select)
	else:
		get_tree().change_scene_to_file(return_scene_after_character_select)


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
	_selected_world_name = ""
	_world_name_input.text = ""
	_world_error_label.visible = false
	_refresh_world_list()
	_set_state(State.WORLD_SELECT)


func _on_multiplayer_pressed() -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_mode_back_pressed() -> void:
	if _state != State.MODE_SELECT:
		return
	_set_state(State.STAGE)


func _refresh_world_list() -> void:
	for child in _world_list.get_children():
		child.queue_free()

	var worlds := SaveManager.list_worlds()
	if worlds.is_empty():
		var empty_label := _make_label("Нет сохранённых миров", 17)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_world_list.add_child(empty_label)

	for raw_info in worlds:
		var info: Dictionary = raw_info
		var world_name := str(info.get("name", "Мир"))
		var button := Button.new()
		button.text = world_name
		button.toggle_mode = true
		button.button_pressed = world_name == _selected_world_name
		button.custom_minimum_size = Vector2(0.0, 42.0)
		button.pressed.connect(func(): _on_world_selected(info))
		_world_list.add_child(button)

	_world_start_button.disabled = _selected_world_name.is_empty()


func _on_world_selected(info: Dictionary) -> void:
	_selected_world_name = str(info.get("name", ""))
	SaveManager.select_world(info)
	_world_error_label.visible = false
	_refresh_world_list()


func _on_world_create_pressed() -> void:
	var world_name := _world_name_input.text.strip_edges()
	if world_name.is_empty():
		_show_world_error("Введи название мира")
		return
	if not SaveManager.create_world(world_name):
		_show_world_error("Мир с таким именем уже существует")
		return
	_selected_world_name = SaveManager.get_active_world_name()
	_world_name_input.text = ""
	_world_error_label.visible = false
	_refresh_world_list()


func _show_world_error(message: String) -> void:
	_world_error_label.text = message
	_world_error_label.visible = true


func _on_world_start_pressed() -> void:
	if _selected_world_name.is_empty():
		return
	SaveManager.select_world(_selected_world_name)
	# Гарантируем, что файл мира существует, и не затрагиваем файл персонажа.
	SaveManager.save_world_progress(SaveManager.load_world_progress())
	get_tree().change_scene_to_file(SOLO_SCENE)


func _on_world_back_pressed() -> void:
	_set_state(State.MODE_SELECT)


# ── Редактор внешности ───────────────────────────────────
func _apply_edit_preview() -> void:
	var model: Node3D = _models[_edit_body]
	CharacterModels.apply_appearance(model, {
		"body": _edit_body,
		"skin": _edit_skin.to_html(false),
		"hair": _edit_hair,
	})


# update_picker == false, когда цвет пришёл из самого пикера —
# иначе мы бы заново выставляли ему тот же цвет.
func _set_edit_skin(color: Color, update_picker: bool) -> void:
	_edit_skin = color
	if update_picker:
		_color_picker.color = color
	_apply_edit_preview()


func _on_custom_skin_changed(color: Color) -> void:
	_set_edit_skin(color, false)


func _set_edit_hair(index: int) -> void:
	_edit_hair = index
	_apply_edit_preview()


# Кнопки причёсок под выбранное тело: «Без причёски» + по кнопке на каждую
# причёску модели (имя берётся из имени узла в Hair)
func _rebuild_hair_buttons() -> void:

	for child in _hair_container.get_children():
		_hair_container.remove_child(child)
		child.queue_free()
	_hair_buttons.clear()

	var model: Node3D = _models[_edit_body]
	var labels: Array[String] = ["Без причёски"]
	labels.append_array(CharacterModels.hair_names(model))

	var group := ButtonGroup.new()
	for i in range(labels.size()):
		var hair_button := Button.new()
		hair_button.text = labels[i]
		hair_button.toggle_mode = true
		hair_button.button_group = group
		hair_button.custom_minimum_size = Vector2(140.0, 34.0)
		hair_button.pressed.connect(func(): _set_edit_hair(i))
		_hair_container.add_child(hair_button)
		_hair_buttons.append(hair_button)


func _refresh_hair_buttons() -> void:
	for i in range(_hair_buttons.size()):
		_hair_buttons[i].button_pressed = (i == _edit_hair)


func _show_error(text: String) -> void:
	_error_label.text = text
	_error_label.visible = true
