extends Control

@export var inventory_data: Inventory  # Ссылка на ресурс инвентаря
@export var columns: int = 6           # Сколько колонок в ряду
@export var slot_scene: PackedScene    # Сцена одной ячейки (Slot.tscn)

@onready var grid: GridContainer = $VBoxContainer/ScrollContainer/GridContainer

func _ready():
	# Подписываемся на изменения в данных
	if inventory_data:
		inventory_data.update_slots.connect(refresh_ui)
		refresh_ui()
		
	
	# Настраиваем сетку
	grid.columns = 6
	

func refresh_ui():
	# Очищаем старые ячейки
	for child in grid.get_children():
		child.queue_free()
	
	# Создаем новые на основе размера массива в Inventory.gd
	for slot_data in inventory_data.slots:
		var slot_view = slot_scene.instantiate()
		grid.add_child(slot_view)
		
		if slot_data != null:
			slot_view.display(slot_data) # Функция внутри ячейки для отрисовки иконки
