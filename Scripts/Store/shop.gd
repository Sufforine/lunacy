extends Control
class_name Shop

@export var sell_card: PackedScene
@export var card_container: HBoxContainer

@onready var inventory: Inventory = $Inventory


func _ready() -> void:
	for i in range(1):
		var sell_card_instance = sell_card.instantiate()
		sell_card_instance.inventory = inventory
		card_container.add_child(sell_card_instance)
