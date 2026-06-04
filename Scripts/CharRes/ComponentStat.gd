extends Node
class_name ComponentStat

@export var base_stats: HeroStat

var modifiers: Array[ModifierStat] = []

var current_health: int
var current_mana: int


func _ready():
	current_health = get_stat("health")
	current_mana = get_stat("mana")


func get_stat(stat_name: String):
	if base_stats == null:
		push_error("Base stats not assigned")
		return 0

	var value = base_stats.get(stat_name)

	for modifier in modifiers:
		value += modifier.get(stat_name)

	return value


func add_modifier(modifier: ModifierStat):
	if modifier not in modifiers:
		modifiers.append(modifier)


func remove_modifier(modifier: ModifierStat):
	modifiers.erase(modifier)


func take_damage(amount: float):

	var damage = max(0, amount)

	current_health -= damage

	if current_health <= 0:
		current_health = 0
		die()


func heal(amount: float):

	current_health += amount

	var max_hp = get_stat("health")

	if current_health > max_hp:
		current_health = max_hp


func spend_mana(amount: float):

	current_mana -= amount

	if current_mana < 0:
		current_mana = 0


func restore_mana(amount: float):

	current_mana += amount

	var max_mana = get_stat("mana")

	if current_mana > max_mana:
		current_mana = max_mana


func die():
	print("Character died")
