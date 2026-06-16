# SaveManager.gd — Autoload
# Каждый игрок хранит свой файл сохранения по Steam ID.
# Формат: user://saves/<steam_id>.json
#
# Инвентарь сохраняется как массив item id строк.
# Снаряжение сохраняется как словарь slot → resource_path к .tres файлу.
extends Node

const SAVE_DIR := "res://Saves/"

const EMPTY_EQUIPMENT := {
	"weapon":   "",
	"armor":    "",
	"trinket_1": "",
	"scroll":   "",
}


# =========================================================
# ПУТЬ К ФАЙЛУ
# =========================================================
func get_save_path() -> String:

	var steam_id: int = Steam.getSteamID()

	if steam_id == 0:
		push_warning("SaveManager: Steam не инициализирован, используется offline.json")
		return SAVE_DIR + "offline.json"

	return SAVE_DIR + str(steam_id) + ".json"


# =========================================================
# СОХРАНЕНИЕ
# Вызывать после миссии или при выходе из лобби.
# =========================================================
func save_profile() -> void:

	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

	var data := {
		"hero_scene": PlayerProfile.hero_scene,
		"level":      PlayerProfile.level,
		"experience": PlayerProfile.experience,
		# Инвентарь — массив id строк (пустой слот = "")
		"inventory":  _serialize_inventory(),
		# Снаряжение — словарь slot → resource_path
		"equipment":  _serialize_equipment(),
	}

	var file := FileAccess.open(get_save_path(), FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: не удалось открыть файл для записи: %s" % get_save_path())
		return

	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	print("SaveManager: сохранено → %s" % get_save_path())


# =========================================================
# ЗАГРУЗКА
# Вызывать при старте игры (в SteamLobby._ready или главном меню).
# =========================================================
func load_profile() -> void:

	var path := get_save_path()

	if not FileAccess.file_exists(path):
		print("SaveManager: файл сохранения не найден, используются значения по умолчанию")
		return

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SaveManager: не удалось открыть файл для чтения: %s" % path)
		return

	var raw := file.get_as_text()
	file.close()

	var data: Variant = JSON.parse_string(raw)
	if data == null:
		push_error("SaveManager: повреждённый JSON в %s" % path)
		return

	PlayerProfile.hero_scene = data.get("hero_scene", "")
	PlayerProfile.level      = data.get("level",      1)
	PlayerProfile.experience = data.get("experience", 0)

	# Инвентарь: массив id строк → PlayerProfile хранит их,
	# InventoryComponent.set_data() восстановит ItemData через ItemLibrary
	PlayerProfile.inventory  = data.get("inventory", [])

	# Снаряжение: словарь slot → resource_path
	PlayerProfile.equipment  = data.get("equipment", EMPTY_EQUIPMENT.duplicate())

	# Миграция: старые сохранения могут иметь trinket_2 вместо scroll
	if PlayerProfile.equipment.has("trinket_2"):
		PlayerProfile.equipment["scroll"] = PlayerProfile.equipment["trinket_2"]
		PlayerProfile.equipment.erase("trinket_2")

	print("SaveManager: загружено ← %s" % path)


# =========================================================
# СОХРАНИТЬ СОСТОЯНИЕ ИГРОКА ПОСЛЕ МИССИИ
# Вызывать из player.gd когда миссия завершена или игрок выходит.
# =========================================================
func save_player_state(inventory: InventoryComponent, equipment: EquipmentComponent) -> void:

	PlayerProfile.inventory = inventory.get_data()

	PlayerProfile.equipment = {
		"weapon":    equipment.weapon.resource_path    if equipment.weapon    else "",
		"armor":     equipment.armor.resource_path     if equipment.armor     else "",
		"trinket_1": equipment.trinket_1.resource_path if equipment.trinket_1 else "",
		"scroll":    equipment.scroll.resource_path    if equipment.scroll    else "",
	}

	save_profile()
	print("SaveManager: состояние игрока сохранено")


# =========================================================
# СЕРИАЛИЗАЦИЯ
# =========================================================
func _serialize_inventory() -> Array:

	# PlayerProfile.inventory может быть уже массивом id строк
	# (если set_data ещё не вызывался) или пустым
	if PlayerProfile.inventory is Array:
		return PlayerProfile.inventory
	return []


func _serialize_equipment() -> Dictionary:

	if PlayerProfile.equipment is Dictionary:
		# Убедиться что все ключи присутствуют
		var result := EMPTY_EQUIPMENT.duplicate()
		for key in PlayerProfile.equipment:
			result[key] = PlayerProfile.equipment[key]
		return result

	return EMPTY_EQUIPMENT.duplicate()
