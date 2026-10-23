extends Node3D

var _dialog: ConfirmationDialog
var _player: Player
var _player_input := true
var _inventory_input := true
var _mouse_mode: int

func _ready() -> void:
	add_to_group("hub_interactable")

func interact(player: Player) -> void:
	if is_instance_valid(_dialog) or SteamLobby.is_gameplay_locked():
		return
	_player = player
	_player_input = player.is_processing_input()
	_inventory_input = player.inventory_ui.is_processing_input()
	_mouse_mode = Input.mouse_mode
	player.set_process_input(false)
	player.inventory_ui.set_process_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_dialog = ConfirmationDialog.new()
	_dialog.title = "Выход из подземелья"
	_dialog.dialog_text = "Вы действительно хотите выйти в главное меню?"
	if SteamLobby.is_session_active() and multiplayer.is_server():
		_dialog.dialog_text += "\nВы хост — сессия завершится для всех игроков."
	_dialog.ok_button_text = "Выйти"
	_dialog.cancel_button_text = "Остаться"
	add_child(_dialog)
	_dialog.confirmed.connect(_confirm)
	_dialog.canceled.connect(_cancel)
	_dialog.popup_centered(Vector2i(480, 160))

func _cancel() -> void:
	if is_instance_valid(_player):
		_player.set_process_input(_player_input)
		_player.inventory_ui.set_process_input(_inventory_input)
	Input.mouse_mode = _mouse_mode
	_dialog.hide()
	_dialog.queue_free()
	_dialog = null

func _confirm() -> void:
	if is_instance_valid(_player) and _player.inventory.network_pending:
		_dialog.dialog_text = "Дождитесь завершения операции с инвентарём."
		_dialog.popup_centered()
		return
	if is_instance_valid(_player) and not SaveManager.save_player_state(_player.inventory, _player.equipment):
		_dialog.dialog_text = "Не удалось сохранить персонажа. Выход отменён."
		_dialog.popup_centered()
		return
	SteamLobby.leave_to_main_menu()
