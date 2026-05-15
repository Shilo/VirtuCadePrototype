class_name Machine extends Area2D

@export var target_name: String


func use(player: Player):
	if not target_name:
		return
	
	if not player:
		push_error("[" + str(self) + "] Player is null.")
		return
	
	ExperienceManager.load_experience(target_name)
