extends Control

@onready var host_game_button: Button = $VBoxContainer/HostGame


func _ready() -> void:
	# SteamLobby — автозагрузка, уже успела отработать свой _ready() к этому моменту
	SteamLobby.lobby_failed.connect(_on_steam_failed)

	# Если Steam не инициализировался ДО того как мы подписались
	# (например меню открыли не первым экраном), проверяем явно
	if not SteamLobby.is_steam_ready():
		_on_steam_failed("")


func _on_steam_failed(_reason: String) -> void:
	if host_game_button:
		host_game_button.disabled = true
		host_game_button.tooltip_text = "Steam недоступен. Запусти Steam, залогинься и перезапусти игру."


func _on_debug_pressed() -> void:
	get_tree().change_scene_to_file("res://screens/mission/ui/mission.tscn")


# Соло-старт — никакого Steam и мультиплеера, просто смена сцены
func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://screens/character-select/ui/character_select.tscn")


func _on_host_game_pressed() -> void:
	get_tree().change_scene_to_file("res://features/steam-lobby/ui/lobby_menu.tscn")
