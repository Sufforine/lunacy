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
@onready var save_picker_list: VBoxContainer = $SavePickerPopup/VBox/ScrollContainer/SaveListContainer
@onready var save_name_input: LineEdit     = $SavePickerPopup/VBox/NewSaveRow/NameInput
@onready var save_create_button: Button    = $SavePickerPopup/VBox/NewSaveRow/CreateButton

@onready var steam_lobby = SteamLobby




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
	_update_nickname_label()
	_clear_players_list()

	if steam_lobby:
		steam_lobby.lobby_ready.connect(_on_lobby_ready)
		steam_lobby.lobby_failed.connect(_on_lobby_failed)
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
# где players = [{ peer_id, nickname, hero_scene }, ...]
#
# TODO: сейчас показывается только Steam-ник. Чтобы показать реальное
# имя персонажа (character_name) других игроков, нужно чтобы оно тоже
# передавалось по сети — добавь его в payload рядом с nickname там,
# где сервер формирует список игроков.
# ════════════════════════════════════════════════════════
func _on_players_updated(players: Array) -> void:

	_clear_players_list()

	for info in players:
		var label := Label.new()
		var nick: String = info.get("nickname", "Игрок")
		var character_name: String = info.get("character_name", "")
		label.text = "%s — %s" % [nick, character_name] if not character_name.is_empty() else nick
		players_list.add_child(label)


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
