extends Node
class_name EquipmentComponent

signal changed

var weapon:    ItemData = null
var armor:     ItemData = null
var trinket_1: ItemData = null
var scroll: ItemData = null


func equip(item: ItemData) -> void:

	if item == null or not item.is_equipment():
		push_warning("EquipmentComponent: '%s' не является снаряжением" % (item.id if item else "null"))
		return

	match item.slot:
		ItemData.Slot.WEAPON:    weapon    = item
		ItemData.Slot.ARMOR:     armor     = item
		ItemData.Slot.TRINKET_1: trinket_1 = item
		ItemData.Slot.SCROLL: scroll = item

	changed.emit()
	print("EquipmentComponent: надет '%s'" % item.id)


func unequip(slot: ItemData.Slot) -> void:

	match slot:
		ItemData.Slot.WEAPON:    weapon    = null
		ItemData.Slot.ARMOR:     armor     = null
		ItemData.Slot.TRINKET_1: trinket_1 = null
		ItemData.Slot.SCROLL: scroll = null

	changed.emit()


func get_slot_item(slot: ItemData.Slot) -> ItemData:
	match slot:
		ItemData.Slot.WEAPON:    return weapon
		ItemData.Slot.ARMOR:     return armor
		ItemData.Slot.TRINKET_1: return trinket_1
		ItemData.Slot.SCROLL: return scroll
	return null


func get_all_items() -> Array[ItemData]:
	var items: Array[ItemData] = []
	if weapon:    items.append(weapon)
	if armor:     items.append(armor)
	if trinket_1: items.append(trinket_1)
	if scroll: items.append(scroll)
	return items


func load_from_profile() -> void:
	weapon    = _load_item(PlayerProfile.equipment.get("weapon",    ""))
	armor     = _load_item(PlayerProfile.equipment.get("armor",     ""))
	trinket_1 = _load_item(PlayerProfile.equipment.get("trinket_1", ""))
	scroll = _load_item(PlayerProfile.equipment.get("scroll", ""))
	changed.emit()


func save_to_profile() -> void:
	PlayerProfile.equipment = {
		"weapon":    weapon.resource_path    if weapon    else "",
		"armor":     armor.resource_path     if armor     else "",
		"trinket_1": trinket_1.resource_path if trinket_1 else "",
		"scroll": scroll.resource_path if scroll else "",
	}
	SaveManager.save_profile()


func _load_item(path: String) -> ItemData:
	if path.is_empty():
		return null
	var res: Resource = load(path)
	if not res is ItemData or not (res as ItemData).is_equipment():
		push_warning("EquipmentComponent: '%s' не является снаряжением" % path)
		return null
	return res as ItemData
