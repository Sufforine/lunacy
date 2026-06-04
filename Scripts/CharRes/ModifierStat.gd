extends Resource
class_name ModifierStat

@export_group("Damage")
@export var physical_damage: int = 0
@export var magical_damage: int = 0

@export_group("Defense")
@export var physical_resistance: int = 0
@export var magical_resistance: int = 0

@export_group("Resources")
@export var health: int = 0
@export var mana: int = 0

@export_group("Combat")
@export var attack_speed: float = 0.0
@export var crit_chance: float = 0.0
@export var crit_damage: float = 0.0

@export_group("Movement")
@export var move_speed: float = 0.0
