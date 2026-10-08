# SaveManager.gd — Autoload
#
# По умолчанию сохранение привязано к Steam ID: user://saves/<steam_id>.json
# Каждое ИМЕНОВАННОЕ сохранение — это отдельный персонаж:
#   user://saves/<steam_id>__<slug>.json
# Текущий активный файл хранится в _active_save_name (пусто = сохранение по умолчанию).
extends Node

const SAVE_DIR := "user://saves/"

# Сцена, которая используется для ЛЮБОГО созданного персонажа.
# Заранее готовых героев больше нет — в игре пока используется общая сцена
# игрока. ВАЖНО: укажи сюда реальный путь к твоей базовой сцене игрока
# (той, что раньше была у Dullahan/Slon), иначе персонаж не заспавнится.
const DEFAULT_HERO_SCENE := ""

const DEFAULT_APPEARANCE := {"color": "3498db", "hair": 0}

const EMPTY_EQUIPMENT := {
	"weapon":     "",
	"helmet":     "",
	"chestplate": "",
	"leggings":   "",
	"cloak":      "",
	"trinket_1":  "",
	"trinket_2":  "",
}

# Имя текущего активного именованного сохранения. Пусто = сохранение по умолчанию (steam_id.json)
var _active_save_name: String = ""


# =========================================================
# ПУТЬ К ФАЙЛУ
# =========================================================
func get_save_path() -> String:

	var prefix: String = _save_prefix()

	if _active_save_name.is_empty():
		return SAVE_DIR + prefix + ".json"

	return SAVE_DIR + prefix + "__" + _active_save_name + ".json"


# Префикс файла сохранения. Если Steam не запущен/не инициализирован —
# используем "offline", не трогая Steam.getSteamID() вообще, иначе
# godotsteam падает с C++ ошибкой (SteamUser() == null).
func _save_prefix() -> String:

	if not SteamLobby.is_steam_ready():
		return "offline"

	var steam_id: int = Steam.getSteamID()
	return str(steam_id) if steam_id != 0 else "offline"


func get_active_save_name() -> String:
	return PlayerProfile.character_name if not PlayerProfile.character_name.is_empty() else "Без персонажа"


# Есть ли у игрока вообще созданный/выбранный персонаж прямо сейчас
func has_active_character() -> bool:
	return not PlayerProfile.character_name.is_empty()


# =========================================================
# СПИСОК ВСЕХ СОХРАНЕНИЙ ТЕКУЩЕГО ИГРОКА
# Каждый элемент:
#   name           — отображаемое имя (character_name или запасной вариант)
#   character_name — имя персонажа из файла ("" у старых сохранений без персонажа)
#   slug           — часть имени файла
#   path           — путь к файлу
#   is_default     — это файл <steam_id>.json без слага
#   created_at     — время создания (для старых файлов — время изменения файла)
#   appearance     — {"color": "rrggbb", "hair": int}
# =========================================================
func list_saves() -> Array:

	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

	var prefix: String = _save_prefix()

	var result: Array = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return result

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json") and file_name.begins_with(prefix):
			var path: String = SAVE_DIR + file_name
			var is_default: bool = file_name == prefix + ".json"
			var is_named: bool = file_name.begins_with(prefix + "__")

			if is_default or is_named:
				var slug: String = ""
				if not is_default:
					slug = file_name.trim_prefix(prefix + "__").trim_suffix(".json")

				var data: Dictionary = _peek_save(path)
				var saved_name: String = str(data.get("character_name", ""))

				var display_name: String = saved_name
				if display_name.is_empty():
					display_name = "Без персонажа" if is_default else slug

				var created: float = float(data.get("created_at", 0.0))
				if created <= 0.0:
					created = float(FileAccess.get_modified_time(path))

				var appearance: Dictionary = DEFAULT_APPEARANCE.duplicate()
				var raw_appearance: Variant = data.get("appearance", null)
				if raw_appearance is Dictionary:
					appearance = raw_appearance

				result.append({
					"name":           display_name,
					"character_name": saved_name,
					"slug":           slug,
					"path":           path,
					"is_default":     is_default,
					"created_at":     created,
					"appearance":     appearance,
				})
		file_name = dir.get_next()
	dir.list_dir_end()

	return result


# Только настоящие персонажи (у которых есть имя), новые первыми
func list_characters() -> Array:

	var result: Array = []
	for entry in list_saves():
		var info: Dictionary = entry
		if str(info.get("character_name", "")).is_empty():
			continue
		result.append(info)

	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("created_at", 0.0)) > float(b.get("created_at", 0.0)))

	return result


# Последний созданный персонаж или {} если ни одного нет
func get_last_character() -> Dictionary:

	var characters: Array = list_characters()
	if characters.is_empty():
		return {}

	var latest: Dictionary = characters[0]
	return latest


# Прочитать файл сохранения целиком, не трогая активный PlayerProfile
func _peek_save(path: String) -> Dictionary:

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}

	var raw: String = file.get_as_text()
	file.close()

	var data: Variant = JSON.parse_string(raw)
	if data is Dictionary:
		return data as Dictionary
	return {}


# =========================================================
# СОЗДАТЬ НОВОГО ПЕРСОНАЖА
# Имя, введённое игроком, становится и отображаемым именем персонажа,
# и (в очищенном виде) именем файла сохранения.
# appearance — {"color": "rrggbb", "hair": int}
# =========================================================
func create_character(character_name: String, appearance: Dictionary = {}) -> bool:

	var clean_name: String = character_name.strip_edges()
	if clean_name.is_empty():
		push_warning("SaveManager: имя персонажа не может быть пустым")
		return false

	var slug: String = _unique_slug(clean_name.validate_filename())

	_active_save_name = slug

	var final_appearance: Dictionary = appearance
	if final_appearance.is_empty():
		final_appearance = DEFAULT_APPEARANCE.duplicate()

	# Полный сброс профиля под нового персонажа
	PlayerProfile.character_name = clean_name
	PlayerProfile.appearance     = final_appearance.duplicate(true)
	PlayerProfile.created_at     = Time.get_unix_time_from_system()
	PlayerProfile.hero_scene     = DEFAULT_HERO_SCENE
	PlayerProfile.level          = 1
	PlayerProfile.experience     = 0
	PlayerProfile.inventory      = []
	PlayerProfile.quickslots     = ["", "", ""]
	PlayerProfile.equipment      = EMPTY_EQUIPMENT.duplicate()

	if DEFAULT_HERO_SCENE.is_empty():
		push_warning("SaveManager: DEFAULT_HERO_SCENE не задан — персонаж не сможет заспавниться. Укажи путь к базовой сцене игрока в SaveManager.gd.")

	save_profile()
	print("SaveManager: создан персонаж '%s' (%s)" % [clean_name, slug])
	return true


# Подобрать свободное имя файла, если слаг уже занят другим персонажем
# (например игрок дважды создал персонажа с одинаковым именем).
func _unique_slug(base_slug: String) -> String:

	var prefix: String = _save_prefix()
	var candidate: String = base_slug
	var suffix: int = 2

	while FileAccess.file_exists(SAVE_DIR + prefix + "__" + candidate + ".json"):
		candidate = "%s_%d" % [base_slug, suffix]
		suffix += 1

	return candidate


# =========================================================
# ВЫБРАТЬ АКТИВНОГО ПЕРСОНАЖА И ЗАГРУЗИТЬ ЕГО
# =========================================================
func select_save(save_info: Dictionary) -> void:

	_active_save_name = "" if save_info.get("is_default", true) else str(save_info.get("slug", ""))
	load_profile()
	print("SaveManager: выбран персонаж '%s'" % get_active_save_name())


# =========================================================
# СОХРАНЕНИЕ
# =========================================================
func save_profile() -> void:

	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

	var data := {
		"character_name": PlayerProfile.character_name,
		"appearance":     PlayerProfile.appearance,
		"created_at":     PlayerProfile.created_at,
		"hero_scene":     PlayerProfile.hero_scene,
		"level":          PlayerProfile.level,
		"experience":     PlayerProfile.experience,
		"inventory":      _serialize_inventory(),
		"quickslots":     _serialize_quickslots(),
		"equipment":      _serialize_equipment(),
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

	var path: String = get_save_path()

	if not FileAccess.file_exists(path):
		print("SaveManager: файл сохранения не найден, персонаж не выбран")
		PlayerProfile.character_name = ""
		PlayerProfile.hero_scene     = ""
		PlayerProfile.created_at     = 0.0
		PlayerProfile.appearance     = DEFAULT_APPEARANCE.duplicate()
		return

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SaveManager: не удалось открыть файл для чтения: %s" % path)
		return

	var raw: String = file.get_as_text()
	file.close()

	var data: Variant = JSON.parse_string(raw)
	if data == null:
		push_error("SaveManager: повреждённый JSON в %s" % path)
		return

	PlayerProfile.character_name = data.get("character_name", "")
	PlayerProfile.created_at     = float(data.get("created_at", 0.0))
	PlayerProfile.hero_scene     = data.get("hero_scene", "")
	PlayerProfile.level          = data.get("level",      1)
	PlayerProfile.experience     = data.get("experience", 0)
	PlayerProfile.inventory      = data.get("inventory", [])
	PlayerProfile.quickslots     = data.get("quickslots", ["", "", ""])
	PlayerProfile.equipment      = data.get("equipment", EMPTY_EQUIPMENT.duplicate())

	var loaded_appearance: Variant = data.get("appearance", null)
	if loaded_appearance is Dictionary:
		PlayerProfile.appearance = loaded_appearance
	else:
		PlayerProfile.appearance = DEFAULT_APPEARANCE.duplicate()

	print("SaveManager: загружено ← %s" % path)


# =========================================================
# СОХРАНИТЬ СОСТОЯНИЕ ИГРОКА ПОСЛЕ МИССИИ
# =========================================================
func save_player_state(inventory: InventoryComponent, equipment: EquipmentComponent) -> void:

	PlayerProfile.inventory  = inventory.get_data()
	PlayerProfile.quickslots = inventory.get_quickslot_data()
	PlayerProfile.equipment  = equipment.to_dict()

	save_profile()
	print("SaveManager: состояние игрока сохранено")


# =========================================================
# СЕРИАЛИЗАЦИЯ
# =========================================================
func _serialize_inventory() -> Array:
	if PlayerProfile.inventory is Array:
		return PlayerProfile.inventory
	return []


func _serialize_equipment() -> Dictionary:
	if PlayerProfile.equipment is Dictionary:
		var result := EMPTY_EQUIPMENT.duplicate()
		for key in PlayerProfile.equipment:
			result[key] = PlayerProfile.equipment[key]
		return result
	return EMPTY_EQUIPMENT.duplicate()


func _serialize_quickslots() -> Array:
	if PlayerProfile.quickslots is Array:
		return PlayerProfile.quickslots
	return ["", "", ""]


# =========================================================
# СТАРТОВЫЙ ИНВЕНТАРЬ
# Вызывается из hub.gd перед спавном соло-игрока.
# Если инвентарь пустой — выдаёт базовый набор предметов.
# =========================================================
func ensure_starter_inventory_if_empty() -> void:

	var has_items: bool = false
	for id in PlayerProfile.inventory:
		if id != "":
			has_items = true
			break

	if has_items:
		return

	var starter_ids := ["health_potion", "mana_potion", "health_potion"]

	var filled: Array = []
	for id in starter_ids:
		filled.append(id)

	while filled.size() < 36:
		filled.append("")

	PlayerProfile.inventory = filled
	save_profile()
	print("SaveManager: выдан стартовый инвентарь")
