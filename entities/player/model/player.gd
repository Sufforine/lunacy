extends CharacterBody3D
class_name Player

const PAUSE_MENU_SCENE := preload("res://screens/pause/ui/pause_menu.tscn")
const ANIM_IDLE := [&"idle", &"T"]
const ANIM_RUN := [&"walk", &"Run"]
const ANIM_CRAWL := [&"downed", &"Crawl"]
const ANIM_DEAD := [&"dead", &"T"]
const ANIM_SLASH := [&"attack", &"Slash"]
const ANIM_ABILITY := [&"ability", &"Fireballs"]
const ANIM_JUMP := [&"jump", &"Jump"]

@export var ease_speed: float = 5.0
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


# ── состояния анимации ───────────────────────────────────
enum AnimationState { IDLE, WALK, DOWNED, DEAD }
var animation_state: AnimationState = AnimationState.IDLE
var _action_locked: bool = false


# ════════════════════════════════════════════════════════
# READY
# ════════════════════════════════════════════════════════
func _ready() -> void:

	add_to_group("player")

	# Первым делом: заменить модель из сцены на модель, созданную в редакторе
	# персонажа (до того как что-то начнёт использовать model/animation_player)
	_apply_character_model()
	_resolve_animation_player()
	if animation_player != null and not animation_player.animation_finished.is_connected(_on_action_animation_finished):
		animation_player.animation_finished.connect(_on_action_animation_finished)

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

		# Любая смена снаряжения уходит остальным игрокам
		equipment.changed.connect(_on_local_equipment_changed)
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
	if not is_multiplayer_authority():
		return

	inventory_ui.bind(inventory, equipment, stats)
	inventory.set_quickslot_data(PlayerProfile.quickslots)
	inventory.add_item(ItemLibrary.get_item("experience_relic"))
	inventory.add_item(ItemLibrary.get_item("ShieldArmor"))


# ════════════════════════════════════════════════════════
# PHYSICS
# ════════════════════════════════════════════════════════
func _physics_process(delta: float) -> void:

	if not is_multiplayer_authority():
		return

	# В агонии или мёртв — не двигаемся
	if stats.is_downed or stats.is_dead:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	_handle_movement()
	_handle_rotation(delta)


# ════════════════════════════════════════════════════════
# PROCESS
# ════════════════════════════════════════════════════════
func _process(_delta: float) -> void:
	_update_animation()


# ════════════════════════════════════════════════════════
# MOVEMENT
# ════════════════════════════════════════════════════════
func _handle_movement() -> void:

	var input_dir := InputManager.get_input_direction()
	if camera_rig != null:
		input_dir = camera_rig.get_camera_relative_direction(input_dir)
	var speed: float = stats.get_stat("move_speed")

	velocity.x = input_dir.x * speed
	velocity.z = input_dir.z * speed

	animation_state = AnimationState.WALK if input_dir.length() > 0 else AnimationState.IDLE
	move_and_slide()


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

	if not is_multiplayer_authority():
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

	if stats.is_downed or not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed("attack"):
		_play_action(ANIM_SLASH)
	elif event.is_action_pressed("ability"):
		_play_action(ANIM_ABILITY)
	elif event.is_action_pressed("jump"):
		_play_action(ANIM_JUMP)


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
# АНИМАЦИИ
# ════════════════════════════════════════════════════════
func _update_animation() -> void:

	if animation_player == null or _action_locked:
		return

	match animation_state:
		AnimationState.IDLE:
			_play_loop(ANIM_IDLE)
		AnimationState.WALK:
			_play_loop(ANIM_RUN)
		AnimationState.DOWNED:
			_play_loop(ANIM_CRAWL)
		AnimationState.DEAD:
			_play_loop(ANIM_DEAD)


func _resolve_animation_player() -> void:
	if animation_player == null and model != null:
		animation_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer


func _find_animation(candidates: Array) -> StringName:
	if animation_player == null:
		return &""
	for animation_name in candidates:
		if animation_player.has_animation(animation_name):
			return animation_name
	return &""


func _play_loop(candidates: Array) -> void:
	var animation_name := _find_animation(candidates)
	if animation_name != &"" and animation_player.current_animation != animation_name:
		animation_player.play(animation_name)


func _play_action(candidates: Array) -> void:
	if _action_locked:
		return
	var animation_name := _find_animation(candidates)
	if animation_name == &"":
		return
	_start_action_animation(animation_name)
	if SteamLobby.is_session_active():
		_rpc_play_action_animation.rpc(animation_name)


@rpc("authority", "call_remote", "reliable")
func _rpc_play_action_animation(animation_name: StringName) -> void:
	if animation_player == null or not animation_player.has_animation(animation_name):
		return
	_start_action_animation(animation_name)


func _start_action_animation(animation_name: StringName) -> void:
	_action_locked = true
	animation_player.play(animation_name)


func _on_action_animation_finished(_animation_name: StringName) -> void:
	if not _action_locked:
		return
	_action_locked = false
	_update_animation()


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
	if what == NOTIFICATION_PREDELETE and is_inside_tree():
		if is_multiplayer_authority():
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
func _on_local_equipment_changed() -> void:
	SteamLobby.sync_equipment(equipment.to_dict())


# ════════════════════════════════════════════════════════
# МОДЕЛЬ ПЕРСОНАЖА
# Модель из сцены игрока заменяется на ту, что собрана в редакторе
# персонажа (тело, цвет кожи, причёска — см. character_models.gd).
# ════════════════════════════════════════════════════════
func _apply_character_model() -> void:

	var appearance: Dictionary = _resolve_appearance()
	if appearance.is_empty():
		return  # внешности нет — остаётся модель из сцены

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

	CharacterModels.apply_appearance(new_model, appearance)


# Чью внешность показывать: свою — из профиля, чужую — из сетевого состояния
func _resolve_appearance() -> Dictionary:

	if is_multiplayer_authority():
		# Нет созданного персонажа (например отладочный запуск миссии) —
		# оставляем модель сцены
		if PlayerProfile.character_name.is_empty():
			return {}
		return PlayerProfile.appearance

	var net_state: Dictionary = get_meta("network_state", {})
	var remote_appearance: Variant = net_state.get("appearance", null)
	if remote_appearance is Dictionary and not (remote_appearance as Dictionary).is_empty():
		return remote_appearance as Dictionary
	return {}
