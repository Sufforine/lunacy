class_name Player
extends CharacterBody3D

## Скорость движения
@export var move_speed: float = 5.0
## Скорость поворота персонажа (лицом по направлению движения)
@export var rotation_speed: float = 10.0

## Ссылка на вашу новую камеру-риг
@onready var camera_rig = $CameraPivot # Убедитесь, что имя совпадает с узлом в сцене

func _physics_process(delta: float) -> void:
	_handle_movement(delta)

func _handle_movement(delta: float) -> void:
	# 1. Получаем вектор ввода (например, WASD)
	var input_dir = InputManager.get_input_direction() # Ожидается Vector3
	
	# 2. Берем базис (направление) камеры
	# .basis.z — это куда смотрит камера "вглубь"
	# .basis.x — это "право" камеры
	var camera_basis = camera_rig.global_transform.basis
	
	# 3. Рассчитываем направление движения относительно камеры
	# Мы обнуляем Y, чтобы игрок не пытался "лететь" вверх, если камера наклонена
	var forward = camera_basis.z
	var right = camera_basis.x
	forward.y = 0
	right.y = 0
	forward = forward.normalized()
	right = right.normalized()
	
	# Итоговый вектор: (вперед/назад по камере) + (лево/право по камере)
	var direction = (forward * input_dir.z + right * input_dir.x).normalized()
	
	if direction.length() > 0.001:
		# Двигаем персонажа
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
		
		# ПОВОРОТ ПЕРСОНАЖА: 
		# Вместо того чтобы смотреть на курсор, персонаж плавно поворачивается 
		# в ту сторону, КУДА ОН ИДЕТ (как в большинстве экшн-MOBA)
		var target_angle = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)

	move_and_slide()
