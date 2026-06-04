extends Node
class_name EquipmentComponent

@export var weapon: ItemData
@export var armor: ItemData
@export var trinket_1: ItemData
@export var trinket_2: ItemData


func get_all_items() -> Array[ItemData]:
	var items: Array[ItemData] = []

	if weapon:
		items.append(weapon)

	if armor:
		items.append(armor)

	if trinket_1:
		items.append(trinket_1)

	if trinket_2:
		items.append(trinket_2)

	return items
