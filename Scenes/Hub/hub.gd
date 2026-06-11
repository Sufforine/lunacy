extends Node3D

func _ready():
	var playerCharPath = GlobalData.playerCharPath
	var playerNode = load(playerCharPath).instantiate()
	add_child(playerNode)
	
