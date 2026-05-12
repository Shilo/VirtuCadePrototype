extends Node

const base_path: StringName = &"res://virtu_machines/"
const main_scene_path: StringName = &"res://main.tscn"


func load(target_name: String) -> void:
	var target_path := get_virtu_machine_scene_path(target_name)
	if not ResourceLoader.exists(target_path):
		push_error("[" + str(self) + "] Scene doesn't exist \"" + target_path + "\".")
		VirtuMachineError.show_scene(target_name)
		return
	
	var error: Error = get_tree().change_scene_to_file(target_path)
	if error:
		push_error("[" + str(self) + "] Failed to change scene \"" + target_path + "\". Error: " + str(error))
		VirtuMachineError.show_scene(target_name)


func unload() -> void:
	if _is_current_scene_virtu_machine():
		get_tree().change_scene_to_file(main_scene_path)


func get_virtu_machine_scene_path(virtu_machine_name: String) -> String:
	return base_path + virtu_machine_name + "/" + virtu_machine_name + ".tscn"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _is_current_scene_virtu_machine():
		_prompt_virtu_machine_exit()


func _is_current_scene_virtu_machine() -> bool:
	return get_tree().current_scene.scene_file_path.begins_with(base_path)


func _prompt_virtu_machine_exit() -> void:
	if get_tree().current_scene is VirtuMachineError:
		unload()
		return
	
	var confirmDialog: ConfirmationDialog = ConfirmationDialog.new()
	confirmDialog.title = "Exit " + get_tree().current_scene.name.capitalize()
	confirmDialog.dialog_text = "Return to Ship?"
	confirmDialog.confirmed.connect(unload)
	add_child(confirmDialog)
	confirmDialog.popup_centered_clamped()
