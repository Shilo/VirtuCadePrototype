class_name VirtuMachine extends Area2D

@export var target_name: String


func use(player: Player):
	if not target_name:
		return
	
	if not player:
		push_error("[" + str(self) + "] Player is null.")
		return
	
	VirtuMachineManager.load(target_name)
