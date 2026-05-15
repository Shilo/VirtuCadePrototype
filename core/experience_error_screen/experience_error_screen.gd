class_name ExperienceErrorScreen extends CenterContainer

static func show_error(experience_name: String, error_message: String = "") -> void:
	var scene_path := (ExperienceErrorScreen as GDScript).resource_path.get_basename() + ".tscn"
	var scene: PackedScene = load(scene_path)
	
	var experience_error_screen: ExperienceErrorScreen = scene.instantiate()
	if experience_name:
		experience_error_screen.set_experience_name(experience_name)
	if error_message:
		experience_error_screen.set_error_message(error_message)
	
	Engine.get_main_loop().change_scene_to_node(experience_error_screen)


func set_experience_name(value: String) -> void:
	name = value.capitalize()
	%ExperienceName.text = name

func set_error_message(value: String) -> void:
	%ErrorMessage.text = value.capitalize()


func exit() -> bool:
	ExperienceManager.unload_experience()
	return true
