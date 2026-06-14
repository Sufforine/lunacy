extends Node
class_name StatsComponent

@export var base_stats: HeroStat

@onready var equipment: EquipmentComponent = $"../EquipmentComponent"

var current_health: int
var current_mana: int


func _ready():
	current_health = get_stat("health")
	current_mana = get_stat("mana")


func get_stat(stat_name: String):

	var value = base_stats.get(stat_name)

	for item in equipment.get_all_items():
		value += item.get(stat_name)

	return value


func take_damage(amount: int):

	current_health -= amount

	if current_health <= 0:
		current_health = 0
		print("Dead")
