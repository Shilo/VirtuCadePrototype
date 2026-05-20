extends SceneTree


func _init() -> void:
	var app_id := OS.get_environment("FUSION_APP_ID").strip_edges()
	if app_id.is_empty():
		push_error("FUSION_APP_ID is not set.")
		quit(1)
		return

	ProjectSettings.set_setting("fusion/connection/app_id", app_id)
	ProjectSettings.set_setting("fusion/debug/log_level", 0)

	var error := ProjectSettings.save()
	if error != OK:
		push_error("Failed to save project settings: %s" % error_string(error))
		quit(1)
		return

	print("Applied Fusion app id to CI project settings; app_id length=%d" % app_id.length())
	quit()
