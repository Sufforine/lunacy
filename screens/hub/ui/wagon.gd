extends Node3D

@export var gathering_radius: float = 4.0
@export var countdown_seconds: float = 5.0
var _selected := false
var _remaining := 5.0
var _departing := false
var _last_status := ""
@onready var label: Label3D = $Label3D


func request_departure() -> void:
	if not SteamLobby.is_session_active() or multiplayer.is_server():
		_select_mission(multiplayer.get_unique_id())
	else:
		_request_departure.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_departure() -> void:
	if multiplayer.is_server():
		_select_mission(multiplayer.get_remote_sender_id())


func _select_mission(peer_id: int) -> void:
	if SteamLobby.is_gameplay_locked() or _departing:
		return
	var player := get_parent().get_node_or_null(str(peer_id)) as Player
	var board := get_parent().get_node("runouts") as Node3D
	if player == null or player.global_position.distance_to(board.global_position) > 3.0:
		return
	if not _selected:
		_selected = true
		_remaining = countdown_seconds


func _process(delta: float) -> void:
	if SteamLobby.is_session_active() and not multiplayer.is_server():
		return
	if _departing or SteamLobby.is_gameplay_locked():
		return
	if not _selected:
		_show_status("")
		return
	var peers: Array = [1]
	if SteamLobby.is_session_active():
		peers = [multiplayer.get_unique_id()]
		for id in multiplayer.get_peers():
			peers.append(int(id))
	var ready := 0
	for id in peers:
		var player := get_parent().get_node_or_null(str(id)) as Player
		if player != null and not player.stats.is_dead and not player.stats.is_downed:
			if player.global_position.distance_to(global_position) <= gathering_radius:
				ready += 1
	if ready != peers.size():
		_remaining = countdown_seconds
		_show_status("")
		return
	_remaining -= delta
	_show_status("Миссия 1\nОтправление через %d" % maxi(0, int(ceil(_remaining))))
	if _remaining <= 0:
		_departing = true
		SteamLobby.request_scene_change(SteamLobby.MISSION_SCENE)


func _show_status(message: String) -> void:
	if message == _last_status:
		return
	_last_status = message
	if SteamLobby.is_session_active():
		_status.rpc(message)
	else:
		_status(message)


@rpc("authority", "call_local", "reliable")
func _status(message: String) -> void:
	label.text = message
	label.visible = not message.is_empty()
