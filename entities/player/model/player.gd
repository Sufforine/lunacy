extends CharacterBody3D
class_name Player

const PAUSE_MENU_SCENE := preload("res://screens/pause/ui/pause_menu.tscn")

@export var ease_speed: float = 5.0
@export_group("Movement")
@export_range(1.0, 3.0, 0.05) var sprint_multiplier: float = 1.6
@export_range(1.0, 15.0, 0.1) var jump_velocity: float = 8.0
@export_range(1.0, 8.0, 0.1) var gravity_multiplier: float = 3.0
@export_range(1.0, 3.0, 0.1) var falling_multiplier: float = 1.5
@export_range(10.0, 100.0, 1.0) var terminal_speed: float = 45.0
@export_range(1.0, 80.0, 1.0) var acceleration: float = 30.0
@export_range(0.0, 1.0, 0.05) var air_control: float = 0.4
@export_group("Knockback")
@export_range(1.0, 200.0, 1.0) var body_mass: float = 70.0
@export_range(0.0, 50.0, 0.5) var ground_impulse_drag: float = 12.0
@export_range(0.0, 10.0, 0.1) var air_impulse_drag: float = 1.0
@export_group("")
# Если выброшенные предметы летят НАЗАД от героя — поставь галочку:
# значит перёд твоей модели смотрит вдоль +Z, а не -Z.
@export var model_faces_positive_z: bool = false
# Поворот модели персонажа вокруг Y. glTF-модели смотрят в +Z, а герой
# целится вдоль -Z, поэтому по умолчанию модель разворачивается на 180°.
# Если персонаж стоит спиной к курсору — поменяй значение.
@export var character_model_yaw_degrees: float = 180.0

@onready var camera_rig          = $CameraRig
@onready var model: Node3D           = $Model
@onready var animation_player: AnimationPlayer = get_node_or_null("Model/AnimationPlayer") as AnimationPlayer

@onready var stats: StatsComponent         = $StatsComponent
@onready var equipment: EquipmentComponent = $EquipmentComponent
@onready var effects: EffectsComponent     = $EffectsComponent
@onready var inventory: InventoryComponent = $InventoryComponent
@onready var inventory_ui                  = $CanvasLayer/InventoryUI
@onready var interaction_prompt: InteractionPrompt = $CanvasLayer/InteractionPrompt
var hud_bars: HUDBars = null
var weapon_combat: Node
var character_animation: Node


# ── состояния анимации ───────────────────────────────────
enum AnimationState { IDLE, WALK, DOWNED, DEAD, SPRINT, JUMP, FALL }
var animation_state: AnimationState = AnimationState.IDLE
var animation_tree: AnimationTree
var _movement_velocity := Vector3.ZERO
var _external_velocity := Vector3.ZERO
var owns_local_profile := false


# ════════════════════════════════════════════════════════
# READY
# ════════════════════════════════════════════════════════
func _ready() -> void:
	owns_local_profile = is_multiplayer_authority()

	add_to_group("player")

	# Первым делом: заменить модель из сцены на модель, созданную в редакторе
	# персонажа (до того как что-то начнёт использовать model/animation_player)
	_apply_character_model()
	character_animation = load("res://entities/player/model/character_animation_controller.gd").new()
	character_animation.name = "CharacterAnimationController"
	add_child(character_animation)

	# Герой владельца берёт данные из локального профиля, чужой герой — из
	# network_state, который NetSpawner кладёт в meta при спавне.
	# Иначе у чужих героев оказался бы инвентарь и снаряжение локального игрока.
	if is_multiplayer_authority():
		equipment.load_from_profile()
		inventory.set_data(PlayerProfile.inventory)
	else:
		var net_state: Dictionary = get_meta("network_state", {})
		equipment.load_from_dict(net_state.get("equipment", {}))
		inventory.set_data(net_state.get("inventory", []))
		inventory.set_quickslot_data(net_state.get("quickslots", []))

	weapon_combat = load("res://entities/player/model/weapon_combat.gd").new()
	weapon_combat.name = "WeaponCombat"
	add_child(weapon_combat)
	var presenter: Node = load("res://entities/player/model/weapon_presenter.gd").new()
	presenter.name = "WeaponPresenter"
	add_child(presenter)

	stats.current_health = int(stats.get_stat("health"))
	stats.current_mana   = int(stats.get_stat("mana"))

	# Подписаться на сигналы состояния
	stats.downed.connect(_on_downed)
	stats.died.connect(_on_died)
	stats.revived.connect(_on_revived)

	if is_multiplayer_authority():
		inventory_ui.set_process_input(true)
		hud_bars = HUDBars.new()
		$CanvasLayer.add_child(hud_bars)
		hud_bars.bind(stats)
		# Меню создаётся только у владельца этого Player. Поэтому Escape и
		# полноэкранный интерфейс не дублируются для сетевых копий героев.
		$CanvasLayer.add_child(PAUSE_MENU_SCENE.instantiate())
		# CameraRig готовится раньше корневого Player. Повторная отложенная
		# активация гарантирует, что после спавна всех сетевых игроков текущей
		# останется камера владельца, а мышь снова будет захвачена после меню.
		call_deferred("_activate_local_camera")

	else:
		# Интерфейс чужого героя на моём экране не нужен
		# и не должен реагировать на глобальные I/Escape. Иначе каждый
		# сетевой Player меняет общий Input.mouse_mode при открытии/закрытии.
		inventory_ui.set_process_input(false)
		$CanvasLayer.visible = false

	call_deferred("_init_inventory")

	print("Player ready:", name, " auth:", is_multiplayer_authority())


func _activate_local_camera() -> void:
	if is_multiplayer_authority() and camera_rig != null:
		camera_rig.activate_for_local_player()


func set_interaction_available(available: bool) -> void:
	if not is_multiplayer_authority() or interaction_prompt == null:
		return
	if available:
		interaction_prompt.show_action(&"interact")
	else:
		interaction_prompt.hide_prompt()


func _init_inventory() -> void:
	if is_multiplayer_authority():
		inventory_ui.bind(inventory, equipment, stats)
		inventory.set_quickslot_data(PlayerProfile.quickslots)


# ════════════════════════════════════════════════════════
# PHYSICS
# ════════════════════════════════════════════════════════
func _physics_process(delta: float) -> void:

	if not is_multiplayer_authority() or SteamLobby.is_gameplay_locked():
		return

	# Вертикальная физика продолжается даже при заблокированном управлении.
	if not is_on_floor():
		var fall_scale := falling_multiplier if velocity.y < 0.0 else 1.0
		velocity += get_gravity() * gravity_multiplier * fall_scale * delta
		velocity.y = maxf(velocity.y, -terminal_speed)

	var controls_enabled := not stats.is_downed and not stats.is_dead \
		and not GameChat.is_typing \
		and is_processing_input() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
		and not SteamLobby.is_mission_loading()
	if inventory_ui != null and inventory_ui.is_main_panel_open():
		controls_enabled = false

	_handle_movement(delta, controls_enabled)
	if controls_enabled:
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = jump_velocity
		_handle_rotation(delta)
	move_and_slide()
	# Это состояние синхронизируется существующим MultiplayerSynchronizer.
	# Клиенты не проверяют is_on_floor(): физику копии выполняет её владелец.
	if not is_on_floor() and not stats.is_downed and not stats.is_dead:
		animation_state = AnimationState.JUMP if velocity.y > 0.0 else AnimationState.FALL
	# Убираем составляющие толчка, направленные внутрь стен и склонов.
	for index in get_slide_collision_count():
		var normal := get_slide_collision(index).get_normal()
		if _external_velocity.dot(normal) < 0.0:
			_external_velocity = _external_velocity.slide(normal)
		if _movement_velocity.dot(normal) < 0.0:
			_movement_velocity = _movement_velocity.slide(normal)
	_external_velocity.y = 0.0
	_movement_velocity.y = 0.0
	var drag := ground_impulse_drag if is_on_floor() else air_impulse_drag
	_external_velocity = _external_velocity.move_toward(Vector3.ZERO, drag * delta)


# ════════════════════════════════════════════════════════
# MOVEMENT
# ════════════════════════════════════════════════════════
func _handle_movement(delta: float, controls_enabled: bool) -> void:

	var input_dir := InputManager.get_input_direction() if controls_enabled else Vector3.ZERO
	if camera_rig != null:
		input_dir = camera_rig.get_camera_relative_direction(input_dir)
	var speed: float = stats.get_stat("move_speed")
	var sprinting := controls_enabled and Input.is_action_pressed("sprint") and not input_dir.is_zero_approx()
	if weapon_combat != null and weapon_combat.blocking:
		sprinting = false
		speed *= weapon_combat.movement_multiplier()
	if sprinting:
		speed *= sprint_multiplier

	var movement_acceleration := acceleration * (1.0 if is_on_floor() else air_control)
	_movement_velocity = _movement_velocity.move_toward(input_dir * speed, movement_acceleration * delta)
	velocity.x = _movement_velocity.x + _external_velocity.x
	velocity.z = _movement_velocity.z + _external_velocity.z

	if not stats.is_downed and not stats.is_dead:
		animation_state = AnimationState.IDLE
		if Vector2(velocity.x, velocity.z).length() > 0.1:
			animation_state = AnimationState.SPRINT if sprinting else AnimationState.WALK


# Импульс в Н·с. В сетевой игре вызывается хостом на копии цели;
# физику исполняет владелец, позиция передаётся обычным синхронизатором.
func apply_impulse(impulse: Vector3) -> void:
	if not impulse.is_finite():
		return
	if SteamLobby.is_session_active():
		if not multiplayer.is_server():
			return
		if not is_multiplayer_authority():
			_rpc_apply_impulse.rpc_id(get_multiplayer_authority(), impulse)
			return
	_add_impulse(impulse)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_apply_impulse(impulse: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1 or not is_multiplayer_authority():
		return
	if impulse.is_finite():
		_add_impulse(impulse)


func _add_impulse(impulse: Vector3) -> void:
	var change := impulse / maxf(body_mass, 1.0)
	_external_velocity += Vector3(change.x, 0.0, change.z)
	velocity.y += change.y


# Вызывается системой взрыва на каждой потенциальной цели.
# Препятствия/видимость проверяются системой взрыва до этого вызова.
func apply_explosion(origin: Vector3, radius: float, impulse_strength: float, upward_bias: float = 0.35) -> void:
	if radius <= 0.0 or impulse_strength <= 0.0:
		return
	var offset := global_position + Vector3.UP * 1.0 - origin
	var distance := offset.length()
	if distance >= radius:
		return
	var direction := offset.normalized() if distance > 0.001 else Vector3.UP
	direction = (direction + Vector3.UP * maxf(0.0, upward_bias)).normalized()
	apply_impulse(direction * impulse_strength * (1.0 - distance / radius))


# ════════════════════════════════════════════════════════
# ROTATION
# ════════════════════════════════════════════════════════
func _handle_rotation(delta: float) -> void:

	if camera_rig == null:
		return
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var aim_direction: Vector3 = camera_rig.get_aim_direction()
		var camera_target_y := atan2(-aim_direction.x, -aim_direction.z)
		rotation.y = lerp_angle(
			rotation.y,
			camera_target_y,
			1.0 - pow(0.001, delta * ease_speed)
		)
		return

	var camera: Camera3D = camera_rig.camera
	if camera == null:
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir    := camera.project_ray_normal(mouse_pos)

	var plane := Plane(Vector3.UP, global_position.y)
	var hit: Variant = plane.intersects_ray(ray_origin, ray_dir)
	if hit == null:
		return

	var dir: Vector3 = (global_position - (hit as Vector3)).normalized()
	var target_y: float = atan2(dir.x, dir.z)

	rotation.y = lerp_angle(
		rotation.y,
		target_y,
		1.0 - pow(0.001, delta * ease_speed)
	)


# ════════════════════════════════════════════════════════
# INPUT
# ════════════════════════════════════════════════════════
func _input(event: InputEvent) -> void:
	if GameChat.is_typing:
		return

	if not is_multiplayer_authority() or SteamLobby.is_gameplay_locked():
		return

	# В агонии/смерти — только кнопки которые не требуют управления
	if stats.is_dead:
		return
	# Пока открыт инвентарь, мышь и цифровые клавиши принадлежат интерфейсу.
	if inventory_ui != null and inventory_ui.is_main_panel_open():
		return

	if event is InputEventKey and event.pressed and not event.echo:
		# 1/2/3 всегда относятся только к панели быстрого доступа.
		match event.keycode:
			KEY_1: inventory.use_quickslot(0, self)
			KEY_2: inventory.use_quickslot(1, self)
			KEY_3: inventory.use_quickslot(2, self)

	# Боевой ввод обрабатывается WeaponCombat после UI в _unhandled_input.


# ════════════════════════════════════════════════════════
# СОСТОЯНИЯ (downed / died / revived)
# ════════════════════════════════════════════════════════
func _on_downed() -> void:
	animation_state = AnimationState.DOWNED
	# TODO: проиграть анимацию падения
	print("Player %s: упал, агония %.0f сек" % [name, stats.get_agony_duration()])


func _on_died() -> void:
	animation_state = AnimationState.DEAD
	# TODO: проиграть анимацию смерти, скрыть UI, показать экран смерти
	print("Player %s: погиб окончательно" % name)


func _on_revived() -> void:
	animation_state = AnimationState.IDLE
	# TODO: проиграть анимацию подъёма
	print("Player %s: поднят" % name)


# ════════════════════════════════════════════════════════
# SAVE
# ════════════════════════════════════════════════════════
func save_game() -> void:
	PlayerProfile.inventory = inventory.get_data()
	equipment.save_to_profile()
	SaveManager.save_profile()


func on_mission_complete() -> void:
	if not is_multiplayer_authority():
		return
	SaveManager.save_player_state(inventory, equipment)


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE and is_node_ready():
		# Транспорт уже может быть закрыт: authority больше нельзя запрашивать.
		if owns_local_profile:
			SaveManager.save_player_state(inventory, equipment)


# ════════════════════════════════════════════════════════
# НАПРАВЛЕНИЕ ВЗГЛЯДА
# Горизонтальный вектор куда смотрит герой. Герой поворачивается к
# курсору (см. _handle_rotation), поэтому это направление на курсор.
# ════════════════════════════════════════════════════════
func get_facing_direction() -> Vector3:
	var forward: Vector3 = global_transform.basis.z if model_faces_positive_z else -global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		return Vector3(0, 0, -1)
	return forward.normalized()


# ════════════════════════════════════════════════════════
# СЕТЬ
# ════════════════════════════════════════════════════════
# ════════════════════════════════════════════════════════
# МОДЕЛЬ ПЕРСОНАЖА
# Модель из сцены игрока заменяется на ту, что собрана в редакторе
# персонажа (тело, цвет кожи, причёска — см. character_models.gd).
# ════════════════════════════════════════════════════════
func _apply_character_model() -> void:

	var appearance: Dictionary = _resolve_appearance()
	if appearance.is_empty():
		appearance = {"body": CharacterModels.DEFAULT_BODY, "skin": CharacterModels.DEFAULT_SKIN, "hair": 0}

	var body_id: String = str(appearance.get("body", CharacterModels.DEFAULT_BODY))
	var new_model: Node3D = CharacterModels.create_model(body_id)

	# Старую модель убираем, а новую ставим на то же место в дереве
	var slot_index: int = 0
	if model != null:
		slot_index = model.get_index()
		model.name = "ModelReplaced"  # освободить имя "Model"
		remove_child(model)
		model.queue_free()

	new_model.name = "Model"
	new_model.rotation_degrees.y = character_model_yaw_degrees
	add_child(new_model)
	move_child(new_model, slot_index)

	model = new_model
	animation_player = new_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	animation_tree = new_model.find_child("AnimationTree", true, false) as AnimationTree

	CharacterModels.apply_appearance(new_model, appearance)


# Чью внешность показывать: свою — из профиля, чужую — из сетевого состояния
func _resolve_appearance() -> Dictionary:

	if is_multiplayer_authority():
		# Нет созданного персонажа (например отладочный запуск миссии) —
		# используем внешность по умолчанию.
		if PlayerProfile.character_name.is_empty():
			return {}
		return PlayerProfile.appearance

	var net_state: Dictionary = get_meta("network_state", {})
	var remote_appearance: Variant = net_state.get("appearance", null)
	if remote_appearance is Dictionary and not (remote_appearance as Dictionary).is_empty():
		return remote_appearance as Dictionary
	return {}
