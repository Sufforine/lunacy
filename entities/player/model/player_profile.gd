extends Node

var save_version: int = 2
var hero_scene: String = ""

# Имя, которое игрок дал персонажу при создании. Пусто = персонаж ещё
# не создан — Start/Host должны требовать создать или выбрать персонажа.
var character_name: String = ""

# Внешность персонажа: {"body": "male"/"female", "skin": "rrggbb", "hair": индекс}.
# Выбирается при создании в главном меню (см. character_models.gd).
var appearance: Dictionary = {"body": "male", "skin": "e0ac69", "hair": 0}

# Unix-время создания — по нему находим «последнего созданного» персонажа
var created_at: float = 0.0

var level: int = 1
var experience: int = 0

# Очки, которые игрок вручную вложил в четыре основные характеристики.
# Базовые значения задаются в сцене Player, здесь хранится только развитие
# конкретного созданного персонажа.
var attributes: Dictionary = {
	"strength": 0,
	"agility": 0,
	"intellect": 0,
	"wisdom": 0,
}
var attribute_points: int = 0

var inventory: Array = []

# 3 слота быстрого доступа (Alt+1/2/3)
var quickslots: Array = ["", "", ""]

var equipment: Dictionary = {
	"weapon":     "",
	"helmet":     "",
	"chestplate": "",
	"leggings":   "",
	"cloak":      "",
	"trinket_1":  "",
	"trinket_2":  "",
}

func mark_dirty():
	pass
