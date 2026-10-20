extends Control

@export var preview_mode: bool = false
var camera: Camera3D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameSettings.crosshair_changed.connect(queue_redraw)
	resized.connect(queue_redraw)
	if preview_mode:
		set_process(false)
	else:
		visible = false


func _process(_delta: float) -> void:
	visible = is_instance_valid(camera) and camera.is_current() \
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not get_tree().paused


func _draw() -> void:
	var center := size * 0.5
	var thickness: float = GameSettings.crosshair_thickness
	var outline := Color(0.0, 0.0, 0.0, 0.85)
	match GameSettings.crosshair_shape:
		GameSettings.CrosshairShape.DOT:
			draw_circle(center, thickness * 0.5 + 1.0, outline, true, -1.0, true)
			draw_circle(center, thickness * 0.5, Color.WHITE, true, -1.0, true)
		GameSettings.CrosshairShape.CROSS:
			for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				var start: Vector2 = center + direction * 5.0
				var end: Vector2 = center + direction * 13.0
				draw_line(start, end, outline, thickness + 2.0, true)
				draw_line(start, end, Color.WHITE, thickness, true)
		GameSettings.CrosshairShape.CIRCLE:
			draw_arc(center, 10.0, 0.0, TAU, 64, outline, thickness + 2.0, true)
			draw_arc(center, 10.0, 0.0, TAU, 64, Color.WHITE, thickness, true)
