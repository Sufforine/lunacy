extends CharacterBody3D
class_name Player

@export var ease_speed: float = 5.0

@onready var camera_rig          = $CameraRig
@onready var model: Node3D           = $Model
@onready var animation_player: AnimationPlayer = $Model/AnimationPlayer

@onready var stats: StatsComponent         = $StatsComponent
@onready var equipment: EquipmentComponent = $EquipmentComponent
@onready var inventory: InventoryComponent = $InventoryComponent
@onready var inventory_ui                  = $CanvasLayer/InventoryUI
@onready var stats_label: Label            = $CanvasLayer/StatsLabel


# ── состояния анимации ───────────────────────────────────
enum AnimationState { IDLE, WALK, DOWNED, DEAD }
var animation_state: AnimationState = AnimationState.IDLE

var _persist_player_data_enabled := false


# ════════════════════════════════════════════════════════
# READY
# ════════════════════════════════════════════════════════
func _ready() -> void:
	var network_state: Variant = get_meta("network_state") if has_meta("network_state") else null

	if network_state is Dictionary and not is_multiplayer_authority():
		_apply_network_state(network_state)
	else:
		equipment.load_from_profile()
		inventory.set_data(PlayerProfile.inventory)

	stats.current_health = int(stats.get_stat("health"))
	stats.current_mana   = int(stats.get_stat("mana"))

	stats.downed.connect(_on_downed)
	stats.died.connect(_on_died)
	stats.revived.connect(_on_revived)

	call_deferred("_finish_setup")

	print("Player ready:", name, " auth:", is_multiplayer_authority())


func _finish_setup() -> void:
	inventory_ui.bind(inventory, equipment)

	if multiplayer.has_multiplayer_peer():
		var is_local := is_multiplayer_authority()
		camera_rig.enabled = is_local
		$CanvasLayer.visible = is_local
	
	
	if not _saved_inventory_has_items():
		_add_debug_starter_items()
		SaveManager.save_player_state(inventory, equipment)

	_enable_persist()


func _saved_inventory_has_items() -> bool:
	print("Xddd")
	for entry in PlayerProfile.inventory:
		if entry is String and not entry.is_empty():
			return true
	return false


func _add_debug_starter_items() -> void:
	inventory.add_item(ItemLibrary.get_item("hpot"))
	inventory.add_item(ItemLibrary.get_item("mpot"))
	inventory.add_item(ItemLibrary.get_item("hpot"))
	inventory.add_item(ItemLibrary.get_item("coat"))
	inventory.add_item(ItemLibrary.get_item("axe"))
	inventory.add_item(ItemLibrary.get_item("spd"))


func _enable_persist() -> void:
	_persist_player_data_enabled = true
	if not _should_persist():
		return

	if not inventory.changed.is_connected(_on_player_data_changed):
		inventory.changed.connect(_on_player_data_changed)
	if not equipment.changed.is_connected(_on_player_data_changed):
		equipment.changed.connect(_on_player_data_changed)


func _should_persist() -> bool:
	if not _persist_player_data_enabled:
		return false
	if multiplayer.has_multiplayer_peer():
		return is_multiplayer_authority()
	return true


func _on_player_data_changed() -> void:
	if not _should_persist():
		return
	SaveManager.save_player_state(inventory, equipment)


func _apply_network_state(state_data: Dictionary) -> void:
	equipment.load_from_dict(state_data.get("equipment", {}))
	inventory.set_data(state_data.get("inventory", []))


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
	_update_stats_ui()
	_update_animation()


# ════════════════════════════════════════════════════════
# MOVEMENT
# ════════════════════════════════════════════════════════
func _handle_movement() -> void:

	var input_dir := InputManager.get_input_direction()
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

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: inventory.use_item(0, self)
			KEY_2: inventory.use_item(1, self)
			KEY_3: inventory.use_item(2, self)
			KEY_4: inventory.use_item(3, self)
			KEY_5: inventory.use_item(4, self)
			KEY_6: inventory.use_item(5, self)


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

	if animation_player == null:
		return

	match animation_state:
		AnimationState.IDLE:
			if not animation_player.current_animation == "idle":
				animation_player.play("idle")
		AnimationState.WALK:
			if not animation_player.current_animation == "walk":
				animation_player.play("walk")
		AnimationState.DOWNED:
			if not animation_player.current_animation == "downed":
				animation_player.play("downed")
		AnimationState.DEAD:
			if not animation_player.current_animation == "dead":
				animation_player.play("dead")


# ════════════════════════════════════════════════════════
# UI
# ════════════════════════════════════════════════════════
func _update_stats_ui() -> void:

	if stats_label == null:
		return

	var agony_text := ""
	if stats.is_downed:
		agony_text = "\nАгония: %.1f сек (дух: %d)" % [
			stats._agony_timer,
			stats.current_morale
		]
	elif stats.is_dead:
		agony_text = "\n[ПОГИБ]"

	stats_label.text = (
		"HP: %d / %d\nMana: %d / %d\nBronya: %d\nMag.res: %d\nMS: %.1f\nCrit: %.0f%%\nDukh: %d%s"
	) % [
		stats.current_health, int(stats.get_stat("health")),
		stats.current_mana,   int(stats.get_stat("mana")),
		int(stats.get_stat("physical_resistance")),
		int(stats.get_stat("magical_resistance")),
		stats.get_stat("move_speed"),
		stats.get_stat("crit_chance") * 100.0,
		stats.current_morale,
		agony_text
	]


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
	if what == NOTIFICATION_PREDELETE:
		if is_multiplayer_authority():
			SaveManager.save_player_state(inventory, equipment)
