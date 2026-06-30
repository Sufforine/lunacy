extends Resource
class_name HeroStat

@export var health: int = 100
@export var mana: int = 50

@export var physical_damage: int = 10
@export var magical_damage: int = 0

@export var physical_resistance: int = 0
@export var magical_resistance: int = 0

@export var move_speed: float = 5.0
@export var attack_speed: float = 1.0

@export var crit_chance: float = 0.05
@export var crit_damage: float = 1.5

# Базовый боевой дух всегда 0 — бонусы дают только предметы снаряжения.
# Не трогай это поле в инспекторе.
var morale: int = 0
