class_name InventoryComponent
extends Node

const SLOT_COUNT := 6

var items: Array = []


func _ready():
	# инициализация 6 слотов
	if items.is_empty():
		items.resize(SLOT_COUNT)
		for i in SLOT_COUNT:
			items[i] = null


# ----------------------------
# ДОБАВИТЬ ПРЕДМЕТ
# ----------------------------
func add_item(item_id: String):

	for i in SLOT_COUNT:
		if items[i] == null:
			items[i] = item_id
			return true

	return false # инвентарь полный


# ----------------------------
# УДАЛИТЬ ПРЕДМЕТ
# ----------------------------
func remove_item(slot: int) -> void:

	if slot < 0 or slot >= SLOT_COUNT:
		return

	items[slot] = null


# ----------------------------
# ИСПОЛЬЗОВАТЬ ПРЕДМЕТ
# ----------------------------
func use_item(slot: int, owner: Node):

	if slot < 0 or slot >= SLOT_COUNT:
		return

	var item_id = items[slot]

	if item_id == null:
		return

	_apply_item_effect(item_id, owner)

	# если предмет одноразовый — удаляем
	items[slot] = null


# ----------------------------
# ЭФФЕКТЫ ПРЕДМЕТОВ
# ----------------------------
func _apply_item_effect(item_id: String, owner: Node):

	match item_id:

		"health_potion":
			if owner.has_method("heal"):
				owner.heal(50)

		"mana_potion":
			if owner.has_method("restore_mana"):
				owner.restore_mana(30)

		"bomb":
			print("BOOM!")

		_:
			print("Unknown item:", item_id)


# ----------------------------
# СЕТЕВОЙ/СЕЙВ ВЫВОД
# ----------------------------
func get_data() -> Array:
	return items


func set_data(data: Array) -> void:
	items = data.duplicate(true)
	items.resize(SLOT_COUNT)
