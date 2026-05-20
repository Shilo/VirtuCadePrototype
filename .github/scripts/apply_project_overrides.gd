extends SceneTree


func _init() -> void:
	if not FileAccess.file_exists("res://override.cfg"):
		print("No override.cfg found; no project settings overrides applied.")
		quit()
		return

	var config := ConfigFile.new()
	var error := config.load("res://override.cfg")
	if error != OK:
		push_error("Failed to load override.cfg: %s" % error_string(error))
		quit(1)
		return

	var applied_count := 0
	for section in config.get_sections():
		for key in config.get_section_keys(section):
			ProjectSettings.set_setting("%s/%s" % [section, key], config.get_value(section, key))
			applied_count += 1

	error = ProjectSettings.save()
	if error != OK:
		push_error("Failed to save project settings: %s" % error_string(error))
		quit(1)
		return

	print("Applied %d project setting override(s) from override.cfg." % applied_count)
	quit()
