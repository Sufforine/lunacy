extends PanelContainer

signal confirmed(amount: int)

@onready var input = $VBoxContainer/HBoxContainer/LineEdit
var current_amount: int = 1
var max_amount: int = 1

func setup(max_val: int):
	max_amount = max_val
	current_amount = 1
	_update_ui()
	show()

func _on_plus_pressed():
	current_amount = min(current_amount + 1, max_amount)
	_update_ui()

func _on_minus_pressed():
	current_amount = max(current_amount - 1, 1)
	_update_ui()

func _update_ui():
	input.text = str(current_amount)

func _on_ok_pressed():
	confirmed.emit(current_amount)
	hide()

func _on_cancel_pressed():
	hide()
