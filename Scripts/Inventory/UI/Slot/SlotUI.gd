extends PanelContainer

@onready var icon_rect = $Icon
@onready var quantity_label = $Quantity

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
