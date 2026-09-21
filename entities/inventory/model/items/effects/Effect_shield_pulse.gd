# effect_shield_pulse.gd
# Пример кастомного эффекта: раз в N секунд (задаётся tick_interval
# в самом EffectData) даёт герою щит, поглощающий урон.
#
# Как использовать:
# 1. Создай EffectData.tres, назначь этот скрипт в effect_script
# 2. duration = -1 (работает пока предмет надет)
# 3. tick_interval = 10 (раз в 10 секунд)
# 4. Назначь этот EffectData в ItemData.passive_effect у нужного предмета
extends EffectLogic

const SHIELD_AMOUNT := 30.0

func on_tick(_player: Node, stats: StatsComponent, _effects: EffectsComponent) -> void:
	stats.current_shield += SHIELD_AMOUNT
	stats.stats_changed.emit()
	print("effect_shield_pulse: +%.0f щита (всего %.0f)" % [SHIELD_AMOUNT, stats.current_shield])
