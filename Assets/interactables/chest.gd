extends StaticBody3D

signal contents_changed

const SLOT_COUNT := 12
const INTERACTION_DISTANCE := 3.5

@export var chest_id: String = "hub_main_chest"

@onready var lid: Node3D = $Lid
@onready var glow_ring: MeshInstance3D = $GlowRing

var slots: Array[ItemData] = []
var _hub: Node = null
var _focus_tween: Tween = null
var _lid_tween: Tween = null


func _ready() -> void:
	add_to_group("hub_interactable")
	add_to_group("world_state_consumer")
	slots.resize(SLOT_COUNT)
	for index in SLOT_COUNT:
		slots[index] = null
	glow_ring.visible = false
	_hub = get_parent()
	if _hub != null and _hub.has_method("get_world_progress"):
		apply_world_progress(_hub.call("get_world_progress"))


func _process(_delta: float) -> void:
	var player := _local_player()
	if player == null or player.inventory_ui == null:
		return
	if player.inventory_ui.is_chest_open(self) and (not _player_is_close(player) or player.stats.is_dead or player.stats.is_downed):
		player.inventory_ui.close_chest()


func interact(player: Player) -> void:
	if player == null or player.inventory_ui == null:
		return
	player.inventory_ui.open_chest(self)
	set_open_visual(true)


func set_interaction_focus(focused: bool) -> void:
	if _focus_tween != null:
		_focus_tween.kill()
	if focused:
		glow_ring.visible = true
		_focus_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		_focus_tween.tween_property(glow_ring, "scale", Vector3(1.15, 0.08, 0.8), 0.18)
	else:
		_focus_tween = create_tween().set_ease(Tween.EASE_IN)
		_focus_tween.tween_property(glow_ring, "scale", Vector3(1.0, 0.0, 0.7), 0.1)
		_focus_tween.tween_callback(func() -> void: glow_ring.visible = false)


func set_open_visual(opened: bool) -> void:
	if _lid_tween != null:
		_lid_tween.kill()
	_lid_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_lid_tween.tween_property(lid, "rotation_degrees:x", -72.0 if opened else 0.0, 0.22)


func get_item(slot_index: int) -> ItemData:
	if slot_index < 0 or slot_index >= SLOT_COUNT:
		return null
	return slots[slot_index]


func get_data() -> Array:
	var data: Array = []
	for item in slots:
		data.append(item.id if item != null else "")
	return data


func apply_world_progress(progress: Dictionary) -> void:
	var chests: Variant = progress.get("chests", {})
	if not chests is Dictionary:
		return
	var saved_slots: Variant = (chests as Dictionary).get(chest_id, [])
	if saved_slots is Array:
		_set_data(saved_slots)


func request_transfer_from_player(slot_index: int, inventory: InventoryComponent) -> void:
	if SteamLobby.is_session_active():
		inventory.network_request({"kind": "chest_put", "index": slot_index, "chest": str(get_path())})
		return
	if inventory == null:
		return
	var item := inventory.get_item(slot_index)
	if item == null:
		return
	var inventory_data := inventory.get_data()
	_server_transfer_from_player(multiplayer.get_unique_id(), slot_index, item.id, inventory_data)


func request_transfer_to_player(slot_index: int, inventory: InventoryComponent) -> void:
	if SteamLobby.is_session_active():
		var item := get_item(slot_index)
		if item == null:
			return
		inventory.network_request({"kind": "chest_take", "index": slot_index, "chest": str(get_path()), "expected": item.id})
		return
	if inventory == null or get_item(slot_index) == null:
		return
	var inventory_data := inventory.get_data()
	_server_transfer_to_player(multiplayer.get_unique_id(), slot_index, inventory_data)


func _server_transfer_from_player(peer_id: int, slot_index: int, expected_item_id: String, inventory_data: Array) -> void:
	var player := _player_for_peer(peer_id)
	var inventory := _inventory_for_player(player)
	if inventory == null or not _player_is_close(player):
		return
	# Inventory is owned by the host during a session.
	var item := inventory.get_item(slot_index)
	var free_slot := _first_free_slot()
	if item == null or item.id != expected_item_id or free_slot < 0:
		_send_inventory_state(peer_id, inventory)
		return
	slots[free_slot] = item
	inventory.slots[slot_index] = null
	inventory.changed.emit()
	_commit_transfer(peer_id, inventory)


func _server_transfer_to_player(peer_id: int, slot_index: int, inventory_data: Array) -> void:
	var player := _player_for_peer(peer_id)
	var inventory := _inventory_for_player(player)
	if inventory == null or not _player_is_close(player):
		return
	# Inventory is owned by the host during a session.
	var item := get_item(slot_index)
	if item == null or not inventory.add_item(item):
		_send_inventory_state(peer_id, inventory)
		return
	slots[slot_index] = null
	_commit_transfer(peer_id, inventory)


func _commit_transfer(peer_id: int, inventory: InventoryComponent) -> void:
	_persist_contents()
	contents_changed.emit()
	if not SteamLobby.is_session_active():
		_send_inventory_state(peer_id, inventory)


func _send_inventory_state(_peer_id: int, inventory: InventoryComponent) -> void:
	if not SteamLobby.is_session_active():
		_save_local_inventory(inventory)


func _persist_contents() -> void:
	if _hub == null or not _hub.has_method("get_world_progress") or not _hub.has_method("set_world_progress_value"):
		return
	var progress: Dictionary = _hub.call("get_world_progress")
	var saved_chests: Variant = progress.get("chests", {})
	var chests: Dictionary = saved_chests.duplicate(true) if saved_chests is Dictionary else {}
	chests[chest_id] = get_data()
	_hub.call("set_world_progress_value", "chests", chests)


func _set_data(data: Array) -> void:
	for index in SLOT_COUNT:
		slots[index] = null
	for index in mini(data.size(), SLOT_COUNT):
		var item_id := str(data[index])
		if not item_id.is_empty():
			slots[index] = ItemLibrary.get_item(item_id)
	contents_changed.emit()


func _first_free_slot() -> int:
	for index in SLOT_COUNT:
		if slots[index] == null:
			return index
	return -1


func _player_for_peer(peer_id: int) -> Player:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null(str(peer_id)) as Player


func _local_player() -> Player:
	for node in get_tree().get_nodes_in_group("player"):
		if node is Player and (node as Player).is_multiplayer_authority():
			return node as Player
	return null


func _inventory_for_player(player: Player) -> InventoryComponent:
	return player.inventory if player != null else null


func _player_is_close(player: Player) -> bool:
	return player != null and player.global_position.distance_to(global_position) <= INTERACTION_DISTANCE


func _save_local_inventory(inventory: InventoryComponent) -> void:
	var player := inventory.get_parent() as Player
	if player != null and player.is_multiplayer_authority():
		SaveManager.save_player_state(inventory, player.equipment)
