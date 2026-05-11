extends Node


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _is_current_scene_virtu_machine():
		_prompt_virtu_machine_exit()


func _is_current_scene_virtu_machine() -> bool:
	return get_tree().current_scene.scene_file_path.begins_with("res://virtu_machine/")


func _prompt_virtu_machine_exit() -> void:
	var confirmDialog: ConfirmationDialog = ConfirmationDialog.new()
	confirmDialog.title = "Exit " + get_tree().current_scene.name
	confirmDialog.dialog_text = "Return to Ship?"
	confirmDialog.confirmed.connect(func():
		get_tree().change_scene_to_file("res://main.tscn")
	)
	add_child(confirmDialog)
	confirmDialog.popup_centered_clamped()
