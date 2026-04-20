extends Resource
class_name Inventory

signal update_slots

@export var slots: Array = []

func setup(size: int):
	slots.clear()
	for i in range(size):
		slots.append(null)
	update_slots.emit()
	


func swap_slots(index1: int, index2: int):
	print("index1 - ", index1)
	print("index2! - ", index2)
	var temp = slots[index1]
	slots[index1] = slots[index2]
	slots[index2] = temp
	update_slots.emit()


func split_stack(index: int, amount: int):
	var slot = slots[index]
	print(slot)
	if slot and slot.amount > amount:
		slot.amount -= amount
		# Ищем пустую ячейку для новой пачки
		#add_item(slot.item, amount) 
		update_slots.emit()


func add_item(new_item: Item, amount: int = 1):
	print("Started")
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

func place_at(index: int, item_to_add: Item, amount: int) -> bool:
	var target_slot = slots[index]
	
	# Если слот пустой — просто кладем
	if target_slot == null:
		slots[index] = {"item": item_to_add, "amount": amount}
		update_slots.emit()
		return true
	
	# Если там такой же предмет — стакаем
	if target_slot.item.id == item_to_add.id and target_slot.item.is_stackable:
		target_slot.amount += amount
		update_slots.emit()
		return true
		
	return false # Слот занят чем-то другим


func expand(extra_slots: int):
	for i in range(extra_slots):
		slots.append(null)
	update_slots.emit()


func remove_at(index: int):
	if index < slots.size():
		slots[index] = null
		update_slots.emit()
