# ItemData.gd
# Единый класс для всех предметов игры.
# Расходники: slot = NONE, is_consumable = true
# Снаряжение: slot = WEAPON / ARMOR / TRINKET_1 / SCROLL
extends Resource
class_name ItemData

enum Slot { NONE, WEAPON, ARMOR, TRINKET_1, SCROLL }

@export var id: String = ""
@export var item_name: String = ""
@export var icon: Texture2D = null
@export var description: String = ""

# Расходник — исчезает после использования
@export var is_consumable: bool = false

# Слот экипировки. NONE = не является снаряжением
@export var slot: Slot = Slot.NONE

# Эффекты при использовании (зелья)
@export_group("On Use")
@export var heal_hp: int = 0
@export var heal_mana: int = 0

# Бонусы к статам (снаряжение)
@export_group("Stat Bonuses")
@export var bonus_health: int = 0
@export var bonus_mana: int = 0
@export var bonus_physical_damage: int = 0
@export var bonus_magical_damage: int = 0
@export var bonus_physical_resistance: int = 0
@export var bonus_magical_resistance: int = 0
@export var bonus_move_speed: float = 0.0
@export var bonus_attack_speed: float = 0.0
@export var bonus_crit_chance: float = 0.0
@export var bonus_crit_damage: float = 0.0
@export var bonus_morale: int = 0


func is_equipment() -> bool:
	return slot != Slot.NONE


func use(player: Node) -> bool:

	var used := false

	if heal_hp > 0 and player.has_node("StatsComponent"):
		var stats: StatsComponent = player.get_node("StatsComponent")
		var before := stats.current_health
		stats.current_health = min(stats.current_health + heal_hp, int(stats.get_stat("health")))
		if stats.current_health > before:
			print("ItemData: HP +", heal_hp)
			used = true

	if heal_mana > 0 and player.has_node("StatsComponent"):
		var stats: StatsComponent = player.get_node("StatsComponent")
		var before := stats.current_mana
		stats.current_mana = min(stats.current_mana + heal_mana, int(stats.get_stat("mana")))
		if stats.current_mana > before:
			print("ItemData: Mana +", heal_mana)
			used = true

	return used
