extends Resource
class_name HeroDefinition

@export var id: StringName = ""
@export var hero_name: String = ""
@export var icon: Texture2D = null
@export_file("*.tscn") var scene_path: String = ""

@export_group("Base Stats")
@export var base_health: float = 100.0
@export var base_mana: float = 100.0
@export var base_ad: float = 100.0
@export var base_ap: float = 100.0
@export var base_ar: float = 100.0
@export var base_mr: float = 100.0
@export var move_speed: float = 5.0
@export var attack_speed: float = 1.0
@export var base_cc: float = 0.0
@export var base_cd: float = 1.5
@export var morale: int = 0


func load_scene() -> PackedScene:
	if scene_path.is_empty():
		return null
	return load(scene_path) as PackedScene
