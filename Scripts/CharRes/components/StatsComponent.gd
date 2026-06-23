extends Node
class_name StatsComponent

# ── сигналы ─────────────────────────────────────────────
signal stats_changed
signal downed                  # HP упал до 0, начата агония
signal died                    # агония завершилась смертью
signal revived                 # подняли союзники до конца агонии

# ── базовые статы ────────────────────────────────────────
@export var base_stats: HeroStat

@onready var equipment: EquipmentComponent = $"../EquipmentComponent"

# ── текущие значения ─────────────────────────────────────
var current_health: int = 0
var current_mana: int   = 0

# ── боевой дух: хранится отдельно, изменяется при падениях
# Стартовое значение берётся из base_stats.morale при _ready()
var current_morale: int = 0

# ── состояние агонии ─────────────────────────────────────
var is_downed: bool  = false
var is_dead: bool    = false
var _agony_timer: float = 0.0   # сколько секунд осталось в агонии


# ════════════════════════════════════════════════════════
# READY
# ════════════════════════════════════════════════════════
func _ready() -> void:

	if base_stats == null:
		push_error("StatsComponent: base_stats не назначен в инспекторе")
		return

	if equipment:
		equipment.changed.connect(_on_equipment_changed)

	current_health = int(get_stat("health"))
	current_mana   = int(get_stat("mana"))
	current_morale = int(get_stat("morale"))  # 0 + bonus_morale от снаряжения


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

	stats_changed.emit()  # чтобы UI полосы агонии обновлялся


# ════════════════════════════════════════════════════════
# GET STAT
# ════════════════════════════════════════════════════════
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


# ════════════════════════════════════════════════════════
# TAKE DAMAGE
# ════════════════════════════════════════════════════════
func take_damage(amount: int, is_magical: bool = false) -> void:

	if is_dead:
		return

	var resistance: float = get_stat(
		"magical_resistance" if is_magical else "physical_resistance"
	)
	var actual: int = max(1, amount - int(resistance))

	current_health = max(0, current_health - actual)
	stats_changed.emit()

	if current_health == 0 and not is_downed:
		_trigger_down()


# ════════════════════════════════════════════════════════
# HEAL
# ════════════════════════════════════════════════════════
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

# Сколько секунд длится агония при текущем боевом духе
func get_agony_duration() -> float:
	return max(1.0, 100.0 + float(current_morale))


# Сколько времени осталось (0.0 - 1.0 от максимума) — для UI
func get_agony_progress() -> float:
	var total := get_agony_duration()
	if total <= 0.0:
		return 0.0
	return clamp(_agony_timer / total, 0.0, 1.0)


func _trigger_down() -> void:

	is_downed    = true
	current_health = 0

	# Уменьшить боевой дух на 10 за каждое падение
	current_morale = clamp(current_morale - 10, -100, 100)

	_agony_timer = get_agony_duration()

	print("StatsComponent: %s упал. Моральный дух: %d, агония: %.0f сек" % [
		get_parent().name, current_morale, _agony_timer
	])

	downed.emit()
	stats_changed.emit()


func _trigger_death() -> void:

	is_dead  = true
	is_downed = false

	print("StatsComponent: %s погиб окончательно." % get_parent().name)
	died.emit()
	stats_changed.emit()


# Поднять игрока (союзником или предметом)
# revive_health — сколько HP восстановить (по умолчанию 1)
func revive(revive_health: int = 1) -> void:

	if not is_downed or is_dead:
		return

	is_downed      = false
	_agony_timer   = 0.0
	current_health = max(1, revive_health)

	print("StatsComponent: %s поднят с %d HP" % [get_parent().name, current_health])
	revived.emit()
	stats_changed.emit()


# ════════════════════════════════════════════════════════
# ПЕРЕСЧЁТ ПРИ СМЕНЕ СНАРЯЖЕНИЯ
# ════════════════════════════════════════════════════════
func _on_equipment_changed() -> void:

	var old_max_hp:   float = get_stat("health")
	var old_max_mana: float = get_stat("mana")
	var old_max_morale: int = int(get_stat("morale"))

	var new_max_hp:    int = int(get_stat("health"))
	var new_max_mana:  int = int(get_stat("mana"))
	var new_max_morale: int = int(get_stat("morale"))

	if old_max_hp > 0:
		current_health = int(float(current_health) / old_max_hp * float(new_max_hp))
	current_health = clamp(current_health, 0, new_max_hp)

	if old_max_mana > 0:
		current_mana = int(float(current_mana) / old_max_mana * float(new_max_mana))
	current_mana = clamp(current_mana, 0, new_max_mana)

	# Сохранить штраф за падения: разница от старого максимума переносится на новый
	var morale_penalty: int = old_max_morale - current_morale
	current_morale = clamp(new_max_morale - morale_penalty, -100, 100)

	stats_changed.emit()
