# shield_visual.gd
# Самодостаточный визуал щита. Ничего не знает про player.gd —
# сам создаёт свою сферу, сам находит StatsComponent (сосед по дереву,
# т.к. EffectsComponent добавляет этот визуал прямо в героя) и сам решает
# когда быть видимым.
#
# Использование: назначь этот скрипт в EffectData.visual_script.
# EffectsComponent создаст и удалит его автоматически вместе с эффектом.
extends Node3D

var _mesh: MeshInstance3D = null
var _stats: StatsComponent = null


func _ready() -> void:

	_stats = get_parent().get_node_or_null("StatsComponent")
	if _stats == null:
		push_warning("shield_visual: StatsComponent не найден у родителя")
		return

	_build_mesh()
	_stats.stats_changed.connect(_update_visibility)
	_update_visibility()


func _process(delta: float) -> void:
	if visible:
		rotate_y(delta * 0.6)


func _update_visibility() -> void:
	visible = _stats.current_shield > 0.0


func _build_mesh() -> void:

	_mesh = MeshInstance3D.new()

	var sphere := SphereMesh.new()
	sphere.radius = 1.1
	sphere.height = 2.2
	sphere.radial_segments = 24
	sphere.rings = 12
	_mesh.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.3, 0.7, 1.0, 0.28)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.7, 1.0)
	mat.emission_energy_multiplier = 0.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = mat

	_mesh.position = Vector3(0, 1.1, 0)
	add_child(_mesh)
