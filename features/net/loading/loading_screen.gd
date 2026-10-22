class_name NetworkLoadingScreen
extends CanvasLayer

const WAITING_COLOR := Color(0.42, 0.44, 0.48, 1.0)
const READY_COLOR := Color(0.94, 0.97, 1.0, 1.0)
const ERROR_COLOR := Color(1.0, 0.34, 0.34, 1.0)

@onready var title_label: Label = %TitleLabel
@onready var status_label: Label = %StatusLabel
@onready var players_list: VBoxContainer = %PlayersList
@onready var progress_bar: ProgressBar = %ProgressBar

var _player_labels: Dictionary = {}


func configure(players: Array, title: String = "Загрузка миссии") -> void:
	title_label.text = title
	for child in players_list.get_children():
		child.queue_free()
	_player_labels.clear()

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
		label.add_theme_color_override("font_color", WAITING_COLOR)
		players_list.add_child(label)
		_player_labels[peer_id] = label

	_update_status()


func set_player_ready(peer_id: int, ready: bool) -> void:
	var label := _player_labels.get(peer_id) as Label
	if label == null:
		return
	label.add_theme_color_override("font_color", READY_COLOR if ready else WAITING_COLOR)
	_update_status()


func remove_player(peer_id: int) -> void:
	var label := _player_labels.get(peer_id) as Label
	if label != null:
		label.queue_free()
	_player_labels.erase(peer_id)
	_update_status()


func set_status(text: String) -> void:
	status_label.text = text


func set_progress(value: float) -> void:
	progress_bar.value = clampf(value, 0.0, 1.0) * 100.0
	status_label.text = "Загрузка сцены: %d%%" % int(round(progress_bar.value))


func set_player_error(peer_id: int) -> void:
	var label := _player_labels.get(peer_id) as Label
	if label != null:
		label.add_theme_color_override("font_color", ERROR_COLOR)


func _update_status() -> void:
	var ready_count := 0
	for label_value in _player_labels.values():
		var label := label_value as Label
		if label != null and label.get_theme_color("font_color") == READY_COLOR:
			ready_count += 1
	status_label.text = "Готово: %d/%d" % [ready_count, _player_labels.size()]
