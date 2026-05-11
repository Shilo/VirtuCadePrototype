class_name VirtuMachine extends Area2D

@export var target_name: String


func use(player: Player):
	if not target_name:
		return
	
	if not player:
		push_error("[" + str(self) + "] Player is null.")
		return
	
	var target_path := "virtu_machine/" + target_name + "/" + target_name + ".tscn"
	if not ResourceLoader.exists(target_path):
		push_error("[" + str(self) + "] Scene doesn't exist \"" + target_path + "\".")
		return
	
	var error: Error = get_tree().change_scene_to_file(target_path)
	if error:
		push_error("[" + str(self) + "] Failed to change scene \"" + target_path + "\". Error: " + str(error))
