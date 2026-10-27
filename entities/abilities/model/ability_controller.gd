extends Node

signal activation_started(ability: AbilityDefinition, activation: int)
signal activation_cancelled(activation: int)

const SKILL_ACTIONS := [&"weapon_q", &"weapon_e", &"weapon_r"]
const PRIMARY := -1
const SECONDARY := -2
var hero: Player
var weapon: WeaponData
var blocking := false
# Keyed by ability ID, so changing a weapon/slot cannot reset its cooldown.
var cooldowns: Dictionary = {}
var _busy_until := 0.0
var _generation := 0
var _event_sequence := 0
var _last_event := 0
var _active_ability: AbilityDefinition
var _last_request := -1.0
var _next_clock_sync_msec := 0
static var _server_clock_offset_msec := 0.0
static var _clock_best_rtt_msec := INF
static var _clock_ready := false


func _ready() -> void:
	hero = get_parent() as Player
	for i in 3:
		if not InputMap.has_action(SKILL_ACTIONS[i]):
			InputMap.add_action(SKILL_ACTIONS[i])
			var key := InputEventKey.new()
			key.physical_keycode = [KEY_Q, KEY_E, KEY_R][i]
			InputMap.action_add_event(SKILL_ACTIONS[i], key)
	hero.equipment.changed.connect(_refresh_equipment)
	hero.stats.damage_received.connect(_on_damage_received)
	_refresh_equipment()
	if hero.is_multiplayer_authority():
		if multiplayer.is_server() or not SteamLobby.is_session_active():
			_server_clock_offset_msec = 0.0
			_clock_best_rtt_msec = 0.0
			_clock_ready = true
		else:
			_clock_best_rtt_msec = INF
			_clock_ready = false
			_next_clock_sync_msec = 0
	if hero.is_multiplayer_authority():
		var bar: Control = load("res://entities/player/ui/action_hud.gd").new()
		bar.name = "ActionHUD"
		bar.combat = self
		hero.get_node("CanvasLayer").add_child(bar)


func _refresh_equipment() -> void:
	var equipped := hero.equipment.weapon as WeaponData
	if equipped == weapon:
		return
	cancel_action()
	weapon = equipped
	hero.character_animation.configure_weapon(weapon)


func cancel_action() -> void:
	if _active_ability != null:
		activation_cancelled.emit(_generation)
	_generation += 1
	_active_ability = null
	blocking = false
	_busy_until = 0.0
	if hero.character_animation != null:
		hero.character_animation.cancel_action()


func _exit_tree() -> void:
	_generation += 1


func _can_control() -> bool:
	return hero.is_multiplayer_authority() and not SteamLobby.is_gameplay_locked() \
		and not SteamLobby.is_mission_loading() and not GameChat.is_typing \
		and not hero.stats.is_dead and not hero.stats.is_downed \
		and hero.is_processing_input() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
		and not hero.inventory_ui.is_main_panel_open()


func _can_start(ability: AbilityDefinition) -> bool:
	if weapon == null or ability == null or not ability.is_valid():
		return false
	if not _can_continue(ability):
		return false
	return not ability.requires_grounded or hero.animation_state not in [Player.AnimationState.JUMP, Player.AnimationState.FALL]


func _can_continue(ability: AbilityDefinition) -> bool:
	return weapon != null and ability != null \
		and not SteamLobby.is_gameplay_locked() and not SteamLobby.is_mission_loading() \
		and not hero.stats.is_dead and not hero.stats.is_downed \
		and hero.animation_state not in [Player.AnimationState.DOWNED, Player.AnimationState.DEAD]


func _process(_delta: float) -> void:
	_update_network_clock()
	# Every copy cancels presentation when replicated state becomes incompatible.
	if _active_ability != null and not _can_continue(_active_ability):
		cancel_action()
	elif _active_ability != null:
		if _active_ability.is_interrupted_by(AbilityDefinition.InterruptReason.JUMP) \
				and hero.animation_state in [Player.AnimationState.JUMP, Player.AnimationState.FALL]:
			try_interrupt(AbilityDefinition.InterruptReason.JUMP)
		elif _active_ability.is_interrupted_by(AbilityDefinition.InterruptReason.MOVEMENT) \
				and hero.locomotion_speed > _active_ability.movement_interrupt_speed:
			try_interrupt(AbilityDefinition.InterruptReason.MOVEMENT)
	if _active_ability != null and not blocking and _now() >= _busy_until:
		_active_ability = null
	if not hero.is_multiplayer_authority() or weapon == null:
		return
	var secondary := weapon.secondary_action
	if secondary == null or not secondary.held:
		return
	var wants_block := _can_control() and Input.is_action_pressed("block")
	if wants_block != blocking and _now() - _last_request > 0.15:
		_last_request = _now()
		if SteamLobby.is_session_active() and not multiplayer.is_server():
			_request_hold.rpc_id(1, wants_block, weapon.id)
		else:
			_server_hold(wants_block, weapon.id)


func _unhandled_input(event: InputEvent) -> void:
	if not _can_control() or weapon == null or not event.is_pressed() or event.is_echo():
		return
	var index := -3
	if event.is_action_pressed("attack"):
		index = PRIMARY
	elif event.is_action_pressed("block"):
		index = SECONDARY
	for i in mini(3, weapon.skills.size()):
		if event.is_action_pressed(SKILL_ACTIONS[i]):
			index = i
	var ability := weapon.get_ability(index)
	if ability == null:
		return
	get_viewport().set_input_as_handled()
	if ability.held or remaining(index) > 0.0 or _now() < _busy_until:
		return
	if SteamLobby.is_session_active() and not multiplayer.is_server():
		_request_attack.rpc_id(1, index, weapon.id)
	else:
		_server_attack(index, weapon.id)


@rpc("any_peer", "call_remote", "reliable", 1)
func _request_attack(index: int, item_id: String) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == hero.get_multiplayer_authority():
		_server_attack(index, item_id)


func _server_attack(index: int, item_id: String) -> void:
	if weapon == null or weapon.id != item_id:
		return
	var ability := weapon.get_ability(index)
	if not _can_start(ability) or ability.held:
		return
	if remaining(index) > 0.0 or _now() < _busy_until or hero.stats.current_mana < ability.mana_cost:
		return
	_event_sequence += 1
	var started_at_msec := Time.get_ticks_msec()
	_apply_activation(ability, true, started_at_msec)
	if SteamLobby.is_session_active():
		_confirm_attack.rpc(index, item_id, ability.id, _event_sequence, started_at_msec)
	var generation := _generation
	var used_weapon := weapon
	await get_tree().create_timer(ability.effect_delay).timeout
	if is_activation_current(generation) and weapon == used_weapon and _can_continue(ability):
		ability.behavior.execute({
			"controller": self, "actor": hero, "weapon": used_weapon,
			"ability": ability, "activation": generation,
		})


func is_activation_current(generation: int) -> bool:
	return is_inside_tree() and generation == _generation


@rpc("any_peer", "call_remote", "reliable", 1)
func _confirm_attack(index: int, item_id: String, ability_id: StringName, sequence: int, started_at_msec: int) -> void:
	if multiplayer.get_remote_sender_id() != 1 or sequence <= _last_event:
		return
	_last_event = sequence
	var used_weapon := ItemLibrary.get_item(item_id) as WeaponData
	if used_weapon == null:
		return
	var ability := used_weapon.get_ability(index)
	if ability != null and ability.id == ability_id:
		# Inventory snapshots use another channel and may arrive before this
		# confirmation. Keep the cost/cooldown, but do not animate an old weapon.
		_apply_activation(ability, weapon != null and weapon.id == item_id, started_at_msec)


func _apply_activation(ability: AbilityDefinition, animate: bool = true, started_at_msec: int = -1) -> void:
	var elapsed := _elapsed_since_server(started_at_msec)
	cooldowns[ability.id] = _now() + maxf(0.0, ability.cooldown - elapsed)
	if ability.mana_cost > 0:
		hero.stats.current_mana = maxi(0, hero.stats.current_mana - ability.mana_cost)
		hero.stats.stats_changed.emit()
	if not animate or elapsed >= ability.get_duration():
		return
	if _active_ability != null:
		activation_cancelled.emit(_generation)
	_generation += 1
	blocking = false
	_active_ability = ability
	_busy_until = _now() + maxf(0.0, ability.get_duration() - elapsed)
	hero.character_animation.play_action(ability, elapsed)
	activation_started.emit(ability, _generation)
	if ability.behavior != null:
		ability.behavior.present({
			"controller": self, "actor": hero, "weapon": weapon,
			"ability": ability, "activation": _generation,
		})


@rpc("any_peer", "call_remote", "reliable", 1)
func _request_hold(value: bool, item_id: String) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == hero.get_multiplayer_authority():
		_server_hold(value, item_id)


func _server_hold(value: bool, item_id: String) -> void:
	if weapon == null or weapon.id != item_id:
		return
	var ability := weapon.secondary_action
	if value:
		if not _can_start(ability) or not ability.held or _now() < _busy_until \
			or remaining(SECONDARY) > 0.0 or hero.stats.current_mana < ability.mana_cost:
			return
	if value == blocking:
		return
	_event_sequence += 1
	var started_at_msec := Time.get_ticks_msec()
	_apply_hold(value, started_at_msec)
	if SteamLobby.is_session_active():
		_confirm_hold.rpc(value, item_id, _event_sequence, started_at_msec)


@rpc("any_peer", "call_remote", "reliable", 1)
func _confirm_hold(value: bool, item_id: String, sequence: int, started_at_msec: int) -> void:
	if multiplayer.get_remote_sender_id() != 1 or sequence <= _last_event:
		return
	_last_event = sequence
	if weapon != null and weapon.id == item_id:
		_apply_hold(value, started_at_msec)


func _apply_hold(value: bool, started_at_msec: int = -1) -> void:
	cancel_action()
	blocking = value
	if value:
		_active_ability = weapon.secondary_action
		var elapsed := _elapsed_since_server(started_at_msec)
		cooldowns[_active_ability.id] = _now() + maxf(0.0, _active_ability.cooldown - elapsed)
		if _active_ability.mana_cost > 0:
			hero.stats.current_mana = maxi(0, hero.stats.current_mana - _active_ability.mana_cost)
			hero.stats.stats_changed.emit()
		hero.character_animation.play_hold(_active_ability, elapsed)


func try_interrupt(reason: int) -> bool:
	if _active_ability == null or not _active_ability.is_interrupted_by(reason):
		return false
	var ability_id := _active_ability.id
	var activation_sequence := _event_sequence if multiplayer.is_server() else _last_event
	if SteamLobby.is_session_active() and hero.is_multiplayer_authority() and not multiplayer.is_server():
		_request_interrupt.rpc_id(1, reason, ability_id, activation_sequence)
	cancel_action()
	if SteamLobby.is_session_active() and multiplayer.is_server():
		_event_sequence += 1
		_confirm_interrupt.rpc(ability_id, _event_sequence)
	return true


func _on_damage_received(_amount: int, _magical: bool) -> void:
	try_interrupt(AbilityDefinition.InterruptReason.DAMAGE)


@rpc("any_peer", "call_remote", "reliable", 1)
func _request_interrupt(reason: int, ability_id: StringName, activation_sequence: int) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != hero.get_multiplayer_authority():
		return
	if reason not in [AbilityDefinition.InterruptReason.MOVEMENT, AbilityDefinition.InterruptReason.JUMP, AbilityDefinition.InterruptReason.DAMAGE] \
			or activation_sequence != _event_sequence or _active_ability == null \
			or _active_ability.id != ability_id or not _active_ability.is_interrupted_by(reason):
		return
	try_interrupt(reason)


@rpc("any_peer", "call_remote", "reliable", 1)
func _confirm_interrupt(ability_id: StringName, sequence: int) -> void:
	if multiplayer.get_remote_sender_id() != 1 or sequence <= _last_event:
		return
	_last_event = sequence
	if _active_ability != null and _active_ability.id == ability_id:
		cancel_action()


func movement_multiplier() -> float:
	return _active_ability.movement_multiplier if _has_movement_restriction() else 1.0


func allows_sprint() -> bool:
	return _active_ability.allow_sprint if _has_movement_restriction() else true


func _has_movement_restriction() -> bool:
	return _active_ability != null and (blocking or _now() < _busy_until) and _can_continue(_active_ability)


func mitigate_damage(amount: int, magical: bool) -> int:
	if blocking and _active_ability != null and not magical and _can_continue(_active_ability):
		return maxi(1, int(round(amount * (1.0 - _active_ability.physical_damage_reduction))))
	return amount


func remaining(index: int) -> float:
	var ability := weapon.get_ability(index) if weapon != null else null
	return maxf(0.0, float(cooldowns.get(ability.id, 0.0)) - _now()) if ability != null else 0.0


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _elapsed_since_server(started_at_msec: int) -> float:
	if started_at_msec < 0 or multiplayer.is_server() or not _clock_ready:
		return 0.0
	var estimated_server_now := float(Time.get_ticks_msec()) + _server_clock_offset_msec
	return maxf(0.0, (estimated_server_now - float(started_at_msec)) / 1000.0)


func _update_network_clock() -> void:
	if not hero.is_multiplayer_authority() or not SteamLobby.is_session_active() or multiplayer.is_server():
		return
	var now_msec := Time.get_ticks_msec()
	if now_msec < _next_clock_sync_msec:
		return
	_next_clock_sync_msec = now_msec + 5000
	_request_clock_sample.rpc_id(1, now_msec)


@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _request_clock_sample(client_sent_msec: int) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != hero.get_multiplayer_authority():
		return
	_clock_sample.rpc_id(multiplayer.get_remote_sender_id(), client_sent_msec, Time.get_ticks_msec())


@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _clock_sample(client_sent_msec: int, server_received_msec: int) -> void:
	if multiplayer.get_remote_sender_id() != 1 or not hero.is_multiplayer_authority():
		return
	var client_received_msec := Time.get_ticks_msec()
	var rtt := maxf(0.0, float(client_received_msec - client_sent_msec))
	var sample := float(server_received_msec) - (float(client_sent_msec) + rtt * 0.5)
	if not _clock_ready:
		_server_clock_offset_msec = sample
		_clock_ready = true
	elif rtt <= _clock_best_rtt_msec * 1.5:
		_server_clock_offset_msec = lerpf(_server_clock_offset_msec, sample, 0.2)
	_clock_best_rtt_msec = minf(_clock_best_rtt_msec, rtt)


# Shared host-only damage delivery, usable by melee and future executors.
func apply_damage(target: Node, physical: int, magical: int) -> void:
	if SteamLobby.is_session_active() and not multiplayer.is_server():
		return
	if not is_instance_valid(target) or target is Player:
		return
	var target_stats := target.get_node_or_null("StatsComponent") as StatsComponent
	if target_stats == null or target_stats.is_dead:
		return
	if physical > 0:
		target_stats.take_damage(physical)
	if magical > 0:
		target_stats.take_damage(magical, true)
	if SteamLobby.is_session_active():
		_confirm_hit.rpc(target.get_path(), target_stats.current_health, target_stats.current_shield, target_stats.is_downed, target_stats.is_dead)


@rpc("any_peer", "call_remote", "reliable", 1)
func _confirm_hit(target_path: NodePath, health: int, shield: float, downed: bool, dead: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	var target := get_node_or_null(target_path)
	if target == null or target is Player:
		return
	var target_stats := target.get_node_or_null("StatsComponent") as StatsComponent
	if target_stats != null:
		# Absolute result avoids double damage with the existing HP synchronizer.
		target_stats.current_health = health
		target_stats.current_shield = shield
		target_stats.is_downed = downed
		target_stats.is_dead = dead
		target_stats.stats_changed.emit()
