class_name NetworkLoadingScreen
extends CanvasLayer

const ERROR_COLOR := Color(1.0, 0.34, 0.34, 1.0)

@onready var background: ColorRect = $Background
@onready var panel: PanelContainer = $Background/Center/Panel
@onready var title_label: Label = %TitleLabel
@onready var status_label: Label = %StatusLabel
@onready var players_list: VBoxContainer = %PlayersList
@onready var progress_bar: ProgressBar = %ProgressBar

var _player_labels: Dictionary = {}
var _player_ready: Dictionary = {}
var _waiting_color := Color(0.42, 0.44, 0.48, 1.0)
var _ready_color := Color(0.94, 0.97, 1.0, 1.0)


func _ready() -> void:
	GameSettings.inventory_theme_changed.connect(_apply_theme)
	GameSettings.ui_scale_changed.connect(_apply_ui_scale)
	panel.resized.connect(_update_scale_pivot)
	_apply_theme()
	_apply_ui_scale()


func configure(players: Array, title: String = "Загрузка миссии") -> void:
	title_label.text = title
	for child in players_list.get_children():
		child.queue_free()
	_player_labels.clear()
	_player_ready.clear()

	var ordered_players := players.duplicate(true)
	ordered_players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("peer_id", 0)) < int(b.get("peer_id", 0)))

	for raw_player in ordered_players:
		var player: Dictionary = raw_player
		var peer_id := int(player.get("peer_id", 0))
		if peer_id <= 0:
			continue
		var character_name := str(player.get("character_name", "")).strip_edges()
		if character_name.is_empty():
			character_name = str(player.get("nickname", "Игрок")).strip_edges()
		if character_name.is_empty():
			character_name = "Игрок %d" % peer_id

		var label := Label.new()
		label.text = character_name
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 26)
		label.add_theme_color_override("font_color", _waiting_color)
		players_list.add_child(label)
		_player_labels[peer_id] = label
		_player_ready[peer_id] = false

	_update_status()


func set_player_ready(peer_id: int, ready: bool) -> void:
	var label := _player_labels.get(peer_id) as Label
	if label == null:
		return
	_player_ready[peer_id] = ready
	label.add_theme_color_override("font_color", _ready_color if ready else _waiting_color)
	_update_status()


func remove_player(peer_id: int) -> void:
	var label := _player_labels.get(peer_id) as Label
	if label != null:
		label.queue_free()
	_player_labels.erase(peer_id)
	_player_ready.erase(peer_id)
	_update_status()


func set_status(text: String) -> void:
	status_label.text = text


func set_progress(value: float) -> void:
	progress_bar.value = clampf(value, 0.0, 1.0) * 100.0
	status_label.text = "Загрузка сцены: %d%%" % int(round(progress_bar.value))


func set_player_error(peer_id: int) -> void:
	var label := _player_labels.get(peer_id) as Label
	if label != null:
		_player_ready[peer_id] = false
		label.add_theme_color_override("font_color", ERROR_COLOR)


func _update_status() -> void:
	var ready_count := 0
	for ready in _player_ready.values():
		if bool(ready):
			ready_count += 1
	status_label.text = "Готово: %d/%d" % [ready_count, _player_labels.size()]


func _apply_ui_scale() -> void:
	panel.scale = Vector2.ONE * GameSettings.get_ui_scale()
	_update_scale_pivot.call_deferred()


func _update_scale_pivot() -> void:
	panel.pivot_offset = panel.size * 0.5


func _apply_theme() -> void:
	var palette := GameSettings.get_ui_theme_palette()
	background.color = palette.dimmer.darkened(0.18)
	_waiting_color = palette.text.darkened(0.38)
	_ready_color = palette.text
	var panel_style := _style(palette.background, palette.border, 3, 14)
	panel_style.content_margin_left = 56.0
	panel_style.content_margin_top = 38.0
	panel_style.content_margin_right = 56.0
	panel_style.content_margin_bottom = 38.0
	panel.add_theme_stylebox_override("panel", panel_style)
	title_label.add_theme_color_override("font_color", palette.text)
	status_label.add_theme_color_override("font_color", palette.text.darkened(0.2))
	progress_bar.add_theme_stylebox_override("background", _style(palette.surface, palette.border, 1, 4))
	progress_bar.add_theme_stylebox_override("fill", _style(palette.accent, palette.border, 1, 4))
	for peer_id in _player_labels:
		var label := _player_labels[peer_id] as Label
		if label != null:
			label.add_theme_color_override("font_color", _ready_color if bool(_player_ready.get(peer_id, false)) else _waiting_color)


func _style(background_color: Color, border_color: Color, width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	return style
