extends Resource
class_name WeaponSkill

@export var title: String = ""
@export var icon: Texture2D
@export var animation: StringName = &"Sword_Attack"
@export_range(0.1, 60.0) var cooldown: float = 5.0
@export_range(0.0, 5.0) var hit_delay: float = 0.3
@export var damage_multiplier: float = 1.0
@export var range_multiplier: float = 1.0
@export_range(1.0, 360.0) var arc_degrees: float = 90.0
@export var knockback: float = 0.0
