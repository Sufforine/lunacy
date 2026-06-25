# SteamLobby.gd
# Управляет Steam-лобби и спавном игроков.
# Структура: каждый клиент шлёт свой PlayerState хосту,
# хост рассылает всем полный список — все видят всех.
extends Node

signal lobby_ready(lobby_id: int)
signal players_updated(players: Array)

var lobby_id: int = 0
var peer: SteamMultiplayerPeer
var is_host: bool = false
var is_joining: bool = false

@export var player_scene: PackedScene  # не используется — берём из PlayerState

# peer_id → PlayerState. Хранится только на хосте.
var _player_states: Dictionary = {}


# =========================================================
# READY
# =========================================================
func _ready() -> void:

	var init_result = Steam.steamInit(480, true)
	print("Steam initialized: ", init_result)

	await get_tree().process_frame

	print("Steam ID: ", Steam.getSteamID())
	SaveManager.load_profile()
	Steam.initRelayNetworkAccess()
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	print("Loaded hero: ", PlayerProfile.hero_scene)


# =========================================================
# HOST
# =========================================================
func host_lobby() -> void:
	Steam.createLobby(Steam.LobbyType.LOBBY_TYPE_PUBLIC, 4)
	is_host = true


func _on_lobby_created(result: int, id: int) -> void:

	if result != Steam.Result.RESULT_OK:
		push_error("SteamLobby: не удалось создать лобби: %d" % result)
		return

	lobby_id = id
	peer = SteamMultiplayerPeer.new()
	peer.server_relay = true
	peer.create_host()

	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	# Зарегистрировать хоста в _player_states без спавна сцены
	_register_local_player(1)
	lobby_ready.emit(lobby_id)
	print("SteamLobby: лобби создано ", lobby_id)


# =========================================================
# JOIN
# =========================================================
func join_lobby(id: int) -> void:
	is_joining = true
	Steam.joinLobby(id)


func _on_lobby_joined(id: int, _permissions: int, _locked: bool, response: int) -> void:

	if not is_joining:
		return

	lobby_id = id
	peer = SteamMultiplayerPeer.new()
	peer.server_relay = true
	peer.create_client(Steam.getLobbyOwner(lobby_id))
	multiplayer.multiplayer_peer = peer
	is_joining = false
	lobby_ready.emit(lobby_id)

	# Отправить свой PlayerState хосту как только подключимся
	multiplayer.connected_to_server.connect(_on_connected_to_server, CONNECT_ONE_SHOT)


func _on_connected_to_server() -> void:
	# Зарегистрировать себя локально чтобы сразу видеть себя в списке
	_register_local_player(multiplayer.get_unique_id())
	# Отправить свой state хосту
	var state_data := _local_state_to_dict()
	_rpc_send_state.rpc_id(1, state_data)
	print("SteamLobby: отправлен PlayerState хосту")


# =========================================================
# PEER EVENTS (только хост получает)
# =========================================================
func _on_peer_connected(id: int) -> void:
	print("SteamLobby: подключился peer ", id)
	# Клиент сам пришлёт свой state через _rpc_send_state


func _on_peer_disconnected(id: int) -> void:
	print("SteamLobby: отключился peer ", id)
	_player_states.erase(id)
	_despawn_player(id)
	# Уведомить остальных
	_rpc_despawn_player.rpc(id)
	_broadcast_player_list()


# =========================================================
# RPC — клиент → хост: передать свой PlayerState
# =========================================================
@rpc("any_peer", "reliable")
func _rpc_send_state(state_data: Dictionary) -> void:

	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	state_data["peer_id"] = sender_id

	var state := PlayerState.new()
	_dict_to_state(state_data, state)
	_player_states[sender_id] = state

	# Заспавнить нового игрока у всех
	_rpc_spawn_player.rpc(state_data)
	print("SteamLobby: получен PlayerState от peer ", sender_id)

	# Новому игроку дослать state всех уже подключённых
	for existing_id in _player_states:
		if existing_id == sender_id:
			continue
		var existing_data := _state_to_dict(_player_states[existing_id])
		_rpc_spawn_player.rpc_id(sender_id, existing_data)

	_broadcast_player_list()


# =========================================================
# RPC — хост → все: заспавнить игрока
# =========================================================
@rpc("authority", "call_local", "reliable")
func _rpc_spawn_player(state_data: Dictionary) -> void:

	var peer_id: int = state_data.get("peer_id", 0)
	var hero_path: String = state_data.get("hero_scene", "")

	if hero_path.is_empty():
		push_error("SteamLobby: hero_scene пустой для peer %d" % peer_id)
		return

	var hero_scene = load(hero_path)
	if hero_scene == null:
		push_error("SteamLobby: не удалось загрузить '%s'" % hero_path)
		return

	var hero = hero_scene.instantiate()
	hero.name = str(peer_id)
	hero.set_multiplayer_authority(peer_id)
	add_child(hero)

	print("SteamLobby: заспавнен герой для peer ", peer_id)


# =========================================================
# RPC — хост → все: удалить игрока
# =========================================================
@rpc("authority", "call_local", "reliable")
func _rpc_despawn_player(peer_id: int) -> void:
	_despawn_player(peer_id)


func _despawn_player(peer_id: int) -> void:
	var node = get_node_or_null(str(peer_id))
	if node:
		node.queue_free()


# =========================================================
# РЕГИСТРАЦИЯ ХОСТА В ЛОББИ (без спавна сцены)
# =========================================================
func _register_local_player(peer_id: int) -> void:

	var state := PlayerState.new()
	state.from_profile(PlayerProfile)
	state.peer_id = peer_id
	_player_states[peer_id] = state

	_broadcast_player_list()


# =========================================================
# СПАВН ХОСТА НА МИССИИ (вызывается из hub.gd при старте)
# =========================================================
func _spawn_local_player(peer_id: int) -> void:

	if PlayerProfile.hero_scene.is_empty():
		push_error("SteamLobby: hero_scene не выбран")
		return

	var state := PlayerState.new()
	state.from_profile(PlayerProfile)
	state.peer_id = peer_id
	_player_states[peer_id] = state

	var state_data := _state_to_dict(state)

	# Хост спавнит у себя и рассылает всем подключённым
	_rpc_spawn_player.rpc(state_data)
	_broadcast_player_list()


# =========================================================
# СЕРИАЛИЗАЦИЯ PlayerState ↔ Dictionary
# =========================================================
func _local_state_to_dict() -> Dictionary:
	var state := PlayerState.new()
	state.from_profile(PlayerProfile)
	state.peer_id = multiplayer.get_unique_id()
	return _state_to_dict(state)


func _state_to_dict(state: PlayerState) -> Dictionary:
	return {
		"peer_id":    state.peer_id,
		"steam_id":   state.steam_id,
		"nickname":   state.nickname,
		"hero_scene": state.hero_scene,
		"level":      state.level,
		"experience": state.experience,
		"inventory":  state.inventory.duplicate(),
		"equipment":  state.equipment.duplicate(),
	}


func _dict_to_state(data: Dictionary, state: PlayerState) -> void:
	state.peer_id    = data.get("peer_id",    0)
	state.steam_id    = data.get("steam_id",   0)
	state.nickname    = data.get("nickname",   "Игрок")
	state.hero_scene = data.get("hero_scene", "")
	state.level      = data.get("level",      1)
	state.experience = data.get("experience", 0)
	state.inventory  = data.get("inventory",  [])
	state.equipment  = data.get("equipment",  {})


# =========================================================
# СПИСОК ИГРОКОВ ДЛЯ UI ЛОББИ
# Хост рассылает всем краткую инфу: peer_id, nickname, hero_scene
# =========================================================
func _broadcast_player_list() -> void:

	var list: Array = []
	for peer_id in _player_states:
		var state: PlayerState = _player_states[peer_id]
		list.append({
			"peer_id":    state.peer_id,
			"nickname":   state.nickname,
			"hero_scene": state.hero_scene,
		})

	_rpc_player_list.rpc(list)


@rpc("authority", "call_local", "reliable")
func _rpc_player_list(list: Array) -> void:
	players_updated.emit(list)


# =========================================================
# СМЕНА ГЕРОЯ В ЛОББИ
# Вызывается из lobby_menu.gd при выборе героя
# =========================================================
func notify_hero_changed() -> void:

	if multiplayer.is_server():
		var my_id := multiplayer.get_unique_id()
		if _player_states.has(my_id):
			_player_states[my_id].hero_scene = PlayerProfile.hero_scene
			_broadcast_player_list()
	else:
		_rpc_update_hero.rpc_id(1, PlayerProfile.hero_scene)


@rpc("any_peer", "reliable")
func _rpc_update_hero(hero_scene: String) -> void:

	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if _player_states.has(sender_id):
		_player_states[sender_id].hero_scene = hero_scene
		_broadcast_player_list()


# UI-обработчики (Host/Join) перенесены в lobby_menu.gd —
# он вызывает host_lobby() / join_lobby() напрямую.
