# SaveManager.gd — Autoload
#
# По умолчанию сохранение привязано к Steam ID: user://saves/<steam_id>.json
# Игрок может создать ИМЕНОВАННЫЕ сохранения и переключаться между ними:
#   user://saves/<steam_id>__<custom_name>.json
# Текущий активный файл хранится в _active_save_name (пусто = дефолтный по Steam ID).
extends Node

const SAVE_DIR := "res://Saves/"

const EMPTY_EQUIPMENT := {
	"weapon":   "",
	"armor":    "",
	"trinket_1": "",
	"scroll":   "",
}

const RESOURCE_PATH_MIGRATIONS := {
	"res://Scenes/Chars/Dullahan.tscn": "res://entities/hero/ui/Dullahan.tscn",
	"res://Scenes/Chars/Slon.tscn": "res://entities/hero/ui/Slon.tscn",
	"res://Scripts/CharRes/Consumables/health_potion.tres": "res://entities/inventory/model/items/consumables/health_potion.tres",
	"res://Scripts/CharRes/Consumables/mana_potion.tres": "res://entities/inventory/model/items/consumables/mana_potion.tres",
	"res://Scripts/CharRes/Consumables/big_potion.tres": "res://entities/inventory/model/items/consumables/big_potion.tres",
	"res://Scripts/CharRes/itemjsons/armor/DullahanCoat.tres": "res://entities/inventory/model/items/armor/DullahanCoat.tres",
	"res://Scripts/CharRes/itemjsons/trinkets/SpeedCharm.tres": "res://entities/inventory/model/items/trinkets/SpeedCharm.tres",
	"res://Scripts/CharRes/itemjsons/trinkets/HealthCharm.tres": "res://entities/inventory/model/items/trinkets/HealthCharm.tres",
	"res://Scripts/CharRes/itemjsons/trinkets/DamageCharm.tres": "res://entities/inventory/model/items/trinkets/DamageCharm.tres",
	"res://Scripts/CharRes/itemjsons/weapon/Axe.tres": "res://entities/inventory/model/items/weapon/Axe.tres",
}

# Имя текущего активного именованного сохранения. Пусто = сохранение по умолчанию (steam_id.json)
var _active_save_name: String = ""


# =========================================================
# ПУТЬ К ФАЙЛУ
# =========================================================
func get_save_path() -> String:

	var steam_id: int = _steam_id()
	var prefix: String = str(steam_id) if steam_id != 0 else "offline"

	if _active_save_name.is_empty():
		return SAVE_DIR + prefix + ".json"

	return SAVE_DIR + prefix + "__" + _active_save_name + ".json"


func get_active_save_name() -> String:
	return _active_save_name if not _active_save_name.is_empty() else "По умолчанию"


# =========================================================
# СПИСОК ВСЕХ СОХРАНЕНИЙ ТЕКУЩЕГО ИГРОКА
# Возвращает массив { "name": String, "path": String, "is_default": bool }
# =========================================================
func list_saves() -> Array:

	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

	var steam_id: int = _steam_id()
	var prefix: String = str(steam_id) if steam_id != 0 else "offline"

	var result: Array = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return result

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json") and file_name.begins_with(prefix):
			var path := SAVE_DIR + file_name
			if file_name == prefix + ".json":
				result.append({"name": "По умолчанию", "path": path, "is_default": true})
			elif file_name.begins_with(prefix + "__"):
				var custom_name := file_name.trim_prefix(prefix + "__").trim_suffix(".json")
				result.append({"name": custom_name, "path": path, "is_default": false})
		file_name = dir.get_next()
	dir.list_dir_end()

	return result


# =========================================================
# СОЗДАТЬ НОВОЕ ИМЕНОВАННОЕ СОХРАНЕНИЕ
# =========================================================
func create_named_save(save_name: String) -> bool:

	var clean := save_name.strip_edges()
	if clean.is_empty():
		push_warning("SaveManager: имя сохранения не может быть пустым")
		return false

	# Убрать символы недопустимые в именах файлов
	clean = clean.validate_filename()

	_active_save_name = clean

	# Сбросить профиль на значения по умолчанию для нового сохранения
	PlayerProfile.hero_scene = ""
	PlayerProfile.level = 1
	PlayerProfile.experience = 0
	PlayerProfile.inventory = []
	PlayerProfile.equipment = EMPTY_EQUIPMENT.duplicate()

	save_profile()
	print("SaveManager: создано новое сохранение '%s'" % clean)
	return true


# =========================================================
# ВЫБРАТЬ АКТИВНОЕ СОХРАНЕНИЕ И ЗАГРУЗИТЬ ЕГО
# =========================================================
func select_save(save_info: Dictionary) -> void:

	_active_save_name = "" if save_info.get("is_default", true) else save_info.get("name", "")
	load_profile()
	print("SaveManager: выбрано сохранение '%s'" % get_active_save_name())


# =========================================================
# СОХРАНЕНИЕ
# =========================================================
func save_profile() -> void:

	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

	var data := {
		"hero_scene": PlayerProfile.hero_scene,
		"level":      PlayerProfile.level,
		"experience": PlayerProfile.experience,
		"inventory":  _serialize_inventory(),
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

	PlayerProfile.hero_scene = _migrate_resource_path(data.get("hero_scene", ""))
	PlayerProfile.level      = data.get("level",      1)
	PlayerProfile.experience = data.get("experience", 0)
	PlayerProfile.inventory  = _normalize_inventory(data.get("inventory", []))
	PlayerProfile.equipment  = _migrate_equipment_paths(data.get("equipment", EMPTY_EQUIPMENT.duplicate()))

	if PlayerProfile.equipment.has("trinket_2"):
		PlayerProfile.equipment["scroll"] = PlayerProfile.equipment["trinket_2"]
		PlayerProfile.equipment.erase("trinket_2")

	print("SaveManager: загружено ← %s" % path)


# =========================================================
# СОХРАНИТЬ СОСТОЯНИЕ ИГРОКА ПОСЛЕ МИССИИ
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
	return _normalize_inventory(PlayerProfile.inventory if PlayerProfile.inventory is Array else [])


func _normalize_inventory(raw: Array) -> Array:
	const SLOT_COUNT := 6
	var result: Array = []
	result.resize(SLOT_COUNT)
	for i in SLOT_COUNT:
		result[i] = ""
	for i in mini(raw.size(), SLOT_COUNT):
		var entry: Variant = raw[i]
		result[i] = entry if entry is String else ""
	return result


func _serialize_equipment() -> Dictionary:
	if PlayerProfile.equipment is Dictionary:
		var result := EMPTY_EQUIPMENT.duplicate()
		for key in PlayerProfile.equipment:
			result[key] = PlayerProfile.equipment[key]
		return result
	return EMPTY_EQUIPMENT.duplicate()


func _migrate_equipment_paths(equipment: Dictionary) -> Dictionary:
	var result := EMPTY_EQUIPMENT.duplicate()
	for key in equipment:
		result[key] = _migrate_resource_path(equipment[key])
	return result


func _migrate_resource_path(path: String) -> String:
	if RESOURCE_PATH_MIGRATIONS.has(path):
		return RESOURCE_PATH_MIGRATIONS[path]
	return path


func _steam_id() -> int:
	var steam = Engine.get_singleton("Steam")
	if steam == null:
		return 0
	return steam.getSteamID()
