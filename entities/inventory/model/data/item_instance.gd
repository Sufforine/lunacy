class_name ItemInstance
extends RefCounted

# ссылка на базовый предмет
var data: ItemData

# ----------------------------
# МОДИФИКАТОРЫ (рандом при выпадении)
# ----------------------------
var bonus_armor: int = 0
var bonus_damage: int = 0
var bonus_health: int = 0

# ----------------------------
# ПРОКАЧКА (0–3)
# ----------------------------
var upgrade_level: int = 0  # +0 ... +3

# ----------------------------
# ПАССИВКА (runtime)
# ----------------------------
var passive_timer: float = 0.0
var passive_active: bool = false
var owner: Node = null


# ----------------------------
# ИНИЦИАЛИЗАЦИЯ
# ----------------------------
func setup(item_data: ItemData):
	data = item_data

	# случайные модификаторы (1–3)
	if data.type == "armor":
		bonus_armor = randi_range(1, 3)

	if data.type == "weapon":
		bonus_damage = randi_range(1, 3)

	if data.type == "trinket":
		bonus_health = randi_range(1, 3)


# ----------------------------
# ПРОКАЧКА ДО +3
# ----------------------------
func upgrade():

	if upgrade_level >= 3:
		return

	upgrade_level += 1


# ----------------------------
# ИТОГОВЫЕ СТАТЫ
# ----------------------------
func get_armor() -> int:
	return data.armor + bonus_armor + upgrade_level


func get_damage() -> int:
	return data.damage + bonus_damage + upgrade_level


func get_health() -> int:
	return data.health + bonus_health + upgrade_level


# ----------------------------
# ПАССИВКА (ТЕСТ: ЩИТ)
# ----------------------------
func start_passive(_owner: Node):
	owner = _owner
	passive_active = true
	passive_timer = 0.0


func update(delta: float):

	if not passive_active:
		return

	passive_timer += delta

	if passive_timer >= 10.0:
		passive_timer = 0.0
		print("ЩИТ")
