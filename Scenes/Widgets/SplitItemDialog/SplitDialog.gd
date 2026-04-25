extends PanelContainer

signal confirmed(amount: int)

@onready var input = $VBoxContainer/HBoxContainer/LineEdit

var current_amount: int = 1
var max_amount: int = 1

func _ready():
	GlobalRefs.split_dialog_root = self
	hide() 

func setup(max_val: int):
	max_amount = max_val
	current_amount = 1
	_update_ui()
	show()
	grab_focus() 

func _update_ui():
	input.text = str(current_amount)


func _on_plus_btn_pressed():
	if current_amount < max_amount:
		current_amount += 1
		_update_ui()

func _on_minus_btn_pressed():
	if current_amount > 1:
		current_amount -= 1
		_update_ui()

func _on_confirm_btn_pressed():
	confirmed.emit(current_amount) # Испускаем сигнал с числом
	hide()

func _on_cancel_btn_pressed():
	hide()
