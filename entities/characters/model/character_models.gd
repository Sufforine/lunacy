# Общая модель для героя и конструктора: скелет UAL2, мужской/женский меш,
# отдельные материалы кожи и геометрические причёски на кости головы.
class_name CharacterModels
extends RefCounted

const BODY_TYPES := [
	{"id": "male",   "label": "Мужской", "scene": "res://Assets/skeleton/Mannequin.tscn"},
	{"id": "female", "label": "Женский", "scene": "res://Assets/skeleton/Mannequin_F.tscn"},
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


# Создать выбранное тело на общем анимированном скелете UAL2.
static func create_model(body_id: String) -> Node3D:

	var body_def: Dictionary = get_body_def(body_id)
	return _build_mannequin(str(body_def["id"]))


static func _build_mannequin(body_id: String) -> Node3D:
	var scene_path: String = get_body_def(body_id)["scene"]
	var model := (load(scene_path) as PackedScene).instantiate() as Node3D
	model.name = "Model"
	var skeleton := model.find_child("HumanSkeleton", true, false) as Skeleton3D
	_add_mannequin_hair(skeleton, body_id == "female")
	return model


static func _add_mannequin_hair(skeleton: Skeleton3D, female: bool) -> void:
	var attachment := BoneAttachment3D.new()
	attachment.name = "HeadAccessories"
	attachment.bone_name = "Head"
	skeleton.add_child(attachment)
	var hair := Node3D.new()
	hair.name = HAIR_NODE
	attachment.add_child(hair)
	var top := 0.25
	var styles: Array[Dictionary] = [
		_hair_on_top("Ёжик", top, Vector3(0.24, 0.06, 0.24)),
		_hair_on_top("Башня", top, Vector3(0.16, 0.24, 0.16)),
		_hair_on_top("Шляпа", top, Vector3(0.42, 0.06, 0.36)),
		_hair_on_top("Гребень", top, Vector3(0.06, 0.18, 0.25)),
	]
	if female:
		styles.append({"name": "Длинные", "size": Vector3(0.25, 0.42, 0.09), "pos": Vector3(0, 0.06, -0.12)})
	for style in styles:
		var box := _box(style["size"], style["pos"], Color8(60, 38, 24))
		box.name = style["name"]
		box.visible = false
		hair.add_child(box)


static func play_idle(model: Node3D) -> void:
	var tree := model.get_node_or_null("AnimationTree") as AnimationTree
	if tree != null:
		tree.active = true
		var playback := tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		var alive_playback := tree.get("parameters/Alive/playback") as AnimationNodeStateMachinePlayback
		tree.set("parameters/Alive/Grounded/blend_position", 0.0)
		alive_playback.start(&"Grounded")
		playback.start(&"Alive")


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
