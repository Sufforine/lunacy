extends Control

@export var inventory_data: Inventory  # Ссылка на ресурс инвентаря
@export var columns: int = 6           # Сколько колонок в ряду
@export var slot_scene: PackedScene    # Сцена одной ячейки (Slot.tscn)

enum LayoutSide { BOTTOM_LEFT, BOTTOM_RIGHT, TOP_LEFT, TOP_RIGHT }
@export var layout_side: LayoutSide = LayoutSide.BOTTOM_LEFT

@onready var grid: GridContainer = $GridContainer

func apply_layout_settings():
	grid.columns = columns
	
	match layout_side:
		LayoutSide.BOTTOM_LEFT:
			#self.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
			grid.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
			grid.layout_direction = Control.LAYOUT_DIRECTION_LTR
			
		LayoutSide.BOTTOM_RIGHT:
			grid.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
			grid.layout_direction = Control.LAYOUT_DIRECTION_LTR
			
		LayoutSide.TOP_LEFT:
			grid.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			grid.layout_direction = Control.LAYOUT_DIRECTION_LTR
			
		LayoutSide.TOP_RIGHT:
			grid.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
			grid.layout_direction = Control.LAYOUT_DIRECTION_LTR


func _ready():
	GlobalRefs.player_inventory_root = self
	# Подписываемся на изменения в данных
	if inventory_data:
		inventory_data.update_slots.connect(refresh_ui)
		refresh_ui()
		
	apply_layout_settings()
	#grid.columns = columns
	

func refresh_ui():
	# Очищаем старые ячейки
	for child in grid.get_children():
		child.queue_free()
	
	
	for i in range(inventory_data.slots.size()):
		var slot_view = slot_scene.instantiate()
		grid.add_child(slot_view)
		slot_view.slot_index = i
		slot_view.display(inventory_data.slots[i])
		
