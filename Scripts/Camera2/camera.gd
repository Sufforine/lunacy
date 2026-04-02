extends Node3D

@export var rotation_speed: float = 10 # Скорость вращения камеры
@export var deadzone: float = 0.1 # "Мертвая зона" в центре экрана

@export var player: Player
var _offset = Vector3.ZERO

func _calc_offset():
	if not player:
		printerr("Player is no assigned")
		return	
	var offset_x = global_position.x - player.position.x
	var offset_z = global_position.z - player.position.z
	_offset = Vector3(offset_x, 0, offset_z)

func _ready():
	# Делаем курсор видимым
	_calc_offset()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# Отвязываем от вращения игрока
	top_level = true

func _process(delta: float):
	# 1. Следуем за игроком
	if get_parent():
		global_position = get_parent().global_position
	
	# 2. Логика поворота за курсором
	_rotate_camera_to_mouse(delta)

func _rotate_camera_to_mouse(delta: float):
	var viewport = get_viewport()
	var mouse_pos = viewport.get_mouse_position()
	var screen_size = viewport.get_visible_rect().size
	
	# Получаем позицию мыши от -1.0 (лево) до 1.0 (право) относительно центра
	var center_offset = (mouse_pos.x / screen_size.x) * 2.0 - 1.0
	
	# Если мышь не в центре (вне мертвой зоны), вращаем камеру
	if abs(center_offset) > deadzone:
		# Рассчитываем скорость поворота
		# Чем дальше мышь от центра, тем быстрее крутится камера
		var rotation_amount = center_offset * rotation_speed * delta
		rotate_y(-rotation_amount)
