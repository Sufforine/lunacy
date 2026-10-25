extends AbilityBehavior
class_name MeleeAbilityBehavior

@export var damage_multiplier: float = 1.0
@export var range_multiplier: float = 1.0
@export_range(1.0, 360.0) var arc_degrees: float = 100.0
@export var knockback: float = 0.0


func execute(context: Dictionary) -> void:
	var hero := context.actor as Player
	var controller: Node = context.controller
	var used_weapon := context.weapon as WeaponData
	var reach := used_weapon.attack_range * range_multiplier
	var arc: float = arc_degrees
	var multiplier: float = damage_multiplier
	var origin := hero.global_position + Vector3.UP
	var shape := SphereShape3D.new()
	shape.radius = reach
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = origin
	query.exclude = [hero.get_rid()]
	var seen: Array[Node] = []
	for hit in hero.get_world_3d().direct_space_state.intersect_shape(query, 64):
		var target := hit.collider as Node3D
		# Кооперативный режим: союзные герои не получают урон друг от друга.
		if target == null or target is Player or seen.has(target):
			continue
		var target_stats := target.get_node_or_null("StatsComponent") as StatsComponent
		if target_stats == null or target_stats.is_dead:
			continue
		seen.append(target)
		var point := target.global_position + Vector3.UP * 0.8
		var offset := point - origin
		var horizontal := Vector3(offset.x, 0, offset.z)
		if horizontal.length() > reach or hero.get_facing_direction().dot(horizontal.normalized()) < cos(deg_to_rad(arc * 0.5)):
			continue
		var ray := PhysicsRayQueryParameters3D.create(origin, point, 1)
		ray.exclude = [hero.get_rid()]
		if not hero.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		var physical := int(round(used_weapon.get_physical_damage(hero.stats) * multiplier))
		var magical := int(round(used_weapon.get_magical_damage(hero.stats) * multiplier))
		controller.apply_damage(target, physical, magical)
		if knockback > 0.0 and target.has_method("apply_impulse"):
			target.call("apply_impulse", horizontal.normalized() * knockback)


