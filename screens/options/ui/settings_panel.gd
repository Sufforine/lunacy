extends Control

signal close_requested

@onready var resolution_option: OptionButton = %ResolutionOption
@onready var refresh_option: OptionButton = %RefreshOption
@onready var master_slider: HSlider = %MasterSlider
@onready var master_value: Label = %MasterValue
@onready var environment_slider: HSlider = %EnvironmentSlider
@onready var environment_value: Label = %EnvironmentValue


func _ready() -> void:
	_fill_resolutions()
	_fill_refresh_rates()
	master_slider.value = GameSettings.master_volume
	environment_slider.value = GameSettings.environment_volume
	_update_volume_labels()


func _fill_resolutions() -> void:
	resolution_option.clear()
	var selected_index := 0
	for resolution in GameSettings.get_available_resolutions():
		resolution_option.add_item("%d × %d" % [resolution.x, resolution.y])
		var index := resolution_option.item_count - 1
		resolution_option.set_item_metadata(index, resolution)
		if resolution == GameSettings.resolution:
			selected_index = index
	resolution_option.select(selected_index)


func _fill_refresh_rates() -> void:
	refresh_option.clear()
	var selected_index := 0
	for refresh_rate in GameSettings.get_available_refresh_rates():
		refresh_option.add_item("%d Гц" % refresh_rate)
		var index := refresh_option.item_count - 1
		refresh_option.set_item_metadata(index, refresh_rate)
		if refresh_rate == GameSettings.refresh_rate:
			selected_index = index
	refresh_option.select(selected_index)


func _on_resolution_selected(index: int) -> void:
	var value: Vector2i = resolution_option.get_item_metadata(index)
	GameSettings.set_resolution(value)


func _on_refresh_selected(index: int) -> void:
	GameSettings.set_refresh_rate(int(refresh_option.get_item_metadata(index)))


func _on_master_changed(value: float) -> void:
	GameSettings.set_master_volume(value)
	_update_volume_labels()


func _on_environment_changed(value: float) -> void:
	GameSettings.set_environment_volume(value)
	_update_volume_labels()


func _update_volume_labels() -> void:
	master_value.text = "%d%%" % int(round(master_slider.value))
	environment_value.text = "%d%%" % int(round(environment_slider.value))


func _on_back_pressed() -> void:
	close_requested.emit()
