extends Node

var save_version: int = 1
var hero_scene: String = ""

var level: int = 1
var experience: int = 0

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
	"scroll":     "",
}

func mark_dirty():
	pass
