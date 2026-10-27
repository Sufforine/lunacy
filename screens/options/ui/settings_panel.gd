extends Control

signal close_requested

@onready var dimmer: ColorRect = $Dimmer
@onready var panel: PanelContainer = $CenterContainer/PanelContainer
@onready var tabs: TabContainer = %Tabs
@onready var back_button: Button = %Back
@onready var resolution_option: OptionButton = %ResolutionOption
@onready var refresh_option: OptionButton = %RefreshOption
@onready var master_slider: HSlider = %MasterSlider
@onready var master_value: Label = %MasterValue
@onready var environment_slider: HSlider = %EnvironmentSlider
@onready var environment_value: Label = %EnvironmentValue
@onready var crosshair_option: OptionButton = %CrosshairOption
@onready var thickness_slider: HSlider = %ThicknessSlider
@onready var thickness_value: Label = %ThicknessValue
@onready var ui_scale_slider: HSlider = %UIScaleSlider
@onready var ui_scale_value: Label = %UIScaleValue
@onready var chat_scale_slider: HSlider = %ChatScaleSlider
@onready var chat_scale_value: Label = %ChatScaleValue
@onready var inventory_theme_option: OptionButton = %InventoryThemeOption


func _ready() -> void:
	tabs.set_tab_title(0, "Графика")
	tabs.set_tab_title(1, "Аудио")
	tabs.set_tab_title(2, "Игра")
	_fill_resolutions()
	_fill_refresh_rates()
	master_slider.set_value_no_signal(GameSettings.master_volume)
	environment_slider.set_value_no_signal(GameSettings.environment_volume)
	_update_volume_labels()
	crosshair_option.add_item("Точка", GameSettings.CrosshairShape.DOT)
	crosshair_option.add_item("Перекрестие", GameSettings.CrosshairShape.CROSS)
	crosshair_option.add_item("Круг", GameSettings.CrosshairShape.CIRCLE)
	crosshair_option.select(crosshair_option.get_item_index(GameSettings.crosshair_shape))
	thickness_slider.set_value_no_signal(GameSettings.crosshair_thickness)
	_update_thickness_label()
	ui_scale_slider.set_value_no_signal(GameSettings.ui_scale_percent)
	_update_percent_label(ui_scale_value, ui_scale_slider.value)
	chat_scale_slider.set_value_no_signal(GameSettings.chat_scale_percent)
	_update_percent_label(chat_scale_value, chat_scale_slider.value)
	inventory_theme_option.add_item("День", GameSettings.InventoryTheme.DAY)
	inventory_theme_option.add_item("Ночь", GameSettings.InventoryTheme.NIGHT)
	inventory_theme_option.select(inventory_theme_option.get_item_index(GameSettings.inventory_theme))
	_connect_controls()
	GameSettings.inventory_theme_changed.connect(_apply_theme)
	_apply_theme()


func _connect_controls() -> void:
	resolution_option.item_selected.connect(_on_resolution_selected)
	refresh_option.item_selected.connect(_on_refresh_selected)
	master_slider.value_changed.connect(_on_master_changed)
	environment_slider.value_changed.connect(_on_environment_changed)
	crosshair_option.item_selected.connect(_on_crosshair_selected)
	thickness_slider.value_changed.connect(_on_thickness_changed)
	ui_scale_slider.value_changed.connect(_on_ui_scale_changed)
	chat_scale_slider.value_changed.connect(_on_chat_scale_changed)
	inventory_theme_option.item_selected.connect(_on_inventory_theme_selected)
	back_button.pressed.connect(_on_back_pressed)


func _on_inventory_theme_selected(index: int) -> void:
	GameSettings.set_inventory_theme(inventory_theme_option.get_item_id(index))


func _on_crosshair_selected(index: int) -> void:
	GameSettings.set_crosshair_shape(crosshair_option.get_item_id(index))


func _on_thickness_changed(value: float) -> void:
	GameSettings.set_crosshair_thickness(value)
	_update_thickness_label()


func _update_thickness_label() -> void:
	thickness_value.text = "%d" % int(round(thickness_slider.value))


func _on_ui_scale_changed(value: float) -> void:
	GameSettings.set_ui_scale_percent(value)
	_update_percent_label(ui_scale_value, value)


func _on_chat_scale_changed(value: float) -> void:
	GameSettings.set_chat_scale_percent(value)
	_update_percent_label(chat_scale_value, value)


func _update_percent_label(label: Label, value: float) -> void:
	var rounded := int(round(value))
	label.text = "+%d%%" % rounded if rounded > 0 else "%d%%" % rounded


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


func _apply_theme() -> void:
	var palette := GameSettings.get_ui_theme_palette()
	dimmer.color = palette.dimmer
	var panel_style := _style(palette.background, palette.border, 3, 12)
	panel_style.shadow_color = Color(0, 0, 0, 0.45)
	panel_style.shadow_size = 16
	panel.add_theme_stylebox_override("panel", panel_style)
	tabs.add_theme_stylebox_override("panel", _style(palette.background.darkened(0.04), palette.border, 1, 7))
	tabs.add_theme_color_override("font_selected_color", palette.text)
	tabs.add_theme_color_override("font_unselected_color", palette.text.darkened(0.25))
	_apply_theme_to_children(panel, palette)


func _apply_theme_to_children(node: Node, palette: Dictionary) -> void:
	for child in node.get_children():
		if child is Label:
			var label := child as Label
			label.add_theme_color_override("font_color", palette.accent if label.name.ends_with("Title") else palette.text)
		elif child is Button:
			var button := child as Button
			button.add_theme_color_override("font_color", palette.text)
			button.add_theme_color_override("font_hover_color", palette.text)
			button.add_theme_stylebox_override("normal", _style(palette.surface, palette.border, 1, 5))
			button.add_theme_stylebox_override("hover", _style(palette.surface_hover, palette.border, 2, 5))
			button.add_theme_stylebox_override("pressed", _style(palette.surface.darkened(0.1), palette.border, 2, 5))
		elif child is HSlider:
			var slider := child as HSlider
			slider.add_theme_stylebox_override("slider", _style(palette.surface, palette.border, 1, 4))
			slider.add_theme_stylebox_override("grabber_area", _style(palette.accent, palette.border, 1, 4))
		_apply_theme_to_children(child, palette)


func _style(background: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	return style


func _on_back_pressed() -> void:
	close_requested.emit()
