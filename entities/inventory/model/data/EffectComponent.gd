# EffectsComponent.gd
# Управляет активными эффектами игрока: баффы, дебаффы, пассивки от снаряжения.
# Ставится рядом с StatsComponent на игроке:
#   Player
#   ├── StatsComponent
#   ├── EquipmentComponent
#   ├── EffectsComponent   ← этот компонент
#   └── ...
extends Node
class_name EffectsComponent

signal effect_applied(active: ActiveEffect)
signal effect_removed(active: ActiveEffect)

@onready var stats: StatsComponent         = $"../StatsComponent"
@onready var equipment: EquipmentComponent = $"../EquipmentComponent"


# Внутреннее представление активного эффекта — данные + прогресс во времени.
class ActiveEffect:
	var data: EffectData
	var source: Object          # что вызвало эффект (ItemData, способность, null)
	var time_left: float = 0.0  # для duration > 0
	var tick_timer: float = 0.0
	var stacks: int = 1
	var logic: EffectLogic = null  # инстанс effect_script, если есть


var _active: Array[ActiveEffect] = []


# ════════════════════════════════════════════════════════
# READY
# ════════════════════════════════════════════════════════
func _ready() -> void:

	if equipment:
		equipment.item_equipped.connect(_on_item_equipped)
		equipment.item_unequipped.connect(_on_item_unequipped)


# ════════════════════════════════════════════════════════
# PROCESS — тики и истечение длительности
# ════════════════════════════════════════════════════════
func _process(delta: float) -> void:

	# Идём с конца, чтобы безопасно удалять во время итерации
	for i in range(_active.size() - 1, -1, -1):
		var active: ActiveEffect = _active[i]

		# Тики
		if active.data.tick_interval > 0.0:
			active.tick_timer -= delta
			if active.tick_timer <= 0.0:
				active.tick_timer += active.data.tick_interval
				if active.logic:
					active.logic.on_tick(get_parent(), stats, self)

		# Длительность (duration == -1 живёт вечно, 0 уже снят сразу после apply)
		if active.data.duration > 0.0:
			active.time_left -= delta
			if active.time_left <= 0.0:
				_remove_active(i)


# ════════════════════════════════════════════════════════
# ПРИМЕНИТЬ ЭФФЕКТ
# ════════════════════════════════════════════════════════
func apply_effect(data: EffectData, source: Object = null) -> void:

	if data == null:
		return

	# Проверить существующий такой же эффект от того же источника — для стаков
	var existing := _find_active(data, source)

	if existing != null:
		if existing.stacks < data.max_stacks:
			existing.stacks += 1
		# Обновить длительность в любом случае (refresh)
		existing.time_left = data.duration
		stats.stats_changed.emit()
		return

	var active := ActiveEffect.new()
	active.data = data
	active.source = source
	active.time_left = data.duration
	active.tick_timer = data.tick_interval

	if data.effect_script != null:
		active.logic = data.effect_script.new()

	_active.append(active)

	if active.logic:
		active.logic.on_apply(get_parent(), stats, self)

	effect_applied.emit(active)
	stats.stats_changed.emit()

	print("EffectsComponent: применён '%s'%s" % [
		data.id,
		(" от " + str(source)) if source else ""
	])

	# Мгновенный эффект — снимаем сразу же после apply
	if data.duration == 0.0:
		_remove_active(_active.find(active))


# ════════════════════════════════════════════════════════
# СНЯТЬ ЭФФЕКТ
# ════════════════════════════════════════════════════════

# Снять все эффекты пришедшие от конкретного источника
# (используется при снятии предмета — убирает его пассивки)
func remove_effects_from_source(source: Object) -> void:

	for i in range(_active.size() - 1, -1, -1):
		if _active[i].source == source:
			_remove_active(i)


func remove_effect_by_id(id: String) -> void:

	for i in range(_active.size() - 1, -1, -1):
		if _active[i].data.id == id:
			_remove_active(i)


func has_effect(id: String) -> bool:
	for active in _active:
		if active.data.id == id:
			return true
	return false


# ════════════════════════════════════════════════════════
# ПОЛУЧЕНИЕ БОНУСОВ — вызывается из StatsComponent
# ════════════════════════════════════════════════════════
func get_stat_bonus(stat_name: String) -> float:

	var total := 0.0
	for active in _active:
		if active.data.stat_modifiers.has(stat_name):
			total += float(active.data.stat_modifiers[stat_name]) * active.stacks
	return total


func get_characteristic_bonus(stat_name: String) -> float:

	var total := 0.0
	for active in _active:
		if active.data.characteristic_modifiers.has(stat_name):
			total += float(active.data.characteristic_modifiers[stat_name]) * active.stacks
	return total


# ════════════════════════════════════════════════════════
# INTERNAL
# ════════════════════════════════════════════════════════
func _find_active(data: EffectData, source: Object) -> ActiveEffect:
	for active in _active:
		if active.data == data and active.source == source:
			return active
	return null


func _remove_active(index: int) -> void:

	if index < 0 or index >= _active.size():
		return

	var active: ActiveEffect = _active[index]

	if active.logic:
		active.logic.on_expire(get_parent(), stats, self)

	_active.remove_at(index)
	effect_removed.emit(active)
	stats.stats_changed.emit()


# ════════════════════════════════════════════════════════
# РЕАКЦИЯ НА СМЕНУ СНАРЯЖЕНИЯ
# Пассивка предмета хранится в ItemData.passive_effect (добавь это поле
# в ItemData когда понадобится первая пассивка на снаряжении).
# ════════════════════════════════════════════════════════
func _on_item_equipped(item: ItemData) -> void:

	if "passive_effect" in item and item.passive_effect != null:
		apply_effect(item.passive_effect, item)


func _on_item_unequipped(item: ItemData) -> void:

	if "passive_effect" in item and item.passive_effect != null:
		remove_effects_from_source(item)
