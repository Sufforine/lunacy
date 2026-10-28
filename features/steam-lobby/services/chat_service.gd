# Development chat commands and player display names.
extends "res://features/steam-lobby/services/lobby_service.gd"


func chat_player_name(peer_id: int) -> String:
	if not is_session_active():
		return PlayerProfile.character_name
	if _session.player_states.has(peer_id):
		var state: PlayerState = _session.player_states[peer_id]
		return state.character_name if not state.character_name.is_empty() else state.nickname
	return "Игрок %d" % peer_id


func execute_chat_command(peer_id: int, message: String) -> String:
	# Команды доступны всем игрокам для тестирования, но меняют только
	# их собственного героя. В сетевой игре выдачу выполняет хост.
	if is_session_active() and not multiplayer.is_server():
		return "Команду должен выполнить хост."
	if is_gameplay_locked():
		return "Дождитесь окончания загрузки."
	var hero := _hero_for_peer(peer_id) as Player
	if hero == null and not is_session_active():
		var scene := get_tree().current_scene
		if scene != null:
			for candidate in scene.find_children("*", "CharacterBody3D", true, false):
				if candidate is Player and candidate.is_multiplayer_authority():
					hero = candidate as Player
					break
	if hero == null:
		return "Команды выдачи доступны после появления героя в мире."
	if hero.inventory.network_pending:
		return "Дождитесь завершения операции с инвентарём."
	var separator := message.find(" ")
	var command := message.substr(0, separator) if separator >= 0 else message
	var argument := message.substr(separator + 1).strip_edges() if separator >= 0 else ""
	match command.to_lower():
		"/give":
			var selected: ItemData = null
			argument = argument.trim_prefix('"').trim_suffix('"')
			for item in ItemLibrary.all_items():
				if item.id.to_lower() == argument.to_lower() or item.item_name.to_lower() == argument.to_lower():
					selected = item
					break
			if selected == null:
				return "Предмет не найден. /items — список; /give <id или название>."
			if not hero.inventory.add_item(selected):
				return "Инвентарь заполнен."
			if is_session_active():
				hero.inventory.network_revision += 1
				_publish_inventory(peer_id)
			else:
				SaveManager.save_player_state(hero.inventory, hero.equipment)
			return "Выдан предмет: %s" % selected.item_name
		"/xp", "/exp":
			if not argument.is_valid_int() or int(argument) < 1 or int(argument) > 100000:
				return "Использование: /xp <число от 1 до 100000>."
			hero.stats.add_experience(int(argument))
			if is_session_active():
				var progress := hero.stats.get_progress_data()
				_session.update_progress(peer_id, progress)
				_lobby._rpc_apply_progress.rpc(peer_id, progress)
			return "Выдано опыта: %d" % int(argument)
	return "Неизвестная команда. /help — список команд."


# Calls into other services go through the facade.


func _hero_for_peer(peer_id: int) -> Node:
	return _lobby._hero_for_peer(peer_id)


func _publish_inventory(peer_id: int, sequence: int = 0) -> void:
	_lobby._publish_inventory(peer_id, sequence)


func is_gameplay_locked() -> bool:
	return _lobby.is_gameplay_locked()


func is_session_active() -> bool:
	return _lobby.is_session_active()
