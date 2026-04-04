@tool

extends Control
class_name Inventory

var inventory_item_scene = preload("res://scenes/Inventory/InventorySlot/InventoryItem/InventoryItem.tscn")

@export var rows: int = 3
@export var cols: int = 6

@export var inventory_grid: GridContainer

@export var inventory_slot_scene: PackedScene
var slots: Array[InventorySlot]

@export var tooltip: Tooltip # Must be shared among all instanesself


static var selected_item: Item = null


func _ready():
	inventory_grid.columns = cols
	for i in range(rows * cols):
		var slot = inventory_slot_scene.instantiate()
		slots.append(slot)
		inventory_grid.add_child(slot)
		slot.slot_input.connect(self._on_slot_input) # binding not necessary as
		slot.slot_hovered.connect(self._on_slot_hovered) # it does while emit() call
	tooltip.visible = false


func _process(delta):
	tooltip.global_position = get_global_mouse_position() + Vector2.ONE * 8
	if selected_item:
		tooltip.visible = false
		selected_item.global_position = get_global_mouse_position()


func _on_slot_input(which: InventorySlot, action: InventorySlot.InventorySlotAction):
	print(action)
	# Select/deselect items
	if not selected_item:
		# Spliting only occurs if not item selected already
		if action == InventorySlot.InventorySlotAction.SELECT:
			selected_item = which.select_item()
		elif action == InventorySlot.InventorySlotAction.SPLIT:
			selected_item = which.split_item() # Split means selecting half amount
	else:
		selected_item = which.deselect_item(selected_item)



func _on_slot_hovered(which: InventorySlot, is_hovering: bool):
	if which.item:
		tooltip.set_text(which.item.item_name)
		tooltip.visible = is_hovering
	elif which.hint_item:
		tooltip.set_text(which.hint_item.item_name)
		tooltip.visible = is_hovering





# API::

# !DESTRUCTUVE (removes item itself from world  and adds its copy to inventory)
# Calling thius func impies that item is not already in inventory
func add_item(item: Item, amount: int) -> void:
	var _item: InventoryItem = inventory_item_scene.instantiate() # Duplicate
	_item.set_data(
		item.item_name, item.icon, item.is_stackable, amount
	)
	item.queue_free() # Consume the item by inventory (by the end of frame)
	if item.is_stackable:
		for slot in slots:
			if slot.item and slot.item.item_name == _item.item_name: # if item and is of same type
				slot.item.amount += _item.amount
				return
	for slot in slots:
		if slot.item == null and slot.is_respecting_hint(_item):
			slot.item = _item
			slot.update_slot()
			return



# !DESTRUCTUVE (removes from inventory if retrieved)
#A function to remove item from inventory and return if it exists
func retrieve_item(_item_name: String) -> Item:
	for slot in slots:
		if slot.item and slot.item.item_name == _item_name:
			var copy_item := Item.new()
			copy_item.item_name = slot.item.item_name
			copy_item.name = copy_item.item_name
			copy_item.icon = slot.item.icon
			copy_item.is_stackable = slot.item.is_stackable
			if slot.item.amount > 1:
				slot.item.amount -= 1
			else:
				slot.remove_item()
			return copy_item
	return null



# !NON-DESTRUCTIVE (read-only function) to get all items in inventory
func all_items() -> Array[Item]:
	var items: Array[Item] = []
	for slot in slots:
		if slot.item:
			items.append(slot.item)
	return items



# ! NON-DESTRUCTUVE (read-only), returns all items of a particular type
func all(_name: String) -> Array[Item]:
	var items: Array[Item] = []
	for slot in slots:
		if slot.item and slot.item.item_name == _name:
			items.append(slot.item)
	return items



# !DESTRUCTUVE (removes all items of a particular type)
func remove_all(_name: String) -> void:
	for slot in slots:
		if slot.item and slot.item.item_name == _name:
			slot.remove_item()



# !DESTRUCTUVE (removes all items from inventory)
func clear_inventory() -> void:
	for slot in slots:
		slot.remove_item()
