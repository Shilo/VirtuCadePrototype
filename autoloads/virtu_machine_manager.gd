extends Node

const base_path: StringName = &"res://virtu_machines/"
const main_scene_path: StringName = &"res://main.tscn"


func get_virtu_machine_scene_path(virtu_machine_name: String) -> String:
	return base_path + virtu_machine_name + "/" + virtu_machine_name + ".tscn"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _is_current_scene_virtu_machine():
		_prompt_virtu_machine_exit()


func _is_current_scene_virtu_machine() -> bool:
	return get_tree().current_scene.scene_file_path.begins_with(base_path)


func _prompt_virtu_machine_exit() -> void:
	var confirmDialog: ConfirmationDialog = ConfirmationDialog.new()
	confirmDialog.title = "Exit " + get_tree().current_scene.name
	confirmDialog.dialog_text = "Return to Ship?"
	confirmDialog.confirmed.connect(func():
		get_tree().change_scene_to_file(main_scene_path)
	)
	add_child(confirmDialog)
	confirmDialog.popup_centered_clamped()
