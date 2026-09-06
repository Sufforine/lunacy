extends Node

var _heroes: Dictionary = {}

func _ready() -> void:
	_register_all([
		preload("res://entities/characters/dullahan/Dullahan.tres"),
	])


func get_hero(id: StringName) -> HeroDefinition:
	if not _heroes.has(id):
		push_error("HeroLibrary: герой не найден → '%s'" % id)
		return null
	return _heroes[id]


func all_heroes() -> Array[HeroDefinition]:
	var result: Array[HeroDefinition] = []
	for value: Variant in _heroes.values():
		result.append(value as HeroDefinition)
	return result


func _register_all(definitions: Array) -> void:
	for value: Variant in definitions:
		var hero := value as HeroDefinition
		if hero == null:
			push_warning("HeroLibrary: некорректный элемент в списке")
			continue
		if hero.id.is_empty():
			push_error("HeroLibrary: герой без id: %s" % hero.hero_name)
			continue
		_heroes[hero.id] = hero
		print("HeroLibrary: зарегистрирован '%s'" % hero.id)
