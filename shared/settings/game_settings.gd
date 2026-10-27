extends Node

signal crosshair_changed
signal chat_scale_changed
signal inventory_theme_changed
signal ui_scale_changed

enum CrosshairShape { DOT, CROSS, CIRCLE }
enum InventoryTheme { DAY, NIGHT }

const SETTINGS_PATH := "user://settings.cfg"
const ENVIRONMENT_BUS := &"Environment"
const MIN_VOLUME_DB := -80.0

var resolution: Vector2i = Vector2i.ZERO
var refresh_rate: int = 60
var master_volume: float = 100.0
var environment_volume: float = 100.0
var crosshair_shape: int = CrosshairShape.DOT
var crosshair_thickness: float = 3.0
var chat_scale_percent: float = 0.0
var ui_scale_percent: float = 0.0
var inventory_theme: int = InventoryTheme.DAY


func set_crosshair_shape(value: int) -> void:
	crosshair_shape = clampi(value, CrosshairShape.DOT, CrosshairShape.CIRCLE)
	crosshair_changed.emit()
	_save_settings()


func set_crosshair_thickness(value: float) -> void:
	crosshair_thickness = clampf(value, 1.0, 8.0)
	crosshair_changed.emit()
	_save_settings()


func set_chat_scale_percent(value: float) -> void:
	chat_scale_percent = clampf(value, -50.0, 50.0)
	chat_scale_changed.emit()
	_save_settings()


func set_ui_scale_percent(value: float) -> void:
	ui_scale_percent = clampf(value, -50.0, 50.0)
	ui_scale_changed.emit()
	_save_settings()


func get_ui_scale() -> float:
	return 1.0 + ui_scale_percent / 100.0


func set_inventory_theme(value: int) -> void:
	var selected := clampi(value, InventoryTheme.DAY, InventoryTheme.NIGHT)
	if inventory_theme == selected:
		return
	inventory_theme = selected
	inventory_theme_changed.emit()
	_save_settings()


func get_inventory_theme_palette() -> Dictionary:
	return get_ui_theme_palette()


func get_ui_theme_palette() -> Dictionary:
	var night := inventory_theme == InventoryTheme.NIGHT
	return {
		"background": Color("152940") if night else Color("e2cfaa"),
		"border": Color("75c9ec") if night else Color("702522"),
		"text": Color("e8f5ff") if night else Color("47241f"),
		"surface": Color("0b1c2d") if night else Color("b9aa8c"),
		"surface_hover": Color("214566") if night else Color("cfbb94"),
		"accent": Color("75c9ec") if night else Color("a33d32"),
		"dimmer": Color(0.01, 0.025, 0.045, 0.9) if night else Color(0.12, 0.065, 0.045, 0.78),
	}


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
	crosshair_shape = clampi(int(config.get_value("crosshair", "shape", crosshair_shape)), CrosshairShape.DOT, CrosshairShape.CIRCLE)
	crosshair_thickness = clampf(float(config.get_value("crosshair", "thickness", crosshair_thickness)), 1.0, 8.0)
	chat_scale_percent = clampf(float(config.get_value("chat", "scale_percent", chat_scale_percent)), -50.0, 50.0)
	ui_scale_percent = clampf(float(config.get_value("ui", "scale_percent", ui_scale_percent)), -50.0, 50.0)
	var saved_theme: Variant = config.get_value("ui", "theme", config.get_value("inventory", "theme", inventory_theme))
	inventory_theme = clampi(int(saved_theme), InventoryTheme.DAY, InventoryTheme.NIGHT)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("display", "resolution", resolution)
	config.set_value("display", "refresh_rate", refresh_rate)
	config.set_value("audio", "master", master_volume)
	config.set_value("audio", "environment", environment_volume)
	config.set_value("crosshair", "shape", crosshair_shape)
	config.set_value("crosshair", "thickness", crosshair_thickness)
	config.set_value("chat", "scale_percent", chat_scale_percent)
	config.set_value("ui", "scale_percent", ui_scale_percent)
	config.set_value("ui", "theme", inventory_theme)
	config.set_value("inventory", "theme", inventory_theme)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("GameSettings: не удалось сохранить настройки (%s)" % error_string(error))
