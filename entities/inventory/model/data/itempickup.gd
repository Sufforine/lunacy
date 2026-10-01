# ItemPickup.gd
# Предмет, лежащий в мире. Создаётся кодом (см. InventoryUI._spawn_world_drop),
# подбирается при касании героем — но только через PICKUP_DELAY секунд после
# появления, чтобы выброшенный предмет не подбирался мгновенно обратно.
#
# Порядок использования:
#   var pickup := ItemPickup.new()
#   pickup.item = some_item
#   get_tree().current_scene.add_child(pickup)
#   pickup.global_position = ...
#   pickup.launch(direction, speed, up_speed, thrower)   # опционально: бросок
#
# В игре создавать пикапы нужно через SteamLobby.request_drop(...): он сам
# разошлёт предмет всем игрокам и выдаст drop_id.
extends Area3D
class_name ItemPickup

const PICKUP_DELAY     := 1.0    # сек, в течение которых предмет не подбирается
const GRAVITY          := 14.0
const MAX_FLIGHT_TIME  := 3.0    # страховка: если земля не найдена, остановиться
const LAND_OFFSET      := 0.05   # насколько выше точки касания встаёт предмет

var item: ItemData = null
var drop_id: int = 0        # одинаковый на всех пирах, назначает сервер

var _velocity: Vector3 = Vector3.ZERO
var _flying: bool = false
var _flight_time: float = 0.0
var _can_pickup: bool = false
var _request_pending: bool = false
var _exclude: Array[RID] = []


func _ready() -> void:

	monitoring   = true
	monitorable  = true
	# Слушаем все слои — не знаем как настроены коллизии в проекте.
	# Если у игрока отдельный физический слой, можно сузить через collision_mask.
	collision_mask = 0x7FFFFFFF

	_build_visual()
	_build_collision()

	body_entered.connect(_on_body_entered)

	# Запретить подбор на PICKUP_DELAY секунд
	get_tree().create_timer(PICKUP_DELAY).timeout.connect(_enable_pickup)


# ════════════════════════════════════════════════════════
# БРОСОК
# direction — горизонтальное направление, speed — скорость вперёд,
# up_speed — начальная скорость вверх. thrower исключается из поиска земли.
# ════════════════════════════════════════════════════════
func launch(direction: Vector3, speed: float, up_speed: float, thrower: Node3D = null) -> void:

	direction.y = 0.0
	direction = direction.normalized()

	_velocity = direction * speed + Vector3(0, up_speed, 0)
	_flight_time = 0.0
	_flying = true

	if thrower is CollisionObject3D:
		_exclude.append((thrower as CollisionObject3D).get_rid())


func _physics_process(delta: float) -> void:

	if not _flying:
		return

	_flight_time += delta
	_velocity.y -= GRAVITY * delta

	var from := global_position
	var to := from + _velocity * delta

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = _exclude
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	if not hit.is_empty():
		var normal: Vector3 = hit.normal
		global_position = hit.position + normal * LAND_OFFSET
		if normal.y > 0.5:
			_land()          # попали в пол — приземлились
		else:
			# Попали в стену — гасим горизонтальную скорость и падаем дальше
			_velocity.x = 0.0
			_velocity.z = 0.0
		return

	global_position = to

	if _flight_time >= MAX_FLIGHT_TIME:
		_land()


func _land() -> void:
	_flying = false
	_velocity = Vector3.ZERO


# ════════════════════════════════════════════════════════
# ПОДБОР
# ════════════════════════════════════════════════════════
func _enable_pickup() -> void:

	_can_pickup = true

	# Герой мог уже стоять в зоне подбора — body_entered для него не сработает
	for body in get_overlapping_bodies():
		_try_pickup(body)


func _on_body_entered(body: Node) -> void:
	_try_pickup(body)


func _try_pickup(body: Node) -> void:

	if not _can_pickup or item == null or _request_pending:
		return
	if not body.is_in_group("player"):
		return

	# Подбирает только владелец героя — иначе каждый пир слал бы свой запрос
	if not body.is_multiplayer_authority():
		return

	var inventory: InventoryComponent = body.get_node_or_null("InventoryComponent")
	if inventory == null or not inventory.has_free_slot():
		return

	# Сами предмет не забираем: просим подтверждение у сервера.
	# Нода удалится когда сервер разошлёт удаление всем пирам.
	_request_pending = true
	get_tree().create_timer(2.0).timeout.connect(func(): _request_pending = false)
	SteamLobby.request_pickup(drop_id, inventory)


# ════════════════════════════════════════════════════════
# ВИЗУАЛ И КОЛЛИЗИЯ
# ════════════════════════════════════════════════════════
func _build_collision() -> void:
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.6
	shape.shape = sphere
	add_child(shape)


func _build_visual() -> void:
	if item == null:
		return
	var sprite := Sprite3D.new()
	sprite.texture = item.icon
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.pixel_size = 0.01
	sprite.position = Vector3(0, 0.4, 0)
	add_child(sprite)
