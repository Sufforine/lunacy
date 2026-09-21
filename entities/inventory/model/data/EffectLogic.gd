# EffectLogic.gd
# Базовый класс для кастомной логики эффекта. Наследуй его в отдельном
# .gd файле и назначь в EffectData.effect_script для сложных эффектов
# (щит, поджог, что угодно что не сводится к простому stat_modifiers).
#
# Пример — "щит раз в 10 секунд":
#   extends EffectLogic
#   func on_tick(player, stats, effects) -> void:
#       stats.current_shield += 30
extends RefCounted
class_name EffectLogic

# Вызывается один раз в момент применения эффекта
func on_apply(_player: Node, _stats: StatsComponent, _effects: EffectsComponent) -> void:
	pass

# Вызывается каждые effect_data.tick_interval секунд, если tick_interval > 0
func on_tick(_player: Node, _stats: StatsComponent, _effects: EffectsComponent) -> void:
	pass

# Вызывается когда эффект снят — по истечении duration или вручную
func on_expire(_player: Node, _stats: StatsComponent, _effects: EffectsComponent) -> void:
	pass
