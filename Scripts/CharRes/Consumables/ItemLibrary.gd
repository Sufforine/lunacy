# ItemLibrary.gd
# Автозагрузка (Autoload). Project → Project Settings → Autoload
# Имя синглтона: ItemLibrary
#
# КАК ДОБАВИТЬ НОВЫЙ ПРЕДМЕТ:
# 1. Создай файл: res://Items/my_item.tres (New Resource → ItemData)
# 2. Заполни поля в инспекторе (id, item_name, icon, heal_hp и т.д.)
# 3. Добавь строку ниже в _ready()
extends Node

# Все предметы игры. Ключ — id предмета (String).
var _items: Dictionary = {}


func _ready() -> void:
	# Регистрируем предметы.
	# Пути к .tres файлам — поправь под свою структуру папок.
	_register_all([
		preload("res://Scripts/CharRes/Consumables/health_potion.tres"),
		preload("res://Scripts/CharRes/Consumables/mana_potion.tres"),
		preload("res://Scripts/CharRes/Consumables/big_potion.tres"),
		preload("res://Scripts/CharRes/itemjsons/armor/DullahanCoat.tres"),
		preload("res://Scripts/CharRes/itemjsons/trinkets/SpeedCharm.tres"),
		preload("res://Scripts/CharRes/itemjsons/weapon/Axe.tres"),
	])


# =========================================================
# PUBLIC API
# =========================================================

# Получить предмет по id. Возвращает null если не найден.
func get_item(id: String) -> ItemData:
	if not _items.has(id):
		push_error("ItemLibrary: предмет не найден → '%s'" % id)
		return null
	return _items[id]


func has_item(id: String) -> bool:
	return _items.has(id)


func all_items() -> Array:
	return _items.values()


# =========================================================
# INTERNAL
# =========================================================
func _register_all(list: Array) -> void:
	for item in list:
		if item == null:
			push_warning("ItemLibrary: null предмет в списке")
			continue
		if not item is ItemData:
			push_warning("ItemLibrary: объект не является ItemData: %s" % str(item))
			continue
		if item.id.is_empty():
			push_error("ItemLibrary: предмет без id: %s" % item.item_name)
			continue
		if _items.has(item.id):
			push_warning("ItemLibrary: дублирующий id '%s' — перезаписан" % item.id)
		_items[item.id] = item
		print("ItemLibrary: зарегистрирован '%s'" % item.id)
