# SaveManager.gd — Autoload
#
# Персонажи и миры хранятся в разных файлах, как в Valheim.
# Старые user://saves/*.json мигрируются в user://characters/.
extends Node

const CHARACTER_DIR := "user://characters/"
const WORLD_DIR := "user://worlds/"
const LEGACY_SAVE_DIR := "user://saves/"
const SAVE_VERSION := 2
const PLAYER_SCENE_PATH := "res://entities/characters/model/Player.tscn"

# Сцена, которую хаб/миссия инстанцируют для ЛЮБОГО созданного персонажа.
# В ней уже должны быть player.gd и все компоненты (Stats, Equipment,
# Inventory, Effects, CameraRig, CanvasLayer/InventoryUI и т.д.) —
# собирается один раз в редакторе, а не кодом при создании персонажа.
# Путь больше не является выбором персонажа и не должен приходить из старого
# сохранения или от сетевого клиента. Внешность хранится отдельно в appearance.
var default_hero_scene: String = PLAYER_SCENE_PATH

const DEFAULT_APPEARANCE := {"body": "male", "skin": "e0ac69", "hair": 0}

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
var _active_world_name: String = "default"


# =========================================================
# ПУТЬ К ФАЙЛУ
# =========================================================
func get_save_path() -> String:

	var prefix: String = _save_prefix()

	if _active_save_name.is_empty():
		return CHARACTER_DIR + prefix + ".json"

	return CHARACTER_DIR + prefix + "__" + _active_save_name + ".json"


func get_world_save_path(world_name: String = "") -> String:
	var clean_world := world_name.strip_edges().validate_filename()
	if clean_world.is_empty():
		clean_world = _active_world_name
	return WORLD_DIR + _save_prefix() + "__" + clean_world + ".json"


func get_active_world_name() -> String:
	return _active_world_name


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


# Можно ли реально заспавнить текущего персонажа: сцена задана и существует
func has_valid_hero_scene() -> bool:
	return (
		not PlayerProfile.character_name.is_empty()
		and PlayerProfile.hero_scene == PLAYER_SCENE_PATH
		and ResourceLoader.exists(PLAYER_SCENE_PATH)
	)


# =========================================================
# СПИСОК ВСЕХ СОХРАНЕНИЙ ТЕКУЩЕГО ИГРОКА
# Каждый элемент:
#   name           — отображаемое имя (character_name или запасной вариант)
#   character_name — имя персонажа из файла ("" у старых сохранений без персонажа)
#   slug           — часть имени файла
#   path           — путь к файлу
#   is_default     — это файл <steam_id>.json без слага
#   created_at     — время создания (для старых файлов — время изменения файла)
#   appearance     — {"body": id, "skin": "rrggbb", "hair": int}
# =========================================================
func list_saves() -> Array:

	_migrate_legacy_characters()
	DirAccess.make_dir_recursive_absolute(CHARACTER_DIR)

	var prefix: String = _save_prefix()

	var result: Array = []
	var dir := DirAccess.open(CHARACTER_DIR)
	if dir == null:
		return result

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json") and file_name.begins_with(prefix):
			var path: String = CHARACTER_DIR + file_name
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
# appearance — {"body": id, "skin": "rrggbb", "hair": int}
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
	PlayerProfile.hero_scene     = PLAYER_SCENE_PATH
	PlayerProfile.level          = 1
	PlayerProfile.experience     = 0
	PlayerProfile.attributes     = _empty_attributes()
	PlayerProfile.attribute_points = 0
	PlayerProfile.inventory      = []
	PlayerProfile.quickslots     = ["", "", ""]
	PlayerProfile.equipment      = EMPTY_EQUIPMENT.duplicate()

	save_profile()
	print("SaveManager: создан персонаж '%s' (%s)" % [clean_name, slug])
	return true


# Подобрать свободное имя файла, если слаг уже занят другим персонажем
# (например игрок дважды создал персонажа с одинаковым именем).
func _unique_slug(base_slug: String) -> String:

	var prefix: String = _save_prefix()
	var candidate: String = base_slug
	var suffix: int = 2

	while FileAccess.file_exists(CHARACTER_DIR + prefix + "__" + candidate + ".json"):
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
# УДАЛИТЬ ПЕРСОНАЖА
# Удаляет файл сохранения. Если удаляется активный персонаж —
# профиль в памяти сбрасывается, чтобы его нельзя было случайно
# перезаписать обратно в файл.
# =========================================================
func delete_character(save_info: Dictionary) -> bool:

	var path: String = str(save_info.get("path", ""))

	# Страховка: трогаем только .json внутри папки сохранений
	if not path.begins_with(CHARACTER_DIR) or not path.ends_with(".json"):
		push_error("SaveManager: отказ удалять файл вне папки сохранений: '%s'" % path)
		return false

	if not FileAccess.file_exists(path):
		push_warning("SaveManager: файл персонажа уже удалён: '%s'" % path)
		return false

	var was_active: bool = path == get_save_path()

	var result: Error = _remove_file(path)
	if result != OK:
		push_error("SaveManager: не удалось удалить '%s' (ошибка %d)" % [path, result])
		return false

	# До разделения сохранений файл персонажа находился в user://saves.
	# Если оставить старую копию, list_characters() мигрирует её снова и
	# удалённый персонаж немедленно появится в списке.
	var legacy_path := LEGACY_SAVE_DIR + path.get_file()
	if FileAccess.file_exists(legacy_path):
		var legacy_result := _remove_file(legacy_path)
		if legacy_result != OK:
			push_warning("SaveManager: не удалось удалить старую копию '%s' (ошибка %d)" % [legacy_path, legacy_result])

	if was_active:
		_active_save_name = ""
		PlayerProfile.character_name = ""
		PlayerProfile.hero_scene     = ""
		PlayerProfile.created_at     = 0.0
		PlayerProfile.appearance     = DEFAULT_APPEARANCE.duplicate()
		PlayerProfile.level          = 1
		PlayerProfile.experience     = 0
		PlayerProfile.attributes     = _empty_attributes()
		PlayerProfile.attribute_points = 0
		PlayerProfile.inventory      = []
		PlayerProfile.quickslots     = ["", "", ""]
		PlayerProfile.equipment      = EMPTY_EQUIPMENT.duplicate()

	print("SaveManager: удалён персонаж '%s'" % str(save_info.get("character_name", path)))
	return true


# =========================================================
# СОХРАНЕНИЕ
# =========================================================
func save_profile() -> void:

	DirAccess.make_dir_recursive_absolute(CHARACTER_DIR)

	if not PlayerProfile.character_name.is_empty():
		PlayerProfile.hero_scene = PLAYER_SCENE_PATH

	var data := {
		"save_version":   SAVE_VERSION,
		"character_name": PlayerProfile.character_name,
		"appearance":     PlayerProfile.appearance,
		"created_at":     PlayerProfile.created_at,
		"hero_scene":     PlayerProfile.hero_scene,
		"level":          PlayerProfile.level,
		"experience":     PlayerProfile.experience,
		"attributes":     PlayerProfile.attributes,
		"attribute_points": PlayerProfile.attribute_points,
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

	_migrate_legacy_characters()
	var path: String = get_save_path()

	if not FileAccess.file_exists(path):
		print("SaveManager: файл сохранения не найден, персонаж не выбран")
		PlayerProfile.character_name = ""
		PlayerProfile.hero_scene     = ""
		PlayerProfile.created_at     = 0.0
		PlayerProfile.appearance     = DEFAULT_APPEARANCE.duplicate()
		PlayerProfile.level          = 1
		PlayerProfile.experience     = 0
		PlayerProfile.attributes     = _empty_attributes()
		PlayerProfile.attribute_points = 0
		PlayerProfile.inventory      = []
		PlayerProfile.quickslots     = ["", "", ""]
		PlayerProfile.equipment      = EMPTY_EQUIPMENT.duplicate()
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
	# После перехода на конструктор все персонажи используют одну Player-сцену.
	# Старый путь намеренно не читаем: он мог указывать на Dullahan или другую
	# сцену с несовместимой структурой сетевых узлов.
	PlayerProfile.hero_scene     = PLAYER_SCENE_PATH if not PlayerProfile.character_name.is_empty() else ""
	PlayerProfile.level          = data.get("level",      1)
	PlayerProfile.experience     = data.get("experience", 0)
	PlayerProfile.attributes     = _normalize_attributes(data.get("attributes", {}))
	PlayerProfile.attribute_points = max(0, int(data.get("attribute_points", 0)))
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
# СОХРАНЕНИЕ МИРА
# Данные героя сюда никогда не попадают.
# =========================================================
func save_world_progress(progress: Dictionary, world_name: String = "") -> bool:
	DirAccess.make_dir_recursive_absolute(WORLD_DIR)
	var selected_name := world_name.strip_edges().validate_filename()
	if selected_name.is_empty():
		selected_name = _active_world_name
	var data := {
		"save_version": SAVE_VERSION,
		"world_name": selected_name,
		"updated_at": Time.get_unix_time_from_system(),
		"progress": progress.duplicate(true),
	}
	return _write_json(get_world_save_path(selected_name), data)


func load_world_progress(world_name: String = "") -> Dictionary:
	var data := _peek_save(get_world_save_path(world_name))
	var progress: Variant = data.get("progress", {})
	return progress.duplicate(true) if progress is Dictionary else {}


func list_worlds() -> Array:
	DirAccess.make_dir_recursive_absolute(WORLD_DIR)
	var result: Array = []
	var dir := DirAccess.open(WORLD_DIR)
	if dir == null:
		return result
	var prefix := _save_prefix() + "__"
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if file_name.begins_with(prefix) and file_name.ends_with(".json"):
			var path := WORLD_DIR + file_name
			var data := _peek_save(path)
			var fallback := file_name.trim_prefix(prefix).trim_suffix(".json")
			result.append({
				"name": str(data.get("world_name", fallback)),
				"path": path,
				"updated_at": float(data.get("updated_at", FileAccess.get_modified_time(path))),
			})
		file_name = dir.get_next()
	dir.list_dir_end()
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("updated_at", 0.0)) > float(b.get("updated_at", 0.0)))
	return result


func create_world(world_name: String) -> bool:
	var clean_world := world_name.strip_edges().validate_filename()
	if clean_world.is_empty():
		return false
	if FileAccess.file_exists(get_world_save_path(clean_world)):
		push_warning("SaveManager: мир '%s' уже существует" % clean_world)
		return false
	_active_world_name = clean_world
	return save_world_progress({}, clean_world)


func select_world(world: Variant) -> void:
	var world_name := str(world.get("name", "")) if world is Dictionary else str(world)
	var clean_world := world_name.strip_edges().validate_filename()
	_active_world_name = clean_world if not clean_world.is_empty() else "default"


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


func _empty_attributes() -> Dictionary:
	return {"strength": 0, "agility": 0, "intellect": 0, "wisdom": 0}


func _normalize_attributes(raw: Variant) -> Dictionary:
	var result := _empty_attributes()
	if raw is Dictionary:
		for key in result:
			result[key] = max(0, int(raw.get(key, 0)))
	return result


func _write_json(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: не удалось открыть файл для записи: %s" % path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true


func _remove_file(path: String) -> Error:
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# Бесшовная миграция старой схемы, где персонаж лежал в saves.
func _migrate_legacy_characters() -> void:
	DirAccess.make_dir_recursive_absolute(CHARACTER_DIR)
	var legacy := DirAccess.open(LEGACY_SAVE_DIR)
	if legacy == null:
		return
	var prefix := _save_prefix()
	var legacy_files: Array[String] = []
	legacy.list_dir_begin()
	var file_name := legacy.get_next()
	while not file_name.is_empty():
		var belongs_to_player := file_name == prefix + ".json" or file_name.begins_with(prefix + "__")
		if file_name.ends_with(".json") and belongs_to_player:
			legacy_files.append(file_name)
		file_name = legacy.get_next()
	legacy.list_dir_end()

	for legacy_file in legacy_files:
		var legacy_path := LEGACY_SAVE_DIR + legacy_file
		var target := CHARACTER_DIR + legacy_file
		var migration_complete := FileAccess.file_exists(target)
		if not migration_complete:
			var legacy_data := _peek_save(legacy_path)
			if not legacy_data.is_empty():
				legacy_data["save_version"] = SAVE_VERSION
				legacy_data["attributes"] = _normalize_attributes(legacy_data.get("attributes", {}))
				legacy_data["attribute_points"] = max(0, int(legacy_data.get("attribute_points", 0)))
				migration_complete = _write_json(target, legacy_data)

		# Миграция должна быть одноразовым переносом. Повреждённый исходник
		# оставляем на месте, чтобы данные можно было восстановить вручную.
		if migration_complete:
			var remove_result := _remove_file(legacy_path)
			if remove_result != OK:
				push_warning("SaveManager: не удалось убрать старое сохранение '%s' (ошибка %d)" % [legacy_path, remove_result])
