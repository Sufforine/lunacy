extends CharacterBody3D
class_name Player

@export var ease_speed: float = 5.0

@onready var camera_rig = $CameraRig
@onready var dullahan: Node3D = $Dullahan
@onready var animation_player: AnimationPlayer = $Dullahan/AnimationPlayer

@onready var stats: StatsComponent = $StatsComponent
@onready var equipment: EquipmentComponent = $EquipmentComponent

@onready var stats_label: Label = $CanvasLayer/StatsLabel

@onready var inventory_ui = $CanvasLayer/InventoryUI
@onready var inventory = $InventoryComponent


enum AnimationState {
	IDLE,
	WALK
}

var animation_state: AnimationState = AnimationState.IDLE


# =========================================================
# READY
# =========================================================
func _ready() -> void:
 
	equipment.load_from_profile()
	inventory.set_data(PlayerProfile.inventory)
 
	stats.current_health = stats.get_stat("health")
	stats.current_mana   = stats.get_stat("mana")
 
	# call_deferred гарантирует что InventoryUI._ready() уже отработал
	# и _collect_slots() собрал кнопки до того как мы зовём bind/add_item
	call_deferred("_init_inventory")
 
	print("Player ready:", name, " auth:", is_multiplayer_authority())
 
 
func _init_inventory() -> void:
 
	inventory_ui.bind(inventory, equipment)   # <- добавить equipment
 
	inventory.add_item(ItemLibrary.get_item("hpot"))
	inventory.add_item(ItemLibrary.get_item("mpot"))
	inventory.add_item(ItemLibrary.get_item("bpot"))
	inventory.add_item(ItemLibrary.get_item("hpot"))
	inventory.add_item(ItemLibrary.get_item("coat"))
	inventory.add_item(ItemLibrary.get_item("axe"))





# =========================================================
# PHYSICS
# =========================================================
func _physics_process(delta: float):

	# движение только у локального игрока
	if not is_multiplayer_authority():
		return

	_handle_movement()
	_handle_rotation(delta)


# =========================================================
# PROCESS
# =========================================================
func _process(_delta: float):
	_update_stats_ui()


# =========================================================
# MOVEMENT
# =========================================================
func _handle_movement():

	var input_dir = InputManager.get_input_direction()

	var speed = stats.get_stat("move_speed")

	velocity.x = input_dir.x * speed
	velocity.z = input_dir.z * speed

	if input_dir.length() > 0:
		animation_state = AnimationState.WALK
	else:
		animation_state = AnimationState.IDLE

	move_and_slide()


# =========================================================
# ROTATION
# =========================================================
func _handle_rotation(delta: float):

	if camera_rig == null:
		return

	var camera: Camera3D = camera_rig.camera
	if camera == null:
		return

	var mouse_pos = get_viewport().get_mouse_position()

	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)

	var plane = Plane(Vector3.UP, global_position.y)
	var hit = plane.intersects_ray(ray_origin, ray_dir)

	if hit == null:
		return

	var dir = (global_position - hit).normalized()
	var target_y = atan2(dir.x, dir.z)

	rotation.y = lerp_angle(
		rotation.y,
		target_y,
		1.0 - pow(0.001, delta * ease_speed)
	)


# =========================================================
# INPUT (HOTBAR)
# =========================================================
func _input(event):

	if not is_multiplayer_authority():
		return

	if event is InputEventKey and event.pressed:

		match event.keycode:

			KEY_1: inventory.use_item(0, self)
			KEY_2: inventory.use_item(1, self)
			KEY_3: inventory.use_item(2, self)
			KEY_4: inventory.use_item(3, self)
			KEY_5: inventory.use_item(4, self)
			KEY_6: inventory.use_item(5, self)


# =========================================================
# UI
# =========================================================
func _update_stats_ui():

	if stats_label == null:
		return

	stats_label.text = "HP: %s\nMana: %s\nDMG: %s\nARM: %s\nMS: %s\nCRIT: %s" % [
			stats.get_stat("health"),
			stats.get_stat("mana"),
			stats.get_stat("physical_damage"),
			stats.get_stat("physical_resistance"),
			stats.get_stat("move_speed"),
			stats.get_stat("crit_chance")
		]


# =========================================================
# SAVE
# =========================================================
func save_game():

	PlayerProfile.inventory = inventory.get_data()
	equipment.save_to_profile()
	SaveManager.save_profile()
