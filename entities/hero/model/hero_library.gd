# HeroLibrary.gd — Autoload
# Project Settings → Autoload → имя "HeroLibrary"
#
# КАК ДОБАВИТЬ ГЕРОЯ:
# 1. Создай res://Heroes/<name>/<name>.tres (New Resource → HeroDefinition)
# 2. Заполни id, hero_name, icon, scene (.tscn героя)
# 3. Добавь preload() в список ниже
extends Node

var _heroes: Dictionary = {}  # id → HeroDefinition


func _ready() -> void:
	_register_all([
		preload("res://entities/hero/model/definitions/Dullahan/Dullahan_def.tres"),
		preload("res://entities/hero/model/definitions/Slon/Slon_def.tres"),
		# добавляй сюда новых героев
	])


func get_hero(id: String) -> HeroDefinition:
	if not _heroes.has(id):
		push_error("HeroLibrary: герой не найден → '%s'" % id)
		return null
	return _heroes[id]


func all_heroes() -> Array:
	return _heroes.values()


func _register_all(list: Array) -> void:
	for hero in list:
		if hero == null or not hero is HeroDefinition:
			push_warning("HeroLibrary: некорректный элемент в списке")
			continue
		if hero.id.is_empty():
			push_error("HeroLibrary: герой без id: %s" % hero.hero_name)
			continue
		_heroes[hero.id] = hero
		print("HeroLibrary: зарегистрирован '%s'" % hero.id)
