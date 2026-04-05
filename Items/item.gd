extends Node
class_name Item

@export var item_name: String = ""
@export var icon: Texture2D
@export var is_stackable: bool = false

var inventory: Inventory

func _ready():
	add_to_group("items")
