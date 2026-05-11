@tool
class_name NeoCadeThemeOptionButton extends OptionButton

## Reusable OptionButton that lists NeoCade styles and applies the selected Theme to a target Control.
##
## The optional None entry applies a null theme so the target falls back to the project/default Godot theme.
## The built-in styles are loaded from the canonical NeoCade theme resource.

## Emitted after a user selection applies a Theme. The theme argument is null when the None entry is selected.
signal theme_selected(theme: Theme, index: int)

const NO_THEME_LABEL := "None"
const NO_THEME_TOOLTIP := "Applies no theme so the target uses the project/default Godot theme."
const NO_THEME_STYLE := -1
const SELECTED_PROPERTY := &"selected"

## Control that receives the selected theme. If empty, the scene root is used when available.
@export_node_path("Control") var theme_target_path: NodePath:
	set(value):
		theme_target_path = value
		if _is_ready:
			_refresh_should_mirror_target = true
		_queue_refresh()

## Optional canonical NeoCade theme resource. Leave empty to load the .tres matching the addon folder name.
@export_file("*.tres") var theme_resource_path := "":
	set(value):
		theme_resource_path = value
		if _is_ready:
			_refresh_should_mirror_target = true
		_queue_refresh()

## Adds a final "None" entry that applies a null theme to the target.
@export var allow_no_theme := true:
	set(value):
		if allow_no_theme == value:
			return

		allow_no_theme = value
		_queue_refresh()

var _item_styles: PackedInt32Array = PackedInt32Array()
var _is_ready := false
var _refresh_should_mirror_target := false
var _selected_apply_queued := false
var _default_theme_resource_path := ""


func _set(property: StringName, _value: Variant) -> bool:
	if property == SELECTED_PROPERTY:
		_queue_selected_apply()

	return false


func _ready() -> void:
	_is_ready = true
	if not item_selected.is_connected(_on_item_selected):
		item_selected.connect(_on_item_selected)

	refresh_theme_list()


func refresh_theme_list() -> void:
	var target := _theme_target()
	var requested_selected := selected

	clear()
	_item_styles = PackedInt32Array()

	for style_entry in _style_entries():
		_add_style_item(
			String(style_entry["label"]),
			int(style_entry["style"]),
			String(style_entry["tooltip"])
		)

	if allow_no_theme:
		_add_style_item(NO_THEME_LABEL, NO_THEME_STYLE, NO_THEME_TOOLTIP)

	if item_count == 0:
		select(-1)
		return

	if requested_selected == -1:
		_refresh_should_mirror_target = false
		if _should_sync_selected_from_target() and _select_current_target_style(target):
			return

		select(-1)
		return

	if _refresh_should_mirror_target:
		_refresh_should_mirror_target = false
		if _select_current_target_style(target):
			return

		select(-1)
		return

	if requested_selected >= 0 and requested_selected < _item_styles.size():
		select(requested_selected)
		_apply_theme(requested_selected)
		return

	if not _select_current_target_style(target):
		select(-1)


func _on_item_selected(index: int) -> void:
	_apply_theme(index)


func _apply_theme(index: int) -> void:
	var target := _theme_target()
	if target == null or index < 0 or index >= _item_styles.size():
		return

	var selected_style := _item_styles[index]
	if selected_style == NO_THEME_STYLE:
		if target.theme == null:
			return

		target.theme = null
		theme_selected.emit(null, index)
		return

	if _target_has_style(target, selected_style):
		return

	var next_theme := _theme_for_style(selected_style)
	if next_theme == null:
		return

	target.theme = next_theme
	theme_selected.emit(next_theme, index)


func _style_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for style_value in NeoCadeTheme.selectable_styles():
		entries.append({
			"label": NeoCadeTheme.style_label(style_value),
			"style": style_value,
			"tooltip": NeoCadeTheme.style_description(style_value),
		})

	entries.sort_custom(_compare_style_entries)
	return entries


func _compare_style_entries(a: Dictionary, b: Dictionary) -> bool:
	var label_order := String(a["label"]).nocasecmp_to(String(b["label"]))
	if label_order != 0:
		return label_order < 0

	return int(a["style"]) < int(b["style"])


func _add_style_item(label: String, style_value: int, tooltip: String) -> void:
	add_item(label)
	_item_styles.append(style_value)
	set_item_metadata(item_count - 1, style_value)
	set_item_tooltip(item_count - 1, tooltip)


func _theme_for_style(style_value: int) -> NeoCadeTheme:
	var resource_path := _resolved_theme_resource_path()
	if resource_path.is_empty():
		return null

	var loaded_theme := load(resource_path) as NeoCadeTheme
	if loaded_theme == null:
		return null

	var next_theme := loaded_theme.duplicate(true) as NeoCadeTheme
	next_theme.style = style_value
	return next_theme


func _resolved_theme_resource_path() -> String:
	if not theme_resource_path.is_empty():
		return theme_resource_path

	if not _default_theme_resource_path.is_empty():
		return _default_theme_resource_path

	var script := get_script() as Script
	if script == null or script.resource_path.is_empty():
		return ""

	var addon_directory := script.resource_path.get_base_dir().get_base_dir()
	var resource_file_name := "%s.tres" % addon_directory.get_file()
	_default_theme_resource_path = addon_directory.path_join(resource_file_name)
	return _default_theme_resource_path


func _select_current_target_style(target: Control) -> bool:
	var matching_index := _index_for_target_theme(target)
	if matching_index == -1:
		return false

	select(matching_index)
	return true


func _index_for_target_theme(target: Control) -> int:
	if target == null:
		return -1

	if target.theme == null:
		return _index_for_style(NO_THEME_STYLE)

	var neocade_theme := target.theme as NeoCadeTheme
	if neocade_theme == null:
		return -1

	return _index_for_style(neocade_theme.style)


func _index_for_style(style_value: int) -> int:
	for index in range(_item_styles.size()):
		if _item_styles[index] == style_value:
			return index

	return -1


func _target_has_style(target: Control, style_value: int) -> bool:
	var neocade_theme := target.theme as NeoCadeTheme
	return neocade_theme != null and neocade_theme.style == style_value


func _theme_target() -> Control:
	if theme_target_path != NodePath():
		var explicit_target := get_node_or_null(theme_target_path)
		if explicit_target is Control:
			return explicit_target
		return null

	if not is_inside_tree():
		return null

	var tree := get_tree()
	if tree == null:
		return null

	var edited_root := tree.get("edited_scene_root") as Node
	if edited_root is Control:
		return edited_root

	var current_scene := tree.current_scene
	if current_scene is Control:
		return current_scene

	if owner is Control:
		return owner

	return null


func _queue_refresh() -> void:
	if not _is_ready or not is_inside_tree():
		return

	call_deferred("refresh_theme_list")


func _queue_selected_apply() -> void:
	if not _is_ready or not is_inside_tree() or _selected_apply_queued:
		return

	_selected_apply_queued = true
	call_deferred("_apply_selected_change")


func _apply_selected_change() -> void:
	_selected_apply_queued = false
	if selected == -1:
		if _should_sync_selected_from_target():
			var target := _theme_target()
			if not _select_current_target_style(target):
				select(-1)
		return

	_apply_theme(selected)


func _should_sync_selected_from_target() -> bool:
	return not Engine.is_editor_hint()
