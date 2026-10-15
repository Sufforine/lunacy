# character_models.gd
# Всё, что связано с моделями персонажа: список тел, создание модели и
# применение внешности (цвет кожи, причёска). Используется меню создания
# персонажа, позже тем же кодом можно одеть героя в игре:
#   CharacterModels.apply_appearance(model, PlayerProfile.appearance)
#
# ══ КАК ПОДКЛЮЧИТЬ НАСТОЯЩУЮ МОДЕЛЬ ═════════════════════════════
# 1. Впиши путь к сцене модели в BODY_TYPES (поле "scene").
#    Пока путь пустой, строится заглушка из боксов.
# 2. Правила для модели (их нужно соблюсти в самой сцене):
#    • MeshInstance3D, которые красятся цветом кожи, добавь в группу "skin".
#      Цвет ложится множителем на albedo материала, текстура сохраняется.
#    • Причёски — дети узла с именем "Hair" (любого уровня вложенности).
#      Каждый ребёнок — одна причёска, ИМЯ УЗЛА показывается на кнопке.
#      Лысый вариант добавлять не нужно: он есть всегда (индекс 0).
#    • AnimationPlayer с анимациями "idle", "walk", "downed", "dead":
#      "idle" играет в меню, остальные использует player.gd в игре.
# ═════════════════════════════════════════════════════════════════
class_name CharacterModels
extends RefCounted

const BODY_TYPES := [
	{"id": "male",   "label": "Мужской", "scene": ""},
	{"id": "female", "label": "Женский", "scene": ""},
]

const DEFAULT_BODY := "male"
const DEFAULT_SKIN := "e0ac69"

const SKIN_GROUP := "skin"
const HAIR_NODE := "Hair"


# ════════════════════════════════════════════════════════
# ТЕЛА
# ════════════════════════════════════════════════════════
static func get_body_def(body_id: String) -> Dictionary:
	for entry in BODY_TYPES:
		var body_def: Dictionary = entry
		if str(body_def["id"]) == body_id:
			return body_def
	var fallback: Dictionary = BODY_TYPES[0]
	return fallback


static func is_valid_body(body_id: String) -> bool:
	for entry in BODY_TYPES:
		var body_def: Dictionary = entry
		if str(body_def["id"]) == body_id:
			return true
	return false


# Создать модель выбранного тела: настоящую, если задан путь к сцене,
# иначе заглушку из боксов.
static func create_model(body_id: String) -> Node3D:

	var body_def: Dictionary = get_body_def(body_id)
	var scene_path: String = str(body_def.get("scene", ""))

	if not scene_path.is_empty() and ResourceLoader.exists(scene_path):
		var packed := load(scene_path) as PackedScene
		if packed != null:
			var instance: Node = packed.instantiate()
			if instance is Node3D:
				return instance as Node3D
			instance.queue_free()
			push_warning("CharacterModels: корень '%s' должен быть Node3D" % scene_path)

	return _build_placeholder(body_id)


static func play_idle(model: Node3D) -> void:
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null:
		return
	for animation_name in [&"idle", &"T"]:
		if player.has_animation(animation_name):
			player.play(animation_name)
			return


# ════════════════════════════════════════════════════════
# ВНЕШНОСТЬ
# appearance: {"body": id, "skin": "rrggbb", "hair": индекс}
# hair: 0 — без причёски, N — N-й ребёнок узла Hair
# (старые сохранения хранили цвет под ключом "color" — он тоже читается)
# ════════════════════════════════════════════════════════
static func apply_appearance(model: Node3D, appearance: Dictionary) -> void:

	var skin_html: String = str(appearance.get("skin", appearance.get("color", DEFAULT_SKIN)))
	# Внешность может прийти по сети от другого игрока — не доверяем строке слепо
	if not Color.html_is_valid(skin_html):
		skin_html = DEFAULT_SKIN
	var skin: Color = Color.html(skin_html)
	var hair_index: int = int(appearance.get("hair", 0))

	for node in model.find_children("*", "", true, false):
		if node.is_in_group(SKIN_GROUP):
			_tint(node, skin)

	var hair_root := model.find_child(HAIR_NODE, true, false)
	if hair_root != null:
		var styles := hair_root.get_children()
		for i in range(styles.size()):
			var style := styles[i] as Node3D
			if style != null:
				style.visible = (hair_index == i + 1)


# Имена причёсок (без «лысого» варианта) — для кнопок в редакторе
static func hair_names(model: Node3D) -> Array[String]:

	var result: Array[String] = []
	var hair_root := model.find_child(HAIR_NODE, true, false)
	if hair_root == null:
		return result

	for style in hair_root.get_children():
		result.append(str(style.name))
	return result


static func _tint(node: Node, skin: Color) -> void:

	# Заглушка: CSG-боксы
	if node is CSGShape3D:
		var material := StandardMaterial3D.new()
		material.albedo_color = skin
		node.set("material", material)
		return

	# Настоящая модель: красим материал каждой поверхности, сохраняя текстуру
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			return
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var base: Material = mesh_instance.mesh.surface_get_material(surface)
			var tinted: BaseMaterial3D
			if base is BaseMaterial3D:
				tinted = (base as BaseMaterial3D).duplicate() as BaseMaterial3D
			else:
				tinted = StandardMaterial3D.new()
			tinted.albedo_color = skin
			mesh_instance.set_surface_override_material(surface, tinted)


# ════════════════════════════════════════════════════════
# ЗАГЛУШКА (пока нет настоящих моделей)
# Ноги, торс — одежда; руки и голова — группа "skin"; причёски — дети "Hair".
# Начало координат — под ногами.
# ════════════════════════════════════════════════════════
static func _build_placeholder(body_id: String) -> Node3D:

	var female: bool = body_id == "female"

	var leg_h: float = 0.58 if female else 0.6
	var torso_h: float = 0.7 if female else 0.8
	var torso_w: float = 0.7 if female else 0.95
	var torso_d: float = 0.42 if female else 0.5
	var head: float = 0.34 if female else 0.36
	var arm_w: float = 0.18 if female else 0.22
	var leg_w: float = torso_w * 0.42

	var cloth_color: Color = Color8(150, 60, 80) if female else Color8(60, 80, 120)
	var pants_color: Color = Color8(45, 45, 55)
	var hair_color: Color = Color8(60, 38, 24)

	var root := Node3D.new()
	root.name = "Model"

	# Ноги
	for side in [-1.0, 1.0]:
		root.add_child(_box(
			Vector3(leg_w, leg_h, torso_d * 0.9),
			Vector3(side * leg_w * 0.55, leg_h * 0.5, 0.0),
			pants_color))

	# Торс
	var torso_y: float = leg_h + torso_h * 0.5
	root.add_child(_box(Vector3(torso_w, torso_h, torso_d), Vector3(0.0, torso_y, 0.0), cloth_color))

	# Руки (кожа)
	for side in [-1.0, 1.0]:
		var arm := _box(
			Vector3(arm_w, torso_h * 0.95, arm_w),
			Vector3(side * (torso_w * 0.5 + arm_w * 0.5 + 0.02), torso_y, 0.0),
			Color.WHITE)
		arm.add_to_group(SKIN_GROUP)
		root.add_child(arm)

	# Голова (кожа)
	var head_top: float = leg_h + torso_h + head
	var head_box := _box(Vector3(head, head, head), Vector3(0.0, head_top - head * 0.5, 0.0), Color.WHITE)
	head_box.add_to_group(SKIN_GROUP)
	root.add_child(head_box)

	# Причёски
	var hair_root := Node3D.new()
	hair_root.name = HAIR_NODE
	root.add_child(hair_root)

	var styles: Array[Dictionary] = []
	styles.append(_hair_on_top("Ёжик", head_top, Vector3(head * 1.06, 0.08, head * 1.06)))
	styles.append(_hair_on_top("Башня", head_top, Vector3(head * 0.6, head * 0.9, head * 0.6)))
	styles.append(_hair_on_top("Шляпа", head_top, Vector3(head * 1.6, 0.07, head * 1.6)))
	styles.append(_hair_on_top("Гребень", head_top, Vector3(head * 0.2, head * 0.5, head * 1.05)))
	if female:
		# Длинные: высокий бокс за головой — так число причёсок у тел разное
		var long_size := Vector3(head * 1.15, head * 2.2, 0.1)
		styles.append({
			"name": "Длинные",
			"size": long_size,
			"pos":  Vector3(0.0, head_top - long_size.y * 0.5 + 0.06, -(head * 0.5 + 0.04)),
		})

	for style in styles:
		var hair_box := _box(style["size"], style["pos"], hair_color)
		hair_box.name = str(style["name"])
		hair_box.visible = false
		hair_root.add_child(hair_box)

	return root


static func _hair_on_top(style_name: String, head_top: float, hair_size: Vector3) -> Dictionary:
	return {
		"name": style_name,
		"size": hair_size,
		"pos":  Vector3(0.0, head_top + hair_size.y * 0.5 - 0.02, 0.0),
	}


static func _box(box_size: Vector3, box_position: Vector3, color: Color) -> CSGBox3D:
	var box := CSGBox3D.new()
	box.size = box_size
	box.position = box_position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	box.material = material
	return box
