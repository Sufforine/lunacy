extends PanelContainer

@onready var icon_rect = $Icon
@onready var quantity_label = $Quantity

var slot_index: int

static var active_drag_data = null

func display(slot_data):
	if slot_data == null:
		icon_rect.texture = null
		quantity_label.text = ""
	else:
		var item = slot_data.item
		icon_rect.texture = item.icon
		# Показываем число, только если предмет стакается и его больше 1
		if item.is_stackable and slot_data.amount > 1:
			quantity_label.text = str(slot_data.amount)
		else:
			quantity_label.text = ""

func create_preview():
	var preview = TextureRect.new()
	preview.z_index = 160
	preview.texture = icon_rect.texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.custom_minimum_size = Vector2(50, 50)
	
	var previewLabel = Label.new()
	previewLabel.text = str(1)
	previewLabel.name = "CountLabel"
	previewLabel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE)
	preview.add_child(previewLabel)
	
	return preview

func create_drag_data_for_split(item: Item):
	return {
		"origin_index": slot_index,
		"item": item,
		"amount": 1,
		"is_split": true
	}

func _get_drag_data(_at_position):
	var inventory_data = GlobalRefs.player_inventory_root.inventory_data
	var slot_data = inventory_data.slots[slot_index]
	if slot_data == null: return null
	
	if active_drag_data != null: return null
	
	active_drag_data = {
		"origin_index": slot_index,
		"item": slot_data.item,
		"amount": slot_data.amount,
		"is_split": false
	}
	
	var dragPreview = create_preview()
	set_drag_preview(dragPreview)
	
	inventory_data.remove_at(slot_index)
	return active_drag_data

func _can_drop_data(_at_position, data):
	return data is Dictionary

func _drop_data(_at_position, data):
	var inventory = GlobalRefs.player_inventory_root.inventory_data
#	index: int, item_to_add: Item, amount: int
	inventory.place_at(slot_index, data.item, data.amount)

# В пизду
func _gui_input(event):
	var inventory_data = GlobalRefs.player_inventory_root.inventory_data
	var slot_data = inventory_data.slots[slot_index]
	
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT and Input.is_key_pressed(KEY_SHIFT):
			if slot_data and slot_data.amount > 1:
				if active_drag_data == null:
					slot_data.amount -= 1
					active_drag_data = create_drag_data_for_split(slot_data.item)
					var preview_node = create_preview()
					
					inventory_data.update_slots.emit()
					force_drag(active_drag_data, preview_node)

func _notification(what):
	if what == NOTIFICATION_DRAG_END:
		if not get_viewport().gui_is_drag_successful():
			# Используем нашу сохраненную ссылку вместо системной
			if active_drag_data != null:
				_on_drag_failed(active_drag_data)
		
		# В любом случае очищаем ссылку в конце, чтобы не занимать память
		active_drag_data = null

func _on_drag_failed(data):
	var inventory = GlobalRefs.player_inventory_root.inventory_data
	inventory.place_at(data.origin_index, data.item, data.amount)
