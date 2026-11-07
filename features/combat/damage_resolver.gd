extends RefCounted

# One transaction for both damage types. Never changes the target itself.
static func resolve(stats: StatsComponent, physical: int, magical: int) -> Dictionary:
	var result := {"physical": 0, "magical": 0, "absorbed": 0.0}
	var shield := maxf(stats.current_shield, 0.0)
	var health := maxi(stats.current_health, 0)
	var combat := stats.get_parent().get_node_or_null("WeaponCombat")
	for kind in ["physical", "magical"]:
		var amount: int = maxi(physical if kind == "physical" else magical, 0)
		if amount == 0:
			continue
		if combat != null:
			amount = combat.mitigate_damage(amount, kind == "magical")
		var resistance := maxf(0.0, stats.get_stat("armor" if kind == "physical" else "magic_resistance"))
		amount = maxi(0, amount - int(resistance))
		var absorbed := minf(shield, amount)
		shield -= absorbed
		result.absorbed += absorbed
		amount = maxi(0, ceili(amount - absorbed))
		if not stats.training_target:
			amount = mini(amount, health)
			health -= amount
		result[kind] = amount
	result["shield"] = shield
	result["health"] = stats.current_health if stats.training_target else health
	return result
