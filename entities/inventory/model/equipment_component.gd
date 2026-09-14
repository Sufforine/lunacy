extends Node
class_name EquipmentComponent

signal changed

var weapon:     ItemData = null
var helmet:     ItemData = null
var chestplate: ItemData = null
var leggings:   ItemData = null
var cloak:      ItemData = null
var trinket_1:  ItemData = null
var scroll:     ItemData = null


func equip(item: ItemData) -> void:

	if item == null or not item.is_equipment():
		push_warning("EquipmentComponent: '%s' не является снаряжением" % (item.id if item else "null"))
		return

	match item.slot:
		ItemData.Slot.WEAPON:     weapon     = item
		ItemData.Slot.HELMET:     helmet     = item
		ItemData.Slot.CHESTPLATE: chestplate = item
		ItemData.Slot.LEGGINGS:   leggings   = item
		ItemData.Slot.CLOAK:      cloak      = item
		ItemData.Slot.TRINKET_1:  trinket_1  = item
		ItemData.Slot.SCROLL:     scroll     = item

	changed.emit()
	print("EquipmentComponent: надет '%s'" % item.id)


func unequip(slot: ItemData.Slot) -> void:

	match slot:
		ItemData.Slot.WEAPON:     weapon     = null
		ItemData.Slot.HELMET:     helmet     = null
		ItemData.Slot.CHESTPLATE: chestplate = null
		ItemData.Slot.LEGGINGS:   leggings   = null
		ItemData.Slot.CLOAK:      cloak      = null
		ItemData.Slot.TRINKET_1:  trinket_1  = null
		ItemData.Slot.SCROLL:     scroll     = null

	changed.emit()


func get_slot_item(slot: ItemData.Slot) -> ItemData:
	match slot:
		ItemData.Slot.WEAPON:     return weapon
		ItemData.Slot.HELMET:     return helmet
		ItemData.Slot.CHESTPLATE: return chestplate
		ItemData.Slot.LEGGINGS:   return leggings
		ItemData.Slot.CLOAK:      return cloak
		ItemData.Slot.TRINKET_1:  return trinket_1
		ItemData.Slot.SCROLL:     return scroll
	return null


func get_all_items() -> Array[ItemData]:
	var items: Array[ItemData] = []
	if weapon:     items.append(weapon)
	if helmet:     items.append(helmet)
	if chestplate: items.append(chestplate)
	if leggings:   items.append(leggings)
	if cloak:      items.append(cloak)
	if trinket_1:  items.append(trinket_1)
	if scroll:     items.append(scroll)
	return items


func load_from_profile() -> void:
	weapon     = _load_item(PlayerProfile.equipment.get("weapon",     ""))
	helmet     = _load_item(PlayerProfile.equipment.get("helmet",     ""))
	chestplate = _load_item(PlayerProfile.equipment.get("chestplate", ""))
	leggings   = _load_item(PlayerProfile.equipment.get("leggings",   ""))
	cloak      = _load_item(PlayerProfile.equipment.get("cloak",      ""))
	trinket_1  = _load_item(PlayerProfile.equipment.get("trinket_1",  ""))
	scroll     = _load_item(PlayerProfile.equipment.get("scroll",     ""))
	changed.emit()


func save_to_profile() -> void:
	PlayerProfile.equipment = {
		"weapon":     weapon.resource_path     if weapon     else "",
		"helmet":     helmet.resource_path     if helmet     else "",
		"chestplate": chestplate.resource_path if chestplate else "",
		"leggings":   leggings.resource_path   if leggings   else "",
		"cloak":      cloak.resource_path      if cloak      else "",
		"trinket_1":  trinket_1.resource_path  if trinket_1  else "",
		"scroll":     scroll.resource_path     if scroll     else "",
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
