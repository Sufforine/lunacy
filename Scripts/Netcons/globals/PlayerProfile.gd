extends Node

var save_version: int = 1
var hero_scene : String = ""

var level : int = 1
var experience : int = 0

var inventory : Array = []

var equipment : Dictionary = {
	"weapon": "",
	"armor": "",
	"trinket_1": "",
	"trinket_2": ""
}

func mark_dirty():
	# можно использовать для автосейва
	pass
