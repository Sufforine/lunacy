# InventoryComponent.gd
# Нода-компонент на игроке. Хранит предметы как ItemData (Resource).
extends Node
class_name InventoryComponent

signal changed

const SLOT_COUNT := 36
const QUICKSLOT_COUNT := 3

# Слоты: массив из ItemData или null
var slots: Array = []
var quickslots: Array = []  # 3 слота быстрого доступа


func _ready() -> void:
	slots.resize(SLOT_COUNT)
	for i in SLOT_COUNT:
		slots[i] = null
	quickslots.resize(QUICKSLOT_COUNT)
	for i in QUICKSLOT_COUNT:
		quickslots[i] = null


# =========================================================
# ADD
# =========================================================
func add_item(item: ItemData) -> bool:

	if item == null:
		push_warning("InventoryComponent: попытка добавить null")
		return false

	for i in SLOT_COUNT:
		if slots[i] == null:
			slots[i] = item
			changed.emit()
			print("InventoryComponent: добавлен '%s' в слот %d" % [item.id, i])
			return true

	print("InventoryComponent: инвентарь полон, '%s' не добавлен" % item.id)
	return false


# =========================================================
# REMOVE
# =========================================================
func remove_item(slot_index: int) -> void:

	if not _valid(slot_index):
		return

	var id = slots[slot_index].id if slots[slot_index] else "пусто"
	slots[slot_index] = null
	changed.emit()
	print("InventoryComponent: удалён '%s' из слота %d" % [id, slot_index])


# =========================================================
# MOVE (drag & drop между слотами)
# =========================================================
func move_item(from_index: int, to_index: int) -> void:

	if not _valid(from_index) or not _valid(to_index):
		return
	if from_index == to_index:
		return

	var tmp = slots[to_index]
	slots[to_index] = slots[from_index]
	slots[from_index] = tmp
	changed.emit()


# =========================================================
# USE
# =========================================================
func use_item(slot_index: int, player: Node) -> void:

	if not _valid(slot_index):
		return

	var item: ItemData = slots[slot_index]
	if item == null:
		return
	if item.experience_amount > 0:
		_request_experience_relic(item, "inventory", slot_index, player)
		return

	var used := item.use(player)

	if used and item.is_consumable:
		remove_item(slot_index)


# =========================================================
# GET
# =========================================================
func get_item(slot_index: int) -> ItemData:

	if not _valid(slot_index):
		return null
	return slots[slot_index]


func is_empty(slot_index: int) -> bool:
	return get_item(slot_index) == null


func has_free_slot() -> bool:
	for i in SLOT_COUNT:
		if slots[i] == null:
			return true
	return false


# =========================================================
# SERIALISATION  (PlayerProfile хранит массив id строк)
# =========================================================
func get_data() -> Array:
	var data: Array = []
	for slot in slots:
		data.append(slot.id if slot != null else "")
	return data


func get_quickslot_data() -> Array:
	var data: Array = []
	for slot in quickslots:
		data.append(slot.id if slot != null else "")
	return data


func set_quickslot_data(data: Array) -> void:
	for i in QUICKSLOT_COUNT:
		quickslots[i] = null
	if data == null or data.is_empty():
		return
	for i in min(data.size(), QUICKSLOT_COUNT):
		var id: String = data[i]
		if id.is_empty():
			continue
		quickslots[i] = ItemLibrary.get_item(id)


func use_quickslot(slot_index: int, player: Node) -> void:
	if slot_index < 0 or slot_index >= QUICKSLOT_COUNT:
		return
	var item: ItemData = quickslots[slot_index]
	if item == null:
		return
	if item.experience_amount > 0:
		_request_experience_relic(item, "quickslot", slot_index, player)
		return
	var used := item.use(player)
	if used and item.is_consumable:
		quickslots[slot_index] = null
		changed.emit()


func get_source_item(source: String, slot_index: int) -> ItemData:
	if source == "inventory":
		return get_item(slot_index)
	if source == "quickslot" and slot_index >= 0 and slot_index < QUICKSLOT_COUNT:
		return quickslots[slot_index]
	return null


func find_item_location(item_id: String) -> Dictionary:
	for i in slots.size():
		if slots[i] != null and slots[i].id == item_id:
			return {"source": "inventory", "slot_index": i}
	for i in quickslots.size():
		if quickslots[i] != null and quickslots[i].id == item_id:
			return {"source": "quickslot", "slot_index": i}
	return {}


func consume_network_item(source: String, slot_index: int, expected_item_id: String) -> bool:
	var item := get_source_item(source, slot_index)
	if item == null or item.id != expected_item_id:
		return false
	if source == "inventory":
		slots[slot_index] = null
	else:
		quickslots[slot_index] = null
	changed.emit()
	return true


func _request_experience_relic(item: ItemData, source: String, slot_index: int, player: Node) -> void:
	if SteamLobby.is_session_active():
		SteamLobby.request_use_experience_relic(source, slot_index, item.id)
		return
	var stats := player.get_node_or_null("StatsComponent") as StatsComponent
	if stats == null:
		return
	stats.add_experience(item.experience_amount)
	consume_network_item(source, slot_index, item.id)


func move_to_quickslot(inv_idx: int, qs_idx: int) -> void:
	if qs_idx < 0 or qs_idx >= QUICKSLOT_COUNT:
		return
	var displaced: ItemData = quickslots[qs_idx]
	quickslots[qs_idx] = slots[inv_idx]
	slots[inv_idx] = displaced
	changed.emit()


func set_data(data: Array) -> void:

	for i in SLOT_COUNT:
		slots[i] = null

	if data == null or data.is_empty():
		changed.emit()
		return

	for i in min(data.size(), SLOT_COUNT):
		var id: String = data[i]
		if id.is_empty():
			continue
		var item = ItemLibrary.get_item(id)
		if item != null:
			slots[i] = item
		else:
			push_warning("InventoryComponent: set_data — неизвестный id '%s'" % id)

	changed.emit()


# =========================================================
# INTERNAL
# =========================================================
func _valid(index: int) -> bool:
	if index < 0 or index >= SLOT_COUNT:
		push_warning("InventoryComponent: неверный индекс %d" % index)
		return false
	return true
