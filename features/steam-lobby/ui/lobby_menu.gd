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
@onready var save_picker_list: VBoxContainer = $SavePickerPopup/VBox/ScrollContainer/SaveListContainer
@onready var save_name_input: LineEdit     = $SavePickerPopup/VBox/NewSaveRow/NameInput
@onready var save_create_button: Button    = $SavePickerPopup/VBox/NewSaveRow/CreateButton

@onready var steam_lobby = SteamLobby

var _avatar_cache: Dictionary = {}
var _avatar_targets: Dictionary = {}
var _avatar_placeholder: ImageTexture



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

	_refresh_character_label()
	_update_save_label()
	_clear_players_list()
	_avatar_placeholder = _make_avatar_placeholder()

	if steam_lobby:
		steam_lobby.lobby_ready.connect(_on_lobby_ready)
		steam_lobby.lobby_failed.connect(_on_lobby_failed)
		steam_lobby.players_updated.connect(_on_players_updated)
	if not Steam.avatar_loaded.is_connected(_on_avatar_loaded):
		Steam.avatar_loaded.connect(_on_avatar_loaded)


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

	var is_host: bool = multiplayer.is_server()

	# Кнопки выбора сохранения — только для хоста
	save_select_button.visible = is_host
	save_new_button.visible = is_host
	save_label.visible = is_host

	# Кнопка старта — только для хоста
	ready_button.visible = is_host
	if is_host:
		ready_button.text = "Старт"
		ready_button.pressed.connect(_on_start_pressed)


func _on_lobby_failed(reason: String) -> void:
	push_warning("lobby_menu: %s" % reason)
	host_button.disabled = false
	join_button.disabled = false


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
# ПЕРСОНАЖ
# Заранее готовых героев больше нет — персонаж создаётся и выбирается
# заранее в главном меню (SaveManager.create_character / select_save).
# Здесь просто показываем кто уже выбран, без возможности сменить.
# ════════════════════════════════════════════════════════
func _refresh_character_label() -> void:

	if hero_grid:
		hero_grid.visible = false

	if PlayerProfile.character_name.is_empty():
		hero_name_label.text = "Персонаж не выбран — вернись в меню"
	else:
		hero_name_label.text = PlayerProfile.character_name


# ════════════════════════════════════════════════════════
# СПИСОК ИГРОКОВ В ЛОББИ
# Вызывается сигналом players_updated(players: Array)
# где players = [{ peer_id, steam_id, nickname, character_name, ... }, ...]
# ════════════════════════════════════════════════════════
func _on_players_updated(players: Array) -> void:

	_clear_players_list()
	_avatar_targets.clear()

	for info in players:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0.0, 68.0)
		row.add_theme_constant_override("separation", 12)
		players_list.add_child(row)

		var avatar := TextureRect.new()
		avatar.custom_minimum_size = Vector2(64.0, 64.0)
		avatar.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		avatar.texture = _avatar_placeholder
		row.add_child(avatar)

		var names := VBoxContainer.new()
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		names.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(names)

		var nick: String = info.get("nickname", "Игрок")
		var character_name: String = info.get("character_name", "")
		var nickname := Label.new()
		nickname.text = nick
		nickname.add_theme_font_size_override("font_size", 18)
		names.add_child(nickname)

		if not character_name.is_empty():
			var character := Label.new()
			character.text = character_name
			character.modulate = Color(0.72, 0.76, 0.84)
			names.add_child(character)

		var steam_id := int(info.get("steam_id", 0))
		_set_or_request_avatar(steam_id, avatar)


func _clear_players_list() -> void:
	for child in players_list.get_children():
		child.queue_free()


func _set_or_request_avatar(steam_id: int, target: TextureRect) -> void:
	if steam_id <= 0:
		return
	if _avatar_cache.has(steam_id):
		target.texture = _avatar_cache[steam_id]
		return

	if not _avatar_targets.has(steam_id):
		_avatar_targets[steam_id] = []
	var targets: Array = _avatar_targets[steam_id]
	targets.append(target)
	Steam.getPlayerAvatar(Steam.AVATAR_MEDIUM, steam_id)


func _on_avatar_loaded(steam_id: int, avatar_size: int, avatar_data: PackedByteArray) -> void:
	if avatar_size <= 0 or avatar_data.is_empty():
		return
	var image := Image.create_from_data(
		avatar_size,
		avatar_size,
		false,
		Image.FORMAT_RGBA8,
		avatar_data
	)
	if image == null or image.is_empty():
		return

	var texture := ImageTexture.create_from_image(image)
	_avatar_cache[steam_id] = texture
	if not _avatar_targets.has(steam_id):
		return
	for target in _avatar_targets[steam_id]:
		if is_instance_valid(target):
			target.texture = texture
	_avatar_targets.erase(steam_id)


func _make_avatar_placeholder() -> ImageTexture:
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.23, 0.29, 1.0))
	return ImageTexture.create_from_image(image)


# ════════════════════════════════════════════════════════
# СОХРАНЕНИЯ — выбор существующего / создание нового
# ════════════════════════════════════════════════════════
func _update_save_label() -> void:
	save_label.text = "Мир: %s" % SaveManager.get_active_world_name()


func _open_save_picker() -> void:

	for child in save_picker_list.get_children():
		child.queue_free()

	for info in SaveManager.list_worlds():
		var btn := Button.new()
		btn.text = info["name"]
		btn.custom_minimum_size = Vector2(0, 32)
		btn.pressed.connect(func(): _on_save_selected(info))
		save_picker_list.add_child(btn)

	save_name_input.text = ""
	save_picker.popup_centered(Vector2i(280, 320))


func _on_save_selected(info: Dictionary) -> void:

	SaveManager.select_world(info)
	_update_save_label()
	save_picker.hide()


func _on_create_save_pressed() -> void:

	var save_name := save_name_input.text.strip_edges()
	if save_name.is_empty():
		push_warning("lobby_menu: введите имя для нового сохранения")
		return

	if not SaveManager.create_world(save_name):
		return

	_update_save_label()
	save_picker.hide()


# ════════════════════════════════════════════════════════
# СТАРТ — только хост
# ════════════════════════════════════════════════════════
func _on_start_pressed() -> void:

	if not multiplayer.is_server():
		return

	# Проверить что хост выбрал героя
	if PlayerProfile.hero_scene.is_empty():
		push_warning("lobby_menu: хост не выбрал героя")
		# TODO: показать сообщение об ошибке в UI
		return

	ready_button.disabled = true
	SteamLobby.start_game()
