class_name NetSteamTransport
extends RefCounted

var peer: MultiplayerPeer


func create_steam_host(multiplayer_api: MultiplayerAPI) -> SteamMultiplayerPeer:
	var steam_peer := SteamMultiplayerPeer.new()
	steam_peer.server_relay = true
	steam_peer.create_host()
	peer = steam_peer
	multiplayer_api.multiplayer_peer = steam_peer
	return steam_peer


func create_steam_client(multiplayer_api: MultiplayerAPI, lobby_owner_id: int) -> SteamMultiplayerPeer:
	var steam_peer := SteamMultiplayerPeer.new()
	steam_peer.server_relay = true
	steam_peer.create_client(lobby_owner_id)
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
