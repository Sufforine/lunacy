# CharacterStats.gd
# Универсальные базовые значения игрока или NPC. Развитие конкретного
# игрока хранится отдельно в PlayerProfile.attributes.
extends Resource
class_name CharacterStats

# ════════════════════════════════════════════════════════
# ХАРАКТЕРИСТИКИ — первичные, влияют на показатели
# ════════════════════════════════════════════════════════
@export_group("Strength")
@export var strength: int = 10

@export_group("Agility")
@export var agility: int = 10

@export_group("Intellect")
@export var intellect: int = 10

@export_group("Wisdom")
@export var wisdom: int = 10

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


# Получить базовое значение характеристики.
func get_characteristic(stat_name: String) -> float:
	var base: Variant = get(stat_name)
	if base == null:
		return 0.0
	return float(base)
