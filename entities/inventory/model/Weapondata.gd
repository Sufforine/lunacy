# WeaponData.gd
# Специализация ItemData для оружия. slot всегда WEAPON,
# is_consumable всегда false — оружие нельзя использовать как расходник.
#
# Тип урона определяется тем, какие коэффициенты заполнены:
#   strength_ratio / agility_ratio  → физический урон
#   intellect_ratio / wisdom_ratio  → магический урон
# Оружие может скейлиться от обоих типов одновременно (гибридное оружие) —
# тогда физическая и магическая часть считаются и наносятся раздельно.
extends ItemData
class_name WeaponData

@export_group("Damage Scaling — Physical")
@export var physical_base_damage: float = 40.0
@export var strength_ratio: float = 0.0   # доля силы в физ. уроне (0.7 = 70%)
@export var agility_ratio: float = 0.0    # доля ловкости в физ. уроне

@export_group("Damage Scaling — Magical")
@export var magical_base_damage: float = 0.0
@export var intellect_ratio: float = 0.0  # доля интеллекта в маг. уроне
@export var wisdom_ratio: float = 0.0     # доля мудрости в маг. уроне

@export_group("Weapon Info")
@export var attack_range: float = 1.5


func _init() -> void:
	slot = ItemData.Slot.WEAPON
	is_consumable = false


# Скрыть поля, неприменимые к оружию: слот всегда WEAPON, расходовать нельзя.
func _validate_property(property: Dictionary) -> void:
	if property.name in ["slot", "is_consumable"]:
		property.usage = PROPERTY_USAGE_NONE


# ════════════════════════════════════════════════════════
# УРОН
# ════════════════════════════════════════════════════════

# Есть ли у оружия физическая составляющая урона
func has_physical_damage() -> bool:
	return physical_base_damage > 0.0 or strength_ratio > 0.0 or agility_ratio > 0.0


# Есть ли у оружия магическая составляющая урона
func has_magical_damage() -> bool:
	return magical_base_damage > 0.0 or intellect_ratio > 0.0 or wisdom_ratio > 0.0


func get_physical_damage(stats: StatsComponent) -> float:

	if not has_physical_damage():
		return 0.0

	var raw := physical_base_damage \
		+ strength_ratio * stats.get_characteristic("strength") \
		+ agility_ratio  * stats.get_characteristic("agility")

	var bonus_pct := stats.get_stat("physical_damage_bonus")
	return raw * (1.0 + bonus_pct / 100.0)


func get_magical_damage(stats: StatsComponent) -> float:

	if not has_magical_damage():
		return 0.0

	var raw := magical_base_damage \
		+ intellect_ratio * stats.get_characteristic("intellect") \
		+ wisdom_ratio    * stats.get_characteristic("wisdom")

	return stats.get_magical_damage_total(raw)


# Итог: {"physical": x, "magical": y} — удобно для нанесения раздельного урона
func get_damage_breakdown(stats: StatsComponent) -> Dictionary:
	return {
		"physical": get_physical_damage(stats),
		"magical":  get_magical_damage(stats),
	}
