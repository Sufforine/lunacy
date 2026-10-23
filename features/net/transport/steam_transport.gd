class_name NetSteamTransport
extends RefCounted

var peer: MultiplayerPeer
var last_error: Error = OK


func _configure_steam_peer(steam_peer: SteamMultiplayerPeer) -> void:
	# Вывод транспорта нужен на обоих компьютерах для диагностики P2P.
	if steam_peer.has_method("set_debug_level") and ClassDB.class_has_integer_constant("SteamMultiplayerPeer", "DEBUG_LEVEL_PEER"):
		steam_peer.call("set_debug_level", ClassDB.class_get_integer_constant("SteamMultiplayerPeer", "DEBUG_LEVEL_PEER"))
	# Настройка присутствует не во всех сборках GodotSteam.
	if steam_peer.has_method("set_server_relay"):
		steam_peer.call("set_server_relay", true)


func create_steam_host(multiplayer_api: MultiplayerAPI) -> SteamMultiplayerPeer:
	var steam_peer := SteamMultiplayerPeer.new()
	_configure_steam_peer(steam_peer)
	last_error = steam_peer.create_host()
	print("SteamTransport: create_host: ", error_string(last_error))
	if last_error != OK:
		steam_peer.close()
		return null
	peer = steam_peer
	multiplayer_api.multiplayer_peer = steam_peer
	return steam_peer


func create_steam_client(multiplayer_api: MultiplayerAPI, lobby_owner_id: int) -> SteamMultiplayerPeer:
	var steam_peer := SteamMultiplayerPeer.new()
	_configure_steam_peer(steam_peer)
	last_error = steam_peer.create_client(lobby_owner_id)
	print("SteamTransport: create_client: ", error_string(last_error))
	if last_error != OK:
		steam_peer.close()
		return null
	peer = steam_peer
	multiplayer_api.multiplayer_peer = steam_peer
	return steam_peer


func create_enet_host(multiplayer_api: MultiplayerAPI, port: int, max_clients: int = 4) -> ENetMultiplayerPeer:
	var enet_peer := ENetMultiplayerPeer.new()
	enet_peer.create_server(port, max_clients)
	peer = enet_peer
	multiplayer_api.multiplayer_peer = enet_peer
	return enet_peer


func create_enet_client(multiplayer_api: MultiplayerAPI, address: String, port: int) -> ENetMultiplayerPeer:
	var enet_peer := ENetMultiplayerPeer.new()
	enet_peer.create_client(address, port)
	peer = enet_peer
	multiplayer_api.multiplayer_peer = enet_peer
	return enet_peer


func close_connection(multiplayer_api: MultiplayerAPI) -> void:
	if peer:
		peer.close()
	peer = null
	multiplayer_api.multiplayer_peer = null
