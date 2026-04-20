extends Control

@export var inventory_data: Inventory  # Ссылка на ресурс инвентаря
@export var columns: int = 6           # Сколько колонок в ряду
@export var slot_scene: PackedScene    # Сцена одной ячейки (Slot.tscn)

@onready var grid: GridContainer = $VBoxContainer/ScrollContainer/GridContainer

func _ready():
	GlobalRefs.player_inventory_root = self
	print(GlobalRefs.player_inventory_root)
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
	
	
	for i in range(inventory_data.slots.size()):
		var slot_view = slot_scene.instantiate()
		grid.add_child(slot_view)
		slot_view.slot_index = i
		slot_view.display(inventory_data.slots[i])
		
