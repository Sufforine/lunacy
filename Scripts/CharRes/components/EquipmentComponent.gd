extends Node
class_name EquipmentComponent


@export var weapon: ItemData
@export var armor: ItemData
@export var trinket_1: ItemData
@export var trinket_2: ItemData


func load_from_profile():

	if PlayerProfile.equipment.weapon != "":
		weapon = load(
			PlayerProfile.equipment.weapon
		)

	if PlayerProfile.equipment.armor != "":
		armor = load(
			PlayerProfile.equipment.armor
		)

	if PlayerProfile.equipment.trinket_1 != "":
		trinket_1 = load(
			PlayerProfile.equipment.trinket_1
		)

	if PlayerProfile.equipment.trinket_2 != "":
		trinket_2 = load(
			PlayerProfile.equipment.trinket_2
		)


func save_to_profile():

	PlayerProfile.equipment.weapon = ""
	PlayerProfile.equipment.armor = ""
	PlayerProfile.equipment.trinket_1 = ""
	PlayerProfile.equipment.trinket_2 = ""

	if weapon:
		PlayerProfile.equipment.weapon = (
			weapon.resource_path
		)

	if armor:
		PlayerProfile.equipment.armor = (
			armor.resource_path
		)

	if trinket_1:
		PlayerProfile.equipment.trinket_1 = (
			trinket_1.resource_path
		)

	if trinket_2:
		PlayerProfile.equipment.trinket_2 = (
			trinket_2.resource_path
		)

	SaveManager.save_profile()


func get_all_items() -> Array[ItemData]:

	var items: Array[ItemData] = []

	if weapon:
		items.append(weapon)

	if armor:
		items.append(armor)

	if trinket_1:
		items.append(trinket_1)

	if trinket_2:
		items.append(trinket_2)

	return items
