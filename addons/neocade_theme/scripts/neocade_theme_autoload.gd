extends Node

## Drop-in autoload that merges the bundled NeoCade Theme into Godot's
## `ThemeDB.default_theme` on startup. Register at Project Settings >
## AutoLoad (any name works, e.g. `NeoCadeThemeLoader`) and every Control
## in the project inherits NeoCade via the standard Godot theme fallback
## chain — main scene, other autoloads, popups, dialogs, every UI surface.
##
## No `[gui] theme/custom` setting needed; no stub file. The autoload
## sidesteps godotengine/godot#111656 by populating `default_theme`
## at runtime, past the boot-time window where the engine bug fires.

func _ready() -> void:
	NeoCadeTheme.apply_globally()
	queue_free()  # single-shot — merge is the only job
