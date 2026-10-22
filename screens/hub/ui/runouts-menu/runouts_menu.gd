extends Control

signal mission_selected
var _player: Player
var _input_enabled := true
var _inventory_input_enabled := true

func _ready() -> void:
	add_to_group("mission_selection")
	for node in get_tree().get_nodes_in_group("player"):
		if node is Player and node.is_multiplayer_authority():
			_player = node
			_input_enabled = node.is_processing_input()
			_inventory_input_enabled = node.inventory_ui.is_processing_input()
			node.set_process_input(false)
			node.inventory_ui.set_process_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("esc"):
		get_viewport().set_input_as_handled()
		close()


func select_mission() -> void:
	mission_selected.emit()
	close()


func close() -> void:
	if is_instance_valid(_player):
		_player.set_process_input(_input_enabled)
		_player.inventory_ui.set_process_input(_inventory_input_enabled)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_parent().queue_free()
