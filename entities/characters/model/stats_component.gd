# StatsComponent.gd
# Считает итоговые показатели героя:
#   Характеристика = base + per_level*(level-1) + бонусы снаряжения
#   Показатель     = base + бонусы снаряжения + производные от характеристик
extends Node
class_name StatsComponent

# ── сигналы ─────────────────────────────────────────────
signal stats_changed
signal level_increased(new_level: int)
signal downed
signal died
signal revived
signal damage_received(amount: int, magical: bool)

# ── базовые статы героя ──────────────────────────────────
@export var base_stats: CharacterStats
@export var uses_player_progress: bool = true

@onready var equipment: EquipmentComponent = get_node_or_null("../EquipmentComponent") as EquipmentComponent
@onready var effects: EffectsComponent     = get_node_or_null("../EffectsComponent") as EffectsComponent

# ── текущий уровень (берётся из PlayerProfile) ───────────
var level: int = 1
var experience: int = 0
var attribute_points: int = 0
var attributes: Dictionary = {
	"strength": 0,
	"agility": 0,
	"intellect": 0,
	"wisdom": 0,
}

const ATTRIBUTE_NAMES := ["strength", "agility", "intellect", "wisdom"]
const EXPERIENCE_PER_LEVEL := 100
const ATTRIBUTE_POINTS_PER_LEVEL := 1

# ── текущие значения ─────────────────────────────────────
var current_health: int = 0
var current_mana: int   = 0
var current_morale: int = 0
var current_shield: float = 0.0  # поглощает урон до HP; наполняется эффектами

# Последние максимумы нужны, потому что сигнал EquipmentComponent.changed
# приходит уже после замены предмета.
var _last_max_health: int = 1
var _last_max_mana: int = 1
var _last_max_morale: int = 0

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

	# Свой герой берёт прогресс из локального файла персонажа,
	# чужой — из проверенного хостом network_state.
	if uses_player_progress:
		var net_state: Dictionary = get_parent().get_meta("network_state", {})
		level = int(net_state.get("level", PlayerProfile.level))
		experience = int(net_state.get("experience", PlayerProfile.experience))
		attribute_points = int(net_state.get("attribute_points", PlayerProfile.attribute_points))
		var loaded_attributes: Variant = net_state.get("attributes", PlayerProfile.attributes)
		if loaded_attributes is Dictionary:
			for attribute_name in ATTRIBUTE_NAMES:
				attributes[attribute_name] = max(0, int(loaded_attributes.get(attribute_name, 0)))

	if equipment:
		equipment.changed.connect(_on_equipment_changed)

	current_health = int(get_stat("health"))
	current_mana   = int(get_stat("mana"))
	current_morale = int(get_stat("morale"))
	_remember_resource_maximums()


# ════════════════════════════════════════════════════════
# PROCESS — таймер агонии
# ════════════════════════════════════════════════════════
func _process(delta: float) -> void:
	if SteamLobby.is_session_active() and not get_parent().is_multiplayer_authority():
		return

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

	var value: float = base_stats.get_characteristic(name)
	value += float(attributes.get(name, 0))

	if equipment:
		for item in equipment.get_all_items():
			var bonus: Variant = item.get("bonus_" + name)
			if bonus != null:
				value += float(bonus)

	if effects:
		value += effects.get_characteristic_bonus(name)

	return value


# ════════════════════════════════════════════════
# РАЗВИТИЕ ПЕРСОНАЖА
# В сетевой игре любое изменение сначала проверяет хост.
# ════════════════════════════════════════════════
func request_spend_attribute(attribute_name: String) -> void:
	if not uses_player_progress:
		return
	if not ATTRIBUTE_NAMES.has(attribute_name) or attribute_points <= 0:
		return
	if SteamLobby.is_session_active():
		SteamLobby.request_spend_attribute(attribute_name)
		return
	_apply_spent_attribute(attribute_name)
	_save_local_progress()


func add_experience(amount: int) -> void:
	if not uses_player_progress or amount <= 0:
		return
	experience += amount
	while experience >= EXPERIENCE_PER_LEVEL:
		experience -= EXPERIENCE_PER_LEVEL
		level += 1
		attribute_points += ATTRIBUTE_POINTS_PER_LEVEL
		level_increased.emit(level)
	_save_local_progress()
	stats_changed.emit()


func _apply_spent_attribute(attribute_name: String) -> bool:
	if not ATTRIBUTE_NAMES.has(attribute_name) or attribute_points <= 0:
		return false
	attributes[attribute_name] = int(attributes.get(attribute_name, 0)) + 1
	attribute_points -= 1
	_preserve_resource_ratios_after_stat_change()
	stats_changed.emit()
	return true


func get_progress_data() -> Dictionary:
	return {
		"level": level,
		"experience": experience,
		"attributes": attributes.duplicate(true),
		"attribute_points": attribute_points,
	}


func apply_progress_data(data: Dictionary, persist_for_owner: bool = true) -> void:
	var previous_level := level
	level = max(1, int(data.get("level", level)))
	experience = max(0, int(data.get("experience", experience)))
	attribute_points = max(0, int(data.get("attribute_points", attribute_points)))
	var incoming: Variant = data.get("attributes", attributes)
	if incoming is Dictionary:
		for attribute_name in ATTRIBUTE_NAMES:
			attributes[attribute_name] = max(0, int(incoming.get(attribute_name, 0)))
	_preserve_resource_ratios_after_stat_change()
	if level > previous_level:
		level_increased.emit(level)
	if uses_player_progress and persist_for_owner and get_parent().is_multiplayer_authority():
		_save_local_progress()
	stats_changed.emit()


func _save_local_progress() -> void:
	if not uses_player_progress or not get_parent().is_multiplayer_authority():
		return
	PlayerProfile.level = level
	PlayerProfile.experience = experience
	PlayerProfile.attributes = attributes.duplicate(true)
	PlayerProfile.attribute_points = attribute_points
	SaveManager.save_profile()


func _clamp_resources_to_maximums() -> void:
	current_health = clamp(current_health, 0, int(get_stat("health")))
	current_mana = clamp(current_mana, 0, int(get_stat("mana")))
	_remember_resource_maximums()


# ════════════════════════════════════════════════════════
# ПОКАЗАТЕЛИ
# ════════════════════════════════════════════════════════
func get_stat(stat_name: String) -> float:

	if base_stats == null:
		return 0.0

	match stat_name:
		"health":
			return _base(stat_name) + get_characteristic("strength") * 10.0 + _equip_bonus(stat_name) + _effect_bonus(stat_name)
		"mana":
			return _base(stat_name) + get_characteristic("wisdom") * 10.0 + _equip_bonus(stat_name) + _effect_bonus(stat_name)
		"attack_speed":
			return _base(stat_name) + get_characteristic("agility") * 10.0 + _equip_bonus(stat_name) + _effect_bonus(stat_name)
		"magical_damage_bonus":
			return _base(stat_name) + get_characteristic("intellect") + _equip_bonus(stat_name) + _effect_bonus(stat_name)
		"morale":
			# База всегда 0 — только бонусы снаряжения и эффектов
			return _equip_bonus(stat_name) + _effect_bonus(stat_name)
		_:
			return _base(stat_name) + _equip_bonus(stat_name) + _effect_bonus(stat_name)


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
	var combat := get_parent().get_node_or_null("WeaponCombat")
	if combat != null:
		amount = combat.mitigate_damage(amount, is_magical)

	var resistance: float = get_stat(
		"magic_resistance" if is_magical else "armor"
	)
	var actual: int = max(1, amount - int(resistance))

	# Щит поглощает урон первым
	if current_shield > 0.0:
		var absorbed: float = min(current_shield, float(actual))
		current_shield -= absorbed
		actual -= int(absorbed)

	damage_received.emit(actual, is_magical)
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
	_preserve_resource_ratios_after_stat_change()
	stats_changed.emit()


func _preserve_resource_ratios_after_stat_change() -> void:
	var new_max_health: int = maxi(0, int(get_stat("health")))
	var new_max_mana: int = maxi(0, int(get_stat("mana")))
	var new_max_morale: int = int(get_stat("morale"))

	current_health = _scaled_resource(current_health, _last_max_health, new_max_health, true)
	current_mana = _scaled_resource(current_mana, _last_max_mana, new_max_mana, false)

	var morale_penalty := _last_max_morale - current_morale
	current_morale = clamp(new_max_morale - morale_penalty, -100, 100)

	_last_max_health = new_max_health
	_last_max_mana = new_max_mana
	_last_max_morale = new_max_morale


func _scaled_resource(current: int, old_maximum: int, new_maximum: int, keep_alive: bool) -> int:
	if new_maximum <= 0:
		return 0
	if old_maximum <= 0:
		return clamp(current, 0, new_maximum)
	var scaled := roundi(float(current) / float(old_maximum) * float(new_maximum))
	if keep_alive and current > 0:
		scaled = max(1, scaled)
	return clamp(scaled, 0, new_maximum)


func _remember_resource_maximums() -> void:
	_last_max_health = max(0, int(get_stat("health")))
	_last_max_mana = max(0, int(get_stat("mana")))
	_last_max_morale = int(get_stat("morale"))


# ════════════════════════════════════════════════════════
# INTERNAL
# ════════════════════════════════════════════════════════

# Базовое значение показателя из CharacterStats (без характеристик и снаряжения)
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


# Сумма бонусов от активных эффектов (баффы/дебаффы) для показателя
func _effect_bonus(stat_name: String) -> float:
	if effects == null:
		return 0.0
	return effects.get_stat_bonus(stat_name)
