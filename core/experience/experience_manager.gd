extends Node

const base_path: StringName = &"res://experiences/"
var main_scene_path: StringName = ProjectSettings.get_setting("application/run/main_scene")


func load_experience(experience_name: String) -> void:
	var experience_path := get_experience_scene_path(experience_name)
	if not ResourceLoader.exists(experience_path):
		_show_load_error(experience_name, "Scene doesn't exist \"" + experience_path + "\".")
		return
	
	var error: Error = get_tree().change_scene_to_file(experience_path)
	if error:
		_show_load_error(experience_name, "Failed to change scene \"" + experience_path + "\". Error: " + str(error))
		return

	NetworkManager.join_experience_room(experience_name)


func unload_experience() -> void:
	if _is_current_scene_experience():
		get_tree().change_scene_to_file(main_scene_path)
		NetworkManager.join_lobby_room()


func get_experience_scene_path(experience_name: String) -> String:
	return base_path + experience_name + "/" + experience_name + ".tscn"


func _show_load_error(experience_name: String, error_message: String = "") -> void:
	push_error("[" + str(self) + "] " + error_message)
	ExperienceErrorScreen.show_error(experience_name)
	NetworkManager.join_experience_room(experience_name)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _is_current_scene_experience():
		_request_experience_exit()


func _is_current_scene_experience() -> bool:
	var current_scene := get_tree().current_scene
	return current_scene is ExperienceErrorScreen or current_scene.scene_file_path.begins_with(base_path)


func _request_experience_exit() -> void:
	var current_scene := get_tree().current_scene
	if current_scene.has_method("exit") and current_scene.exit():
		return
	
	var confirmDialog: ConfirmationDialog = ConfirmationDialog.new()
	confirmDialog.title = "Exit " + get_tree().current_scene.name.capitalize()
	confirmDialog.dialog_text = "Return to Ship?"
	confirmDialog.confirmed.connect(unload_experience)
	add_child(confirmDialog)
	confirmDialog.popup_centered_clamped()
