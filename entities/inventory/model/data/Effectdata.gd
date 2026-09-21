# EffectData.gd
# Описание эффекта (баффа/дебаффа/пассивки). Создавай .tres файлы:
# New Resource → EffectData
#
# Три режима работы, по значению duration:
#   duration == 0   → мгновенный эффект (применился один раз и всё, как зелье)
#   duration > 0    → временный эффект, снимается сам через duration секунд
#   duration == -1  → постоянный, пока источник не уберут вручную
#                      (например пока предмет надет — EquipmentComponent
#                      сам вызовет remove_effect при снятии)
#
# tick_interval > 0 запускает effect_script.on_tick() каждые N секунд —
# именно так делается "щит раз в 10 секунд": duration = -1, tick_interval = 10.
#
# stat_modifiers — простые баффы без кода: например {"armor": 20} даёт
# +20 брони, пока эффект активен. Работает через StatsComponent автоматически.
#
# effect_script — GDScript наследующий EffectLogic, для сложной логики
# (что именно происходит на tick, apply, expire).
extends Resource
class_name EffectData

@export var id: String = ""
@export var effect_name: String = ""
@export var icon: Texture2D = null
@export var description: String = ""

@export_group("Timing")
@export var duration: float = 0.0        # 0 = мгновенный, -1 = бессрочный
@export var tick_interval: float = 0.0   # 0 = без тиков

@export_group("Stacking")
@export var max_stacks: int = 1          # 1 = не стакается, обновляет длительность

@export_group("Simple Stat Bonuses")
@export var stat_modifiers: Dictionary = {}       # {"armor": 20, "move_speed": 1.5}
@export var characteristic_modifiers: Dictionary = {}  # {"strength": 5}

@export_group("Custom Logic")
@export var effect_script: Script = null  # extends EffectLogic

@export_group("Visual")
# Скрипт визуала (extends Node3D), создаётся как ребёнок героя пока
# эффект активен и удаляется когда эффект снят. Полностью самодостаточный —
# сам решает как выглядеть и на что реагировать (см. shield_visual.gd).
@export var visual_script: Script = null
@export var visual_offset: Vector3 = Vector3.ZERO
