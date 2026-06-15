extends Node3D

@onready var spawns = $SpawnPoints.get_children()

func _ready():
	spawn_player(1) # тест локально

func spawn_player(peer_id: int):

	var hero_scene = load(PlayerProfile.hero_scene)
	var hero = hero_scene.instantiate()

	var spawn_index = peer_id % spawns.size()

	hero.global_position = spawns[spawn_index].global_position

	add_child(hero)
