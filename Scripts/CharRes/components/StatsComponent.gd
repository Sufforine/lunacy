extends Node
class_name StatsComponent

signal stats_changed

@export var base_stats: HeroStat

@onready var equipment: EquipmentComponent = $"../EquipmentComponent"

var current_health: int
var current_mana: int


func _ready() -> void:

	if base_stats == null:
		push_error("StatsComponent: base_stats не назначен в инспекторе")
		return

	if equipment:
		equipment.changed.connect(func(): stats_changed.emit())

	current_health = int(get_stat("health"))
	current_mana   = int(get_stat("mana"))


# Возвращает базовый стат + бонусы от снаряжения
func get_stat(stat_name: String) -> float:

	if base_stats == null:
		push_error("StatsComponent.get_stat: base_stats == null")
		return 0.0

	var base: Variant = base_stats.get(stat_name)
	if base == null:
		push_warning("StatsComponent.get_stat: поле '%s' не найдено в HeroStat" % stat_name)
		return 0.0

	var value := float(base)

	if equipment:
		for item in equipment.get_all_items():
			var bonus: Variant = item.get("bonus_" + stat_name)
			if bonus != null:
				value += float(bonus)

	return value


func take_damage(amount: int) -> void:

	var resistance: float = get_stat("physical_resistance")
	var actual: int = max(1, amount - int(resistance))

	current_health = max(0, current_health - actual)
	stats_changed.emit()

	if current_health == 0:
		print("StatsComponent: '%s' погиб" % get_parent().name)
