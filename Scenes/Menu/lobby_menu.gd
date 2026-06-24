# lobby_menu.gd
# Главное меню с Host/Join + панель лобби: код, выбор героя,
# список игроков под ним, и выбор/создание сохранения.
extends Control

@onready var main_menu_panel: Panel        = $MainMenuPanel
@onready var host_button: Button           = $MainMenuPanel/VBox/HostButton
@onready var id_prompt: LineEdit           = $MainMenuPanel/VBox/JoinRow/id_prompt
@onready var join_button: Button           = $MainMenuPanel/VBox/JoinRow/JoinButton

@onready var lobby_panel: Control          = $LobbyPanel
@onready var code_label: Label             = $LobbyPanel/LobbyCodeBox/HBox/CodeLabel
@onready var copy_button: Button           = $LobbyPanel/LobbyCodeBox/HBox/CopyButton

@onready var nickname_label: Label         = $LobbyPanel/HeroSelectBox/VBox/NicknameLabel
@onready var hero_name_label: Label        = $LobbyPanel/HeroSelectBox/VBox/HeroNameLabel
@onready var hero_grid: GridContainer      = $LobbyPanel/HeroSelectBox/VBox/HeroGrid

# Список игроков — под выбором героя
@onready var players_list: VBoxContainer   = $LobbyPanel/HeroSelectBox/VBox/PlayersList

@onready var save_label: Label             = $LobbyPanel/SaveInfoBox/VBox/SaveLabel
@onready var save_select_button: Button    = $LobbyPanel/SaveInfoBox/VBox/SaveButtons/SelectSaveButton
@onready var save_new_button: Button       = $LobbyPanel/SaveInfoBox/VBox/SaveButtons/NewSaveButton

@onready var ready_button: Button          = $LobbyPanel/ReadyButton

# Окно выбора сохранения (отдельная всплывающая панель)
@onready var save_picker: PopupPanel       = $SavePickerPopup
@onready var save_picker_list: VBoxContainer = $SavePickerPopup/VBox/SaveListContainer
@onready var save_name_input: LineEdit     = $SavePickerPopup/VBox/NewSaveRow/NameInput
@onready var save_create_button: Button    = $SavePickerPopup/VBox/NewSaveRow/CreateButton

@onready var steam_lobby = $SteamLobby

var _hero_buttons: Dictionary = {}  # id → Button


# ════════════════════════════════════════════════════════
# READY
# ════════════════════════════════════════════════════════
func _ready() -> void:

	lobby_panel.visible = false
	save_picker.visible = false

	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	copy_button.pressed.connect(_on_copy_pressed)
	save_select_button.pressed.connect(_open_save_picker)
	save_new_button.pressed.connect(_open_save_picker)
	save_create_button.pressed.connect(_on_create_save_pressed)

	_populate_hero_grid()
	_update_save_label()
	_update_nickname_label()
	_clear_players_list()

	if steam_lobby:
		steam_lobby.lobby_ready.connect(_on_lobby_ready)
		steam_lobby.players_updated.connect(_on_players_updated)


# ════════════════════════════════════════════════════════
# HOST / JOIN
# ════════════════════════════════════════════════════════
func _on_host_pressed() -> void:
	steam_lobby.host_lobby()


func _on_join_pressed() -> void:
	var code := id_prompt.text.to_int()
	if code == 0:
		push_warning("lobby_menu: введите корректный код лобби")
		return
	steam_lobby.join_lobby(code)


func _on_lobby_ready(lobby_id: int) -> void:
	main_menu_panel.visible = false
	lobby_panel.visible = true
	code_label.text = "Код лобби: %d" % lobby_id

	# Кнопки выбора сохранения — только для хоста
	var is_host: bool = multiplayer.is_server()
	save_select_button.visible = is_host
	save_new_button.visible = is_host
	save_label.visible = is_host


# ════════════════════════════════════════════════════════
# КОПИРОВАНИЕ КОДА
# ════════════════════════════════════════════════════════
func _on_copy_pressed() -> void:
	var code_text := code_label.text.replace("Код лобби: ", "")
	DisplayServer.clipboard_set(code_text)
	copy_button.text = "Скопировано!"
	await get_tree().create_timer(1.2).timeout
	copy_button.text = "Копировать"


# ════════════════════════════════════════════════════════
# ВЫБОР ГЕРОЯ
# ════════════════════════════════════════════════════════
func _populate_hero_grid() -> void:

	for child in hero_grid.get_children():
		child.queue_free()
	_hero_buttons.clear()

	for hero in HeroLibrary.all_heroes():
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(48, 48)
		btn.tooltip_text = hero.hero_name

		var icon := TextureRect.new()
		icon.texture = hero.icon
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		btn.add_child(icon)

		btn.pressed.connect(func(): _on_hero_selected(hero))
		hero_grid.add_child(btn)
		_hero_buttons[hero.id] = btn

	_refresh_hero_selection_highlight()


func _on_hero_selected(hero: HeroDefinition) -> void:

	PlayerProfile.hero_scene = hero.scene.resource_path
	hero_name_label.text = hero.hero_name
	_refresh_hero_selection_highlight()

	# Сообщить хосту/остальным что герой сменился
	if steam_lobby and steam_lobby.peer != null:
		steam_lobby.notify_hero_changed()

	print("lobby_menu: выбран герой '%s'" % hero.id)


func _refresh_hero_selection_highlight() -> void:

	for id in _hero_buttons:
		var btn: Button = _hero_buttons[id]
		var hero: HeroDefinition = HeroLibrary.get_hero(id)
		var selected := hero != null and hero.scene.resource_path == PlayerProfile.hero_scene
		btn.modulate = Color.WHITE if selected else Color(0.6, 0.6, 0.6, 1.0)

		if selected:
			hero_name_label.text = hero.hero_name


# ════════════════════════════════════════════════════════
# СПИСОК ИГРОКОВ В ЛОББИ
# Вызывается сигналом players_updated(players: Array)
# где players = [{ peer_id, nickname, hero_scene }, ...]
# ════════════════════════════════════════════════════════
func _on_players_updated(players: Array) -> void:

	_clear_players_list()

	for info in players:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 32)

		# Иконка героя
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(28, 28)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

		var hero_scene_path: String = info.get("hero_scene", "")
		var hero_def := _find_hero_by_scene_path(hero_scene_path)
		icon.texture = hero_def.icon if hero_def else null
		row.add_child(icon)

		# Ник
		var label := Label.new()
		var nick: String = info.get("nickname", "Игрок")
		var hero_label := hero_def.hero_name if hero_def else "не выбран"
		label.text = "%s — %s" % [nick, hero_label]
		row.add_child(label)

		players_list.add_child(row)


func _find_hero_by_scene_path(path: String) -> HeroDefinition:
	if path.is_empty():
		return null
	for hero in HeroLibrary.all_heroes():
		if hero.scene and hero.scene.resource_path == path:
			return hero
	return null


func _clear_players_list() -> void:
	for child in players_list.get_children():
		child.queue_free()


# ════════════════════════════════════════════════════════
# НИК
# ════════════════════════════════════════════════════════
func _update_nickname_label() -> void:
	nickname_label.text = Steam.getPersonaName()


# ════════════════════════════════════════════════════════
# СОХРАНЕНИЯ — выбор существующего / создание нового
# ════════════════════════════════════════════════════════
func _update_save_label() -> void:
	save_label.text = "Сохранение: %s" % SaveManager.get_active_save_name()


func _open_save_picker() -> void:

	for child in save_picker_list.get_children():
		child.queue_free()

	for info in SaveManager.list_saves():
		var btn := Button.new()
		btn.text = info["name"]
		btn.custom_minimum_size = Vector2(0, 32)
		btn.pressed.connect(func(): _on_save_selected(info))
		save_picker_list.add_child(btn)

	save_name_input.text = ""
	save_picker.popup_centered(Vector2i(280, 320))


func _on_save_selected(info: Dictionary) -> void:

	SaveManager.select_save(info)
	_update_save_label()
	_populate_hero_grid()  # перерисовать выбор героя из загруженного профиля
	save_picker.hide()


func _on_create_save_pressed() -> void:

	var save_name := save_name_input.text.strip_edges()
	if save_name.is_empty():
		push_warning("lobby_menu: введите имя для нового сохранения")
		return

	if not SaveManager.create_named_save(save_name):
		return

	_update_save_label()
	_populate_hero_grid()
	save_picker.hide()
