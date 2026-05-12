extends Node

## Drop-in autoload that applies the bundled NeoCade Theme globally on
## startup. Register at Project Settings > AutoLoad (any name works,
## e.g. `NeoCadeThemeLoader`) and every Control in the project inherits
## the theme — including UI inside other autoloads, popups, and dialogs.
## Same global reach as `[gui] theme/custom` without triggering
## godotengine/godot#111656.

func _ready() -> void:
	NeoCadeTheme.apply_to_root_viewport()
	queue_free()  # single-shot — theme assignment is the only job
