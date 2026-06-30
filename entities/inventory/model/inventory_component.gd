# InventoryComponent.gd
# Нода-компонент на игроке. Хранит предметы как ItemData (Resource).
extends Node
class_name InventoryComponent

signal changed

const SLOT_COUNT := 6

# Слоты: массив из ItemData или null
var slots: Array = []


func _ready() -> void:
	slots.resize(SLOT_COUNT)
	for i in SLOT_COUNT:
		slots[i] = null


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


# =========================================================
# SERIALISATION  (PlayerProfile хранит массив id строк)
# =========================================================
func get_data() -> Array:
	var data: Array = []
	for slot in slots:
		data.append(slot.id if slot != null else "")
	return data


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
