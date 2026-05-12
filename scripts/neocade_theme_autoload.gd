extends Node

## Drop-in autoload that applies the bundled NeoCade Theme globally on
## startup. Register at Project Settings > AutoLoad (any name works,
## e.g. `NeoCadeThemeLoader`) and every Control in the project inherits
## the theme — including UI inside other autoloads, popups, and dialogs.
## Same global reach as `[gui] theme/custom` without triggering
## godotengine/godot#111656.
##
## Override `THEME_PATH` (or copy this file under your own project and
## tweak it there) if you ship a customized theme resource.

const THEME_PATH := "res://addons/neocade_theme/neocade_theme.tres"


func _ready() -> void:
	NeoCadeTheme.apply_to_root_viewport(load(THEME_PATH))
