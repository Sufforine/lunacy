extends Node

const SKILL_ACTIONS := [&"weapon_q", &"weapon_e", &"weapon_r"]
var hero: Player
var weapon: WeaponData
var blocking := false
var cooldowns: Dictionary = {}
var _busy_until := 0.0
var _serial := 0
var _attachments: Array[BoneAttachment3D] = []
var _last_request := -1.0


func _ready() -> void:
	hero = get_parent() as Player
	for i in 3:
		if not InputMap.has_action(SKILL_ACTIONS[i]):
			InputMap.add_action(SKILL_ACTIONS[i])
			var key := InputEventKey.new()
			key.physical_keycode = [KEY_Q, KEY_E, KEY_R][i]
			InputMap.action_add_event(SKILL_ACTIONS[i], key)
	hero.equipment.changed.connect(_refresh_equipment)
	_refresh_equipment()
	if hero.is_multiplayer_authority():
		var bar: Control = load("res://entities/player/ui/weapon_skill_bar.gd").new()
		bar.name = "WeaponSkillBar"
		bar.combat = self
		hero.get_node("CanvasLayer").add_child(bar)


func _refresh_equipment() -> void:
	var equipped := hero.equipment.weapon as WeaponData
	if equipped == weapon:
		return
	weapon = equipped
	blocking = false
	_serial += 1 # Отмена удара, если оружие сняли до попадания.
	for attachment in _attachments:
		attachment.free()
	_attachments.clear()
	if weapon == null:
		return
	if hero.animation_player.has_animation(weapon.block_animation):
		var root := hero.animation_tree.tree_root as AnimationNodeStateMachine
		var alive := root.get_node(&"Alive") as AnimationNodeStateMachine
		(alive.get_node(&"Block") as AnimationNodeAnimation).animation = weapon.block_animation
	_attach(weapon.right_hand_scene, "RightHand", weapon.right_hand_position, weapon.right_hand_rotation, weapon.right_hand_scale)
	_attach(weapon.left_hand_scene, "LeftHand", weapon.left_hand_position, weapon.left_hand_rotation, weapon.left_hand_scale)


func _attach(scene: PackedScene, bone: String, offset: Vector3, angles: Vector3, model_scale: Vector3) -> void:
	if scene == null:
		return
	var skeleton := hero.model.find_child("HumanSkeleton", true, false) as Skeleton3D
	if skeleton == null or skeleton.find_bone(bone) < 0:
		return
	var attachment := BoneAttachment3D.new()
	attachment.name = bone + "Weapon"
	attachment.bone_name = bone
	skeleton.add_child(attachment)
	var visual := scene.instantiate() as Node3D
	attachment.add_child(visual)
	visual.position = offset
	visual.rotation_degrees = angles
	visual.scale = model_scale
	_attachments.append(attachment)


func _can_control() -> bool:
	return hero.is_multiplayer_authority() and not SteamLobby.is_gameplay_locked() \
		and not SteamLobby.is_mission_loading() and not GameChat.is_typing \
		and not hero.stats.is_dead and not hero.stats.is_downed \
		and hero.is_processing_input() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
		and not hero.inventory_ui.is_main_panel_open()


func _process(_delta: float) -> void:
	if hero.is_multiplayer_authority():
		var wants_block := _can_control() and weapon != null and Input.is_action_pressed("block")
		if wants_block != blocking and _now() - _last_request > 0.15:
			_last_request = _now()
			if SteamLobby.is_session_active() and not multiplayer.is_server():
				_request_block.rpc_id(1, wants_block)
			else:
				_server_block(wants_block)
	if (not SteamLobby.is_session_active() or multiplayer.is_server()) and blocking and not _can_fight():
		_server_block(false)


func _unhandled_input(event: InputEvent) -> void:
	if not _can_control() or weapon == null or not event.is_pressed() or event.is_echo():
		return
	var index := -2
	if event.is_action_pressed("attack"):
		index = -1
	for i in mini(3, weapon.skills.size()):
		if event.is_action_pressed(SKILL_ACTIONS[i]):
			index = i
	if index == -2:
		return
	get_viewport().set_input_as_handled()
	if remaining(index) > 0.0 or _now() < _busy_until:
		return
	if SteamLobby.is_session_active() and not multiplayer.is_server():
		_request_attack.rpc_id(1, index, weapon.id)
	else:
		_server_attack(index, weapon.id)


func _can_fight() -> bool:
	return weapon != null and not SteamLobby.is_gameplay_locked() \
		and not hero.stats.is_dead and not hero.stats.is_downed \
		and hero.animation_state not in [Player.AnimationState.DOWNED, Player.AnimationState.DEAD, Player.AnimationState.JUMP, Player.AnimationState.FALL]


@rpc("any_peer", "call_remote", "reliable", 1)
func _request_attack(index: int, item_id: String) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == hero.get_multiplayer_authority():
		_server_attack(index, item_id)


func _server_attack(index: int, item_id: String) -> void:
	if not _can_fight() or weapon.id != item_id or index < -1 or index >= mini(3, weapon.skills.size()):
		return
	if remaining(index) > 0.0 or _now() < _busy_until:
		return
	var skill := weapon.skills[index] if index >= 0 else null
	if index >= 0 and skill == null:
		return
	var animation: StringName = skill.animation if skill else weapon.attack_animation
	var duration := 0.8
	if hero.animation_player.has_animation(animation):
		duration = hero.animation_player.get_animation(animation).length
	var cooldown: float = skill.cooldown if skill else weapon.attack_cooldown
	var delay: float = skill.hit_delay if skill else weapon.attack_hit_delay
	var lock_time := maxf(duration, delay + 0.05)
	_apply_attack(index, animation, cooldown, lock_time)
	if SteamLobby.is_session_active():
		_confirm_attack.rpc(index, animation, cooldown, lock_time)
	_serial += 1
	var attack_serial := _serial
	var used_weapon := weapon
	await get_tree().create_timer(delay).timeout
	if is_inside_tree() and attack_serial == _serial and weapon == used_weapon and _can_fight():
		_hit_targets(used_weapon, skill)


@rpc("any_peer", "call_remote", "reliable", 1)
func _confirm_attack(index: int, animation: StringName, cooldown: float, lock_time: float) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		_apply_attack(index, animation, cooldown, lock_time)


func _apply_attack(index: int, animation: StringName, cooldown: float, lock_time: float) -> void:
	blocking = false
	cooldowns[index] = _now() + cooldown
	_busy_until = _now() + lock_time
	hero._start_action_animation(animation)


@rpc("any_peer", "call_remote", "reliable", 1)
func _request_block(value: bool) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == hero.get_multiplayer_authority():
		_server_block(value)


func _server_block(value: bool) -> void:
	value = value and _can_fight() and _now() >= _busy_until
	if value == blocking:
		return
	blocking = value
	if SteamLobby.is_session_active():
		_confirm_block.rpc(value)


@rpc("any_peer", "call_remote", "reliable", 1)
func _confirm_block(value: bool) -> void:
	if multiplayer.get_remote_sender_id() == 1:
		blocking = value


func mitigate_damage(amount: int, magical: bool) -> int:
	if blocking and weapon != null and not magical and _can_fight():
		return maxi(1, int(round(amount * (1.0 - weapon.block_reduction))))
	return amount


func remaining(index: int) -> float:
	return maxf(0.0, float(cooldowns.get(index, 0.0)) - _now())


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _hit_targets(used_weapon: WeaponData, skill: WeaponSkill) -> void:
	var reach := used_weapon.attack_range * (skill.range_multiplier if skill else 1.0)
	var arc: float = skill.arc_degrees if skill else 100.0
	var multiplier: float = skill.damage_multiplier if skill else 1.0
	var origin := hero.global_position + Vector3.UP
	var shape := SphereShape3D.new()
	shape.radius = reach
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = origin
	query.exclude = [hero.get_rid()]
	var seen: Array[Node] = []
	for hit in hero.get_world_3d().direct_space_state.intersect_shape(query, 64):
		var target := hit.collider as Node3D
		# Кооперативный режим: союзные герои не получают урон друг от друга.
		if target == null or target is Player or seen.has(target):
			continue
		var target_stats := target.get_node_or_null("StatsComponent") as StatsComponent
		if target_stats == null or target_stats.is_dead:
			continue
		seen.append(target)
		var point := target.global_position + Vector3.UP * 0.8
		var offset := point - origin
		var horizontal := Vector3(offset.x, 0, offset.z)
		if horizontal.length() > reach or hero.get_facing_direction().dot(horizontal.normalized()) < cos(deg_to_rad(arc * 0.5)):
			continue
		var ray := PhysicsRayQueryParameters3D.create(origin, point, 1)
		ray.exclude = [hero.get_rid()]
		if not hero.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		var physical := int(round(used_weapon.get_physical_damage(hero.stats) * multiplier))
		var magical := int(round(used_weapon.get_magical_damage(hero.stats) * multiplier))
		_apply_hit(target.get_path(), physical, magical)
		if SteamLobby.is_session_active():
			_confirm_hit.rpc(target.get_path(), target_stats.current_health, target_stats.current_shield, target_stats.is_downed, target_stats.is_dead)
		if skill != null and skill.knockback > 0.0 and target.has_method("apply_impulse"):
			target.call("apply_impulse", horizontal.normalized() * skill.knockback)


@rpc("any_peer", "call_remote", "reliable", 1)
func _confirm_hit(target_path: NodePath, health: int, shield: float, downed: bool, dead: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	var target := get_node_or_null(target_path)
	if target == null or target is Player:
		return
	var target_stats := target.get_node_or_null("StatsComponent") as StatsComponent
	if target_stats != null:
		# Передаём результат, чтобы синхронизатор HP не удвоил урон.
		target_stats.current_health = health
		target_stats.current_shield = shield
		target_stats.is_downed = downed
		target_stats.is_dead = dead
		target_stats.stats_changed.emit()


func _apply_hit(target_path: NodePath, physical: int, magical: int) -> void:
	var target := get_node_or_null(target_path)
	if target == null or target is Player:
		return
	var target_stats := target.get_node_or_null("StatsComponent") as StatsComponent
	if target_stats != null:
		if physical > 0:
			target_stats.take_damage(physical)
		if magical > 0:
			target_stats.take_damage(magical, true)
