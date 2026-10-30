class_name PlayerState #Жизнь игрока на миссии

var peer_id: int = 0
var steam_id: int = 0
var nickname: String = ""

# Персонаж, созданный игроком: имя и внешность (см. character_models.gd)
var character_name: String = ""
var appearance: Dictionary = {}

var hero_scene: String = ""

# прогресс (постоянный, но копируется из PlayerProfile)
var level: int = 1
var experience: int = 0
var attributes: Dictionary = {}
var attribute_points: int = 0

# инвентарь (после миссии возвращается в PlayerProfile)
var inventory: Array = []
var quickslots: Array = []

var equipment: Dictionary = {
	"weapon": "",
	"helmet": "",
	"chestplate": "",
	"leggings": "",
	"trinket_1": "",
	"trinket_2": ""
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
	character_name = profile.character_name
	appearance = profile.appearance.duplicate(true)
	level = profile.level
	experience = profile.experience
	attributes = profile.attributes.duplicate(true)
	attribute_points = profile.attribute_points
	inventory = profile.inventory.duplicate(true)
	quickslots = profile.quickslots.duplicate(true)
	equipment = profile.equipment.duplicate(true)
	if SteamLobby.is_steam_ready():
		nickname = Steam.getPersonaName()
		steam_id = Steam.getSteamID()
	else:
		nickname = "Player"
		steam_id = 0

# APPLY BACK TO PROFILE (после миссии)
func apply_to_profile(profile) -> void:
	profile.level = level
	profile.experience = experience
	profile.attributes = attributes.duplicate(true)
	profile.attribute_points = attribute_points

	profile.inventory = inventory.duplicate(true)
	profile.quickslots = quickslots.duplicate(true)
	profile.equipment = equipment.duplicate(true)

func debug_print():
	print("--- PlayerState ---")
	print("peer:", peer_id)
	print("nick:", nickname)
	print("character:", character_name, appearance)
	print("hero:", hero_scene)
	print("lvl:", level)
	print("xp:", experience)
	print("inv:", inventory)
	print("equip:", equipment)
