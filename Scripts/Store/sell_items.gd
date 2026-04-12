extends Control
class_name SellCard

@export var card_frame: TextureRect

## Set by Shop after instantiate — the inventory that receives purchases.
var inventory: Inventory

## World/stack item this card sells; passed to Inventory.add_item (that call frees it).
@onready var item_to_sell: Item = $Item

var hovering: bool

func _process(_delta):
	if is_mouse_over_card():
		hovering = true
		card_frame.scale = Vector2(0.28, 0.28)
	else:
		hovering = false
		card_frame.scale = Vector2(0.25, 0.25)

func is_mouse_over_card() -> bool:
	var mouse_pos: Vector2 = get_global_mouse_position()
	var sprite_rect = Rect2(card_frame.global_position, card_frame.texture.get_size())
	return sprite_rect.has_point(mouse_pos)  
	
func _input(event) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and hovering and inventory and item_to_sell:
			inventory.add_item(item_to_sell, 1)
			queue_free()
