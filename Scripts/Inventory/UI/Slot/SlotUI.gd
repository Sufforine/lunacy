extends PanelContainer

@onready var icon_rect = $Icon
@onready var quantity_label = $Quantity

var slot_index: int

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


func _get_drag_data(_at_position):
	var inventory_ui = GlobalRefs.player_inventory_root
	var data = inventory_ui.inventory_data.slots[slot_index]
	
	if data == null: return null

	# Создаем превью (иконка под курсором)
	var preview = TextureRect.new()
	preview.z_index = 50
	preview.texture = icon_rect.texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.custom_minimum_size = Vector2(50, 50)
	var previewLabel = Label.new()
	previewLabel.name = "CountLabel"
	previewLabel.text = "1"
	previewLabel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE)
	preview.add_child(previewLabel)
	
	set_drag_preview(preview)
	
	return slot_index # Передаем индекс ячейки


func _can_drop_data(_at_position, data):
	return data is int # Проверяем, что нам передали индекс (целое число)


func _drop_data(_at_position, data_index):
	var inventory_ui = GlobalRefs.player_inventory_root
	inventory_ui.inventory_data.swap_slots(data_index, slot_index)


func _gui_input(event):
	if event is InputEventMouseButton and event.pressed:
		var inventory_ui = GlobalRefs.player_inventory_root
		
		# Если нажали ПКМ и зажат Shift — отделяем 1 предмет
		if event.button_index == MOUSE_BUTTON_RIGHT and Input.is_key_pressed(KEY_SHIFT):
			inventory_ui.inventory_data.split_stack(slot_index, 1)
#			force_drag() тут
