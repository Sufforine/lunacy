extends Resource
class_name Item

enum ItemType {
	QUEST,
	CONSUMABLE,
	RESOURCE,
}

@export_group("Visuals")
@export var name: String
@export var icon: Texture2D

@export_group("Logic")
@export var id: int
@export var is_stackable: bool = false
@export var type: ItemType
