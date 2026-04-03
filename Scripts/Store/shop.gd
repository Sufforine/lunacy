extends Control
class_name Shop

@export var sell_card: PackedScene
@export var card_container: HBoxContainer

func _ready() -> void:
	
	
	for i in range(1):
		var sell_card_instance = sell_card.instantiate()
		card_container.add_child(sell_card_instance)
 
