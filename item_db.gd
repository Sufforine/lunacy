extends Node

const ICON_PATH = "res://Icons/"
const ITEMS = {
	"bandage": {
		"icon": ICON_PATH + "bandage.png",
		"slot": "SUPPLIES"
	},
	"error": { 
		"icon": ICON_PATH + "error.png",
		"slot": "NONE"
	}
}

func get_item(item_id):
	if item_id in ITEMS:
		return ITEMS[item_id]
	else:
		return ITEMS["error"]
