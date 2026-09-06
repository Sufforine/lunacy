class_name PlayerState #Жизнь игрока на миссии

var peer_id: int = 0
var steam_id: int = 0
var nickname: String = ""

var hero_scene: String = ""

# прогресс (постоянный, но копируется из PlayerProfile)
var level: int = 1
var experience: int = 0

# инвентарь (после миссии возвращается в PlayerProfile)
var inventory: Array = []

var equipment: Dictionary = {
	"weapon": "",
	"armor": "",
	"trinket_1": "",
	"scroll": ""
}

# --- временные данные миссии ---
var current_hp: int = 0
var current_mana: int = 0

# --- позиция в миссии (если надо респавн / сейв чекпоинтов) ---
var checkpoint_position: Vector3 = Vector3.ZERO

# --- статус ---
var is_dead: bool = false
var is_ready: bool = false


# COPY FROM LOCAL PROFILE
func from_profile(profile) -> void:
	hero_scene = profile.hero_scene
	level = profile.level
	experience = profile.experience
	inventory = profile.inventory.duplicate(true)
	equipment = profile.equipment.duplicate(true)
	var steam = Engine.get_singleton("Steam")
	nickname = steam.getPersonaName() if steam else "Игрок"
	steam_id = steam.getSteamID() if steam else 0

# APPLY BACK TO PROFILE (после миссии)
func apply_to_profile(profile) -> void:
	profile.level = level
	profile.experience = experience

	profile.inventory = inventory.duplicate(true)
	profile.equipment = equipment.duplicate(true)

func debug_print():
	print("--- PlayerState ---")
	print("peer:", peer_id)
	print("nick:", nickname)
	print("hero:", hero_scene)
	print("lvl:", level)
	print("xp:", experience)
	print("inv:", inventory)
	print("equip:", equipment)
