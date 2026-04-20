extends Resource
class_name Inventory

signal update_slots

@export var slots: Array = []

func setup(size: int):
	slots.clear()
	for i in range(size):
		slots.append(null)
	update_slots.emit()

func add_item(new_item: Item, amount: int = 1):
	if new_item.is_stackable:
		for slot in slots:
			if slot and slot.item.id == new_item.id:
				slot.amount += amount
				update_slots.emit()
				return true
	
	for i in range(slots.size()):
		if slots[i] == null:
			slots[i] = {"item": new_item, "amount": amount}
			update_slots.emit()
			return true
			
	return false # Инвентарь полон


func expand(extra_slots: int):
	for i in range(extra_slots):
		slots.append(null)
	update_slots.emit()


func remove_at(index: int):
	if index < slots.size():
		slots[index] = null
		update_slots.emit()
