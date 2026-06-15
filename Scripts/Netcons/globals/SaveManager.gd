extends Node

const SAVE_DIR := "user://saves/"


func get_save_path() -> String:

	var steam_id = Steam.getSteamID()

	if steam_id == 0:

		push_error(
			"SteamID is 0. Steam not initialized."
		)

		return SAVE_DIR + "offline.json"

	return SAVE_DIR + str(steam_id) + ".json"


func save_profile():

	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

	var data = {
		"hero_scene": PlayerProfile.hero_scene,
		"level": PlayerProfile.level,
		"experience": PlayerProfile.experience,
		"inventory": PlayerProfile.inventory,
		"equipment": PlayerProfile.equipment
	}

	var file = FileAccess.open(
		get_save_path(),
		FileAccess.WRITE
	)

	if file:

		file.store_string(
			JSON.stringify(data)
		)

		file.close()


func load_profile():

	var path = get_save_path()

	if !FileAccess.file_exists(path):
		return

	var file = FileAccess.open(
		path,
		FileAccess.READ
	)

	if !file:
		return

	var data = JSON.parse_string(
		file.get_as_text()
	)

	file.close()

	if data == null:
		return

	PlayerProfile.hero_scene = data.get(
		"hero_scene",
		""
	)

	PlayerProfile.level = data.get(
		"level",
		1
	)

	PlayerProfile.experience = data.get(
		"experience",
		0
	)

	PlayerProfile.inventory = data.get(
		"inventory",
		[]
	)

	PlayerProfile.equipment = data.get(
		"equipment",
		{
			"weapon":"",
			"armor":"",
			"trinket_1":"",
			"trinket_2":""
		}
	)
