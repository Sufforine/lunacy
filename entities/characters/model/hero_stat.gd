# HeroStat.gd
# Resource для каждого героя. Создавай .tres файлы: New Resource → HeroStat
# Базовые значения + прирост за уровень редактируются прямо в инспекторе.
extends Resource
class_name HeroStat

# ════════════════════════════════════════════════════════
# ХАРАКТЕРИСТИКИ — первичные, влияют на показатели
# ════════════════════════════════════════════════════════
@export_group("Strength")
@export var strength: int = 10
@export var strength_per_level: float = 2.0   # +X за уровень

@export_group("Agility")
@export var agility: int = 10
@export var agility_per_level: float = 1.5

@export_group("Intellect")
@export var intellect: int = 10
@export var intellect_per_level: float = 1.5

@export_group("Wisdom")
@export var wisdom: int = 10
@export var wisdom_per_level: float = 1.5

# ════════════════════════════════════════════════════════
# ПОКАЗАТЕЛИ — вторичные, базовые значения
# ════════════════════════════════════════════════════════
@export_group("Combat")
@export var health: int = 100          # итого = health + strength * 10
@export var mana: int = 50             # итого = mana + wisdom * 10
@export var armor: int = 0
@export var magic_resistance: int = 0

@export_group("Damage")
@export var attack_speed: float = 1.0  # итого = attack_speed + agility * 10
@export var physical_damage_bonus: float = 0.0   # % усиления физ урона оружия
@export var magical_damage_bonus: float = 0.0    # % усиления маг урона (+= intellect)

@export_group("Movement")
@export var move_speed: float = 5.0

@export_group("Critical")
@export var crit_chance: float = 0.05
@export var crit_multiplier: float = 1.5

@export_group("Utility")
@export var duration: float = 0.0     # % увеличения длительности эффектов
@export var radius: float = 0.0       # бонус к радиусу способностей

@export_group("Morale")
@export var morale: int = 0           # база всегда 0, только бонусы от снаряжения


# Получить значение характеристики с учётом уровня
func get_characteristic(stat_name: String, level: int) -> float:
	var base: Variant = get(stat_name)
	var growth: Variant = get(stat_name + "_per_level")
	if base == null:
		return 0.0
	if growth == null:
		return float(base)
	return float(base) + float(growth) * max(0, level - 1)
