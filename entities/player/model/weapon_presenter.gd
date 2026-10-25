extends Node

var hero: Player
var _attachments: Array[BoneAttachment3D] = []
var _weapon: WeaponData


func _ready() -> void:
	hero = get_parent() as Player
	hero.equipment.changed.connect(refresh)
	refresh()


func refresh() -> void:
	var weapon := hero.equipment.weapon as WeaponData
	if weapon == _weapon:
		return
	_weapon = weapon
	for attachment in _attachments:
		if is_instance_valid(attachment):
			attachment.free()
	_attachments.clear()
	if weapon == null:
		return
	_attach(weapon.right_hand_scene, "RightHand", weapon.right_hand_position, weapon.right_hand_rotation, weapon.right_hand_scale)
	_attach(weapon.left_hand_scene, "LeftHand", weapon.left_hand_position, weapon.left_hand_rotation, weapon.left_hand_scale)


func _attach(scene: PackedScene, bone: String, offset: Vector3, angles: Vector3, model_scale: Vector3) -> void:
	if scene == null:
		return
	var skeleton := hero.model.find_child("HumanSkeleton", true, false) as Skeleton3D
	if skeleton == null or skeleton.find_bone(bone) < 0:
		return
	var attachment := BoneAttachment3D.new()
	attachment.name = bone + "Weapon"
	attachment.bone_name = bone
	skeleton.add_child(attachment)
	var instance := scene.instantiate()
	if not instance is Node3D:
		instance.free()
		attachment.queue_free()
		return
	var visual := instance as Node3D
	attachment.add_child(visual)
	visual.position = offset
	visual.rotation_degrees = angles
	visual.scale = model_scale
	_attachments.append(attachment)


