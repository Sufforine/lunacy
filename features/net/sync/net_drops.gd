class_name NetDrops
extends RefCounted
# Реестр предметов, лежащих в мире. Сами RPC живут в steam_lobby.gd
# (как и у остальных сетевых хелперов) — здесь только учёт и спавн.
#
# У каждого выброшенного предмета есть drop_id, одинаковый на всех пирах.
# По нему сервер решает кто именно подобрал предмет (первый запрос выигрывает).

const CONTAINER_NAME := "Drops"
const LAUNCH_SPEED := 5.0      # скорость броска вперёд
const LAUNCH_UP_SPEED := 3.0   # подброс вверх

var _next_id: int = 1          # используется только на сервере (и в соло)
var _drops: Dictionary = {}    # drop_id → ItemPickup


func allocate_id() -> int:
	var id := _next_id
	_next_id += 1
	return id


func spawn(
	scene: Node,
	drop_id: int,
	item: ItemData,
	position: Vector3,
	direction: Vector3,
	thrower: Node3D = null
) -> ItemPickup:

	if has_drop(drop_id):
		return _drops[drop_id] as ItemPickup

	var pickup := ItemPickup.new()
	pickup.name = "Drop_%d" % drop_id
	pickup.item = item
	pickup.drop_id = drop_id

	_get_container(scene).add_child(pickup)
	pickup.global_position = position
	pickup.launch(direction, LAUNCH_SPEED, LAUNCH_UP_SPEED, thrower)

	_drops[drop_id] = pickup
	return pickup


func has_drop(drop_id: int) -> bool:
	if not _drops.has(drop_id):
		return false
	if not is_instance_valid(_drops[drop_id]):
		# Сцена сменилась и нода уже удалена
		_drops.erase(drop_id)
		return false
	return true


func get_item_id(drop_id: int) -> String:
	if not has_drop(drop_id):
		return ""
	var pickup := _drops[drop_id] as ItemPickup
	if pickup.item == null:
		return ""
	return pickup.item.id


func remove(drop_id: int) -> void:
	if not _drops.has(drop_id):
		return
	var raw: Variant = _drops[drop_id]
	if is_instance_valid(raw):
		(raw as Node).queue_free()
	_drops.erase(drop_id)


func clear() -> void:
	for drop_id in _drops.keys():
		remove(drop_id)
	_drops.clear()


func _get_container(scene: Node) -> Node:
	var container: Node = scene.get_node_or_null(CONTAINER_NAME)
	if container == null:
		container = Node3D.new()
		container.name = CONTAINER_NAME
		scene.add_child(container)
	return container
