extends Node
class_name CameraUtils

func pixel_to_rate(value: int) -> int:
	var wp_size = get_viewport().size
	return value * 100 / wp_size.x

func rate_to_pixel(value: int) -> int:
	var wp_size = get_viewport().size
	return wp_size.x * value / 100
