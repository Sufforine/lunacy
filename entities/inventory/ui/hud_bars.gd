# hud_bars.gd
# Полоски HP / Mana / Shield. Строится полностью программно —
# не требует ручной настройки .tscn, поэтому не ломается от
# расхождения путей нод.
#
# Использование (из player.gd):
#   var hud := HUDBars.new()
#   $CanvasLayer.add_child(hud)
#   hud.bind(stats)
extends Control
class_name HUDBars

const BAR_WIDTH  := 220.0
const BAR_HEIGHT := 18.0
const BAR_GAP    := 4.0

var _stats: StatsComponent = null

var _hp_track:  ColorRect
var _hp_fill:   ColorRect
var _shield_fill: ColorRect
var _hp_label:  Label

var _mp_track:  ColorRect
var _mp_fill:   ColorRect
var _mp_label:  Label


# ════════════════════════════════════════════════════════
# READY — строим всю иерархию нод программно
# ════════════════════════════════════════════════════════
func _ready() -> void:

	# Сам виджет — верхний левый угол экрана
	anchor_left = 0.0
	anchor_top  = 0.0
	position    = Vector2(16, 16)
	size        = Vector2(BAR_WIDTH, BAR_HEIGHT * 2 + BAR_GAP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# ── Health ────────────────────────────────────────────
	_hp_track = _make_rect(Vector2(0, 0), Vector2(BAR_WIDTH, BAR_HEIGHT), Color(0.08, 0.08, 0.08, 0.85))
	add_child(_hp_track)

	_hp_fill = _make_rect(Vector2(0, 0), Vector2(BAR_WIDTH, BAR_HEIGHT), Color(0.75, 0.15, 0.15, 1.0))
	_hp_track.add_child(_hp_fill)

	# Щит — полупрозрачный слой ПОВЕРХ полоски здоровья.
	# Добавлен после _hp_fill, поэтому рисуется сверху.
	_shield_fill = _make_rect(Vector2(0, 0), Vector2(0, BAR_HEIGHT), Color(0.4, 0.8, 1.0, 0.55))
	_hp_track.add_child(_shield_fill)

	_hp_label = _make_label()
	_hp_track.add_child(_hp_label)

	# ── Mana ──────────────────────────────────────────────
	var mp_y := BAR_HEIGHT + BAR_GAP

	_mp_track = _make_rect(Vector2(0, mp_y), Vector2(BAR_WIDTH, BAR_HEIGHT), Color(0.08, 0.08, 0.08, 0.85))
	add_child(_mp_track)

	_mp_fill = _make_rect(Vector2(0, 0), Vector2(BAR_WIDTH, BAR_HEIGHT), Color(0.2, 0.4, 0.85, 1.0))
	_mp_track.add_child(_mp_fill)

	_mp_label = _make_label()
	_mp_track.add_child(_mp_label)


# ════════════════════════════════════════════════════════
# BIND
# ════════════════════════════════════════════════════════
func bind(stats: StatsComponent) -> void:

	if _stats != null and _stats.stats_changed.is_connected(_refresh):
		_stats.stats_changed.disconnect(_refresh)

	_stats = stats

	if _stats != null:
		_stats.stats_changed.connect(_refresh)
		_refresh()


# ════════════════════════════════════════════════════════
# REFRESH
# ════════════════════════════════════════════════════════
func _refresh() -> void:

	if _stats == null:
		return

	var max_hp: float = max(1.0, _stats.get_stat("health"))
	var max_mp: float = max(1.0, _stats.get_stat("mana"))

	var hp_ratio: float = clamp(float(_stats.current_health) / max_hp, 0.0, 1.0)
	var mp_ratio: float = clamp(float(_stats.current_mana)   / max_mp, 0.0, 1.0)
	var shield_ratio: float = clamp(_stats.current_shield / max_hp, 0.0, 1.0)

	_hp_fill.size.x     = BAR_WIDTH * hp_ratio
	_shield_fill.size.x = BAR_WIDTH * shield_ratio
	_mp_fill.size.x     = BAR_WIDTH * mp_ratio

	_hp_label.text = "%d / %d" % [_stats.current_health, int(max_hp)]
	if _stats.current_shield > 0.0:
		_hp_label.text += "  (+%d)" % int(_stats.current_shield)

	_mp_label.text = "%d / %d" % [_stats.current_mana, int(max_mp)]


# ════════════════════════════════════════════════════════
# HELPERS
# ════════════════════════════════════════════════════════
func _make_rect(pos: Vector2, sz: Vector2, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = pos
	r.size = sz
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.clip_contents = true
	return r


func _make_label() -> Label:
	var l := Label.new()
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 12)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
