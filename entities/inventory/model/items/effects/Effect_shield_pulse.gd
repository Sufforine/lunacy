# effect_shield_pulse.gd
# Раз в N секунд (tick_interval из EffectData) даёт герою щит.
#
# Настройка EffectData.tres:
#   duration = -1            (работает пока предмет надет)
#   tick_interval = 10       (раз в 10 секунд)
#   effect_script = effect_shield_pulse.gd   ← эта логика
#   visual_script = shield_visual.gd         ← отдельно отвечает за сферу
#
# Логика и визуал полностью независимы: этот файл ничего не знает
# о том как щит выглядит, shield_visual.gd ничего не знает откуда
# берётся щит — он просто следит за stats.current_shield.
extends EffectLogic

const SHIELD_AMOUNT := 30.0

func on_tick(_player: Node, stats: StatsComponent, _effects: EffectsComponent) -> void:
	if not DamageSystem.is_authority():
		return
	stats.current_shield += SHIELD_AMOUNT
	stats.stats_changed.emit()
	DamageSystem.sync_stats(stats)
	print("effect_shield_pulse: +%.0f щита (всего %.0f)" % [SHIELD_AMOUNT, stats.current_shield])
