extends Node

## Drop-in autoload that merges the bundled NeoCade Theme into Godot's
## project theme on startup. Register at Project Settings > AutoLoad
## (any name works, e.g. `NeoCadeThemeLoader`) and every Control in the
## project inherits NeoCade via standard project-theme inheritance —
## main scene, other autoloads, popups, dialogs.
##
## REQUIRED setup in project.godot:
##
##     [gui]
##     theme/custom="res://addons/neocade_theme/neocade_theme_project_stub.tres"
##
## The stub is a plain `Theme` (no `class_name`, no properties) — Godot
## loads it at boot without triggering godotengine/godot#111656. This
## autoload then merges the real NeoCade theme into it at `_ready()`.

func _ready() -> void:
	NeoCadeTheme.apply_globally()
	queue_free()  # single-shot — merge is the only job
