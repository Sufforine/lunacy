# StatsComponent.gd
# Считает итоговые показатели героя:
#   Характеристика = base + per_level*(level-1) + бонусы снаряжения
#   Показатель     = base + бонусы снаряжения + производные от характеристик
extends Node
class_name StatsComponent

# ── сигналы ─────────────────────────────────────────────
signal stats_changed
signal downed
signal died
signal revived

# ── базовые статы героя ──────────────────────────────────
@export var base_stats: HeroStat

@onready var equipment: EquipmentComponent = $"../EquipmentComponent"

# ── текущий уровень (берётся из PlayerProfile) ───────────
var level: int = 1

# ── текущие значения ─────────────────────────────────────
var current_health: int = 0
var current_mana: int   = 0
var current_morale: int = 0

# ── агония ───────────────────────────────────────────────
var is_downed: bool  = false
var is_dead: bool    = false
var _agony_timer: float = 0.0


# ════════════════════════════════════════════════════════
# READY
# ════════════════════════════════════════════════════════
func _ready() -> void:

	if base_stats == null:
		push_error("StatsComponent: base_stats не назначен в инспекторе")
		return

	level = PlayerProfile.level

	if equipment:
		equipment.changed.connect(_on_equipment_changed)

	current_health = int(get_stat("health"))
	current_mana   = int(get_stat("mana"))
	current_morale = int(get_stat("morale"))


# ════════════════════════════════════════════════════════
# PROCESS — таймер агонии
# ════════════════════════════════════════════════════════
func _process(delta: float) -> void:

	if not is_downed or is_dead:
		return

	_agony_timer -= delta

	if _agony_timer <= 0.0:
		_agony_timer = 0.0
		_trigger_death()

	stats_changed.emit()


# ════════════════════════════════════════════════════════
# ХАРАКТЕРИСТИКИ
# Итог = base_per_level(level) + бонусы снаряжения
# ════════════════════════════════════════════════════════
func get_characteristic(name: String) -> float:

	if base_stats == null:
		return 0.0

	var value: float = base_stats.get_characteristic(name, level)

	if equipment:
		for item in equipment.get_all_items():
			var bonus: Variant = item.get("bonus_" + name)
			if bonus != null:
				value += float(bonus)

	return value


# ════════════════════════════════════════════════════════
# ПОКАЗАТЕЛИ
# ════════════════════════════════════════════════════════
func get_stat(stat_name: String) -> float:

	if base_stats == null:
		return 0.0

	match stat_name:
		"health":
			return _base(stat_name) + get_characteristic("strength") * 10.0
		"mana":
			return _base(stat_name) + get_characteristic("wisdom") * 10.0
		"attack_speed":
			return _base(stat_name) + get_characteristic("agility") * 10.0 + _equip_bonus(stat_name)
		"magical_damage_bonus":
			return _base(stat_name) + get_characteristic("intellect") + _equip_bonus(stat_name)
		"morale":
			# База всегда 0 — только бонусы снаряжения
			return _equip_bonus(stat_name)
		_:
			return _base(stat_name) + _equip_bonus(stat_name)


# Итоговый магический урон предмета/способности с учётом бонусов
func get_magical_damage_total(base_magic: float) -> float:

	var bonus_pct := get_stat("magical_damage_bonus")
	return base_magic * (1.0 + bonus_pct / 100.0)


# ════════════════════════════════════════════════════════
# TAKE DAMAGE / HEAL
# ════════════════════════════════════════════════════════
func take_damage(amount: int, is_magical: bool = false) -> void:

	if is_dead:
		return

	var resistance: float = get_stat(
		"magic_resistance" if is_magical else "armor"
	)
	var actual: int = max(1, amount - int(resistance))

	current_health = max(0, current_health - actual)
	stats_changed.emit()

	if current_health == 0 and not is_downed:
		_trigger_down()


func heal(amount: int) -> void:

	if is_dead:
		return
	current_health = min(current_health + amount, int(get_stat("health")))
	stats_changed.emit()


func restore_mana(amount: int) -> void:

	current_mana = min(current_mana + amount, int(get_stat("mana")))
	stats_changed.emit()


# ════════════════════════════════════════════════════════
# АГОНИЯ
# ════════════════════════════════════════════════════════
func get_agony_duration() -> float:
	return max(1.0, 100.0 + float(current_morale))


func get_agony_progress() -> float:
	var total := get_agony_duration()
	return clamp(_agony_timer / total, 0.0, 1.0) if total > 0.0 else 0.0


func _trigger_down() -> void:
	is_downed      = true
	current_health = 0
	current_morale = clamp(current_morale - 10, -100, 100)
	_agony_timer   = get_agony_duration()
	print("StatsComponent: %s упал. Дух: %d, агония: %.0f сек" % [
		get_parent().name, current_morale, _agony_timer])
	downed.emit()
	stats_changed.emit()


func _trigger_death() -> void:
	is_dead   = true
	is_downed = false
	print("StatsComponent: %s погиб." % get_parent().name)
	died.emit()
	stats_changed.emit()


func revive(revive_health: int = 1) -> void:
	if not is_downed or is_dead:
		return
	is_downed      = false
	_agony_timer   = 0.0
	current_health = max(1, revive_health)
	revived.emit()
	stats_changed.emit()


# ════════════════════════════════════════════════════════
# ПЕРЕСЧЁТ ПРИ СМЕНЕ СНАРЯЖЕНИЯ
# ════════════════════════════════════════════════════════
func _on_equipment_changed() -> void:

	var old_max_hp:    float = get_stat("health")
	var old_max_mana:  float = get_stat("mana")
	var old_max_morale: int  = int(get_stat("morale"))

	var new_max_hp:    int   = int(get_stat("health"))
	var new_max_mana:  int   = int(get_stat("mana"))
	var new_max_morale: int  = int(get_stat("morale"))

	if old_max_hp > 0:
		current_health = int(float(current_health) / old_max_hp * float(new_max_hp))
	current_health = clamp(current_health, 0, new_max_hp)

	if old_max_mana > 0:
		current_mana = int(float(current_mana) / old_max_mana * float(new_max_mana))
	current_mana = clamp(current_mana, 0, new_max_mana)

	var morale_penalty := old_max_morale - current_morale
	current_morale = clamp(new_max_morale - morale_penalty, -100, 100)

	stats_changed.emit()


# ════════════════════════════════════════════════════════
# INTERNAL
# ════════════════════════════════════════════════════════

# Базовое значение показателя из HeroStat (без характеристик и снаряжения)
func _base(stat_name: String) -> float:
	var val: Variant = base_stats.get(stat_name)
	if val == null:
		return 0.0
	return float(val)


# Сумма бонусов от надетого снаряжения для показателя
func _equip_bonus(stat_name: String) -> float:
	if equipment == null:
		return 0.0
	var total := 0.0
	for item in equipment.get_all_items():
		var bonus: Variant = item.get("bonus_" + stat_name)
		if bonus != null:
			total += float(bonus)
	return total
