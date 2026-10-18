extends Node

const SETTINGS_PATH := "user://settings.cfg"
const ENVIRONMENT_BUS := &"Environment"
const MIN_VOLUME_DB := -80.0

var resolution: Vector2i = Vector2i.ZERO
var refresh_rate: int = 60
var master_volume: float = 100.0
var environment_volume: float = 100.0


func _ready() -> void:
	resolution = DisplayServer.window_get_size()
	var detected_rate := DisplayServer.screen_get_refresh_rate()
	refresh_rate = maxi(30, int(round(detected_rate))) if detected_rate > 0.0 else 60
	_load_settings()
	_ensure_audio_buses()
	_apply_audio()
	call_deferred("_apply_display")


func set_resolution(value: Vector2i) -> void:
	if value.x <= 0 or value.y <= 0:
		return
	resolution = value
	_apply_resolution()
	_save_settings()


func set_refresh_rate(value: int) -> void:
	refresh_rate = maxi(30, value)
	Engine.max_fps = refresh_rate
	_save_settings()


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 100.0)
	_set_bus_volume(&"Master", master_volume)
	_save_settings()


func set_environment_volume(value: float) -> void:
	environment_volume = clampf(value, 0.0, 100.0)
	_set_bus_volume(ENVIRONMENT_BUS, environment_volume)
	_save_settings()


func get_available_resolutions() -> Array[Vector2i]:
	var screen_size := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var candidates: Array[Vector2i] = [
		Vector2i(1280, 720),
		Vector2i(1366, 768),
		Vector2i(1600, 900),
		Vector2i(1920, 1080),
		Vector2i(2560, 1440),
		Vector2i(3440, 1440),
		Vector2i(3840, 2160),
	]
	var result: Array[Vector2i] = []
	for candidate in candidates:
		if candidate.x <= screen_size.x and candidate.y <= screen_size.y:
			result.append(candidate)
	if not result.has(resolution):
		result.append(resolution)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x * a.y < b.x * b.y
	)
	return result


func get_available_refresh_rates() -> Array[int]:
	var detected := int(round(DisplayServer.screen_get_refresh_rate()))
	if detected <= 0:
		detected = refresh_rate
	var result: Array[int] = []
	var candidates: Array[int] = [30, 60, 75, 100, 120, 144, 165, 240]
	for candidate in candidates:
		if candidate <= detected and not result.has(candidate):
			result.append(candidate)
	if not result.has(detected):
		result.append(detected)
	if not result.has(refresh_rate):
		result.append(refresh_rate)
	result.sort()
	return result


func _apply_display() -> void:
	_apply_resolution()
	Engine.max_fps = refresh_rate


func _apply_resolution() -> void:
	if resolution == Vector2i.ZERO:
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		return

	DisplayServer.window_set_size(resolution)
	var screen := DisplayServer.window_get_current_screen()
	var usable_rect := DisplayServer.screen_get_usable_rect(screen)
	var centered_position := usable_rect.position + (usable_rect.size - resolution) / 2
	DisplayServer.window_set_position(centered_position)


func _ensure_audio_buses() -> void:
	if AudioServer.get_bus_index(ENVIRONMENT_BUS) >= 0:
		return
	AudioServer.add_bus()
	var bus_index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_index, ENVIRONMENT_BUS)
	AudioServer.set_bus_send(bus_index, &"Master")


func _apply_audio() -> void:
	_set_bus_volume(&"Master", master_volume)
	_set_bus_volume(ENVIRONMENT_BUS, environment_volume)


func _set_bus_volume(bus_name: StringName, percent: float) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return
	var linear_value := clampf(percent / 100.0, 0.0, 1.0)
	AudioServer.set_bus_mute(bus_index, linear_value <= 0.0)
	AudioServer.set_bus_volume_db(
		bus_index,
		MIN_VOLUME_DB if linear_value <= 0.0 else linear_to_db(linear_value)
	)


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	var saved_resolution: Variant = config.get_value("display", "resolution", resolution)
	if saved_resolution is Vector2i:
		resolution = saved_resolution
	refresh_rate = maxi(30, int(config.get_value("display", "refresh_rate", refresh_rate)))
	master_volume = clampf(float(config.get_value("audio", "master", master_volume)), 0.0, 100.0)
	environment_volume = clampf(float(config.get_value("audio", "environment", environment_volume)), 0.0, 100.0)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("display", "resolution", resolution)
	config.set_value("display", "refresh_rate", refresh_rate)
	config.set_value("audio", "master", master_volume)
	config.set_value("audio", "environment", environment_volume)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("GameSettings: не удалось сохранить настройки (%s)" % error_string(error))
