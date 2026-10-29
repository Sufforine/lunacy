extends RefCounted

const STAGE_FLOOR_Y := 0.1

var _host


func build(host: Node3D) -> void:
	_host = host
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.07, 0.08, 0.12)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.6, 0.75)
	environment.ambient_light_energy = 0.5
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_host.add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.shadow_enabled = true
	_host.add_child(sun)
	var floor_box := CSGBox3D.new()
	floor_box.size = Vector3(80.0, 0.2, 60.0)
	floor_box.position = Vector3(-5.0, -0.1, 0.0)
	floor_box.material = _make_material(Color(0.14, 0.15, 0.2))
	_host.add_child(floor_box)
	var platform := CSGBox3D.new()
	platform.size = Vector3(8.0, 0.2, 3.4)
	platform.position = _host.stage_center
	platform.material = _make_material(Color(0.3, 0.32, 0.4))
	_host.add_child(platform)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for index in range(8):
		var pillar_height := rng.randf_range(1.5, 4.0)
		var pillar := CSGBox3D.new()
		pillar.size = Vector3(1.0, pillar_height, 1.0)
		pillar.position = Vector3(rng.randf_range(-6.0, 6.0), pillar_height * 0.5, rng.randf_range(-9.0, -3.0))
		pillar.material = _make_material(Color(0.2, 0.22, 0.3))
		_host.add_child(pillar)
	_host._camera = Camera3D.new()
	_host._camera.position = _host.title_camera_position
	_host._camera.rotation_degrees = Vector3(_host.camera_pitch_degrees, 0.0, 0.0)
	_host.add_child(_host._camera)
	_host._camera.make_current()
	for entry in CharacterModels.BODY_TYPES:
		var body_def: Dictionary = entry
		var body_id := str(body_def["id"])
		var figure := Node3D.new()
		figure.visible = false
		_host.add_child(figure)
		var model := CharacterModels.create_model(body_id)
		figure.add_child(model)
		CharacterModels.play_idle(model)
		_host._figures[body_id] = figure
		_host._models[body_id] = model


func place_figure(body_id: String, x_offset: float) -> void:
	var figure: Node3D = _host._figures[body_id]
	figure.position = _host.stage_center + Vector3(x_offset, STAGE_FLOOR_Y, 0.0)
	figure.rotation = Vector3.ZERO


func hide_all_figures() -> void:
	for body_id in _host._figures:
		(_host._figures[body_id] as Node3D).visible = false


func body_id_of(appearance: Dictionary) -> String:
	var body_id := str(appearance.get("body", CharacterModels.DEFAULT_BODY))
	return body_id if _host._figures.has(body_id) else CharacterModels.DEFAULT_BODY


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material
