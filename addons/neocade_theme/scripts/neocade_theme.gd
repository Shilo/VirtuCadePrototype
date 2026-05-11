@tool
class_name NeoCadeTheme extends Theme

## NeoCade Theme — single concrete `@tool extends Theme` class for the NeoCade addon.
##
## Architecture: one concrete instantiable class + one canonical
## `addons/neocade_theme/neocade_theme.tres` resource. The `style` export switches between
## the approved NeoCade directions; `Style.CUSTOM` leaves the remaining exports fully manual.
##
## Setters on every `@export` property trigger `_regenerate_theme()`, which rebuilds the
## generated theme entries from BINDING_TABLE so stale runtime values cannot survive a style change.
##
## Binding mechanism (D-03 TENTATIVE): the current implementation uses a slot-name + property-name
## table compiled into this file. The user has signaled this may be revised toward a property-name
## convention or a metadata-tagged Resource model post-Phase-4. **This implementation is REVISABLE
## without breaking the public `@export` surface or the `.tres` file format** — only the internal
## binding mechanism would change.
##
## See: .planning/DESIGN_TOKENS.md, .planning/phases/04-.../04-RESEARCH.md, .planning/phases/04-.../04-CONTEXT.md.

## Sizing mode used when regenerating NeoCade theme entries.
enum Platform {
	## Uses desktop control density and spacing.
	DESKTOP = 0,
	## Uses mobile-friendly tap targets and spacing.
	MOBILE = 1,
	## Uses mobile sizing when the runtime reports a mobile OS feature; otherwise uses desktop sizing.
	AUTO = 2,
}

## Built-in NeoCade visual styles.
enum Style {
	## Playful, pillowy, generous controls with soft candy energy.
	BUBBLE = 3,
	## Event-like, high-energy statement controls with amplified hierarchy.
	BURST = 5,
	## Airy, welcoming, gently rounded mint-forward controls.
	DAYBREAK = 4,
	## Arcade-dense cabinet rectangles with bold accent fills.
	PULSE = 1,
	## Spacious, quiet, premium rounded chrome.
	SLATE = 2,
	## Manual style values using NeoCade's neutral fallback personality.
	CUSTOM = 0,
}

# ─── Primary exports ────────────────────────────────────────────────────────────────────────
## Selects the built-in NeoCade visual style, or Custom for manual style values.
@export var style: Style = Style.PULSE:
	set(value):
		if style == value: return
		style = value
		if _syncing_style_from_exports:
			return
		if style == Style.CUSTOM:
			_regenerate_theme()
			return
		_apply_style_exports(style)

## Enables NeoCade's flat extruded depth treatment using solid offset shapes.
@export var raised: bool = false:
	set(value):
		if raised == value: return
		raised = value
		_after_variant_export_changed()

## Chooses desktop sizing, mobile sizing, or AUTO mobile detection via OS feature flags.
@export var platform: Platform = Platform.AUTO:
	set(value):
		if platform == value: return
		platform = value
		_after_variant_export_changed()

# ─── Style overrides ────────────────────────────────────────────────────────────────────────
## Style values applied by built-in styles and editable as overrides when using Custom.
@export_group("Style Overrides")

## Main surface color for generated controls. Light/dark behavior is derived from this color's luminance.
@export var base_color: Color = Color("#151A2E"):
	set(value):
		if base_color == value: return
		base_color = value
		_after_direction_export_changed()

## Primary accent color used for selected, focused, and high-emphasis UI states.
@export var accent_color: Color = Color("#8BFF6A"):
	set(value):
		if accent_color == value: return
		accent_color = value
		_after_direction_export_changed()

## Base corner radius for generated chrome; individual controls may scale or override it by style.
@export var corner_radius: int = 0:
	set(value):
		value = maxi(0, value)
		if corner_radius == value: return
		corner_radius = value
		_after_direction_export_changed()

## Base spacing value used to derive margins, separations, and control padding.
@export var spacing: int = 14:
	set(value):
		value = maxi(0, value)
		if spacing == value: return
		spacing = value
		_after_direction_export_changed()

## Multiplier for raised offset depth when raised mode is enabled.
@export var raised_strength: int = 2:
	set(value):
		value = maxi(0, value)
		if raised_strength == value: return
		raised_strength = value
		_after_direction_export_changed()

## Thickness of generated focus rings on focusable controls.
@export var focus_thickness: int = 2:
	set(value):
		value = maxi(0, value)
		if focus_thickness == value: return
		focus_thickness = value
		_after_direction_export_changed()

## Width of generated outline strokes and hairline separators.
@export var outline_width: int = 1:
	set(value):
		value = maxi(0, value)
		if outline_width == value: return
		outline_width = value
		_after_direction_export_changed()

# ─── Advanced ──────────────────────────────────────────────────────────────────────────────
@export_group("Advanced")

## PopupMenu check/radio items are drawn with item icon_modulate, not CheckBox's
## checked/unchecked color slots. Keep this enabled for consistent menu check/radio
## fills; disable it to fall back to static SVG masks and avoid trivial runtime SVG generation.
@export var use_runtime_popup_selection_icons: bool = true:
	set(value):
		if use_runtime_popup_selection_icons == value: return
		use_runtime_popup_selection_icons = value
		_regenerate_theme()

## Keeps loaded and generated textures cached across theme regenerations for faster
## live tweaking. Leave disabled for one-shot runtime use; NeoCade still uses a
## temporary cache during each regeneration and releases it when the pass finishes.
@export var texture_cache: bool = false:
	set(value):
		if texture_cache == value: return
		texture_cache = value
		if not texture_cache:
			_persistent_icon_cache.clear()
			_persistent_generated_texture_cache.clear()
		_regenerate_theme()

# ─── Internal state (NOT exported) ──────────────────────────────────────────────────────────
var is_light: bool = false  # derived from base_color.get_luminance() at every regenerate
var _regenerating: bool = false  # reentry guard (per RESEARCH.md §4)
var _last_regeneration_usec: int = 0  # diagnostic for probes and profiling
var _applying_style_exports := false
var _syncing_style_from_exports := false
var _active_icon_cache: Dictionary = {}
var _active_generated_texture_cache: Dictionary = {}
var _persistent_icon_cache: Dictionary = {}
var _persistent_generated_texture_cache: Dictionary = {}

func _init() -> void:
	_regenerate_theme()


static func selectable_styles() -> PackedInt32Array:
	return PackedInt32Array([Style.BUBBLE, Style.BURST, Style.DAYBREAK, Style.PULSE, Style.SLATE])


static func style_label(style_value: int) -> String:
	var style_name: Variant = Style.find_key(style_value)
	if style_name == null:
		style_name = String(Style.find_key(Style.CUSTOM))
	return String(style_name).capitalize()


static func style_description(style_value: int) -> String:
	return String(STYLE_DESCRIPTIONS.get(style_value, STYLE_DESCRIPTIONS[Style.CUSTOM]))


func _apply_style_exports(style_value: int) -> void:
	var values: Dictionary = STYLE_EXPORTS.get(style_value, {})
	if values.is_empty():
		style = Style.CUSTOM
		_regenerate_theme()
		return

	_applying_style_exports = true
	base_color = values["base_color"]
	accent_color = values["accent_color"]
	corner_radius = values["corner_radius"]
	spacing = values["spacing"]
	raised_strength = values["raised_strength"]
	focus_thickness = values["focus_thickness"]
	outline_width = values["outline_width"]
	_applying_style_exports = false
	_regenerate_theme()


func _after_direction_export_changed() -> void:
	if _applying_style_exports:
		return

	_sync_style_from_exports()
	_regenerate_theme()


func _after_variant_export_changed() -> void:
	if _applying_style_exports:
		return

	_regenerate_theme()


func _sync_style_from_exports() -> void:
	var matching_style := _matching_style()
	if style == matching_style:
		return

	_syncing_style_from_exports = true
	style = matching_style
	_syncing_style_from_exports = false


func _matching_style() -> Style:
	for style_value in selectable_styles():
		if _exports_match_style(style_value):
			return style_value

	return Style.CUSTOM


func _exports_match_style(style_value: int) -> bool:
	var values: Dictionary = STYLE_EXPORTS.get(style_value, {})
	if values.is_empty():
		return false

	return (
		base_color.is_equal_approx(values["base_color"])
		and accent_color.is_equal_approx(values["accent_color"])
		and corner_radius == values["corner_radius"]
		and spacing == values["spacing"]
		and raised_strength == values["raised_strength"]
		and focus_thickness == values["focus_thickness"]
		and outline_width == values["outline_width"]
	)

func _regenerate_theme() -> void:
	if _regenerating: return
	_regenerating = true
	var was_blocking_signals := is_blocking_signals()
	set_block_signals(true)
	_active_icon_cache = _persistent_icon_cache if texture_cache else {}
	_active_generated_texture_cache = _persistent_generated_texture_cache if texture_cache else {}
	var t0 := Time.get_ticks_usec()
	clear()

	is_light = base_color.get_luminance() >= 0.5
	var p: Platform = _resolve_platform()
	var tokens: Dictionary = _platform_tokens(p)
	var style_personality: Dictionary = _resolve_style_personality()  # Cross-AI Cycle 1 C2 fix

	# ── Surface ramp (DESIGN_TOKENS §6.2) ──
	# spread_factor is the per-direction surface-ramp width control. Sourced from
	# STYLE_PERSONALITY (Cross-AI Cycle 1 C2 fix): Pulse=1.3 wide, Slate=0.7 narrow,
	# Bubble=1.0 medium, Daybreak=1.0 medium, Burst=1.3 wide; custom themes default to 1.0.
	var spread_factor: float = style_personality.spread_factor
	var elevate_target: Color = Color.BLACK if is_light else Color.WHITE

	var surface_base: Color    = base_color
	var surface_low: Color     = _mix(base_color, Color.BLACK, 0.18 * spread_factor)
	var surface_panel: Color   = _mix(base_color, elevate_target, 0.06 * spread_factor)
	var surface_high: Color    = _mix(base_color, elevate_target, 0.13 * spread_factor)
	var surface_overlay: Color = _mix(base_color, elevate_target, 0.20 * spread_factor)
	var outline_color: Color   = _mix(base_color, elevate_target, 0.24 * spread_factor)
	var code_background: Color = _mix(surface_low, Color.BLACK, 0.10)
	var code_current_line: Color = _state_layer_color(code_background, elevate_target, 0.05)

	# Button chrome follows Godot editor/minimal theme behavior: a filled tonal surface
	# derived from the base color, with a same-family edge. This is intentionally
	# separate from surface_panel/outline_color so buttons do not render as outlined boxes.
	var button_normal: Color = _button_tonal_color(base_color, 0.35, 0.85)
	var button_disabled: Color = _button_tonal_color(base_color, 0.20, 0.75)
	var selection_control_off: Color = _button_tonal_color(base_color, 0.85, 0.70)

	# ── Per-color tinted offsets for raised mode (DESIGN_TOKENS §6.3) ──
	var accent_offset: Color          = _tint_toward_base(accent_color, base_color)
	var surface_high_offset: Color    = _tint_toward_base(surface_high, base_color)
	var surface_panel_offset: Color   = _tint_toward_base(surface_panel, base_color)
	var surface_overlay_offset: Color = _tint_toward_base(surface_overlay, base_color)
	var surface_low_offset: Color     = _tint_toward_base(surface_low, base_color)

	# ── Text colors with is_light flip (DESIGN_TOKENS §6.4) ──
	var text_strong: Color
	var text_default: Color
	var text_muted: Color
	if is_light:
		text_strong  = Color("#1B2230")
		text_default = Color("#1B2230")
		text_muted   = Color("#5A6478")
	else:
		text_strong  = Color("#F7F8FB")
		text_default = Color("#F7F8FB")
		text_muted   = Color("#B9C1D0")

	# ── State-layer overlays (DESIGN_TOKENS §6.5) ──
	# Per-direction hover_pct / pressed_pct / disabled_opacity sourced from
	# STYLE_PERSONALITY (Cross-AI Cycle 1 C2 fix). pressed_pct stored as negative in the
	# style (per DESIGN_TOKENS §6.5 convention: hover lifts toward elevate_target,
	# pressed sinks toward BLACK); the `abs()` extracts the magnitude.
	var hover_pct: float = style_personality.hover_pct
	var pressed_pct: float = abs(style_personality.pressed_pct)
	var disabled_opacity: float = style_personality.disabled_opacity
	var state_hover_target: Color = Color.BLACK if is_light else Color.WHITE
	var state_hover: Color = _mix(base_color, state_hover_target, hover_pct / 100.0)
	var state_pressed: Color = _mix(base_color, Color.BLACK, pressed_pct / 100.0)

	# ── Role tokens (DESIGN_TOKENS §7.1) ──
	var role_primary: Color = accent_color
	var accent_rim: Color = _mix(accent_color, Color.WHITE, 0.5)

	var editor_hint := Engine.is_editor_hint()

	# ── Semantic role tokens (DESIGN_TOKENS §7.1; Plan 05-02 Task 2 — review HIGH gate) ──
	# Defaults sourced verbatim from DESIGN_TOKENS §7.1 "Semantic role tokens" table:
	#   role.success → #5CC971   role.warning → #FFD166
	#   role.danger  → #FF6E6E   role.info    → #5FE3FF
	# These keys MUST be in role_table BEFORE BINDING_TABLE walk so Plan 05-03's
	# DangerButton (and any future Success/Warning/Info chrome) can bind via
	# `{"role": "role_danger"}` without silently falling back to surface_panel /
	# text_strong (which would ship the wrong color and breach §7.1).
	# Per DESIGN_TOKENS §7.1: "directions may override" — v1 ships the defaults;
	# direction-specific overrides plug in via STYLE_PERSONALITY.shape.* in v2.
	var role_success: Color = Color("#5CC971")
	var role_warning: Color = Color("#FFD166")
	var role_danger:  Color = Color("#FF6E6E")
	var role_info:    Color = Color("#5FE3FF")
	var role_success_offset: Color = _raised_depth_color(role_success, base_color)
	var role_warning_offset: Color = _raised_depth_color(role_warning, base_color)
	var role_info_offset: Color = _raised_depth_color(role_info, base_color)
	var text_on_primary: Color = _readable_text_color(role_primary)
	var text_on_accent_offset: Color = _readable_text_color(accent_offset)
	var progress_text_color: Color = text_strong
	var progress_text_outline: Color = surface_low
	var text_on_danger: Color = Color("#151922")
	var text_on_success: Color = _readable_text_color(role_success)
	var text_on_warning: Color = _readable_text_color(role_warning)
	var text_on_info: Color = _readable_text_color(role_info)
	var primary_strategy_value: Variant = _lookup_shape(style_personality, "shape.primary_strategy")
	var text_on_primary_button: Color = text_strong if String(primary_strategy_value) == "quiet-pill" else text_on_primary

	# MD3-style state layers: hover/pressed are the same component foreground color
	# over the button's normal container, so each button family changes by the same
	# rule while preserving its own face hue. Semantic filled buttons need a stronger
	# ramp than neutral controls so Primary/Danger read clearly without making every
	# surface feel heavy.
	var neutral_hover_layer := 0.10
	var neutral_pressed_layer := 0.16
	var semantic_hover_layer := 0.18
	var semantic_pressed_layer := 0.30
	var button_edge_layer := 0.06
	var button_hover: Color = _state_layer_color(button_normal, text_strong, neutral_hover_layer)
	var button_pressed: Color = _state_layer_color(button_normal, text_strong, neutral_pressed_layer)
	var button_border: Color = _state_layer_color(button_normal, text_strong, button_edge_layer)
	var button_border_hover: Color = _state_layer_color(button_hover, text_strong, button_edge_layer)
	var button_border_pressed: Color = _state_layer_color(button_pressed, text_strong, button_edge_layer)
	var surface_low_edge: Color = _state_layer_color(surface_low, text_strong, button_edge_layer)
	var surface_panel_edge: Color = _state_layer_color(surface_panel, text_strong, button_edge_layer)
	var surface_high_edge: Color = _state_layer_color(surface_high, text_strong, button_edge_layer)
	var surface_overlay_edge: Color = _state_layer_color(surface_overlay, text_strong, button_edge_layer)

	var primary_button_normal: Color = button_normal if String(primary_strategy_value) == "quiet-pill" else role_primary
	text_on_primary_button = text_strong if String(primary_strategy_value) == "quiet-pill" else _readable_text_color(primary_button_normal)
	var primary_button_hover: Color = _state_layer_color(primary_button_normal, text_on_primary_button, semantic_hover_layer)
	var primary_button_pressed: Color = _state_layer_color(primary_button_normal, text_on_primary_button, semantic_pressed_layer)
	var primary_button_border: Color = _state_layer_color(primary_button_normal, text_on_primary_button, button_edge_layer)
	var primary_button_border_hover: Color = _state_layer_color(primary_button_hover, text_on_primary_button, button_edge_layer)
	var primary_button_border_pressed: Color = _state_layer_color(primary_button_pressed, text_on_primary_button, button_edge_layer)
	var primary_button_disabled: Color = primary_button_normal

	var danger_button_normal: Color = role_danger
	var danger_button_hover: Color = _state_layer_color(danger_button_normal, text_on_danger, semantic_hover_layer)
	var danger_button_pressed: Color = _state_layer_color(danger_button_normal, text_on_danger, semantic_pressed_layer)
	var danger_button_border: Color = _state_layer_color(danger_button_normal, text_on_danger, button_edge_layer)
	var danger_button_border_hover: Color = _state_layer_color(danger_button_hover, text_on_danger, button_edge_layer)
	var danger_button_border_pressed: Color = _state_layer_color(danger_button_pressed, text_on_danger, button_edge_layer)
	var danger_button_disabled: Color = danger_button_normal

	var button_normal_offset: Color = _raised_depth_color(button_normal, base_color)
	var button_hover_offset: Color = _raised_depth_color(button_hover, base_color)
	var button_pressed_offset: Color = _raised_depth_color(button_pressed, base_color)
	var button_disabled_offset: Color = _raised_depth_color(button_disabled, base_color)
	var primary_button_offset: Color = _raised_depth_color(primary_button_normal, base_color)
	var primary_button_hover_offset: Color = _raised_depth_color(primary_button_hover, base_color)
	var primary_button_pressed_offset: Color = _raised_depth_color(primary_button_pressed, base_color)
	var role_primary_offset: Color = _raised_depth_color(role_primary, base_color)
	var danger_button_offset: Color = _raised_depth_color(danger_button_normal, base_color)
	var danger_button_hover_offset: Color = _raised_depth_color(danger_button_hover, base_color)
	var danger_button_pressed_offset: Color = _raised_depth_color(danger_button_pressed, base_color)
	var role_danger_offset: Color = _raised_depth_color(role_danger, base_color)

	# ── BINDING_TABLE walk lands here (Plan 04-05). ──
	# The locals above are the precomputed inputs every entry-population path consumes.
	# Regeneration clears this Theme first, then repopulates every authored slot.

	# ── Theme defaults (Cross-AI Cycle 1 C3 fix + Cycle 6 F6 fix; BL-01 fix 2026-05-06) ──
	# Set the theme-level default_font + default_font_size BEFORE the BINDING_TABLE walk
	# so any Control type without an explicit per-type font entry still renders in Inter.
	# BL-01 fix: load inter_variable.ttf directly (Godot 4 imports .ttf as FontFile via
	# the .import sidecar). Previously preloaded inter_variable.tres which round-tripped
	# the binary as PackedByteArray, doubling the bundle size.
	# FontVariation and FontFile both extend Font but are NOT cast-compatible — Plan 04-08
	# README's `theme.default_font as FontFile` only works if default_font IS a FontFile.
	# Per FONT-06: "Theme default_font is Inter Variable Roman; default_font.fallbacks = []"
	# — implies FontFile. Body-weight Controls/variations reuse this FontFile directly;
	# only header weights need FontVariation resources.
	var inter_file := preload("res://addons/neocade_theme/fonts/inter_variable.ttf") as FontFile
	default_base_scale = 1.0
	default_font = inter_file
	default_font_size = tokens.body
	var body_font := inter_file

	# ── Register type variations (DESIGN_TOKENS §8.5; PITFALLS 1.2) ──
	for variation_name in TYPE_VARIATIONS.keys():
		if not editor_hint and EDITOR_ONLY_THEME_TYPES.has(variation_name):
			continue
		var base_type: String = TYPE_VARIATIONS[variation_name]
		set_type_variation(variation_name, base_type)

	# ── Set explicit fonts on header variations (PITFALLS 1.2 mandate) ──
	var header_large_font  := preload("res://addons/neocade_theme/fonts/inter_header_large.tres") as FontVariation
	var header_medium_font := preload("res://addons/neocade_theme/fonts/inter_header_medium.tres") as FontVariation
	var header_small_font  := preload("res://addons/neocade_theme/fonts/inter_header_small.tres") as FontVariation
	# Text-bearing variations get explicit set_font calls (Cross-AI Cycle 1 C4 fix:
	# CodeLabel included; WindowContentPanel is structural and owns no font slots).
	set_font("font", "HeaderLarge",  header_large_font)
	set_font("font", "HeaderMedium", header_medium_font)
	set_font("font", "HeaderSmall",  header_small_font)
	set_font("font", "Caption",      body_font)
	# Phase 13 § C1: explicit font binding for Role Label variations (PITFALLS 1.2 —
	# type variations do NOT inherit fonts from their base type).
	set_font("font", "SuccessLabel", body_font)
	set_font("font", "WarningLabel", body_font)
	set_font("font", "DangerLabel",  body_font)
	set_font("font", "InfoLabel",    body_font)
	set_font("font", "CodeLabel",    body_font)   # consumer can override to a mono per FONT-04 stricken
	# Kicker (D-09 / Plan 05-04): Inter Variable Roman body weight per UD-4 Option D / D-17.
	# Per PITFALLS 1.2 type variations DO NOT inherit fonts from Label, so this
	# explicit set_font is mandatory — without it Kicker falls back to default_font.
	set_font("font", "Kicker",       body_font)
	# BL-02 fix 2026-05-06 (D-16): InfoText is a RichTextLabel variation; RTL reads `normal_font`,
	# not `font` — the `font` slot was silently ignored, falling back to default_font.
	# The matching size slot is `normal_font_size` (set below); using `font_size`
	# instead would similarly be silently ignored.
	set_font("normal_font", "InfoText", body_font)
	set_font("font", "PrimaryButton",   body_font)
	set_font("font", "GhostButton",     body_font)
	set_font("font", "DangerButton",    body_font)
	set_font("font", "IconButton",      body_font)
	set_font("font", "FlatButton",      body_font)
	set_font("font", "FlatMenuButton",  body_font)
	set_font("font", "CardPanel",       body_font)
	set_font("font", "HeroPanel",       header_medium_font)
	# Tree exposes explicit font slots outside the BINDING_TABLE schema. Runtime Tree
	# keeps body text dense/readable; editor-only Tree variations are populated below
	# only when the theme is being generated for the editor.
	set_font("font", "Tree",              body_font)
	set_font("title_button_font", "Tree", header_small_font)
	# ItemList exposes one official font slot. Keep it explicit because BINDING_TABLE
	# intentionally has no font branch.
	set_font("font", "ItemList", body_font)
	# FoldableContainer likewise exposes a single official title/body font slot.
	set_font("font", "FoldableContainer", body_font)
	# Tabs expose explicit font slots outside the BINDING_TABLE schema.
	set_font("font", "TabBar", body_font)
	set_font("font", "TabContainer", body_font)
	# ProgressBar exposes an official font slot for optional percentage/text display.
	set_font("font", "ProgressBar", body_font)

	if editor_hint:
		set_font("font", "EditorInspectorButton",     body_font)
		set_font("font", "EditorInspectorFlatButton", body_font)
		set_font("font", "BottomPanelButton", body_font)
		set_font("font", "EditorLogFilterButton", body_font)
		set_font("font", "TreeSecondary",              body_font)
		set_font("title_button_font", "TreeSecondary", header_small_font)
		set_font("font", "TreeTable",              body_font)
		set_font("title_button_font", "TreeTable", header_small_font)
		# Godot editor internals read inspector section/property fonts from EditorFonts,
		# not always from Control font slots. Keep those aliases on the same family.
		set_font("main", "EditorFonts", body_font)
		set_font("bold", "EditorFonts", header_small_font)
		set_font("title", "EditorFonts", header_small_font)
		set_font("font", "ItemListSecondary", body_font)
		set_font("font", "TabContainerOdd", body_font)
		set_font("font", "BottomPanel", body_font)

	# ── Set per-variation font sizes (DESIGN_TOKENS §8.5 + tokens) ──
	set_font_size("font_size", "HeaderLarge",  tokens.h1)
	set_font_size("font_size", "HeaderMedium", tokens.h2)
	# Godot editor uses HeaderSmall for compact add_margin_child() section labels
	# such as CreateDialog's Favorites/Search/Description rows. Keep it at body
	# scale like the built-in editor theme; HeaderMedium/Large carry display scale.
	set_font_size("font_size", "HeaderSmall",  tokens.body)
	set_font_size("font_size", "Caption",      tokens.label_)
	# Phase 13 § C1: explicit font_size binding for Role Label variations.
	set_font_size("font_size", "SuccessLabel", tokens.body)
	set_font_size("font_size", "WarningLabel", tokens.body)
	set_font_size("font_size", "DangerLabel",  tokens.body)
	set_font_size("font_size", "InfoLabel",    tokens.body)
	set_font_size("font_size", "CodeLabel",    tokens.label_)
	# Kicker (D-09): tokens.kicker is 12 desktop / 13 mobile per DESIGN_TOKENS §10.1.
	# Burst's "uppercase-bold-larger-scale" enum is owned by content/showcase since
	# Theme can't re-tag tracking; the size delta (kicker+1) is held at the
	# variation level via Burst-specific tres if needed in v1.x. Phase 5 ships the
	# uniform tokens.kicker baseline; per-direction font_size override (Burst+1)
	# is deliberately deferred to a future _apply_kicker_size dispatch when
	# DESIGN_TOKENS §8.6 / FONT-09 is stable.
	set_font_size("font_size", "Kicker",       tokens.kicker)
	# BL-02 fix 2026-05-06 (D-16): InfoText is a RichTextLabel variation. The size
	# slot for RichTextLabel is `normal_font_size`, NOT `font_size`. Using
	# `font_size` here was a Phase 4-close oversight (the font-slot half was fixed,
	# the size-slot half was not). Plan 05-04 Task 1 deletes the wrong `font_size`
	# entry and replaces it with `normal_font_size` to match the `normal_font`
	# slot name — Godot silently ignores the wrong slot and falls back to
	# default_font_size.
	set_font_size("normal_font_size", "InfoText", tokens.body)
	set_font_size("font_size", "PrimaryButton",   tokens.body)
	set_font_size("font_size", "GhostButton",     tokens.body)
	set_font_size("font_size", "DangerButton",    tokens.body)
	set_font_size("font_size", "IconButton",      tokens.body)
	set_font_size("font_size", "FlatButton",      tokens.body)
	set_font_size("font_size", "FlatMenuButton",  tokens.body)
	if editor_hint:
		set_font_size("font_size", "EditorInspectorButton",     tokens.body)
		set_font_size("font_size", "EditorInspectorFlatButton", tokens.body)
		set_font_size("font_size", "BottomPanelButton", tokens.body)
		set_font_size("font_size", "EditorLogFilterButton", tokens.body)
		set_font_size("font_size", "TreeSecondary", tokens.body)
		set_font_size("title_button_font_size", "TreeSecondary", tokens.body)
		set_font_size("font_size", "TreeTable", tokens.body)
		set_font_size("title_button_font_size", "TreeTable", tokens.body)
		set_font_size("main_size", "EditorFonts", tokens.body)
		set_font_size("bold_size", "EditorFonts", tokens.body)
		set_font_size("title_size", "EditorFonts", maxi(tokens.body, 16))
		set_font_size("font_size", "ItemListSecondary", tokens.body)

	# ── Build role lookup table from derivation locals (Plan 04-04) ──
	var role_table: Dictionary = {
		"surface_base":           surface_base,
		"surface_low":            surface_low,
		"surface_panel":          surface_panel,
		"surface_high":           surface_high,
		"surface_overlay":        surface_overlay,
		"code_background":        code_background,
		"code_current_line":      code_current_line,
		"outline_color":          outline_color,
		"button_normal":          button_normal,
		"selection_control_off":  selection_control_off,
		"button_hover":           button_hover,
		"button_pressed":         button_pressed,
		"button_disabled":        button_disabled,
		"button_border":          button_border,
		"button_border_hover":    button_border_hover,
		"button_border_pressed":  button_border_pressed,
		"surface_low_edge":       surface_low_edge,
		"surface_panel_edge":     surface_panel_edge,
		"surface_high_edge":      surface_high_edge,
		"surface_overlay_edge":   surface_overlay_edge,
		"primary_button_normal":  primary_button_normal,
		"primary_button_hover":   primary_button_hover,
		"primary_button_pressed": primary_button_pressed,
		"primary_button_disabled": primary_button_disabled,
		"primary_button_border":  primary_button_border,
		"primary_button_border_hover": primary_button_border_hover,
		"primary_button_border_pressed": primary_button_border_pressed,
		"danger_button_normal":   danger_button_normal,
		"danger_button_hover":    danger_button_hover,
		"danger_button_pressed":  danger_button_pressed,
		"danger_button_disabled": danger_button_disabled,
		"danger_button_border":   danger_button_border,
		"danger_button_border_hover": danger_button_border_hover,
		"danger_button_border_pressed": danger_button_border_pressed,
		"accent_offset":          accent_offset,
		"surface_high_offset":    surface_high_offset,
		"surface_panel_offset":   surface_panel_offset,
		"surface_overlay_offset": surface_overlay_offset,
		"surface_low_offset":     surface_low_offset,
		"button_normal_offset":   button_normal_offset,
		"button_hover_offset":    button_hover_offset,
		"button_pressed_offset":  button_pressed_offset,
		"button_disabled_offset": button_disabled_offset,
		"primary_button_offset":  primary_button_offset,
		"primary_button_hover_offset": primary_button_hover_offset,
		"primary_button_pressed_offset": primary_button_pressed_offset,
		"danger_button_offset":   danger_button_offset,
		"danger_button_hover_offset": danger_button_hover_offset,
		"danger_button_pressed_offset": danger_button_pressed_offset,
		"text_strong":            text_strong,
		"text_default":           text_default,
		"text_muted":             text_muted,
		"state_hover":            state_hover,
		"state_pressed":          state_pressed,
		"role_primary":           role_primary,
		"role_primary_offset":    role_primary_offset,
		"accent_rim":             accent_rim,
		"scroll_shadow":          Color.BLACK,
		# Semantic roles (Plan 05-02 Task 2; DESIGN_TOKENS §7.1).
		"role_success":           role_success,
		"role_warning":           role_warning,
		"role_danger":            role_danger,
		"role_info":              role_info,
		"role_success_offset":    role_success_offset,
		"role_warning_offset":    role_warning_offset,
		"role_danger_offset":     role_danger_offset,
		"role_info_offset":       role_info_offset,
		"text_on_primary":        text_on_primary,
		"text_on_primary_button": text_on_primary_button,
		"text_on_accent_offset":  text_on_accent_offset,
		"progress_text_color":    progress_text_color,
		"progress_text_outline":  progress_text_outline,
		"text_on_danger":         text_on_danger,
		"text_on_success":        text_on_success,
		"text_on_warning":        text_on_warning,
		"text_on_info":           text_on_info,
	}
	if editor_hint:
		# Godot EditorNode reads these renderer semantic colors directly from the
		# Editor theme type; Minimal Theme and Godot's built-in themes author the
		# same slots. They are deliberately editor-only.
		role_table["renderer_forward_plus"] = Color("#5D8C3F")
		role_table["renderer_mobile"] = Color("#A5557D")
		role_table["renderer_compatibility"] = Color("#5586A4")
		role_table["editor_property_x"] = Color("#E16277") if not is_light else Color("#670A18")
		role_table["editor_property_y"] = Color("#C3EF65") if not is_light else Color("#455E10")
		role_table["editor_property_z"] = Color("#6AABF6") if not is_light else Color("#143862")
		role_table["editor_property_w"] = text_default
		role_table["editor_prop_subsection"] = _mix(button_disabled, surface_base, 0.48)

	# ── Walk BINDING_TABLE — entries not in table remain unset and fall through to Godot defaults. ──
	# Cross-AI Cycle 2 N1 fix: only 5 setter branches — NO set_font branch. Per-Control
	# fonts are handled by default_font + explicit set_font on the 14 type variations.
	# Cross-AI Cycle 2 C2 fix: style_personality passed to _resolve_recipe so disabled alpha is
	# sourced per-direction from STYLE_PERSONALITY.disabled_opacity.
	for theme_type in BINDING_TABLE.keys():
		if not editor_hint and EDITOR_ONLY_THEME_TYPES.has(theme_type):
			continue
		var type_block: Dictionary = BINDING_TABLE[theme_type]
		for data_type in type_block.keys():
			var slots: Dictionary = type_block[data_type]
			for slot_name in slots.keys():
				var recipe: Dictionary = slots[slot_name]
				var value = _resolve_recipe(recipe, data_type, role_table, tokens, style_personality)
				if value == null: continue  # D-04 escape hatch — recipe failed; leave slot alone
				if data_type == "stylebox":
					set_stylebox(slot_name, theme_type, value)
				elif data_type == "color":
					set_color(slot_name, theme_type, value)
				elif data_type == "constant":
					set_constant(slot_name, theme_type, int(value))
				elif data_type == "font_size":
					set_font_size(slot_name, theme_type, int(value))
				elif data_type == "icon":
					set_icon(slot_name, theme_type, value)
				# NOTE: data_type == "font" is intentionally NOT handled (Cross-AI Cycle 2
				# N1 fix). Such entries will not appear in BINDING_TABLE since the schema
				# explicitly excludes "font". If they did, _resolve_recipe returns null
				# (its switch has no font branch), and the value==null check above skips.

	if editor_hint:
		_apply_editor_theme_runtime_settings(role_table)
	_apply_separator_styleboxes(role_table)

	# Phase 7 popup/menu font slots must stay outside BINDING_TABLE. Godot exposes these
	# as real Theme font/font_size entries, but the binding iterator intentionally has no
	# font branch and review convergence requires direct calls after the table walk.
	set_font("title_font", "Window", header_small_font)
	set_font_size("title_font_size", "Window", maxi(tokens.body, 16))
	set_font("font", "TooltipLabel", body_font)
	set_font_size("font_size", "TooltipLabel", tokens.body)
	set_font("font", "MenuBar", body_font)
	set_font_size("font_size", "MenuBar", tokens.body)
	set_font("font", "PopupMenu", body_font)
	set_font("font_separator", "PopupMenu", body_font)
	set_font_size("font_size", "PopupMenu", tokens.body)
	set_font_size("font_separator_size", "PopupMenu", tokens.label_)
	set_font("font", "ColorPickerButton", body_font)
	set_font_size("font_size", "ColorPickerButton", tokens.body)

	_last_regeneration_usec = Time.get_ticks_usec() - t0
	if not texture_cache:
		_active_icon_cache = {}
		_active_generated_texture_cache = {}
	set_block_signals(was_blocking_signals)
	if not was_blocking_signals:
		emit_changed()
	_regenerating = false


func _get_editor_setting_value(path: String, fallback: Variant) -> Variant:
	if not Engine.is_editor_hint():
		return fallback
	if not Engine.has_singleton("EditorInterface"):
		return fallback
	var editor_interface := Engine.get_singleton("EditorInterface")
	if editor_interface == null or not editor_interface.has_method("get_editor_settings"):
		return fallback
	var settings: Object = editor_interface.call("get_editor_settings")
	if settings == null:
		return fallback
	if settings.has_method("has_setting") and not bool(settings.call("has_setting", path)):
		return fallback
	if settings.has_method("get_setting"):
		return settings.call("get_setting", path)
	return fallback


func _apply_editor_theme_runtime_settings(role_table: Dictionary) -> void:
	if not Engine.is_editor_hint():
		return

	# Match Godot Modern's editor setting semantics:
	# None=0, Selected Only=1, All=2. Selected Only keeps normal relationship
	# width at 0 and draws only the highlighted selected parent/child path.
	var relationship_mode := int(_get_editor_setting_value("interface/theme/draw_relationship_lines", 1))
	var relationship_opacity := clampf(float(_get_editor_setting_value("interface/theme/relationship_line_opacity", 0.10)), 0.0, 1.0)
	var draw_lines := relationship_mode != 0 and relationship_opacity >= 0.01
	set_constant("draw_relationship_lines", "Tree", 1 if draw_lines else 0)
	set_constant("relationship_line_width", "Tree", 1 if draw_lines and relationship_mode == 2 else 0)
	set_constant("parent_hl_line_width", "Tree", 1 if draw_lines else 0)
	set_constant("children_hl_line_width", "Tree", 1 if draw_lines else 0)
	set_constant("parent_hl_line_margin", "Tree", 3)

	var line_base: Color = role_table.get("text_muted", Color.WHITE)
	set_color("relationship_line_color", "Tree", Color(line_base.r, line_base.g, line_base.b, relationship_opacity))
	set_color("children_hl_line_color", "Tree", Color(line_base.r, line_base.g, line_base.b, relationship_opacity))
	set_color("parent_hl_line_color", "Tree", Color(line_base.r, line_base.g, line_base.b, minf(1.0, relationship_opacity * 2.0)))

	# Godot's editor log/help panes are plain RichTextLabels, but built-in editor
	# themes give RichTextLabel a panel. Keep runtime RichTextLabel text-only by
	# applying this only while the resource is used as the editor theme.
	var editor_rich_text_panel := StyleBoxFlat.new()
	editor_rich_text_panel.bg_color = role_table.get("code_background", Color.TRANSPARENT)
	editor_rich_text_panel.border_color = role_table.get("code_background", Color.TRANSPARENT)
	editor_rich_text_panel.set_border_width_all(0)
	editor_rich_text_panel.set_corner_radius_all(maxi(0, int(round(corner_radius * 0.5))))
	editor_rich_text_panel.set_content_margin_all(8)
	set_stylebox("normal", "RichTextLabel", editor_rich_text_panel)
	set_stylebox("focus", "RichTextLabel", StyleBoxEmpty.new())


# Phase 12 C2' note (RESEARCH OQ2 / D-12.07 item 6): the section-header underline
# accent rebind was DEFERRED. HSeparator's stylebox is shared with PopupMenu
# separators (Phase 7 convention); rebinding here would surface accent inside
# dropdown menu separators — wrong visual. Re-evaluate after Wave 3 ships if
# accent airtime in headings still feels under-served.
func _apply_separator_styleboxes(role_table: Dictionary) -> void:
	var separator_color: Color = role_table.get("outline_color", Color.WHITE)
	separator_color = Color(separator_color.r, separator_color.g, separator_color.b, separator_color.a * 0.62)
	var h_line := StyleBoxLine.new()
	h_line.color = separator_color
	h_line.grow_begin = -2.0
	h_line.grow_end = -2.0
	h_line.thickness = 1
	set_stylebox("separator", "HSeparator", h_line)
	set_stylebox("separator", "PopupMenu", h_line)
	set_stylebox("labeled_separator_left", "PopupMenu", h_line)
	set_stylebox("labeled_separator_right", "PopupMenu", h_line)

	var v_line := h_line.duplicate() as StyleBoxLine
	v_line.vertical = true
	set_stylebox("separator", "VSeparator", v_line)


# ─── Color helpers (DESIGN_TOKENS §6.1) ─────────────────────────────────────────────────────

## Linear RGB lerp matching the renderer's `lerp(a, b, t)` in `neocade-mockups.js`.
func _mix(a: Color, b: Color, amount: float) -> Color:
	return Color(
		a.r + (b.r - a.r) * amount,
		a.g + (b.g - a.g) * amount,
		a.b + (b.b - a.b) * amount,
		1.0
	)

## Element shifted partway toward `base_c` — preserves hue at every brightness, replacing the
## HSL-darken-floored-at-0 antipattern. Default ratio 0.40 per MOCKUP-REVISION-3-HANDOFF.md.
func _tint_toward_base(element: Color, base_c: Color, ratio: float = 0.40) -> Color:
	return _mix(element, base_c, ratio)


func _button_tonal_color(source: Color, brightness_offset: float, saturation_multiplier: float) -> Color:
	var result := Color(source)
	var amount := clampf(0.35 * absf(brightness_offset), 0.0, 1.0)
	var dark_theme := not is_light
	if dark_theme == (brightness_offset > 0.0):
		result.v = lerpf(result.v, 1.0, amount)
	else:
		result.v = lerpf(result.v, 0.0, amount)
	result.s = clampf(result.s * saturation_multiplier, 0.0, 1.0)
	result.a = source.a
	return result


func _state_layer_color(container: Color, foreground: Color, opacity: float) -> Color:
	var result := _mix(container, foreground, clampf(opacity, 0.0, 1.0))
	result.a = container.a
	return result


func _raised_depth_color(element: Color, base_c: Color) -> Color:
	# Phase 12 C4 (D-12.02): HSV value-darken keeps depth in the element's hue family.
	# `base_c` retained for callsite compatibility but unused — depth decouples from
	# surface per the HCGames anchor (spike 002b iteration 5).
	var strength: float = 0.20 + 0.10 * float(raised_strength)
	var h: float = element.h
	var s: float = element.s
	var v: float = element.v * (1.0 - strength)
	var result := Color.from_hsv(h, s, max(v, 0.04))
	result.a = element.a
	return result


func _readable_text_color(bg: Color) -> Color:
	var dark_text := Color("#151922")
	var light_text := Color("#F7F8FB")
	return dark_text if bg.get_luminance() >= 0.20 else light_text


func _contrast_ratio(a: Color, b: Color) -> float:
	var a_lum := _relative_luminance(a)
	var b_lum := _relative_luminance(b)
	var lighter: float = maxf(a_lum, b_lum)
	var darker: float = minf(a_lum, b_lum)
	return (lighter + 0.05) / (darker + 0.05)


func _relative_luminance(c: Color) -> float:
	return (
		0.2126 * _srgb_to_linear(c.r)
		+ 0.7152 * _srgb_to_linear(c.g)
		+ 0.0722 * _srgb_to_linear(c.b)
	)


func _srgb_to_linear(channel: float) -> float:
	return channel / 12.92 if channel <= 0.03928 else pow((channel + 0.055) / 1.055, 2.4)


# ─── Platform helpers (DESIGN_TOKENS §10.1, §10.2) ──────────────────────────────────────────

## Resolve `Platform.AUTO` to MOBILE or DESKTOP via Godot's feature flags.
## DESKTOP / MOBILE are forced and bypass detection.
func _resolve_platform() -> Platform:
	if platform == Platform.AUTO:
		return Platform.MOBILE if OS.has_feature("mobile") else Platform.DESKTOP
	return platform

## Returns the platform-token table for the given resolved Platform per DESIGN_TOKENS §10.1.
## The return is a Dictionary so Plan 04-05's BINDING_TABLE walk can read tokens by string key.
func _platform_tokens(p: Platform) -> Dictionary:
	if p == Platform.MOBILE:
		return {
			"buttonMin": 48,
			"primaryButtonMin": 56,
			"inputMin": 56,
			"toggleMin": 32,
			"checkboxSize": 20,
			"body": 16,
			"label_": 14,
			"h1": 36,
			"h2": 22,
			"kicker": 13,
			"rowMin": 56,
			"tabMin": 48,
			"thumbnailSize": 128,
			"tapPadding": 12,
			"densityScale": 1.5,
		}
	return {  # DESKTOP (or AUTO that resolved to DESKTOP)
		"buttonMin": 36,
		"primaryButtonMin": 44,
		"inputMin": 34,
		"toggleMin": 22,
		"checkboxSize": 18,
		"body": 14,
		"label_": 12,
		"h1": 36,
		"h2": 22,
		"kicker": 12,
		"rowMin": 36,
		"tabMin": 32,
		"thumbnailSize": 96,
		"tapPadding": 8,
		"densityScale": 1.0,
	}


# ─── Raised stylebox helper (DESIGN_TOKENS §9) ──────────────────────────────────────────────

## Construct a StyleBoxFlat base for flat or raised mode.
## Raised depth is applied later as a hard bottom extrusion, never a StyleBoxFlat shadow.
func _make_raised_stylebox(bg: Color, _offset_color: Color, _intensity: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.shadow_color = Color(0, 0, 0, 0)
	sb.shadow_size = 0
	sb.shadow_offset = Vector2.ZERO
	return sb


# ─── Style personality (DESIGN_TOKENS §5/§6, directions.json axis_8/axis_9) ─────────────────
## Per-style non-exported parameters that don't belong on the public 10-export surface but
## must differentiate Pulse (wide spread) from Slate (narrow spread) etc. Sourced from
## directions.json axis_8_surface_spread + axis_9_disabled_opacity + DESIGN_TOKENS §6.5
## state-layer pcts. Cross-AI Cycle 1 C2 fix.
##
## Lookup is by `style`. `Style.CUSTOM` uses the fallback default so users can customize the
## visible exports without keeping hidden direction personality locked to a named style.
##
## Phase 5 Plan 05-02 (D-02 / D-03 / D-04) adds the `shape` sub-Dictionary on every row.
## Shape values are sourced VERBATIM from DESIGN_TOKENS §5.1-§5.5 ("Theme Editor override
## intent" lines). The shape block carries per-direction shape language (radii, paddings,
## raised lifts, surface alphas, primary/ghost/kicker strategies, focus_offset) so
## BINDING_TABLE recipes can reference `shape.<key>` paths via `_lookup_shape()`. Strategy
## names are first-class enums per D-04: adding a 6th direction in v2 = adding a strategy
## entry, not editing 14 recipes.
const STYLE_PERSONALITY: Dictionary = {
	# ─── Pulse — base=#151A2E, accent=#8BFF6A (DESIGN_TOKENS §5.1) ───
	# Personality: arcade-cabinet rectangular; radius=0; tight-cabinet focus ring (offset=0).
	# Buttons rectangular (radius 0), padding 14×10 desktop, primary strategy = bold-accent-fill.
	# Surface alpha all 1.00 (cabinet hardware is solid).
	Style.PULSE: {
		"spread_factor": 1.3, "hover_pct": 6.0, "pressed_pct": -10.0, "disabled_opacity": 0.42,
		"shape": {
			"primary_radius":        0,
			"primary_padding":       Vector2i(12, 8),
			"primary_strategy":      &"bold-accent-fill",
			"ghost_strategy":        &"accent-outlined-accent-text",
			"secondary_radius":      0,
			"tab_radius":            0,
			"chip_radius":           0,
			"card_radius":           0,
			"hero_radius":           0,
			"surface_alpha_panels":  1.00,
			"surface_alpha_popup":   1.00,
			"surface_alpha_buttons": 1.00,
			"raised_lifts": {
				"primary":         2,
				"secondary":       2,
				"ghost":           1,
				"selected_tab":    2,
				"unselected_tab":  2,
				"panel":           2,
				"dialog":          2,
				"list":            2,
				"mark":            2,
				"selected_row":    0,  # Pulse rows do NOT lift (§5.1 raised lifts line)
				"chip":            2,
			},
			"focus_offset":  0,
			"kicker_style":  &"uppercase-tracked-accent",
			"hairline_thickness":  0,
			"min_radius_floor":    0,
			"primary_outline_color":  &"role_primary",
			"primary_outline_offset": 0,
			"primary_outline_width":  0,
			"primary_min_height":  0,
			"primary_min_height_mobile":  0,
		},
	},
	# ─── Slate — base=#111820, accent=#8BD3FF (DESIGN_TOKENS §5.2) ───
	# Personality: iOS-premium-quiet; radius=14 rounded-pill; ios-style-offset focus (offset=2).
	# Buttons rounded (radius 14), padding 16×11 desktop, primary strategy = quiet-pill.
	# Tabs/chips full pill (radius 999). Surface alpha popup 0.92 (iOS NavigationBar bleed).
	Style.SLATE: {
		"spread_factor": 0.7, "hover_pct": 4.0, "pressed_pct": -6.0,  "disabled_opacity": 0.50,
		"shape": {
			"primary_radius":        14,
			"primary_padding":       Vector2i(14, 9),
			"primary_strategy":      &"quiet-pill",
			"ghost_strategy":        &"thin-accent-outline",
			"secondary_radius":      14,
			"tab_radius":            999,
			"chip_radius":           999,
			"card_radius":           14,
			"hero_radius":           14,
			"surface_alpha_panels":  1.00,
			"surface_alpha_popup":   0.92,
			"surface_alpha_buttons": 1.00,
			"raised_lifts": {
				"primary":         2,
				"secondary":       1,
				"ghost":           1,
				"selected_tab":    1,
				"unselected_tab":  1,
				"panel":           2,
				"dialog":          2,
				"list":            2,
				"mark":            2,
				"selected_row":    1,
				"chip":            2,
			},
			"focus_offset":  2,
			"kicker_style":  &"small-caps-subtle",
			"hairline_thickness":  1,   # Phase 12 C6 Slate signature: 1px hairlines on interactive chrome.
			"min_radius_floor":    0,
			"primary_outline_color":  &"role_primary",
			"primary_outline_offset": 0,
			"primary_outline_width":  0,
			"primary_min_height":  0,
			"primary_min_height_mobile":  0,
		},
	},
	# ─── Bubble — base=#241326, accent=#FFB3E6 (DESIGN_TOKENS §5.3) ───
	# Personality: candy-pillowy; base radius 26 / primary radius 999 (pill on primary
	# specifically per §5.3); cheerful-chunky focus (offset=2). Padding 20×14 desktop.
	# Tabs/chips fully-rounded pill (radius 999). Surface alpha all 1.00 (candy is opaque).
	Style.BUBBLE: {
		"spread_factor": 1.0, "hover_pct": 8.0, "pressed_pct": -10.0, "disabled_opacity": 0.45,
		"shape": {
			"primary_radius":        999,
			"primary_padding":       Vector2i(16, 10),
			"primary_strategy":      &"pillowy-fully-rounded",
			"ghost_strategy":        &"rounded-ghost-thicker-outline",
			"secondary_radius":      26,
			"tab_radius":            999,
			"chip_radius":           999,
			"card_radius":           26,
			"hero_radius":           26,
			"surface_alpha_panels":  1.00,
			"surface_alpha_popup":   1.00,
			"surface_alpha_buttons": 1.00,
			"raised_lifts": {
				"primary":         3,
				"secondary":       2,
				"ghost":           1,
				"selected_tab":    2,
				"unselected_tab":  2,
				"panel":           3,
				"dialog":          3,
				"list":            3,
				"mark":            2,
				"selected_row":    1,
				"chip":            2,
			},
			"focus_offset":  2,
			"kicker_style":  &"uppercase-tracked-accent",
			"hairline_thickness":  0,
			"min_radius_floor":    26,   # Phase 12 C6 Bubble signature: floor every resolved radius to >= 26.
			"primary_outline_color":  &"role_primary",
			"primary_outline_offset": 0,
			"primary_outline_width":  0,
			"primary_min_height":  0,
			"primary_min_height_mobile":  0,
		},
	},
	# ─── Daybreak — base=#0B2420, accent=#76F2D1 (DESIGN_TOKENS §5.4) ───
	# Personality: airy-welcoming-lobby; radius=8 gently rounded; airy-mint focus (offset=2).
	# Buttons radius 8, padding 18×12 desktop, primary strategy = friendly-generous.
	# Surface alpha popup 0.90 + panels 0.96 (airy bleed) but buttons 1.00 (tappability).
	Style.DAYBREAK: {
		"spread_factor": 1.0, "hover_pct": 6.0, "pressed_pct": -6.0,  "disabled_opacity": 0.50,
		"shape": {
			"primary_radius":        8,
			"primary_padding":       Vector2i(20, 14),   # Phase 12 C6 Daybreak: generous primary padding.
			"primary_strategy":      &"friendly-generous",
			"ghost_strategy":        &"soft-outline",
			"secondary_radius":      8,
			"tab_radius":            8,
			"chip_radius":           8,
			"card_radius":           8,
			"hero_radius":           8,
			"surface_alpha_panels":  0.96,
			"surface_alpha_popup":   0.90,
			"surface_alpha_buttons": 1.00,
			"raised_lifts": {
				"primary":         3,
				"secondary":       1,
				"ghost":           1,
				"selected_tab":    2,
				"unselected_tab":  2,
				"panel":           3,
				"dialog":          3,
				"list":            3,
				"mark":            3,
				"selected_row":    1,
				"chip":            3,
			},
			"focus_offset":  2,
			"kicker_style":  &"sentence-case-accent",
			"hairline_thickness":  0,
			"min_radius_floor":    0,
			"primary_outline_color":  &"role_primary",   # Phase 12 C6 Daybreak: token name; resolved through role_table.
			"primary_outline_offset": 3,                 # Phase 12 C6 Daybreak: px outside button edge.
			"primary_outline_width":  2,                 # Phase 12 C6 Daybreak: 2px flat outline (NO halo per SC#3). Bumped from 1→2 per SC#4 protocol (MANIFEST 2026-05-11) to clear thumbnail-scale identifiability.
			"primary_min_height":  0,
			"primary_min_height_mobile":  0,
		},
	},
	# ─── Burst — base=#20112E, accent=#FFD166 (DESIGN_TOKENS §5.5) ───
	# Personality: event-celebration-statement; base radius 18 / primary radius 28 (oversized
	# per §5.5); dramatic-event focus (offset=1). Padding 20×14 desktop. Tabs radius 16.
	# Surface alpha all 1.00 (celebration posters solid). Primary strategy = oversized-statement.
	Style.BURST: {
		"spread_factor": 1.3, "hover_pct": 8.0, "pressed_pct": -12.0, "disabled_opacity": 0.45,
		"shape": {
			"primary_radius":        28,
			"primary_padding":       Vector2i(16, 10),
			"primary_strategy":      &"oversized-statement",
			"ghost_strategy":        &"normal-accent-ghost",
			"secondary_radius":      18,
			"tab_radius":            16,
			"chip_radius":           16,
			"card_radius":           18,
			"hero_radius":           18,
			"surface_alpha_panels":  1.00,
			"surface_alpha_popup":   1.00,
			"surface_alpha_buttons": 1.00,
			"raised_lifts": {
				"primary":         3,
				"secondary":       2,
				"ghost":           2,
				"selected_tab":    3,
				"unselected_tab":  3,
				"panel":           3,
				"dialog":          3,
				"list":            3,
				"mark":            2,
				"selected_row":    2,
				"chip":            2,
			},
			"focus_offset":  1,
			"kicker_style":  &"uppercase-bold-larger-scale",
			"hairline_thickness":  0,
			"min_radius_floor":    0,
			"primary_outline_color":  &"role_primary",
			"primary_outline_offset": 0,
			"primary_outline_width":  0,
			"primary_min_height":  64,   # Phase 12 C6 Burst signature: oversized primary CTAs (bumped 56→64 desktop per SC#4 protocol, MANIFEST 2026-05-11).
			"primary_min_height_mobile":  72,   # Phase 12 C6 Burst: 72 mobile (bumped 64→72 to preserve mobile delta over desktop); resolved on densityScale > 1.0.
		},
	},
}

const STYLE_DESCRIPTIONS: Dictionary = {
	Style.BUBBLE: "Playful, pillowy, generous controls with soft candy energy.",
	Style.BURST: "Event-like, high-energy statement controls with amplified hierarchy.",
	Style.DAYBREAK: "Airy, welcoming, gently rounded mint-forward controls.",
	Style.PULSE: "Arcade-dense cabinet rectangles with bold accent fills.",
	Style.SLATE: "Spacious, quiet, premium rounded chrome.",
	Style.CUSTOM: "Manual style values using NeoCade's neutral fallback personality.",
}

const STYLE_EXPORTS: Dictionary = {
	Style.BUBBLE: {
		"base_color": Color("#241326"),
		"accent_color": Color("#FFB3E6"),
		"corner_radius": 26,
		"spacing": 16,
		"raised_strength": 3,
		"focus_thickness": 3,
		"outline_width": 1,
	},
	Style.BURST: {
		"base_color": Color("#20112E"),
		"accent_color": Color("#FFD166"),
		"corner_radius": 18,
		"spacing": 16,
		"raised_strength": 3,
		"focus_thickness": 3,
		"outline_width": 1,
	},
	Style.DAYBREAK: {
		"base_color": Color("#0B2420"),
		"accent_color": Color("#76F2D1"),
		"corner_radius": 8,
		"spacing": 16,
		"raised_strength": 3,
		"focus_thickness": 2,
		"outline_width": 1,
	},
	Style.PULSE: {
		"base_color": Color("#151A2E"),
		"accent_color": Color("#8BFF6A"),
		"corner_radius": 0,
		"spacing": 14,
		"raised_strength": 2,
		"focus_thickness": 2,
		"outline_width": 1,
	},
	Style.SLATE: {
		"base_color": Color("#111820"),
		"accent_color": Color("#8BD3FF"),
		"corner_radius": 14,
		"spacing": 16,
		"raised_strength": 2,
		"focus_thickness": 2,
		"outline_width": 1,
	},
}

## Default hidden direction personality for `Style.CUSTOM` themes.
##
## Per CONTEXT.md D-13: medium-spread / medium-radius defaults. shape.* values give
## NeoCadeTheme.new() consumers with non-approved hex a stable base — the chrome reads as
## "friendly-generous" (Daybreak's strategy) at radius 8 / focus_offset 2 / surface alpha 1.00.
const STYLE_PERSONALITY_DEFAULT: Dictionary = {
	"spread_factor": 1.0, "hover_pct": 8.0, "pressed_pct": -12.0, "disabled_opacity": 0.38,
	"shape": {
		"primary_radius":        8,
		"primary_padding":       Vector2i(16, 11),
		"primary_strategy":      &"friendly-generous",
		"ghost_strategy":        &"soft-outline",
		"secondary_radius":      8,
		"tab_radius":            8,
		"chip_radius":           8,
		"card_radius":           8,
		"hero_radius":           8,
		"surface_alpha_panels":  1.00,
		"surface_alpha_popup":   1.00,
		"surface_alpha_buttons": 1.00,
		"raised_lifts": {
			"primary":         3,
			"secondary":       1,
			"ghost":           1,
			"selected_tab":    2,
			"unselected_tab":  2,
			"panel":           3,
			"dialog":          3,
			"list":            3,
			"mark":            3,
			"selected_row":    1,
			"chip":            3,
		},
		"focus_offset":  2,
		"kicker_style":  &"sentence-case-accent",
		"hairline_thickness":  0,
		"min_radius_floor":    0,
		"primary_outline_color":  &"role_primary",
		"primary_outline_offset": 0,
		"primary_outline_width":  0,
		"primary_min_height":  0,
		"primary_min_height_mobile":  0,
	},
}

## Returns the per-direction sub-dict for the active `style`.
func _resolve_style_personality() -> Dictionary:
	return STYLE_PERSONALITY.get(style, STYLE_PERSONALITY_DEFAULT)


# ─── Type variation registry (DESIGN_TOKENS §8.5; PITFALLS 1.2 mandate explicit fonts) ──────
## NeoCade type variations registered via Theme.set_type_variation().
## Each entry maps `variation_name -> base_type`; entries backed by editor-only
## controls are skipped at runtime by `EDITOR_ONLY_THEME_TYPES`.
## Text-bearing variations still need explicit set_font/set_font_size calls because
## Godot type variations do not inherit those slots from their base type.
##
## Letter-spacing / case-transform note (research finding, Plan 05-04 Test 5):
## official Godot 4.6 Label theme properties do NOT expose a Theme-level
## letter-spacing slot, so the Kicker variation's "uppercase-tracked-accent" /
## "small-caps-subtle" / "uppercase-bold-larger-scale" tracking + transform
## semantics live in CONTENT (showcase / consumer-rendered text), NOT in the
## Theme. Theme owns font / size / color only. Verifier
## assert_no_letter_spacing_claim guards this contract; if a future Godot
## release exposes such a constant, the wiring can be added with a documented
## docs URL plus a precise has_constant assertion in the verifier.
const TYPE_VARIATIONS: Dictionary = {
	# Button family (TYPEVAR-01) plus editor flat-menu variation — 7
	"PrimaryButton":   "Button",
	"GhostButton":     "Button",
	"DangerButton":    "Button",
	"IconButton":      "Button",
	"FlatButton":      "Button",
	"FlatMenuButton":  "MenuButton",
	"FlatButtonNoIconTint": "FlatButton",
	"FlatMenuButtonNoIconTint": "FlatMenuButton",
	"CheckBoxNoIconTint": "CheckBox",
	"MainScreenButton": "Button",
	"PreviewLightButton": "Button",
	"RunBarButton": "FlatMenuButton",
	"RunBarButtonMovieMakerEnabled": "RunBarButton",
	"RunBarButtonMovieMakerDisabled": "RunBarButton",
	"TopBarOptionButton": "OptionButton",
	"EditorInspectorButton": "Button",
	"EditorInspectorFlatButton": "FlatButton",
	"BottomPanelButton": "FlatMenuButton",
	"EditorLogFilterButton": "Button",
	# Label / heading family (TYPEVAR-02) — 5
	"HeaderLarge":  "Label",
	"HeaderMedium": "Label",
	"HeaderSmall":  "Label",
	"Caption":      "Label",
	"CodeLabel":    "Label",     # Cross-AI Cycle 1 C4 fix: INCLUDED (was previously dropped)
	# Kicker (TYPEVAR-02 + D-09; Plan 05-04 closes DESIGN_TOKENS §8.6 todo) — 1
	"Kicker":       "Label",
	# InfoText (TYPEVAR-03; rich-text small body) — 1
	"InfoText":     "RichTextLabel",
	# Panel family (TYPEVAR-04) plus embedded Window content surface — 3
	"CardPanel": "PanelContainer",
	"HeroPanel": "PanelContainer",
	"WindowContentPanel": "PanelContainer",
	# Editor-specific list/help variations used by CreateDialog, FileSystemDock, and docs popups.
	"TreeSecondary": "Tree",
	"TreeTable": "Tree",
	"ItemListSecondary": "ItemList",
	"EditorHelpBitTitle": "RichTextLabel",
	"EditorHelpBitContent": "RichTextLabel",
	"EditorHelpBitTooltipTitle": "EditorHelpBitTitle",
	"EditorHelpBitTooltipContent": "EditorHelpBitContent",
	"TabContainerOdd": "TabContainer",
	"TabContainerInner": "TabContainer",
	"TabBarInner": "TabBar",
	"BottomPanel": "TabContainer",
	"MainMenuBar": "FlatMenuButton",
	"PanelBackgroundButton": "Button",
	"ProjectTagButton": "Button",
	"PopupProgressBar": "ProgressBar",
	"GamePanel": "Panel",
	"PanelForeground": "Panel",
	"PanelContainerTabbarInner": "PanelContainer",
	"ScrollContainerSecondary": "ScrollContainer",
	"EditorAudioBusEffectsTree": "Tree",
	"TreeLineEdit": "LineEdit",
	# Editor dock scroll-body wrappers used after toolbar stacks.
	"NoBorderHorizontal":       "MarginContainer",
	"NoBorderHorizontalBottom": "NoBorderHorizontal",
	# Phase 13 § C1: Role Label opt-in type variations (4)
	"SuccessLabel": "Label",
	"WarningLabel": "Label",
	"DangerLabel":  "Label",
	"InfoLabel":    "Label",
	# Phase 13 § C3: Role Panel opt-in type variations (5)
	"AccentPanel":  "PanelContainer",
	"InfoPanel":    "PanelContainer",
	"WarningPanel": "PanelContainer",
	"DangerPanel":  "PanelContainer",
	"SuccessPanel": "PanelContainer",
}


const EDITOR_ONLY_THEME_TYPES: Dictionary = {
	"AnimationBezierTrackEdit": true,
	"AnimationTimelineEdit": true,
	"AnimationTrackEdit": true,
	"AnimationTrackEditGroup": true,
	"AssetLib": true,
	"BottomPanel": true,
	"BottomPanelButton": true,
	"BottomSideDockTabContainer": true,
	"DockTabContainer": true,
	"Editor": true,
	"EditorAbout": true,
	"EditorAudioBus": true,
	"EditorAudioBusEffectsTree": true,
	"EditorDebuggerInspector": true,
	"EditorDock": true,
	"EditorHelp": true,
	"EditorHelpBitContent": true,
	"EditorHelpBitTitle": true,
	"EditorHelpBitTooltipContent": true,
	"EditorHelpBitTooltipTitle": true,
	"EditorIcons": true,
	"EditorInspector": true,
	"EditorInspectorArray": true,
	"EditorInspectorButton": true,
	"EditorInspectorCategory": true,
	"EditorInspectorFlatButton": true,
	"EditorInspectorForeground": true,
	"EditorInspectorSection": true,
	"EditorLogFilterButton": true,
	"EditorProperty": true,
	"EditorSettingsDialog": true,
	"EditorSpinSlider": true,
	"EditorStyles": true,
	"EditorValidationPanel": true,
	"GamePanel": true,
	"ItemListSecondary": true,
	"MainMenuBar": true,
	"MainScreenButton": true,
	"NoBorderHorizontal": true,
	"NoBorderHorizontalBottom": true,
	"PanelBackgroundButton": true,
	"PanelContainerTabbarInner": true,
	"PanelForeground": true,
	"PopupProgressBar": true,
	"PreviewLightButton": true,
	"ProjectExportDialog": true,
	"ProjectList": true,
	"ProjectManager": true,
	"ProjectSettingsEditor": true,
	"ProjectTagButton": true,
	"RunBarButton": true,
	"RunBarButtonMovieMakerDisabled": true,
	"RunBarButtonMovieMakerEnabled": true,
	"SceneImportSettingsDialog": true,
	"ScrollContainerSecondary": true,
	"SideDockTabContainer": true,
	"TabBarInner": true,
	"TabContainerInner": true,
	"TabContainerOdd": true,
	"ThemeEditor": true,
	"ThemeItemEditorDialog": true,
	"TileSetEditor": true,
	"TopBarOptionButton": true,
	"TreeLineEdit": true,
	"TreeSecondary": true,
	"TreeTable": true,
	"VSRerouteNode": true,
}


# ─── Canonical slot-name freeze (Cross-AI Cycle 2 C1 fix; Cycle 6 F4/F7 reconciled 2026-05-06) ──
## Per-Control slot-name enumeration sourced VERBATIM from MINIMAL-THEME-DISSECTION.md +
## helpers/BINDING_TABLE_SEED.txt (empirical Godot 4.6 ground-truth where they disagreed —
## Cycle 6 F7 fix: dissection had `on`/`off` for CheckButton; Godot 4.6 uses `checked`/`unchecked`).
## Plan 04-06's verifier iterates these arrays and asserts each slot exists on the loaded
## theme, replacing the previous "broad row-count check" that could pass with wrong slot names.
## BINDING_TABLE recipe slot-keys MUST match these arrays exactly.
const CANONICAL_SLOT_NAMES: Dictionary = {
	# Tree — official Godot 4.6.2 slot freeze from Phase 6 local probe
	# (logs/06-research-slot-probe.log). `hover` is intentionally absent; the
	# official row-hover slot is `hovered`.
	"Tree": {
		"stylebox": {
			"button_hover": true,
			"button_pressed": true,
			"cursor": true,
			"cursor_unfocused": true,
			"custom_button": true,
			"custom_button_hover": true,
			"custom_button_pressed": true,
			"focus": true,
			"hovered": true,
			"hovered_dimmed": true,
			"hovered_selected": true,
			"hovered_selected_focus": true,
			"panel": true,
			"selected": true,
			"selected_focus": true,
			"title_button_hover": true,
			"title_button_normal": true,
			"title_button_pressed": true,
		},
		"color": ["children_hl_line_color", "custom_button_font_highlight", "drop_position_color",
				  "font_color", "font_disabled_color", "font_hovered_color",
				  "font_hovered_dimmed_color", "font_hovered_selected_color", "font_outline_color",
				  "font_selected_color", "guide_color", "parent_hl_line_color",
				  "relationship_line_color", "scroll_hint_color", "title_button_color"],
		"constant": ["button_margin", "check_h_separation", "children_hl_line_width",
					 "dragging_unfold_wait_msec", "draw_guides", "draw_relationship_lines",
					 "h_separation", "icon_h_separation", "icon_max_width",
					 "inner_item_margin_bottom", "inner_item_margin_left", "inner_item_margin_right",
					 "inner_item_margin_top", "item_margin", "outline_size", "parent_hl_line_margin",
					 "parent_hl_line_width", "relationship_line_width", "scroll_border",
					 "scroll_speed", "scrollbar_h_separation", "scrollbar_margin_bottom",
					 "scrollbar_margin_left", "scrollbar_margin_right", "scrollbar_margin_top",
					 "scrollbar_v_separation", "v_separation"],
		"font": ["font", "title_button_font"],
		"font_size": ["font_size", "title_button_font_size"],
		"icon": ["arrow", "arrow_collapsed", "arrow_collapsed_mirrored", "checked",
				 "checked_disabled", "indeterminate", "indeterminate_disabled", "scroll_hint",
				 "select_arrow", "unchecked", "unchecked_disabled", "updown"],
	},
	# Button — 6 stylebox + 5+ font colors (per MINIMAL-THEME-DISSECTION.md §Button)
	# NOTE: upstream sets 12 styleboxes (incl. _mirrored variants); v1 ships 6 base + Godot
	# mirrors via type chain. _mirrored slots are added in Phase 5/6 polish.
	"Button": {
		"stylebox": ["normal", "normal_mirrored", "hover", "hover_mirrored",
					 "pressed", "pressed_mirrored", "focus", "disabled",
					 "disabled_mirrored", "hover_pressed", "hover_pressed_mirrored"],
		"color": ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color",
				  "font_disabled_color", "font_hover_pressed_color",
				  "icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color",
				  "icon_disabled_color", "icon_hover_pressed_color"],
		"constant": ["h_separation"],
	},
	# CheckBox — 4 icon slots (per MINIMAL-THEME-DISSECTION.md §CheckBox)
	"CheckBox": {
		"icon": ["checked", "unchecked", "radio_checked", "radio_unchecked",
				 "checked_disabled", "unchecked_disabled", "radio_checked_disabled",
				 "radio_unchecked_disabled"],
		"color": ["font_pressed_color", "font_hover_pressed_color",
				  "checkbox_checked_color", "checkbox_unchecked_color"],
		"stylebox": ["normal", "normal_mirrored", "hover", "hover_mirrored",
					 "pressed", "pressed_mirrored", "focus", "disabled",
					 "disabled_mirrored", "hover_pressed", "hover_pressed_mirrored"],
	},
	# CheckButton — 2 icon slots: `checked`/`unchecked` per Godot 4.6 class_checkbutton.md
	# (Cycle 6 F4 fix 2026-05-06: was "on"/"off"; CheckButton has NO `on`/`off` slots —
	# icon slots are checked, checked_disabled, checked_disabled_mirrored, checked_mirrored,
	# unchecked, unchecked_disabled, unchecked_disabled_mirrored, unchecked_mirrored).
	# Phase 4 ships only the 2 primary slots; the 6 disabled/mirrored variants are
	# deferred to v1.x per CHANGELOG (Plan 04-08).
	"CheckButton": {
		"icon": ["checked", "unchecked", "checked_disabled", "unchecked_disabled",
				 "checked_mirrored", "unchecked_mirrored", "checked_disabled_mirrored",
				 "unchecked_disabled_mirrored"],
		"color": ["font_focus_color", "font_hover_pressed_color", "font_pressed_color",
				  "button_checked_color", "button_unchecked_color"],
		"stylebox": ["normal", "normal_mirrored", "hover", "hover_mirrored",
					 "pressed", "pressed_mirrored", "focus", "disabled",
					 "disabled_mirrored", "hover_pressed", "hover_pressed_mirrored"],
	},
	# OptionButton — 6 stylebox + 1 constant + 1 icon
	"OptionButton": {
		"stylebox": ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"],
		"constant": ["arrow_margin"],
		"icon": ["arrow"],
		"color": ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color",
				  "font_disabled_color"],
	},
	# LineEdit — 3 stylebox + caret + selection + clear icon (per MINIMAL-THEME-DISSECTION.md §LineEdit)
	"LineEdit": {
		"stylebox": ["normal", "focus", "read_only"],
		"color": ["font_placeholder_color"],
		"icon": ["clear"],
	},
	# TextEdit — same 3-stylebox set as LineEdit
	"TextEdit": {
		"stylebox": ["normal", "focus", "read_only"],
	},
	# Phase 7 popup/dialog/advanced controls — official Godot 4.6.2 slot freeze
	# from logs/07-research-slot-probe.log. Empty arrays are intentional for probed
	# data types with no official slots.
	"Window": {
		"stylebox": ["embedded_border", "embedded_unfocused_border"],
		"color": ["title_color", "title_outline_modulate"],
		"constant": ["close_h_offset", "close_v_offset", "resize_margin", "title_height", "title_outline_size"],
		"font": ["title_font"],
		"font_size": ["title_font_size"],
		"icon": ["close", "close_pressed"],
	},
	"PopupPanel": {
		"stylebox": ["panel"],
		"color": [],
		"constant": [],
		"font": [],
		"font_size": [],
		"icon": [],
	},
	"PopupMenu": {
		"stylebox": ["panel", "hover", "separator", "labeled_separator_left", "labeled_separator_right"],
		"color": ["font_accelerator_color", "font_color", "font_disabled_color", "font_hover_color",
				  "font_outline_color", "font_separator_color", "font_separator_outline_color"],
		"constant": ["gutter_compact", "h_separation", "icon_max_width", "indent", "item_end_padding",
					 "item_start_padding", "outline_size", "search_bar_separation",
					 "separator_outline_size", "v_separation"],
		"font": ["font", "font_separator"],
		"font_size": ["font_separator_size", "font_size"],
		"icon": ["checked", "checked_disabled", "radio_checked", "radio_checked_disabled",
				 "radio_unchecked", "radio_unchecked_disabled", "submenu", "submenu_mirrored",
				 "search", "unchecked", "unchecked_disabled"],
	},
	"AcceptDialog": {
		"stylebox": ["panel"],
		"color": [],
		"constant": ["buttons_separation"],
		"font": [],
		"font_size": [],
		"icon": [],
	},
	"ConfirmationDialog": {
		"stylebox": [],
		"color": [],
		"constant": [],
		"font": [],
		"font_size": [],
		"icon": [],
	},
	"FileDialog": {
		"stylebox": [],
		"color": ["file_disabled_color", "file_icon_color", "folder_icon_color"],
		"constant": ["thumbnail_size"],
		"font": [],
		"font_size": [],
		"icon": ["back_folder", "clear", "create_folder", "favorite", "favorite_down",
				 "favorite_up", "file", "file_thumbnail", "folder", "folder_thumbnail",
				 "forward_folder", "list_mode", "load", "parent_folder", "reload", "save",
				 "sort", "thumbnail_mode", "toggle_filename_filter", "toggle_hidden"],
	},
	"TooltipPanel": {
		"stylebox": ["panel"],
		"color": [],
		"constant": [],
		"font": [],
		"font_size": [],
		"icon": [],
	},
	"TooltipLabel": {
		"stylebox": [],
		"color": ["font_color", "font_outline_color", "font_shadow_color"],
		"constant": ["outline_size", "shadow_offset_x", "shadow_offset_y"],
		"font": ["font"],
		"font_size": ["font_size"],
		"icon": [],
	},
	"MenuBar": {
		"stylebox": ["disabled", "hover", "normal", "pressed"],
		"color": ["font_color", "font_disabled_color", "font_focus_color", "font_hover_color",
				  "font_hover_pressed_color", "font_outline_color", "font_pressed_color"],
		"constant": ["h_separation", "outline_size"],
		"font": ["font"],
		"font_size": ["font_size"],
		"icon": [],
	},
	"ColorPicker": {
		"stylebox": ["picker_focus_circle", "picker_focus_rectangle", "sample_focus"],
		"color": ["focused_not_editing_cursor_color"],
		"constant": ["center_slider_grabbers", "h_width", "label_width", "margin", "sv_height", "sv_width"],
		"font": [],
		"font_size": [],
		"icon": ["add_preset", "bar_arrow", "color_hue", "color_script", "expanded_arrow",
				 "folded_arrow", "menu_option", "overbright_indicator", "picker_cursor",
				 "picker_cursor_bg", "sample_bg", "sample_revert", "screen_picker",
				 "shape_circle", "shape_rect", "shape_rect_wheel"],
	},
	"ColorPickerButton": {
		"stylebox": ["disabled", "focus", "hover", "normal", "pressed"],
		"color": ["font_color", "font_disabled_color", "font_focus_color", "font_hover_color",
				  "font_outline_color", "font_pressed_color"],
		"constant": ["h_separation", "outline_size"],
		"font": ["font"],
		"font_size": ["font_size"],
		"icon": ["bg"],
	},
	"ColorPresetButton": {
		"stylebox": ["preset_fg", "preset_focus"],
		"icon": ["preset_bg", "overbright_indicator"],
	},
	"GraphEdit": {
		"stylebox": ["menu_panel", "panel", "panel_focus"],
		"color": ["activity", "connection_hover_tint_color", "connection_rim_color",
				  "connection_valid_target_tint_color", "grid_major", "grid_minor",
				  "selection_fill", "selection_stroke"],
		"constant": ["connection_hover_thickness", "port_hotzone_inner_extent", "port_hotzone_outer_extent"],
		"font": [],
		"font_size": [],
		"icon": ["grid_toggle", "layout", "minimap_toggle", "snapping_toggle",
				 "zoom_in", "zoom_out", "zoom_reset"],
	},
	"GraphNode": {
		"stylebox": ["panel", "panel_focus", "panel_selected", "slot", "slot_selected", "titlebar", "titlebar_selected"],
		"color": ["resizer_color"],
		"constant": ["port_h_offset", "separation"],
		"font": [],
		"font_size": [],
		"icon": ["port", "resizer"],
	},
	"GraphFrame": {
		"stylebox": ["panel", "panel_selected", "titlebar", "titlebar_selected"],
		"color": ["resizer_color"],
		"constant": [],
		"font": [],
		"font_size": [],
		"icon": ["resizer"],
	},
	# HScrollBar — official Godot 4.6.2 slot freeze
	"HScrollBar": {
		"stylebox": ["scroll", "scroll_focus", "grabber", "grabber_highlight", "grabber_pressed"],
		"constant": ["padding_top", "padding_bottom"],
		"icon": ["decrement", "decrement_highlight", "decrement_pressed",
				 "increment", "increment_highlight", "increment_pressed"],
	},
	# VScrollBar — official Godot 4.6.2 slot freeze
	"VScrollBar": {
		"stylebox": ["scroll", "scroll_focus", "grabber", "grabber_highlight", "grabber_pressed"],
		"constant": ["padding_left", "padding_right"],
		"icon": ["decrement", "decrement_highlight", "decrement_pressed",
				 "increment", "increment_highlight", "increment_pressed"],
	},
	# ItemList — official Godot 4.6.2 slot freeze
	"ItemList": {
		"stylebox": ["panel", "focus", "cursor", "cursor_unfocused", "hovered", "selected", "selected_focus",
					 "hovered_selected", "hovered_selected_focus"],
		"color": ["font_color", "font_hovered_color", "font_hovered_selected_color",
				  "font_outline_color", "font_selected_color", "guide_color", "scroll_hint_color"],
		"constant": ["h_separation", "icon_margin", "line_separation", "outline_size", "v_separation"],
		"font": ["font"],
		"font_size": ["font_size"],
		"icon": ["scroll_hint"],
	},
	# TabBar — official Godot 4.6.2 slot freeze. Legacy tab-separation notes
	# are absent in the local probe and must not be bound without new evidence.
	"TabBar": {
		"stylebox": ["button_highlight", "button_pressed", "tab_disabled", "tab_focus",
					 "tab_hovered", "tab_selected", "tab_unselected"],
		"color": ["drop_mark_color", "font_disabled_color", "font_hovered_color", "font_outline_color",
				  "font_selected_color", "font_unselected_color", "icon_disabled_color",
				  "icon_hovered_color", "icon_selected_color", "icon_unselected_color"],
		"constant": ["h_separation", "hover_switch_wait_msec", "icon_max_width", "outline_size"],
		"font": ["font"],
		"font_size": ["font_size"],
		"icon": ["close", "decrement", "decrement_highlight", "drop_mark",
				 "increment", "increment_highlight"],
	},
	# TabContainer — official Godot 4.6.2 slot freeze. Legacy tab-separation
	# notes are absent in the local probe and must not be bound without new evidence.
	"TabContainer": {
		"stylebox": ["tab_selected", "tab_unselected", "tab_hovered", "tab_disabled", "tab_focus",
					 "panel", "tabbar_background"],
		"color": ["drop_mark_color", "font_disabled_color", "font_hovered_color", "font_outline_color",
				  "font_selected_color", "font_unselected_color", "icon_disabled_color",
				  "icon_hovered_color", "icon_selected_color", "icon_unselected_color"],
		"constant": ["icon_max_width", "icon_separation", "outline_size", "side_margin", "tab_separation"],
		"font": ["font"],
		"font_size": ["font_size"],
		"icon": ["decrement", "decrement_highlight", "drop_mark", "increment",
				 "increment_highlight", "menu", "menu_highlight"],
	},
	# FoldableContainer — official Godot 4.6.2 slot freeze.
	"FoldableContainer": {
		"stylebox": ["focus", "panel", "title_collapsed_hover_panel",
					 "title_collapsed_panel", "title_hover_panel", "title_panel"],
		"color": ["collapsed_font_color", "font_color", "font_outline_color", "hover_font_color"],
		"constant": ["h_separation", "outline_size"],
		"font": ["font"],
		"font_size": ["font_size"],
		"icon": ["expanded_arrow", "expanded_arrow_mirrored", "folded_arrow", "folded_arrow_mirrored"],
	},
	# HSlider / VSlider — official Godot 4.6.2 slot freeze.
	"HSlider": {
		"stylebox": ["slider", "grabber_area", "grabber_area_highlight"],
		"constant": ["center_grabber", "grabber_offset", "tick_offset"],
		"icon": ["grabber", "grabber_disabled", "grabber_highlight", "tick"],
	},
	"VSlider": {
		"stylebox": ["slider", "grabber_area", "grabber_area_highlight"],
		"constant": ["center_grabber", "grabber_offset", "tick_offset"],
		"icon": ["grabber", "grabber_disabled", "grabber_highlight", "tick"],
	},
	# ProgressBar — official Godot 4.6.2 slot freeze.
	"ProgressBar": {
		"stylebox": ["background", "fill"],
		"color": ["font_color", "font_outline_color"],
		"constant": ["outline_size"],
		"font": ["font"],
		"font_size": ["font_size"],
	},
	# Container/layout controls — official Godot 4.6.2 slot freeze.
	"ScrollContainer": {
		"stylebox": ["focus", "panel"],
		"color": ["scroll_hint_horizontal_color", "scroll_hint_vertical_color"],
		"icon": ["scroll_hint_horizontal", "scroll_hint_vertical"],
	},
	"SplitContainer": {
		"stylebox": ["split_bar_background"],
		"color": ["touch_dragger_color", "touch_dragger_hover_color", "touch_dragger_pressed_color"],
		"constant": ["autohide", "minimum_grab_thickness", "separation"],
		"icon": ["h_grabber", "h_touch_dragger", "v_grabber", "v_touch_dragger"],
	},
	"HSplitContainer": {
		"stylebox": ["split_bar_background"],
		"constant": ["autohide", "minimum_grab_thickness", "separation"],
		"icon": ["grabber", "touch_dragger"],
	},
	"VSplitContainer": {
		"stylebox": ["split_bar_background"],
		"constant": ["autohide", "minimum_grab_thickness", "separation"],
		"icon": ["grabber", "touch_dragger"],
	},
	"MarginContainer": {
		"constant": ["margin_bottom", "margin_left", "margin_right", "margin_top"],
	},
	"HBoxContainer": {
		"constant": ["separation"],
	},
	"VBoxContainer": {
		"constant": ["separation"],
	},
	"FlowContainer": {
		"constant": ["h_separation", "v_separation"],
	},
	"GridContainer": {
		"constant": ["h_separation", "v_separation"],
	},
	"HSeparator": {
		"stylebox": ["separator"],
		"constant": ["separation"],
	},
	"VSeparator": {
		"stylebox": ["separator"],
		"constant": ["separation"],
	},
	# Label — color only. Labels should not draw background chrome.
	"Label": {
		"stylebox": ["normal", "focus"],
		"color": ["font_color"],
	},
	# RichTextLabel — text only. Explicit transparent styleboxes prevent fallback
	# to Godot's default focus border while still drawing no panel/background chrome.
	"RichTextLabel": {
		"stylebox": ["normal", "focus"],
		"color": ["default_color", "selection_color", "font_selected_color"],
	},
	# PanelContainer-like (Panel) — 1 stylebox
	"Panel": {
		"stylebox": ["panel"],
	},
	# Per-direction polish (Phase 5/6/7) extends these. The Controls below have their slot
	# name lists equal to BINDING_TABLE[type][data_type].keys() at runtime; freezing them
	# in this dict is optional for v1 verification (Plan 04-06 derives slot lists from
	# BINDING_TABLE.keys() for any Control NOT in CANONICAL_SLOT_NAMES).
}


# ─── BINDING_TABLE (Plan 04-05; 37 canonical Controls + narrow EditorIcons overrides) ────────
## CANONICAL 37-ROW FREEZE (Cross-AI Cycle 1 C1 fix; sourced verbatim from
## MINIMAL-THEME-COVERAGE-DELTA.md §Coverage Scorecard). NO executor discretion to add/drop.
## The EditorIcons row below is a non-Control editor integration shim, not a scorecard Control.
##
## Structure: theme_type → data_type ("stylebox"/"color"/"constant"/"font_size"/"icon")
##   → slot_name → recipe Dictionary. Recipes:
##     {"role": "<role>"}              — pulls a derived color from role_table.
##     {"empty": true}                 — emits StyleBoxEmpty for contextual chrome gaps.
##     {"role": "...", "raised_intensity": int} — for stylebox; multiplier for raised lift.
##     {"role": "...", "disabled": true}        — pulls per-direction alpha from style_personality.disabled_opacity (Cycle 2 C2).
##     {"role": "focus_ring"}                   — special: transparent bg + accent border + expand.
##     {"value": "tokens.<key>"}                — for constant/font_size.
##     {"icon": "<filename>"}                   — for icons (file under addons/neocade_theme/icons/).
##
## D-01 invariant: iteration is ADDITIVE only (set_stylebox/set_color/set_constant/set_font_size/set_icon).
## D-04 escape hatch: entries not in BINDING_TABLE are left untouched.
## REVISABLE per CONTEXT.md D-03: this binding mechanism may evolve toward a metadata-tagged
## Resource model post-Phase-4. The public @export surface + .tres format are stable; only
## the internal binding mechanism would change.
const BINDING_TABLE: Dictionary = {
	# Editor icon overrides — Godot editor toolbar/menu buttons request these through
	# EditorIcons, not through TabContainer icon slots. Keep this narrow: only the
	# "more/menu" family that NeoCade restyles for editor chrome.
	"EditorIcons": {
		"icon": {
			"GuiTabMenu":                 {"icon": "tab_menu"},
			"GuiTabMenuHl":               {"icon": "tab_menu"},
			"GuiTabMenuHlDarkBackground": {"icon": "tab_menu"},
			"TripleBar":                  {"icon": "editor_triple_bar_24"},
			"FileBigThumb":               {"icon": "filedialog_file_thumbnail"},
			"FileDeadBigThumb":           {"icon": "filedialog_file_thumbnail"},
			"FolderBigThumb":             {"icon": "filedialog_folder_thumbnail"},
			"FileMediumThumb":            {"icon": "filedialog_file_thumbnail"},
			"FileDeadMediumThumb":        {"icon": "filedialog_file_thumbnail"},
			"FolderMediumThumb":          {"icon": "filedialog_folder_thumbnail"},
		},
	},
	# Editor globals used by inspector sections, vector component labels, Signals dock
	# subsection rows, and complex editor dialogs. These are not Control subclasses, but
	# Godot's editor source requests them from the "Editor" theme type.
	"Editor": {
		"stylebox": {
			"prop_subsection_stylebox": {
				"role": "editor_prop_subsection", "border_role": "editor_prop_subsection",
				"raised_intensity": 0, "border_widths": Vector4i(1, 0, 1, 0),
				"border_alpha": 0.0,
				"radius": "shape.secondary_radius", "padding": Vector2i(6, 2)
			},
			"prop_subsection_stylebox_left": {
				"role": "editor_prop_subsection", "border_role": "editor_prop_subsection",
				"raised_intensity": 0, "border_widths": Vector4i(1, 0, 0, 0),
				"border_alpha": 0.0,
				"radius": "shape.secondary_radius", "padding": Vector2i(6, 2)
			},
			"prop_subsection_stylebox_right": {
				"role": "editor_prop_subsection", "border_role": "editor_prop_subsection",
				"raised_intensity": 0, "border_widths": Vector4i(0, 0, 1, 0),
				"border_alpha": 0.0,
				"radius": "shape.secondary_radius", "padding": Vector2i(6, 2)
			},
		},
		"color": {
			"base_color": {"role": "surface_base"},
			"background": {"role": "surface_base"},
			"accent_color": {"role": "role_primary"},
			"mono_color": {"role": "text_default"},
			"dark_color_1": {"role": "surface_low"},
			"dark_color_2": {"role": "surface_panel"},
			"dark_color_3": {"role": "code_background"},
			"contrast_color_1": {"role": "surface_high"},
			"contrast_color_2": {"role": "surface_overlay"},
			"highlight_color": {"role": "button_pressed"},
			"highlight_disabled_color": {"role": "button_disabled"},
			"disabled_highlight_color": {"role": "button_disabled"},
			"success_color": {"role": "role_success"},
			"success_color_dark_background": {"role": "role_success"},
			"warning_color": {"role": "role_warning"},
			"warning_color_dark_background": {"role": "role_warning"},
			"error_color": {"role": "role_danger"},
			"error_color_dark_background": {"role": "role_danger"},
			"forward_plus_color": {"role": "renderer_forward_plus"},
			"mobile_color": {"role": "renderer_mobile"},
			"gl_compatibility_color": {"role": "renderer_compatibility"},
			"ruler_color": {"role": "surface_high_edge"},
			"selection_color": {"role": "accent_offset"},
			"separator_color": {"role": "surface_high_edge"},
			"disabled_border_color": {"role": "surface_high_edge", "disabled": true},
			"disabled_bg_color": {"role": "button_disabled"},
			"extra_border_color_1": {"role": "surface_high_edge"},
			"extra_border_color_2": {"role": "surface_overlay_edge"},
			"box_selection_fill_color": {"role": "role_primary", "alpha": 0.18},
			"box_selection_stroke_color": {"role": "role_primary", "alpha": 0.55},
			"axis_x_color": {"role": "editor_property_x"},
			"axis_y_color": {"role": "editor_property_y"},
			"axis_z_color": {"role": "editor_property_z"},
			"axis_w_color": {"role": "editor_property_w"},
			"axis_view_plane_color": {"role": "text_muted", "alpha": 0.33},
			# Signals/Groups subsection rows pass this to TreeItem.set_custom_bg_color(),
			# which paints edge-to-edge before the stylebox is drawn. Keep it transparent
			# so prop_subsection_stylebox owns the visible inset fill.
			"prop_subsection": {"role": "editor_prop_subsection", "alpha": 0.0},
			"prop_subsection_stylebox_color": {"role": "editor_prop_subsection"},
			"font_color": {"role": "text_default"},
			"font_focus_color": {"role": "text_strong"},
			"font_hover_color": {"role": "text_strong"},
			"font_pressed_color": {"role": "text_strong"},
			"font_hover_pressed_color": {"role": "text_strong"},
			"font_disabled_color": {"role": "text_muted", "disabled": true},
			"font_readonly_color": {"role": "text_muted"},
			"font_placeholder_color": {"role": "text_muted", "alpha": 0.72},
			"font_outline_color": {"role": "outline_color"},
			"font_dark_background_color": {"role": "text_default"},
			"font_dark_background_focus_color": {"role": "text_strong"},
			"font_dark_background_hover_color": {"role": "text_strong"},
			"font_dark_background_pressed_color": {"role": "text_strong"},
			"font_dark_background_hover_pressed_color": {"role": "text_strong"},
			"readonly_font_color": {"role": "text_muted"},
			"disabled_font_color": {"role": "text_muted", "disabled": true},
			"readonly_color": {"role": "text_muted"},
			"highlighted_font_color": {"role": "text_strong"},
			"icon_normal_color": {"role": "text_default"},
			"icon_focus_color": {"role": "text_strong"},
			"icon_hover_color": {"role": "text_strong"},
			"icon_pressed_color": {"role": "role_primary"},
			"icon_disabled_color": {"role": "text_muted", "disabled": true},
			"icon_saturation": {"role": "text_default"},
			"property_color": {"role": "text_default"},
			"property_color_x": {"role": "editor_property_x"},
			"property_color_y": {"role": "editor_property_y"},
			"property_color_z": {"role": "editor_property_z"},
			"property_color_w": {"role": "editor_property_w"},
		},
		"constant": {
			"class_icon_size": {"value": 16},
			"inspector_margin": {"value": 12},
			"inspector_property_height": {"value": 32, "mobile_value": 48},
		},
	},
	# EditorHelp / EditorHelpBit rich text colors used inside CreateDialog descriptions.
	"EditorHelp": {
		"stylebox": {
			"background": {"role": "surface_base", "border_role": "surface_base",
						   "raised_intensity": 0, "border_width": 0,
						   "radius": 0, "padding": Vector2i(0, 0)},
		},
		"color": {
			"text_color":      {"role": "text_default"},
			"headline_color":  {"role": "text_strong"},
			"comment_color":   {"role": "text_muted"},
			"symbol_color":    {"role": "text_muted"},
			"value_color":     {"role": "text_muted"},
			"qualifier_color": {"role": "text_default"},
			"type_color":      {"role": "role_primary"},
			"title_color":     {"role": "role_primary"},
			"selection_color": {"role": "accent_offset"},
			"link_color":      {"role": "role_primary"},
			"code_color":      {"role": "role_primary"},
			"override_color":  {"role": "role_warning"},
			"code_bg_color":   {"role": "code_background"},
			"kbd_bg_color":    {"role": "surface_low"},
			"param_bg_color":  {"role": "surface_low"},
			"kbd_color":       {"role": "text_strong"},
			"primary_hr_color": {"role": "surface_high_edge"},
			"secondary_hr_color": {"role": "surface_low_edge"},
		},
		"constant": {
			"line_separation":             {"value": 2},
			"paragraph_separation":        {"value": 6},
			"table_h_separation":          {"value": 12},
			"table_v_separation":          {"value": 4},
			"text_highlight_h_padding":    {"value": 1},
			"text_highlight_v_padding":    {"value": 2},
		},
	},
	# Editor inspector/settings properties: Godot source sets most property
	# OptionButtons and EditorSpinSliders to flat=true, so their own normal
	# Button/LineEdit faces are not drawn. The value-cell surface comes from
	# EditorProperty.child_bg instead.
	"EditorProperty": {
		"stylebox": {
			"bg":            {"empty": true},
			"bg_selected":   {"role": "button_pressed", "border_role": "button_pressed",
							  "raised_intensity": 0, "alpha": 0.32, "border_width": 0,
							  "radius": "shape.secondary_radius"},
			"child_bg":      {"role": "button_normal", "border_role": "button_border",
							  "raised_face_edge": true,
							  "raised_intensity": "shape.raised_lifts.secondary",
							  "radius": "shape.secondary_radius", "border_width": 1},
			"bg_group_note": {"role": "role_primary", "alpha": 0.10,
							  "raised_intensity": 0, "border_width": 0,
							  "radius": "shape.secondary_radius",
							  "content_margins": Vector4i(8, 6, 8, 6)},
		},
		"color": {
			"property_color":          {"role": "text_default"},
			"readonly_color":          {"role": "text_muted"},
			"warning_color":           {"role": "role_warning"},
			"readonly_warning_color":  {"role": "role_warning", "alpha": 0.70},
		},
		"constant": {
			"font_offset": {"value": 8},
		},
	},
	"EditorInspectorCategory": {
		"stylebox": {
			"bg": {"role": "surface_high", "border_role": "surface_high_edge",
				   "raised_intensity": 0, "border_width": 0, "radius": 0,
				   "content_margins": Vector4i(0, 6, 0, 6)},
		},
	},
	"EditorInspectorSection": {
		"stylebox": {
			"indent_box": {"role": "role_primary", "alpha": 0.20,
						   "raised_intensity": 0, "border_width": 0,
						   "radius": 0, "padding": Vector2i(2, 0)},
		},
		"color": {
			"font_color": {"role": "text_strong"},
		},
		"constant": {
			"h_separation": {"value": 4},
			"indent_size": {"value": 6},
		},
	},
	"EditorSpinSlider": {
		"stylebox": {
			"label_bg": {"role": "button_normal", "border_role": "button_border",
						 "raised_face_edge": true,
						 "raised_intensity": "shape.raised_lifts.secondary",
						 "radius": "shape.secondary_radius", "border_width": 1,
						 "padding": Vector2i(8, 4)},
		},
		"color": {
			"label_color":           {"role": "role_primary"},
			"read_only_label_color": {"role": "text_muted", "disabled": true},
		},
		"constant": {
			"line_edit_margin":       {"value": 28},
			"line_edit_margin_empty": {"value": 20},
		},
		"icon": {
			"updown":          {"icon": "tree_updown"},
			"updown_disabled": {"icon": "tree_updown"},
		},
	},
	"EditorInspectorButton": {
		"stylebox": {
			"normal":                 {"role": "button_normal", "border_role": "button_border",
									   "raised_face_edge": true,
									   "raised_intensity": "shape.raised_lifts.secondary",
									   "radius": "shape.secondary_radius", "padding": Vector2i(8, 4),
									   "mobile_padding": Vector2i(8, 16)},
			"normal_mirrored":        {"role": "button_normal", "border_role": "button_border",
									   "raised_face_edge": true,
									   "raised_intensity": "shape.raised_lifts.secondary",
									   "radius": "shape.secondary_radius", "padding": Vector2i(8, 4),
									   "mobile_padding": Vector2i(8, 16)},
			"hover":                  {"role": "button_hover", "border_role": "button_border_hover",
									   "raised_face_edge": true,
									   "raised_intensity": "shape.raised_lifts.secondary",
									   "radius": "shape.secondary_radius", "padding": Vector2i(8, 4),
									   "mobile_padding": Vector2i(8, 16)},
			"hover_mirrored":         {"role": "button_hover", "border_role": "button_border_hover",
									   "raised_face_edge": true,
									   "raised_intensity": "shape.raised_lifts.secondary",
									   "radius": "shape.secondary_radius", "padding": Vector2i(8, 4),
									   "mobile_padding": Vector2i(8, 16)},
			"pressed":                {"role": "button_pressed", "border_role": "button_border_pressed",
									   "raised_intensity": 0,
									   "radius": "shape.secondary_radius", "padding": Vector2i(8, 4),
									   "mobile_padding": Vector2i(8, 16)},
			"pressed_mirrored":       {"role": "button_pressed", "border_role": "button_border_pressed",
									   "raised_intensity": 0,
									   "radius": "shape.secondary_radius", "padding": Vector2i(8, 4),
									   "mobile_padding": Vector2i(8, 16)},
			"hover_pressed":          {"role": "button_pressed", "border_role": "button_border_pressed",
									   "raised_intensity": 0,
									   "radius": "shape.secondary_radius", "padding": Vector2i(8, 4),
									   "mobile_padding": Vector2i(8, 16)},
			"hover_pressed_mirrored": {"role": "button_pressed", "border_role": "button_border_pressed",
									   "raised_intensity": 0,
									   "radius": "shape.secondary_radius", "padding": Vector2i(8, 4),
									   "mobile_padding": Vector2i(8, 16)},
			"disabled":               {"role": "button_disabled", "raised_intensity": 0,
									   "border_width": 0, "radius": "shape.secondary_radius",
									   "padding": Vector2i(8, 4),
									   "mobile_padding": Vector2i(8, 16)},
			"disabled_mirrored":      {"role": "button_disabled", "raised_intensity": 0,
									   "border_width": 0, "radius": "shape.secondary_radius",
									   "padding": Vector2i(8, 4),
									   "mobile_padding": Vector2i(8, 16)},
		},
		"color": {
			"font_color":               {"role": "text_strong"},
			"font_hover_color":         {"role": "text_strong"},
			"font_pressed_color":       {"role": "text_strong"},
			"font_focus_color":         {"role": "text_strong"},
			"font_disabled_color":      {"role": "text_strong", "disabled": true},
			"font_hover_pressed_color": {"role": "text_strong"},
			"icon_normal_color":        {"role": "text_strong"},
			"icon_hover_color":         {"role": "text_strong"},
			"icon_pressed_color":       {"role": "text_strong"},
			"icon_focus_color":         {"role": "text_strong"},
			"icon_disabled_color":      {"role": "text_strong", "disabled": true},
			"icon_hover_pressed_color": {"role": "text_strong"},
		},
		"constant": {
			"h_separation": {"value": 4},
		},
	},
	# 1. AcceptDialog — explicit popup shell plus official button-container spacing.
	"AcceptDialog": {
		"stylebox": {
			"panel": {"role": "surface_base", "border_role": "surface_panel_edge",
					  "offset_role": "surface_low_offset", "radius": "shape.secondary_radius",
					  "raised_face_edge": true,
					  "raised_intensity": "shape.raised_lifts.dialog",
					  "padding": Vector2i(12, 10)},
		},
		"constant": {
			"buttons_separation": {"value": "tokens.tapPadding"},
		},
	},
	# 2. Button — 6 styleboxes + font colors + h_separation (PITFALLS 10.3 clean states)
	# Plan 05-03 Task 2 polish: pull per-direction shape via shape.secondary_radius +
	# shape.primary_padding + shape.raised_lifts.secondary so base Button chrome reads
	# the same per-direction language as the TYPEVAR-01 variations. The base Button
	# uses the SECONDARY family (not primary) — primary chrome is reserved for the
	# PrimaryButton variation per TYPEVAR-01 / DESIGN_TOKENS §5.
	"Button": {
		"stylebox": {
			"normal":         {"role": "button_normal", "border_role": "button_border", "raised_face_edge": true,
								"raised_intensity": "shape.raised_lifts.secondary",
								"radius": "shape.secondary_radius", "padding": "shape.primary_padding",
								"mobile_padding": Vector2i(18, 18)},
			"normal_mirrored":{"role": "button_normal", "border_role": "button_border", "raised_face_edge": true,
								"raised_intensity": "shape.raised_lifts.secondary",
								"radius": "shape.secondary_radius", "padding": "shape.primary_padding",
								"mobile_padding": Vector2i(18, 18)},
			"hover":          {"role": "button_hover", "border_role": "button_border_hover", "raised_face_edge": true,
								"raised_intensity": "shape.raised_lifts.secondary",
								"radius": "shape.secondary_radius", "padding": "shape.primary_padding",
								"mobile_padding": Vector2i(18, 18)},
			"hover_mirrored": {"role": "button_hover", "border_role": "button_border_hover", "raised_face_edge": true,
								"raised_intensity": "shape.raised_lifts.secondary",
								"radius": "shape.secondary_radius", "padding": "shape.primary_padding",
								"mobile_padding": Vector2i(18, 18)},
			"pressed":        {"role": "button_pressed", "border_role": "button_border_pressed",
								"raised_intensity": 0,
								"radius": "shape.secondary_radius", "padding": "shape.primary_padding",
								"mobile_padding": Vector2i(18, 18)},  # pressed sinks; never lifted
			"pressed_mirrored":{"role": "button_pressed", "border_role": "button_border_pressed",
								"raised_intensity": 0,
								"radius": "shape.secondary_radius", "padding": "shape.primary_padding",
								"mobile_padding": Vector2i(18, 18)},
			"focus":          {"role": "focus_ring",
								"radius": "shape.secondary_radius"},
			"disabled":       {"role": "button_disabled", "border_width": 0, "raised_intensity": 0,
								"radius": "shape.secondary_radius", "padding": "shape.primary_padding",
								"mobile_padding": Vector2i(18, 18)},  # Cycle 2 C2: per-direction alpha
			"disabled_mirrored":{"role": "button_disabled", "border_width": 0, "raised_intensity": 0,
								"radius": "shape.secondary_radius", "padding": "shape.primary_padding",
								"mobile_padding": Vector2i(18, 18)},
			"hover_pressed":  {"role": "button_pressed", "border_role": "button_border_pressed",
								"raised_intensity": 0,
								"radius": "shape.secondary_radius", "padding": "shape.primary_padding",
								"mobile_padding": Vector2i(18, 18)},
			"hover_pressed_mirrored":{"role": "button_pressed", "border_role": "button_border_pressed",
								"raised_intensity": 0,
								"radius": "shape.secondary_radius", "padding": "shape.primary_padding",
								"mobile_padding": Vector2i(18, 18)},
		},
		"color": {
			"font_color":              {"role": "text_strong"},
			"font_hover_color":        {"role": "text_strong"},
			"font_pressed_color":      {"role": "text_strong"},
			"font_focus_color":        {"role": "text_strong"},
			"font_disabled_color":     {"role": "text_strong", "disabled": true},  # Cycle 2 C2 fix
			"font_hover_pressed_color":{"role": "text_strong"},
			"icon_normal_color":       {"role": "text_strong"},
			"icon_hover_color":        {"role": "text_strong"},
			"icon_pressed_color":      {"role": "text_strong"},
			"icon_focus_color":        {"role": "text_strong"},
			"icon_disabled_color":     {"role": "text_strong", "disabled": true},  # Cycle 2 C2 fix
			"icon_hover_pressed_color":{"role": "text_strong"},
		},
		"constant": {
			"h_separation": {"value": "tokens.tapPadding"},
		},
	},
	# 3. CheckBox — 4 icon slots (CheckBox alternates as RadioButton in Godot)
	"CheckBox": {
		"stylebox": {
			"normal":         {"role": "surface_panel", "raised_intensity": 0, "alpha": 0.0,
								"border_width": 0, "padding": Vector2i(6, 2), "mobile_padding": Vector2i(12, 14)},
			"normal_mirrored":{"role": "surface_panel", "raised_intensity": 0, "alpha": 0.0,
								"border_width": 0, "padding": Vector2i(6, 2), "mobile_padding": Vector2i(12, 14)},
			"hover":          {"role": "state_hover",   "raised_intensity": 0, "alpha": 0.0,
								"border_width": 0, "padding": Vector2i(6, 2), "mobile_padding": Vector2i(12, 14)},
			"hover_mirrored": {"role": "state_hover",   "raised_intensity": 0, "alpha": 0.0,
								"border_width": 0, "padding": Vector2i(6, 2), "mobile_padding": Vector2i(12, 14)},
			"pressed":        {"role": "state_pressed", "raised_intensity": 0, "alpha": 0.0,
								"border_width": 0, "padding": Vector2i(6, 2), "mobile_padding": Vector2i(12, 14)},
			"pressed_mirrored":{"role": "state_pressed", "raised_intensity": 0, "alpha": 0.0,
								"border_width": 0, "padding": Vector2i(6, 2), "mobile_padding": Vector2i(12, 14)},
			"focus":          {"role": "focus_ring"},
			"disabled":       {"role": "surface_panel", "raised_intensity": 0, "alpha": 0.0,
								"border_width": 0, "padding": Vector2i(6, 2), "mobile_padding": Vector2i(12, 14)},
			"disabled_mirrored":{"role": "surface_panel", "raised_intensity": 0, "alpha": 0.0,
								"border_width": 0, "padding": Vector2i(6, 2), "mobile_padding": Vector2i(12, 14)},
			"hover_pressed":  {"role": "state_pressed", "raised_intensity": 0, "alpha": 0.0,
								"border_width": 0, "padding": Vector2i(6, 2), "mobile_padding": Vector2i(12, 14)},
			"hover_pressed_mirrored":{"role": "state_pressed", "raised_intensity": 0, "alpha": 0.0,
								"border_width": 0, "padding": Vector2i(6, 2), "mobile_padding": Vector2i(12, 14)},
		},
		"color": {
			"font_color":              {"role": "text_strong"},
			"font_hover_color":        {"role": "text_strong"},
			"font_pressed_color":      {"role": "text_strong"},
			"font_focus_color":        {"role": "text_strong"},
			"font_disabled_color":     {"role": "text_strong", "disabled": true},
			"font_hover_pressed_color":{"role": "text_strong"},
			"checkbox_checked_color":  {"role": "role_primary"},
			"checkbox_unchecked_color":{"role": "selection_control_off"},
		},
		"constant": {
			"h_separation": {"value": "tokens.tapPadding"},
			"check_v_offset": {"value": 0},
		},
		"icon": {
			"checked":            {"icon": "checkbox_checked", "mobile_svg_scale": 1.25},
			"unchecked":          {"icon": "checkbox_unchecked", "mobile_svg_scale": 1.25},
			"radio_checked":      {"icon": "radio_checked", "mobile_svg_scale": 1.25},
			"radio_unchecked":    {"icon": "radio_unchecked", "mobile_svg_scale": 1.25},
			# Plan 05-03 Task 2 polish: REUSE the existing checked/unchecked
			# SVGs for the disabled variants (Godot 4.6 exposes the slots; the
			# font_disabled_color tints them through). No new artwork needed.
			"checked_disabled":   {"icon": "checkbox_checked", "mobile_svg_scale": 1.25},
			"unchecked_disabled": {"icon": "checkbox_unchecked", "mobile_svg_scale": 1.25},
			"radio_checked_disabled":   {"icon": "radio_checked", "mobile_svg_scale": 1.25},
			"radio_unchecked_disabled": {"icon": "radio_unchecked", "mobile_svg_scale": 1.25},
		},
	},
	# 4. CheckButton — 2 icon slots (Cycle 6 F4 fix: `checked`/`unchecked`, not `on`/`off`)
	"CheckButton": {
		"stylebox": {
			"normal":         {"role": "surface_panel", "raised_intensity": 0, "alpha": 0.0,
								"border_width": 0, "padding": Vector2i(6, 2), "mobile_padding": Vector2i(12, 14)},
			"normal_mirrored":{"role": "surface_panel", "raised_intensity": 0, "alpha": 0.0,
								"border_width": 0, "padding": Vector2i(6, 2), "mobile_padding": Vector2i(12, 14)},
			"hover":          {"role": "state_hover",   "raised_intensity": 0, "alpha": 0.0,
								"border_width": 0, "padding": Vector2i(6, 2), "mobile_padding": Vector2i(12, 14)},
			"hover_mirrored": {"role": "state_hover",   "raised_intensity": 0, "alpha": 0.0,
								"border_width": 0, "padding": Vector2i(6, 2), "mobile_padding": Vector2i(12, 14)},
			"pressed":        {"role": "state_pressed", "raised_intensity": 0, "alpha": 0.0,
								"border_width": 0, "padding": Vector2i(6, 2), "mobile_padding": Vector2i(12, 14)},
			"pressed_mirrored":{"role": "state_pressed", "raised_intensity": 0, "alpha": 0.0,
								"border_width": 0, "padding": Vector2i(6, 2), "mobile_padding": Vector2i(12, 14)},
			"focus":          {"role": "focus_ring"},
			"disabled":       {"role": "surface_panel", "raised_intensity": 0, "alpha": 0.0,
								"border_width": 0, "padding": Vector2i(6, 2), "mobile_padding": Vector2i(12, 14)},
			"disabled_mirrored":{"role": "surface_panel", "raised_intensity": 0, "alpha": 0.0,
								"border_width": 0, "padding": Vector2i(6, 2), "mobile_padding": Vector2i(12, 14)},
			"hover_pressed":  {"role": "state_pressed", "raised_intensity": 0, "alpha": 0.0,
								"border_width": 0, "padding": Vector2i(6, 2), "mobile_padding": Vector2i(12, 14)},
			"hover_pressed_mirrored":{"role": "state_pressed", "raised_intensity": 0, "alpha": 0.0,
								"border_width": 0, "padding": Vector2i(6, 2), "mobile_padding": Vector2i(12, 14)},
		},
		"color": {
			"font_color":              {"role": "text_strong"},
			"font_hover_color":        {"role": "text_strong"},
			"font_pressed_color":      {"role": "text_strong"},
			"font_focus_color":        {"role": "text_strong"},
			"font_disabled_color":     {"role": "text_strong", "disabled": true},
			"font_hover_pressed_color":{"role": "text_strong"},
			"button_checked_color":    {"role": "role_primary"},
			"button_unchecked_color":  {"role": "selection_control_off"},
		},
		"icon": {
			"checked":            {"icon": "checkbutton_checked", "mobile_svg_scale": 1.5},
			"unchecked":          {"icon": "checkbutton_unchecked", "mobile_svg_scale": 1.5},
			# Reuse existing SVG masks for disabled/mirrored variants; colors are
			# supplied through CheckButton's theme color slots.
			"checked_disabled":   {"icon": "checkbutton_checked", "mobile_svg_scale": 1.5},
			"unchecked_disabled": {"icon": "checkbutton_unchecked", "mobile_svg_scale": 1.5},
			"checked_mirrored":            {"icon": "checkbutton_checked", "mobile_svg_scale": 1.5},
			"unchecked_mirrored":          {"icon": "checkbutton_unchecked", "mobile_svg_scale": 1.5},
			"checked_disabled_mirrored":   {"icon": "checkbutton_checked", "mobile_svg_scale": 1.5},
			"unchecked_disabled_mirrored": {"icon": "checkbutton_unchecked", "mobile_svg_scale": 1.5},
		},
	},
	# 5. CodeEdit — inherits TextEdit; Phase 4 ships base stylebox set + Phase 5
	# Plan 05-05 Task 1 finalizes text chrome (font_readonly_color,
	# font_selected_color) + Task 2 wires gutter colors and the official Godot
	# 4.6 `folded` icon slot. CodeEdit syntax highlighting remains OUT OF SCOPE
	# per FEATURES AF-7 — `assert_codeedit_no_syntax_highlighting` fails if any
	# keyword/function/number/symbol/string/comment slot is AUTHORED here.
	#
	# Gutter color recipe rationale (DESIGN_TOKENS roles):
	#   breakpoint_color           -> role_danger   (red stop indicator)
	#   code_folding_color         -> text_muted    (gutter chrome)
	#   bookmark_color             -> role_warning  (yellow bookmark)
	#   executing_line_color       -> role_primary  (active line = accent)
	#   line_length_guideline_color-> outline_color (subtle column guide)
	#   line_number_color          -> text_muted    (gutter chrome; baseline)
	#
	# Folded icon: CONTEXT D-12 + Godot 4.6 official slot name `folded`. The
	# verifier introspects Theme.get_icon_list("CodeEdit") and asserts `folded`
	# is the slot name; if Godot 4.6 disagreed, Task 2 would abort and replan
	# rather than silently picking a different slot.
	"CodeEdit": {
		"stylebox": {
			"normal":    {"role": "code_background", "border_role": "code_background",
						  "radius": "shape.secondary_radius", "raised_intensity": 0,
						  "border_width": 0,
						  "padding": Vector2i(10, 7)},
			"focus":     {"role": "focus_ring"},
			"read_only": {"role": "button_disabled", "disabled": true,
						  "radius": "shape.secondary_radius", "border_width": 0,
						  "padding": Vector2i(10, 7)},
			"completion": {"role": "code_background", "border_role": "surface_low_edge",
						   "radius": "shape.secondary_radius", "raised_intensity": 0,
						   "border_width": 1, "padding": Vector2i(0, 0)},
		},
		"color": {
			"font_color":            {"role": "text_default"},
			"font_placeholder_color":{"role": "text_muted"},
			"font_readonly_color":   {"role": "text_muted",  "disabled": true},
			"font_selected_color":   {"role": "text_on_accent_offset"},
			"caret_color":           {"role": "role_primary"},
			"selection_color":       {"role": "accent_offset"},
			"current_line_color":    {"role": "code_current_line"},
			"line_number_color":     {"role": "text_muted"},
			"completion_background_color":     {"role": "code_background"},
			"completion_selected_color":       {"role": "button_pressed", "alpha": 0.86},
			"completion_existing_color":       {"role": "button_hover", "alpha": 0.72},
			"completion_scroll_color":         {"role": "text_muted", "alpha": 0.36},
			"completion_scroll_hovered_color": {"role": "text_default", "alpha": 0.50},
			"brace_mismatch_color":            {"role": "role_danger"},
			"word_highlighted_color":          {"role": "role_primary", "alpha": 0.16},
			"search_result_color":             {"role": "role_warning", "alpha": 0.20},
			"search_result_border_color":      {"role": "role_warning", "alpha": 0.64},
			"folded_code_region_color":        {"role": "text_muted", "alpha": 0.36},
			# Plan 05-05 Task 2: gutter color slots (Godot 4.6 official names).
			"breakpoint_color":            {"role": "role_danger"},
			"code_folding_color":          {"role": "text_muted"},
			"bookmark_color":              {"role": "role_warning"},
			"executing_line_color":        {"role": "role_primary"},
			"line_length_guideline_color": {"role": "outline_color"},
		},
		"icon": {
			# Plan 05-05 Task 2: official Godot 4.6 CodeEdit `folded` icon slot.
			# 32x32 monochrome white SVG per Phase 4 D-11 icon contract; `.import`
			# sidecar uses svg/scale=0.5 + mipmaps/generate=true + compress/mode=0
			# + process/fix_alpha_border=true.
			"folded": {"icon": "code_folded"},
		},
		"constant": {
			"completion_lines":        {"value": 7},
			"completion_max_width":    {"value": 50},
			"completion_scroll_width": {"value": 6},
			"line_spacing":            {"value": 4, "mobile_value": 6},
			"outline_size":            {"value": 0},
		},
	},
	# 6. ColorPicker — official Godot 4.6.2 focus chrome, desktop metrics, and icon surface.
	# Engine-rendered hue/SV fields stay engine-owned; NeoCade only binds Theme slots.
	"ColorPicker": {
		"stylebox": {
			"picker_focus_circle":    {"role": "focus_ring", "radius": 999},
			"picker_focus_rectangle": {"role": "focus_ring", "radius": 2},
			"sample_focus":           {"role": "focus_ring",
										"radius": "shape.secondary_radius"},
		},
		"color": {
			"focused_not_editing_cursor_color": {"role": "role_primary"},
		},
		"constant": {
			"center_slider_grabbers": {"value": 1},
			"h_width":                {"value": 24},
			"label_width":            {"value": 64},
			"margin":                 {"value": "tokens.tapPadding"},
			"sv_height":              {"value": 180},
			"sv_width":               {"value": 240},
		},
		"icon": {
			"add_preset":           {"icon": "colorpicker_add_preset"},
			"bar_arrow":            {"icon": "colorpicker_bar_arrow"},
			"color_hue":            {"generated_icon": "color_hue"},
			"color_script":         {"icon": "colorpicker_color_script"},
			"expanded_arrow":       {"icon": "colorpicker_expanded_arrow"},
			"folded_arrow":         {"icon": "colorpicker_folded_arrow"},
			"menu_option":          {"icon": "colorpicker_menu_option"},
			"overbright_indicator": {"icon": "colorpicker_overbright_indicator"},
			"picker_cursor":        {"icon": "colorpicker_picker_cursor"},
			"picker_cursor_bg":     {"icon": "colorpicker_picker_cursor_bg"},
			"sample_bg":            {"icon": "colorpicker_sample_bg"},
			"sample_revert":        {"icon": "colorpicker_sample_revert"},
			"screen_picker":        {"icon": "colorpicker_screen_picker"},
			"shape_circle":         {"icon": "colorpicker_shape_circle"},
			"shape_rect":           {"icon": "colorpicker_shape_rect"},
			"shape_rect_wheel":     {"icon": "colorpicker_shape_rect_wheel"},
		},
	},
	# 7. ColorPickerButton — inherits Button family; Plan 05-03 Task 2 polish: shape.* lookups
	# so the swatch button reads with per-direction radius/padding/lift like Button proper.
	"ColorPickerButton": {
		"stylebox": {
			"normal":   {"role": "button_normal", "border_role": "button_border", "raised_face_edge": true,
							"raised_intensity": "shape.raised_lifts.secondary",
							"radius": "shape.secondary_radius", "padding": Vector2i(1, 1)},
			"hover":    {"role": "button_hover", "border_role": "button_border_hover", "raised_face_edge": true,
							"raised_intensity": "shape.raised_lifts.secondary",
							"radius": "shape.secondary_radius", "padding": Vector2i(1, 1)},
			"pressed":  {"role": "button_pressed", "border_role": "button_border_pressed",
							"raised_intensity": 0,
							"radius": "shape.secondary_radius", "padding": Vector2i(1, 1)},
			"focus":    {"role": "focus_ring",
							"radius": "shape.secondary_radius"},
			"disabled": {"role": "button_disabled", "border_width": 0, "raised_intensity": 0,
							"radius": "shape.secondary_radius", "padding": Vector2i(1, 1)},
		},
		"color": {
			"font_color":          {"role": "text_strong"},
			"font_disabled_color": {"role": "text_strong", "disabled": true},
			"font_focus_color":    {"role": "text_strong"},
			"font_hover_color":    {"role": "text_strong"},
			"font_outline_color":  {"role": "outline_color"},
			"font_pressed_color":  {"role": "text_strong"},
		},
		"constant": {
			"h_separation": {"value": "tokens.tapPadding"},
			"outline_size": {"value": 0},
		},
		"icon": {
			"bg": {"icon": "colorpicker_button_bg"},
		},
	},
	"ColorPresetButton": {
		"stylebox": {
			"preset_fg": {"role": "button_normal", "border_role": "button_border",
						  "raised_intensity": 0, "border_width": 1,
						  "radius": "shape.secondary_radius", "padding": Vector2i(0, 0)},
			"preset_focus": {"role": "focus_ring", "radius": "shape.secondary_radius"},
		},
		"icon": {
			"preset_bg": {"icon": "colorpicker_sample_bg"},
			"overbright_indicator": {"icon": "colorpicker_overbright_indicator"},
		},
	},
	"CheckBoxNoIconTint": {
		"color": {
			"icon_pressed_color": {"role": "text_default"},
			"icon_hover_color": {"role": "text_strong"},
			"icon_hover_pressed_color": {"role": "text_strong"},
		},
	},
	"FlatButtonNoIconTint": {
		"color": {
			"icon_pressed_color": {"role": "text_default"},
			"icon_hover_color": {"role": "text_strong"},
			"icon_hover_pressed_color": {"role": "text_strong"},
		},
	},
	"FlatMenuButtonNoIconTint": {
		"color": {
			"icon_pressed_color": {"role": "text_default"},
			"icon_hover_color": {"role": "text_strong"},
			"icon_hover_pressed_color": {"role": "text_strong"},
		},
	},
	"MainScreenButton": {
		"color": {
			"font_color": {"role": "text_default"},
			"font_hover_color": {"role": "text_strong"},
			"font_pressed_color": {"role": "role_primary"},
			"font_hover_pressed_color": {"role": "role_primary"},
			"icon_normal_color": {"role": "text_default"},
			"icon_hover_color": {"role": "text_strong"},
			"icon_pressed_color": {"role": "role_primary"},
			"icon_hover_pressed_color": {"role": "role_primary"},
		},
	},
	"PreviewLightButton": {
		"color": {
			"icon_normal_color": {"role": "text_muted"},
			"icon_focus_color": {"role": "text_muted"},
			"icon_pressed_color": {"role": "text_default"},
			"icon_hover_pressed_color": {"role": "text_default"},
			"icon_hover_color": {"role": "text_strong"},
		},
	},
	"RunBarButton": {
		"stylebox": {
			"normal": {"role": "surface_panel", "raised_intensity": 0,
					  "alpha": 0.0, "border_width": 0, "radius": "shape.secondary_radius",
					  "content_margins": Vector4i(6, 4, 6, 4),
					  "mobile_padding": Vector2i(16, 16)},
			"normal_mirrored": {"role": "surface_panel", "raised_intensity": 0,
								"alpha": 0.0, "border_width": 0, "radius": "shape.secondary_radius",
								"content_margins": Vector4i(6, 4, 6, 4),
								"mobile_padding": Vector2i(16, 16)},
			"hover": {"role": "button_hover", "border_role": "button_hover",
					  "raised_intensity": 0, "border_width": 0, "alpha": 0.10,
					  "radius": "shape.secondary_radius", "content_margins": Vector4i(6, 4, 6, 4),
					  "mobile_padding": Vector2i(16, 16)},
			"hover_mirrored": {"role": "button_hover", "border_role": "button_hover",
							   "raised_intensity": 0, "border_width": 0, "alpha": 0.10,
							   "radius": "shape.secondary_radius", "content_margins": Vector4i(6, 4, 6, 4),
							   "mobile_padding": Vector2i(16, 16)},
			"pressed": {"role": "surface_panel", "raised_intensity": 0,
						"alpha": 0.0, "border_width": 0, "radius": "shape.secondary_radius",
						"content_margins": Vector4i(6, 4, 6, 4),
						"mobile_padding": Vector2i(16, 16)},
			"pressed_mirrored": {"role": "surface_panel", "raised_intensity": 0,
								 "alpha": 0.0, "border_width": 0, "radius": "shape.secondary_radius",
								 "content_margins": Vector4i(6, 4, 6, 4),
								 "mobile_padding": Vector2i(16, 16)},
			"hover_pressed": {"role": "surface_panel", "raised_intensity": 0,
							  "alpha": 0.0, "border_width": 0, "radius": "shape.secondary_radius",
							  "content_margins": Vector4i(6, 4, 6, 4),
							  "mobile_padding": Vector2i(16, 16)},
			"hover_pressed_mirrored": {"role": "surface_panel", "raised_intensity": 0,
									   "alpha": 0.0, "border_width": 0, "radius": "shape.secondary_radius",
									   "content_margins": Vector4i(6, 4, 6, 4),
									   "mobile_padding": Vector2i(16, 16)},
			"disabled": {"role": "surface_panel", "raised_intensity": 0,
						 "alpha": 0.0, "border_width": 0, "radius": "shape.secondary_radius",
						 "content_margins": Vector4i(6, 4, 6, 4),
						 "mobile_padding": Vector2i(16, 16)},
			"disabled_mirrored": {"role": "surface_panel", "raised_intensity": 0,
								  "alpha": 0.0, "border_width": 0, "radius": "shape.secondary_radius",
								  "content_margins": Vector4i(6, 4, 6, 4),
								  "mobile_padding": Vector2i(16, 16)},
		},
		"color": {
			"font_color": {"role": "text_default"},
			"font_hover_color": {"role": "text_strong"},
			"font_pressed_color": {"role": "role_primary"},
			"font_hover_pressed_color": {"role": "role_primary"},
			"font_disabled_color": {"role": "text_default", "disabled": true},
			"icon_normal_color": {"role": "text_default"},
			"icon_hover_color": {"role": "text_strong"},
			"icon_pressed_color": {"role": "role_primary"},
			"icon_hover_pressed_color": {"role": "role_primary"},
			"icon_disabled_color": {"role": "text_default", "disabled": true},
		},
	},
	"RunBarButtonMovieMakerEnabled": {
		"stylebox": {
			"hover": {"role": "button_hover", "border_role": "button_hover",
					  "raised_intensity": 0, "border_width": 0,
					  "radius": "shape.secondary_radius", "padding": Vector2i(6, 4),
					  "mobile_padding": Vector2i(16, 16)},
			"hover_pressed": {"role": "button_pressed", "border_role": "button_pressed",
							  "raised_intensity": 0, "border_width": 0,
							  "radius": "shape.secondary_radius", "padding": Vector2i(6, 4),
							  "mobile_padding": Vector2i(16, 16)},
		},
		"color": {
			"icon_normal_color": {"role": "text_default"},
			"icon_pressed_color": {"role": "role_primary"},
			"icon_hover_color": {"role": "text_strong"},
			"icon_hover_pressed_color": {"role": "role_primary"},
		},
	},
	"TopBarOptionButton": {
		"stylebox": {
			"normal": {"role": "surface_panel", "raised_intensity": 0,
					   "alpha": 0.0, "border_width": 0, "radius": "shape.secondary_radius",
					   "content_margins": Vector4i(6, 4, 6, 4)},
			"normal_mirrored": {"role": "surface_panel", "raised_intensity": 0,
								"alpha": 0.0, "border_width": 0, "radius": "shape.secondary_radius",
								"content_margins": Vector4i(6, 4, 6, 4)},
			"hover": {"role": "button_hover", "raised_intensity": 0,
					  "alpha": 0.10, "border_width": 0, "radius": "shape.secondary_radius",
					  "content_margins": Vector4i(6, 4, 6, 4)},
			"hover_mirrored": {"role": "button_hover", "raised_intensity": 0,
							   "alpha": 0.10, "border_width": 0, "radius": "shape.secondary_radius",
							   "content_margins": Vector4i(6, 4, 6, 4)},
			"pressed": {"role": "surface_panel", "raised_intensity": 0,
						"alpha": 0.0, "border_width": 0, "radius": "shape.secondary_radius",
						"content_margins": Vector4i(6, 4, 6, 4)},
			"pressed_mirrored": {"role": "surface_panel", "raised_intensity": 0,
								 "alpha": 0.0, "border_width": 0, "radius": "shape.secondary_radius",
								 "content_margins": Vector4i(6, 4, 6, 4)},
			"hover_pressed": {"role": "surface_panel", "raised_intensity": 0,
							  "alpha": 0.0, "border_width": 0, "radius": "shape.secondary_radius",
							  "content_margins": Vector4i(6, 4, 6, 4)},
			"hover_pressed_mirrored": {"role": "surface_panel", "raised_intensity": 0,
									   "alpha": 0.0, "border_width": 0, "radius": "shape.secondary_radius",
									   "content_margins": Vector4i(6, 4, 6, 4)},
		},
	},
	"AnimationBezierTrackEdit": {
		"color": {
			"focus_color": {"role": "role_primary", "alpha": 0.80},
			"track_focus_color": {"role": "text_muted", "alpha": 0.10},
			"h_line_color": {"role": "text_muted", "alpha": 0.12},
			"v_line_color": {"role": "text_muted", "alpha": 0.0},
		},
	},
	"AnimationTimelineEdit": {
		"stylebox": {
			"time_unavailable": {"role": "button_disabled", "border_role": "button_disabled",
								 "raised_intensity": 0, "border_width": 0},
		},
		"color": {
			"v_line_primary_color": {"role": "text_muted", "alpha": 0.40},
			"v_line_secondary_color": {"role": "text_muted", "alpha": 0.08},
			"h_line_color": {"role": "text_muted", "alpha": 0.0},
			"font_primary_color": {"role": "text_default"},
			"font_secondary_color": {"role": "text_muted"},
		},
	},
	# 8. ConfirmationDialog — explicit traceability entry even though Godot exposes no
	# own slots in the local probe; runtime inheritance still reads this shell cleanly.
	"ConfirmationDialog": {
		"stylebox": {
			"panel": {"role": "surface_base", "border_role": "surface_panel_edge",
					  "offset_role": "surface_low_offset", "radius": "shape.secondary_radius",
					  "raised_face_edge": true,
					  "raised_intensity": "shape.raised_lifts.dialog",
					  "padding": Vector2i(12, 10)},
		},
		"constant": {
			"buttons_separation": {"value": "tokens.tapPadding"},
		},
	},
	# 8a. PopupDialog — Godot editor themes style this alongside AcceptDialog.
	"PopupDialog": {
		"stylebox": {
			"panel": {"role": "surface_base", "border_role": "surface_panel_edge",
					  "offset_role": "surface_low_offset", "radius": "shape.secondary_radius",
					  "raised_face_edge": true,
					  "raised_intensity": "shape.raised_lifts.dialog",
					  "padding": Vector2i(12, 10)},
		},
	},
	"EditorSettingsDialog": {
		"stylebox": {
			"panel": {"role": "surface_base", "border_role": "surface_base",
					  "raised_intensity": 0, "border_width": 0,
					  "radius": "shape.secondary_radius", "padding": Vector2i(12, 10)},
		},
	},
	"ProjectSettingsEditor": {
		"stylebox": {
			"panel": {"role": "surface_base", "border_role": "surface_base",
					  "raised_intensity": 0, "border_width": 0,
					  "radius": "shape.secondary_radius", "padding": Vector2i(12, 10)},
		},
	},
	"ProjectExportDialog": {
		"stylebox": {
			"panel": {"role": "surface_base", "border_role": "surface_base",
					  "raised_intensity": 0, "border_width": 0,
					  "radius": "shape.secondary_radius", "padding": Vector2i(12, 10)},
		},
	},
	"SceneImportSettingsDialog": {
		"stylebox": {
			"panel": {"role": "surface_base", "border_role": "surface_base",
					  "raised_intensity": 0, "border_width": 0,
					  "radius": "shape.secondary_radius", "padding": Vector2i(12, 10)},
		},
	},
	"EditorAbout": {
		"stylebox": {
			"panel": {"role": "surface_base", "border_role": "surface_base",
					  "raised_intensity": 0, "border_width": 0,
					  "radius": "shape.secondary_radius", "padding": Vector2i(12, 10)},
		},
	},
	"ThemeItemEditorDialog": {
		"stylebox": {
			"panel": {"role": "surface_base", "border_role": "surface_base",
					  "raised_intensity": 0, "border_width": 0,
					  "radius": "shape.secondary_radius", "padding": Vector2i(12, 10)},
		},
	},
	# 9. FileDialog — official Godot 4.6.2 colors, thumbnail metric, and icon surface.
	# Shell chrome resolves through AcceptDialog/Window; local 4.6.2 exposes no FileDialog
	# stylebox slots, so no unsupported FileDialog.panel entry is written here.
	"FileDialog": {
		"color": {
			"file_disabled_color": {"role": "text_muted",  "disabled": true},
			"file_icon_color":     {"role": "text_default"},
			"folder_icon_color":   {"role": "accent_offset"},
		},
		"constant": {
			"thumbnail_size": {"value": "tokens.thumbnailSize"},
		},
		"icon": {
			"back_folder":            {"icon": "filedialog_back_folder"},
			"clear":                  {"icon": "filedialog_clear"},
			"create_folder":          {"icon": "filedialog_create_folder"},
			"favorite":               {"icon": "filedialog_favorite"},
			"favorite_down":          {"icon": "filedialog_favorite_down"},
			"favorite_up":            {"icon": "filedialog_favorite_up"},
			"file":                   {"icon": "filedialog_file"},
			"file_thumbnail":         {"icon": "filedialog_file_thumbnail"},
			"folder":                 {"icon": "filedialog_folder"},
			"folder_thumbnail":       {"icon": "filedialog_folder_thumbnail"},
			"forward_folder":         {"icon": "filedialog_forward_folder"},
			"list_mode":              {"icon": "filedialog_list_mode"},
			"load":                   {"icon": "filedialog_load"},
			"parent_folder":          {"icon": "filedialog_parent_folder"},
			"reload":                 {"icon": "filedialog_reload"},
			"save":                   {"icon": "filedialog_save"},
			"sort":                   {"icon": "filedialog_sort"},
			"thumbnail_mode":         {"icon": "filedialog_thumbnail_mode"},
			"toggle_filename_filter": {"icon": "filedialog_toggle_filename_filter"},
			"toggle_hidden":          {"icon": "filedialog_toggle_hidden"},
		},
	},
	# 10. FoldableContainer — minimal Phase 4 baseline (Phase 6 polish completes)
	"FoldableContainer": {
		"stylebox": {
			"panel":                       {"role": "surface_panel", "raised_intensity": 0,
											 "mobile_padding": Vector2i(12, 12)},
			"title_panel":                 {"role": "surface_high",  "raised_intensity": 0,
											 "mobile_padding": Vector2i(12, 15)},
			"title_hover_panel":           {"role": "button_hover",  "raised_intensity": 0,
											 "border_width": 0, "mobile_padding": Vector2i(12, 15)},
			"title_collapsed_panel":       {"role": "surface_panel", "raised_intensity": 0,
											 "mobile_padding": Vector2i(12, 15)},
			"title_collapsed_hover_panel": {"role": "button_hover",  "raised_intensity": 0,
											 "border_width": 0, "mobile_padding": Vector2i(12, 15)},
			"focus":                       {"role": "focus_ring"},
		},
		"color": {
			"font_color":           {"role": "text_default"},
			"hover_font_color":     {"role": "text_strong"},
			"collapsed_font_color": {"role": "text_default"},
			"font_outline_color":   {"role": "outline_color"},
		},
		"constant": {
			"h_separation": {"value": 6, "mobile_value": 12},
			"outline_size": {"value": 0},
		},
		"font_size": {
			"font_size": {"value": "tokens.body"},
		},
		"icon": {
			"expanded_arrow":           {"icon": "disclosure_expanded", "mobile_svg_scale": 0.75},
			"expanded_arrow_mirrored":  {"icon": "disclosure_expanded_mirrored", "mobile_svg_scale": 0.75},
			"folded_arrow":             {"icon": "disclosure_collapsed", "mobile_svg_scale": 0.75},
			"folded_arrow_mirrored":    {"icon": "disclosure_collapsed_mirrored", "mobile_svg_scale": 0.75},
		},
	},
	# 11. GraphEdit — basic-v1 graph canvas, toolbar, connection, selection, and focus slots.
	"GraphEdit": {
		"stylebox": {
			"panel":       {"role": "surface_low",   "raised_intensity": 0,
							"radius": "shape.secondary_radius", "padding": Vector2i(0, 0)},
			"menu_panel":  {"role": "surface_panel", "raised_intensity": 0,
							"radius": "shape.secondary_radius", "padding": Vector2i(6, 4)},
			"panel_focus": {"role": "focus_ring",    "radius": "shape.secondary_radius"},
		},
		"color": {
			"activity":                           {"role": "role_primary",  "alpha": 0.95},
			"connection_hover_tint_color":        {"role": "role_primary",  "alpha": 0.88},
			"connection_rim_color":               {"role": "outline_color", "alpha": 0.60},
			"connection_valid_target_tint_color": {"role": "role_success",  "alpha": 0.88},
			"grid_major":                         {"role": "outline_color", "alpha": 0.42},
			"grid_minor":                         {"role": "outline_color", "alpha": 0.18},
			"selection_fill":                     {"role": "role_primary",  "alpha": 0.24},
			"selection_stroke":                   {"role": "role_primary"},
		},
		"constant": {
			"connection_hover_thickness": {"value": 3},
			"port_hotzone_inner_extent":  {"value": 12},
			"port_hotzone_outer_extent":  {"value": 20},
		},
		"icon": {
			"grid_toggle":     {"icon": "graph_grid_toggle"},
			"layout":          {"icon": "graph_layout"},
			"minimap_toggle":  {"icon": "graph_minimap_toggle"},
			"snapping_toggle": {"icon": "graph_snapping_toggle"},
			"zoom_in":         {"icon": "graph_zoom_in"},
			"zoom_out":        {"icon": "graph_zoom_out"},
			"zoom_reset":      {"icon": "graph_zoom_reset"},
		},
	},
	"GraphEditMinimap": {
		"stylebox": {
			"panel": {"role": "code_background", "border_role": "surface_high_edge",
					  "raised_intensity": 0, "alpha": 0.72,
					  "border_alpha": 0.55, "border_width": 1,
					  "radius": "shape.secondary_radius", "padding": Vector2i(4, 4)},
			"node": {"role": "surface_high", "border_role": "surface_high_edge",
					 "raised_intensity": 0, "border_width": 1,
					 "radius": 0, "padding": Vector2i(0, 0)},
		},
		"color": {
			"resizer_color": {"role": "text_muted", "alpha": 0.65},
		},
	},
	"GraphElement": {
		"stylebox": {
			"panel": {"role": "surface_panel", "border_role": "surface_panel_edge",
					  "raised_intensity": 0, "border_width": 1,
					  "radius": "shape.card_radius", "padding": Vector2i(10, 8)},
			"panel_selected": {"role": "surface_high", "border_role": "role_primary",
							   "raised_intensity": 0, "border_width": 1,
							   "radius": "shape.card_radius", "padding": Vector2i(10, 8)},
			"titlebar": {"role": "surface_high", "border_role": "surface_high",
						 "raised_intensity": 0, "border_width": 0,
						 "radius": "shape.card_radius", "padding": Vector2i(10, 4)},
			"titlebar_selected": {"role": "accent_offset", "border_role": "role_primary",
								  "raised_intensity": 0, "border_width": 1,
								  "radius": "shape.card_radius", "padding": Vector2i(10, 4)},
		},
		"color": {
			"resizer_color": {"role": "text_muted", "alpha": 0.85},
		},
	},
	"GraphFrameTitleLabel": {
		"color": {
			"font_color": {"role": "text_strong"},
			"font_outline_color": {"role": "outline_color"},
		},
	},
	"GraphNodeTitleLabel": {
		"color": {
			"font_shadow_color": {"role": "outline_color", "alpha": 0.10},
		},
	},
	"GraphStateMachine": {
		"stylebox": {
			"panel": {"role": "code_background", "border_role": "code_background",
					  "raised_intensity": 0, "border_width": 0, "radius": 0},
			"error_panel": {"role": "role_danger", "border_role": "role_danger",
							"raised_intensity": 0, "alpha": 0.16,
							"border_alpha": 0.55, "border_width": 1,
							"radius": "shape.secondary_radius"},
			"node_frame": {"role": "surface_high", "border_role": "surface_high_edge",
						   "raised_intensity": 0, "border_width": 1,
						   "radius": "shape.secondary_radius", "padding": Vector2i(6, 4)},
			"node_frame_selected": {"role": "surface_high", "border_role": "role_primary",
									"raised_intensity": 0, "border_width": 1,
									"radius": "shape.secondary_radius", "padding": Vector2i(6, 4)},
			"node_frame_start": {"role": "role_success", "border_role": "role_success",
								 "raised_intensity": 0, "alpha": 0.20,
								 "border_alpha": 0.85, "border_width": 1,
								 "radius": "shape.secondary_radius", "padding": Vector2i(6, 4)},
			"node_frame_end": {"role": "role_danger", "border_role": "role_danger",
							   "raised_intensity": 0, "alpha": 0.20,
							   "border_alpha": 0.85, "border_width": 1,
							   "radius": "shape.secondary_radius", "padding": Vector2i(6, 4)},
			"node_frame_playing": {"role": "role_warning", "border_role": "role_warning",
								   "raised_intensity": 0, "alpha": 0.22,
								   "border_alpha": 0.85, "border_width": 1,
								   "radius": "shape.secondary_radius", "padding": Vector2i(6, 4)},
		},
		"color": {
			"focus_color": {"role": "role_primary", "alpha": 0.80},
			"guideline_color": {"role": "text_muted", "alpha": 0.22},
			"highlight_color": {"role": "role_primary"},
			"highlight_disabled_color": {"role": "role_primary", "disabled": true},
			"node_title_font_color": {"role": "text_default"},
			"playback_background_color": {"role": "surface_high", "alpha": 0.22},
			"playback_color": {"role": "text_default"},
			"transition_color": {"role": "text_default"},
			"transition_disabled_color": {"role": "text_muted", "disabled": true},
			"transition_icon_color": {"role": "text_strong"},
			"transition_icon_disabled_color": {"role": "text_muted", "disabled": true},
		},
	},
	# 11a. GraphNode — compact functional graph panel with explicit selected/focus/slot states.
	"GraphNode": {
		"stylebox": {
			"panel":             {"role": "surface_panel", "raised_intensity": 0,
								  "radius": "shape.card_radius", "padding": Vector2i(10, 8)},
			"panel_focus":       {"role": "focus_ring",    "radius": "shape.card_radius"},
			"panel_selected":    {"role": "surface_high",  "raised_intensity": 0,
								  "radius": "shape.card_radius", "padding": Vector2i(10, 8)},
			"slot":              {"role": "surface_low",   "raised_intensity": 0,
								  "radius": 4, "padding": Vector2i(6, 2), "alpha": 0.26},
			"slot_selected":     {"role": "role_primary",  "raised_intensity": 0,
								  "radius": 4, "padding": Vector2i(6, 2), "alpha": 0.30},
			"titlebar":          {"role": "surface_high",  "raised_intensity": 0,
								  "radius": "shape.card_radius", "padding": Vector2i(10, 5)},
			"titlebar_selected": {"role": "accent_offset", "raised_intensity": 0,
								  "radius": "shape.card_radius", "padding": Vector2i(10, 5), "alpha": 0.62},
		},
		"color": {
			"resizer_color": {"role": "text_muted", "alpha": 0.90},
		},
		"constant": {
			"port_h_offset": {"value": 8},
			"separation":    {"value": 4},
		},
		"icon": {
			"port":    {"icon": "graph_port"},
			"resizer": {"icon": "graph_resizer"},
		},
	},
	# 11b. GraphFrame — flat grouping chrome for graph regions, sharing the resizer asset.
	"GraphFrame": {
		"stylebox": {
			"panel":             {"role": "surface_low",   "raised_intensity": 0,
								  "radius": "shape.card_radius", "padding": Vector2i(10, 8), "alpha": 0.28},
			"panel_selected":    {"role": "role_primary",  "raised_intensity": 0,
								  "radius": "shape.card_radius", "padding": Vector2i(10, 8), "alpha": 0.34},
			"titlebar":          {"role": "surface_panel", "raised_intensity": 0,
								  "radius": "shape.card_radius", "padding": Vector2i(10, 4), "alpha": 0.42},
			"titlebar_selected": {"role": "accent_offset", "raised_intensity": 0,
								  "radius": "shape.card_radius", "padding": Vector2i(10, 4), "alpha": 0.46},
		},
		"color": {
			"resizer_color": {"role": "text_muted", "alpha": 0.85},
		},
		"icon": {
			"resizer": {"icon": "graph_resizer"},
		},
	},
	"ProjectList": {
		"stylebox": {
			"hovered": {"role": "button_hover", "border_role": "button_hover",
						"raised_intensity": 0, "border_width": 0,
						"radius": "shape.secondary_radius", "padding": Vector2i(6, 4)},
			"selected": {"role": "button_pressed", "border_role": "button_pressed",
						 "raised_intensity": 0, "border_width": 0,
						 "radius": "shape.secondary_radius", "padding": Vector2i(6, 4)},
			"hover_pressed": {"role": "button_pressed", "border_role": "button_pressed",
							  "raised_intensity": 0, "border_width": 0,
							  "radius": "shape.secondary_radius", "padding": Vector2i(6, 4)},
			"focus": {"role": "focus_ring"},
		},
		"color": {
			"font_color": {"role": "text_default"},
			"guide_color": {"role": "surface_low", "alpha": 0.0},
		},
	},
	"VSRerouteNode": {
		"stylebox": {
			"panel": {"role": "surface_panel", "border_role": "surface_panel_edge",
					  "raised_intensity": 0, "border_width": 1,
					  "radius": "shape.secondary_radius", "padding": Vector2i(6, 4)},
			"panel_selected": {"role": "surface_high", "border_role": "role_primary",
							   "raised_intensity": 0, "border_width": 1,
							   "radius": "shape.secondary_radius", "padding": Vector2i(6, 4)},
			"titlebar": {"role": "surface_high", "raised_intensity": 0,
						 "border_width": 0, "radius": "shape.secondary_radius"},
			"titlebar_selected": {"role": "accent_offset", "raised_intensity": 0,
								  "border_width": 0, "radius": "shape.secondary_radius"},
			"slot": {"empty": true},
		},
		"color": {
			"drag_background": {"role": "surface_low"},
			"selected_rim_color": {"role": "role_primary"},
		},
	},
	# 12. HScrollBar — official styleboxes plus six increment/decrement icon slots.
	"HScrollBar": {
		"stylebox": {
			"scroll":            {"role": "surface_low",   "raised_intensity": 0,
								  "alpha": 0.0, "border_width": 0, "radius": 0,
								  "padding": Vector2i(0, 4), "mobile_padding": Vector2i(0, 3)},
			"scroll_focus":      {"role": "surface_low",   "raised_intensity": 0,
								  "alpha": 0.0, "border_width": 0, "radius": 0,
								  "padding": Vector2i(0, 4), "mobile_padding": Vector2i(0, 3)},
			"grabber":           {"role": "text_muted", "raised_intensity": 0,
								  "alpha": 0.32, "border_width": 0,
								  "radius": "shape.secondary_radius",
								  "padding": Vector2i(4, 4), "mobile_padding": Vector2i(3, 3)},
			"grabber_highlight": {"role": "text_strong", "raised_intensity": 0,
								  "alpha": 0.50, "radius": "shape.secondary_radius",
								  "padding": Vector2i(4, 4), "mobile_padding": Vector2i(3, 3),
								  "border_width": 0},
			"grabber_pressed":   {"role": "text_strong", "raised_intensity": 0,
								  "alpha": 0.50, "radius": "shape.secondary_radius",
								  "padding": Vector2i(4, 4), "mobile_padding": Vector2i(3, 3),
								  "border_width": 0},
		},
		"constant": {
			"padding_top":    {"value": 0},
			"padding_bottom": {"value": 0},
		},
		"icon": {
			"decrement":           {"icon": "empty"},
			"decrement_highlight": {"icon": "empty"},
			"decrement_pressed":   {"icon": "empty"},
			"increment":           {"icon": "empty"},
			"increment_highlight": {"icon": "empty"},
			"increment_pressed":   {"icon": "empty"},
		},
	},
	# 13. HSlider — visible calm track plus official grabber/tick icons.
	"HSlider": {
		"stylebox": {
			"slider":                  {"role": "surface_low",   "raised_intensity": 0, "padding": Vector2i(0, 2),
										 "mobile_padding": Vector2i(0, 4)},
			"grabber_area":            {"role": "role_primary",  "raised_intensity": 0, "padding": Vector2i(0, 2),
										 "mobile_padding": Vector2i(0, 4)},
			"grabber_area_highlight":  {"role": "accent_offset", "raised_intensity": 0, "padding": Vector2i(0, 2),
										 "mobile_padding": Vector2i(0, 4)},
		},
		"constant": {
			"center_grabber": {"value": 1},
			"grabber_offset": {"value": 0},
			"tick_offset":    {"value": 8},
		},
		"icon": {
			"grabber":           {"generated_icon": "slider_grabber"},
			"grabber_disabled":  {"generated_icon": "slider_grabber"},
			"grabber_highlight": {"generated_icon": "slider_grabber", "highlight": true},
			"tick":              {"icon": "slider_tick"},
		},
	},
	# 13a. ScrollContainer — visually empty overflow container plus official focus
	# and hint slots, matching Godot's default and Minimal Theme behavior.
	"ScrollContainer": {
		"stylebox": {
			"focus": {"role": "focus_ring"},
			"panel": {"empty": true},
		},
		"color": {
			"scroll_hint_horizontal_color": {"role": "scroll_shadow"},
			"scroll_hint_vertical_color":   {"role": "scroll_shadow"},
		},
		"icon": {
			"scroll_hint_horizontal": {"icon": "scroll_hint_horizontal"},
			"scroll_hint_vertical":   {"icon": "scroll_hint_vertical"},
		},
	},
	# 13b. SplitContainer — base class owns h/v grabbers and touch-dragger colors.
	"SplitContainer": {
		"stylebox": {
			"split_bar_background": {"empty": true},
		},
		"color": {
			"touch_dragger_color":         {"role": "text_muted"},
			"touch_dragger_hover_color":   {"role": "role_primary", "alpha": 0.84},
			"touch_dragger_pressed_color": {"role": "role_primary"},
		},
		"constant": {
			"autohide":               {"value": 1},
			"minimum_grab_thickness": {"value": 6},
			"separation":             {"value": 6},
		},
		"icon": {
			"h_grabber":       {"generated_icon": "split_grabber", "orientation": "vertical"},
			"h_touch_dragger": {"icon": "split_touch_dragger_h"},
			"v_grabber":       {"generated_icon": "split_grabber", "orientation": "horizontal"},
			"v_touch_dragger": {"icon": "split_touch_dragger_v"},
		},
	},
	# 14. HSplitContainer — split-bar chrome plus official grabber/touch-dragger icons.
	"HSplitContainer": {
		"stylebox": {
			"split_bar_background": {"empty": true},
		},
		"constant": {
			"autohide":               {"value": 1},
			"separation":             {"value": 6},
			"minimum_grab_thickness": {"value": 6},
		},
		"icon": {
			"grabber":       {"generated_icon": "split_grabber", "orientation": "vertical"},
			"touch_dragger": {"icon": "split_touch_dragger_h"},
		},
	},
	# 15. ItemList — official Godot 4.6.2 slots. Cursor overlays stay alpha-bearing
	# because Godot draws them above row content (Phase 6 D-04).
	"ItemList": {
		"stylebox": {
			"panel":                  {"role": "surface_low", "border_role": "surface_low",
									   "raised_intensity": 0, "border_width": 0},
			"focus":                  {"role": "focus_ring"},
			"cursor":                 {"role": "button_hover",  "raised_intensity": 0,
										"alpha": 0.72, "border_width": 0},
			"cursor_unfocused":       {"role": "button_hover",  "raised_intensity": 0,
										"alpha": 0.46, "border_width": 0},
			"hovered":                {"role": "button_hover",  "raised_intensity": 0,
										"border_width": 0},
			# Phase 12 C2' (D-12.06/07): 3px left accent stripe via role_primary border_role.
			"selected":               {"role": "button_pressed", "border_role": "role_primary",
										"raised_intensity": 0,
										"border_widths": Vector4i(3, 0, 0, 0)},
			# Phase 12 C2' (D-12.06/07): 3px left accent stripe (matches ItemList.selected).
			"selected_focus":         {"role": "button_pressed", "border_role": "role_primary",
										"raised_intensity": 0,
										"border_widths": Vector4i(3, 0, 0, 0)},
			"hovered_selected":       {"role": "button_pressed", "border_role": "button_pressed",
										"raised_intensity": 0, "border_width": 0},
			"hovered_selected_focus": {"role": "button_pressed", "border_role": "button_pressed",
										"raised_intensity": 0, "border_width": 0},
		},
		"color": {
			"font_color":                  {"role": "text_default"},
			"font_hovered_color":          {"role": "text_strong"},
			"font_selected_color":         {"role": "role_primary"},
			"font_hovered_selected_color": {"role": "role_primary"},
			"font_outline_color":          {"role": "surface_low", "alpha": 0.0},
			"guide_color":                 {"role": "surface_low", "alpha": 0.0},
			"scroll_hint_color":           {"role": "scroll_shadow"},
		},
		"constant": {
			"v_separation":    {"value": "tokens.tapPadding", "mobile_value": 29},
			"h_separation":    {"value": "tokens.tapPadding"},
			"icon_margin":     {"value": 6},
			"line_separation": {"value": 2},
			"outline_size":    {"value": 0},
		},
		"font_size": {
			"font_size": {"value": "tokens.body"},
		},
		"icon": {
			"scroll_hint": {"icon": "tree_scroll_hint"},
		},
	},
	"ItemListSecondary": {
		"stylebox": {
			"panel": {"role": "surface_low", "border_role": "surface_low",
					  "raised_intensity": 0, "border_width": 0},
			"focus": {"role": "focus_ring"},
			"cursor": {"role": "button_hover", "raised_intensity": 0,
					   "alpha": 0.72, "border_width": 0},
			"cursor_unfocused": {"role": "button_hover", "raised_intensity": 0,
								  "alpha": 0.46, "border_width": 0},
			"hovered": {"role": "button_hover", "raised_intensity": 0,
						"border_width": 0},
			"selected": {"role": "button_pressed", "border_role": "button_pressed",
						 "raised_intensity": 0, "border_width": 0},
			"selected_focus": {"role": "button_pressed", "border_role": "button_pressed",
							   "raised_intensity": 0, "border_width": 0},
			"hovered_selected": {"role": "button_pressed", "border_role": "button_pressed",
								 "raised_intensity": 0, "border_width": 0},
			"hovered_selected_focus": {"role": "button_pressed", "border_role": "button_pressed",
									   "raised_intensity": 0, "border_width": 0},
		},
		"color": {
			"font_color":                  {"role": "text_default"},
			"font_hovered_color":          {"role": "text_strong"},
			"font_selected_color":         {"role": "role_primary"},
			"font_hovered_selected_color": {"role": "role_primary"},
			"font_outline_color":          {"role": "surface_low", "alpha": 0.0},
			"guide_color":                 {"role": "surface_low", "alpha": 0.0},
			"scroll_hint_color":           {"role": "scroll_shadow"},
		},
		"constant": {
			"v_separation":    {"value": "tokens.tapPadding", "mobile_value": 29},
			"h_separation":    {"value": "tokens.tapPadding"},
			"icon_margin":     {"value": 6},
			"line_separation": {"value": 2},
			"outline_size":    {"value": 0},
		},
		"icon": {
			"scroll_hint": {"icon": "tree_scroll_hint"},
		},
	},
	# 16. Label — text-only chrome; focus is an outline overlay, never a filled panel.
	"Label": {
		"stylebox": {
			"normal": {"empty": true},
			"focus": {"role": "focus_ring"},
		},
		"color": {
			"font_color": {"role": "text_strong"},
		},
	},
	# 17. LineEdit — 3 stylebox + caret + selection + clear icon
	"LineEdit": {
		"stylebox": {
			"normal":    {"role": "button_normal", "border_role": "button_border",
						  "radius": "shape.secondary_radius", "raised_intensity": 0,
						  "padding": Vector2i(10, 6), "mobile_padding": Vector2i(15, 14)},
			"focus":     {"role": "focus_ring"},
			"read_only": {"role": "button_disabled", "disabled": true,
						  "radius": "shape.secondary_radius", "border_width": 0,
						  "padding": Vector2i(10, 6), "mobile_padding": Vector2i(15, 14)},
		},
		"color": {
			"font_color":            {"role": "text_default"},
			"font_placeholder_color":{"role": "text_muted"},
			"font_uneditable_color": {"role": "text_muted",  "disabled": true},
			"font_selected_color":   {"role": "text_on_accent_offset"},
			"caret_color":           {"role": "role_primary"},
			"selection_color":       {"role": "accent_offset"},
			"clear_button_color":    {"role": "text_muted"},
			"clear_button_color_pressed": {"role": "text_strong"},
		},
		"icon": {
			"clear": {"icon": "clear", "mobile_svg_scale": 0.75},
		},
	},
	# 18. LinkButton — colors only; no styleboxes (TextButton variant)
	"LinkButton": {
		"color": {
			"font_color":              {"role": "role_primary"},
			"font_hover_color":        {"role": "accent_rim"},
			"font_pressed_color":      {"role": "role_primary"},
			"font_focus_color":        {"role": "role_primary"},
			"font_disabled_color":     {"role": "role_primary", "disabled": true},
			"font_hover_pressed_color":{"role": "accent_rim"},
		},
		"constant": {
			"underline_spacing": {"value": 2},
		},
	},
	# 19. MenuBar — low-emphasis menu triggers with complete official colors/metrics.
	"MenuBar": {
		"stylebox": {
			"normal":   {"role": "surface_base", "raised_intensity": 0, "alpha": 0.0,
						 "radius": "shape.secondary_radius", "padding": Vector2i(8, 3),
						 "mobile_padding": Vector2i(14, 14)},
			"hover":    {"role": "button_hover", "raised_intensity": 0,
						 "radius": "shape.secondary_radius", "padding": Vector2i(8, 3),
						 "mobile_padding": Vector2i(14, 14), "border_width": 0},
			"pressed":  {"role": "button_pressed", "raised_intensity": 0,
						 "radius": "shape.secondary_radius", "padding": Vector2i(8, 3),
						 "mobile_padding": Vector2i(14, 14), "border_width": 0},
			"disabled": {"role": "surface_base", "disabled": true, "raised_intensity": 0,
						 "radius": "shape.secondary_radius", "padding": Vector2i(8, 3),
						 "mobile_padding": Vector2i(14, 14)},
		},
		"color": {
			"font_color":               {"role": "text_default"},
			"font_hover_color":         {"role": "text_strong"},
			"font_pressed_color":       {"role": "text_strong"},
			"font_focus_color":         {"role": "role_primary"},
			"font_hover_pressed_color": {"role": "text_strong"},
			"font_outline_color":       {"role": "outline_color"},
			"font_disabled_color":      {"role": "text_default", "disabled": true},
		},
		"constant": {
			"h_separation": {"value": 4},
			"outline_size": {"value": 0},
		},
	},
	# 20. MenuButton — Button-family states
	# Plan 05-03 Task 2 polish: shape.secondary_radius + shape.primary_padding +
	# shape.raised_lifts.secondary so the per-direction shape language flows.
	"MenuButton": {
		"stylebox": {
			"normal":         {"role": "button_normal", "border_role": "button_border", "raised_face_edge": true,
								"raised_intensity": "shape.raised_lifts.secondary",
								"radius": "shape.secondary_radius", "padding": Vector2i(10, 5), "mobile_padding": Vector2i(15, 14)},
			"hover":          {"role": "button_hover", "border_role": "button_border_hover", "raised_face_edge": true,
								"raised_intensity": "shape.raised_lifts.secondary",
								"radius": "shape.secondary_radius", "padding": Vector2i(10, 5), "mobile_padding": Vector2i(15, 14)},
			"pressed":        {"role": "button_pressed", "border_role": "button_border_pressed",
								"raised_intensity": 0,
								"radius": "shape.secondary_radius", "padding": Vector2i(10, 5), "mobile_padding": Vector2i(15, 14)},
			"focus":          {"role": "focus_ring",
								"radius": "shape.secondary_radius"},
			"disabled":       {"role": "button_disabled", "border_width": 0,
								"radius": "shape.secondary_radius", "padding": Vector2i(10, 5), "mobile_padding": Vector2i(15, 14)},
			"hover_pressed":  {"role": "button_pressed", "border_role": "button_border_pressed", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "padding": Vector2i(10, 5), "mobile_padding": Vector2i(15, 14)},
		},
		"color": {
			"font_color":          {"role": "text_strong"},
			"font_hover_color":    {"role": "text_strong"},
			"font_pressed_color":  {"role": "text_strong"},
			"font_focus_color":    {"role": "text_strong"},
			"font_disabled_color": {"role": "text_strong", "disabled": true},
		},
		"constant": {
			"h_separation": {"value": "tokens.tapPadding"},
		},
	},
	# 21. OptionButton — 6 stylebox + arrow icon + arrow_margin constant.
	# Editor inspector dropdowns use this control heavily, so keep its content padding
	# tighter than game CTA buttons while sharing the same button-state colors.
	"OptionButton": {
		"stylebox": {
			"normal":         {"role": "button_normal", "border_role": "button_border", "raised_face_edge": true,
								"raised_intensity": "shape.raised_lifts.secondary",
								"radius": "shape.secondary_radius", "padding": Vector2i(8, 4), "mobile_padding": Vector2i(14, 16)},
			"hover":          {"role": "button_hover", "border_role": "button_border_hover", "raised_face_edge": true,
								"raised_intensity": "shape.raised_lifts.secondary",
								"radius": "shape.secondary_radius", "padding": Vector2i(8, 4), "mobile_padding": Vector2i(14, 16)},
			"pressed":        {"role": "button_pressed", "border_role": "button_border_pressed",
								"raised_intensity": 0,
								"radius": "shape.secondary_radius", "padding": Vector2i(8, 4), "mobile_padding": Vector2i(14, 16)},
			"focus":          {"role": "focus_ring",
								"radius": "shape.secondary_radius"},
			"disabled":       {"role": "button_disabled", "border_width": 0,
								"radius": "shape.secondary_radius", "padding": Vector2i(8, 4), "mobile_padding": Vector2i(14, 16)},
			"hover_pressed":  {"role": "button_pressed", "border_role": "button_border_pressed", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "padding": Vector2i(8, 4), "mobile_padding": Vector2i(14, 16)},
		},
		"color": {
			"font_color":          {"role": "text_strong"},
			"font_hover_color":    {"role": "text_strong"},
			"font_pressed_color":  {"role": "text_strong"},
			"font_focus_color":    {"role": "text_strong"},
			"font_disabled_color": {"role": "text_strong", "disabled": true},
		},
		"constant": {
			"arrow_margin":  {"value": 6},
			"h_separation": {"value": 4},
		},
		"icon": {
			"arrow": {"icon": "arrow_down"},
		},
	},
	# 22. Panel — 1 stylebox (the bare-class)
	"Panel": {
		"stylebox": {
			"panel": {"role": "surface_panel", "border_role": "surface_panel_edge",
					  "raised_intensity": "shape.raised_lifts.panel", "raised_face_edge": true},
		},
	},
	# 23. PopupMenu — dense menu rows, structural separators, full icon coverage.
	"PopupMenu": {
		"stylebox": {
			"panel":                 {"role": "button_normal", "border_role": "button_border",
									  "offset_role": "button_normal_offset",
									  "raised_intensity": "shape.raised_lifts.dialog",
									  "radius": "shape.secondary_radius",
									  "raised_face_edge": true, "border_width": 1, "padding": Vector2i(0, 0)},
			"hover":                 {"role": "button_hover",   "raised_intensity": 0,
									  "border_role": "button_border_hover",
									  "radius": "shape.secondary_radius", "border_width": 0},
			"separator":             {"role": "outline_color",  "raised_intensity": 0, "alpha": 0.55,
									  "padding": Vector2i(0, 0)},
			"labeled_separator_left":{"role": "outline_color",  "raised_intensity": 0, "alpha": 0.55,
									  "padding": Vector2i(0, 0)},
			"labeled_separator_right":{"role": "outline_color", "raised_intensity": 0, "alpha": 0.55,
									  "padding": Vector2i(0, 0)},
		},
		"color": {
			"font_color":            {"role": "text_default"},
			"font_hover_color":      {"role": "text_strong"},
			"font_disabled_color":   {"role": "text_default", "disabled": true},
			"font_outline_color":    {"role": "outline_color"},
			"font_separator_color":  {"role": "text_muted"},
			"font_separator_outline_color":{"role": "outline_color"},
			"font_accelerator_color":{"role": "text_muted"},
		},
		"constant": {
			"gutter_compact":         {"value": 1},
			"h_separation":           {"value": 6},
			"icon_max_width":         {"value": 18, "mobile_value": 40},
			"indent":                 {"value": 16},
			"item_end_padding":       {"value": 8},
			"item_start_padding":     {"value": 8},
			"outline_size":           {"value": 0},
			"search_bar_separation":  {"value": 4, "mobile_value": 29},
			"separator_outline_size": {"value": 0},
			"v_separation":           {"value": 4, "mobile_value": 29},
		},
		"icon": {
			"checked":                  {"generated_icon": "popup_selection_checkbox", "checked": true, "mobile_svg_scale": 1.25},
			"checked_disabled":         {"generated_icon": "popup_selection_checkbox", "checked": true, "disabled": true, "mobile_svg_scale": 1.25},
			"unchecked":                {"generated_icon": "popup_selection_checkbox", "checked": false, "mobile_svg_scale": 1.25},
			"unchecked_disabled":       {"generated_icon": "popup_selection_checkbox", "checked": false, "disabled": true, "mobile_svg_scale": 1.25},
			"radio_checked":            {"generated_icon": "popup_selection_radio", "checked": true, "mobile_svg_scale": 1.25},
			"radio_checked_disabled":   {"generated_icon": "popup_selection_radio", "checked": true, "disabled": true, "mobile_svg_scale": 1.25},
			"radio_unchecked":          {"generated_icon": "popup_selection_radio", "checked": false, "mobile_svg_scale": 1.25},
			"radio_unchecked_disabled": {"generated_icon": "popup_selection_radio", "checked": false, "disabled": true, "mobile_svg_scale": 1.25},
			"submenu":                  {"icon": "popup_submenu"},
			"submenu_mirrored":         {"icon": "popup_submenu_mirrored"},
			"search":                   {"generated_icon": "search", "mobile_svg_scale": 1.0},
		},
	},
	# 24. PopupPanel — first-class popup Window-boundary shell.
	"PopupPanel": {
		"stylebox": {
			"panel": {"role": "button_normal", "border_role": "button_border",
					  "offset_role": "button_normal_offset",
					  "raised_intensity": "shape.raised_lifts.dialog",
					  "radius": "shape.secondary_radius",
					  "raised_face_edge": true, "padding": Vector2i(8, 6)},
		},
	},
	# 25. ProgressBar — 2 styleboxes
	"ProgressBar": {
		"stylebox": {
			"background": {"role": "surface_low",  "raised_intensity": 0, "padding": Vector2i(0, 0)},
			"fill":       {"role": "role_primary", "raised_intensity": 0, "padding": Vector2i(0, 0)},
		},
		"color": {
			"font_color":         {"role": "progress_text_color"},
			"font_outline_color": {"role": "progress_text_outline"},
		},
		"constant": {
			"outline_size": {"value": 4},
		},
		"font_size": {
			"font_size": {"value": "tokens.body"},
		},
	},
	"PopupProgressBar": {
		"stylebox": {
			"background": {"role": "surface_low",  "raised_intensity": 0,
						   "border_width": 0, "padding": Vector2i(0, 0)},
			"fill":       {"role": "role_primary", "raised_intensity": 0,
						   "border_width": 0, "padding": Vector2i(0, 0)},
		},
		"color": {
			"font_color":         {"role": "progress_text_color"},
			"font_outline_color": {"role": "progress_text_outline"},
		},
		"constant": {
			"outline_size": {"value": 4},
		},
	},
	# 26. RichTextLabel — text-only, matching Label visually: no background or border.
	"RichTextLabel": {
		"stylebox": {
			"normal": {"role": "surface_base", "raised_intensity": 0, "alpha": 0.0,
					   "border_width": 0, "padding": Vector2i(0, 0)},
			"focus":  {"role": "surface_base", "raised_intensity": 0, "alpha": 0.0,
					   "border_width": 0, "padding": Vector2i(0, 0)},
		},
		"color": {
			"default_color":    {"role": "text_default"},
			"selection_color":  {"role": "accent_offset"},
			"font_selected_color": {"role": "text_on_accent_offset"},
		},
	},
	"EditorHelpBitTitle": {
		"stylebox": {
			"normal": {"role": "surface_low", "border_role": "surface_low_edge",
					   "raised_intensity": 0, "border_width": 0,
					   "radius": "shape.secondary_radius", "corner_profile": "top_only",
					   "padding": Vector2i(8, 4)},
		},
	},
	"EditorHelpBitContent": {
		"stylebox": {
			"normal": {"role": "surface_low", "border_role": "surface_low_edge",
					   "raised_intensity": 0, "border_width": 0,
					   "radius": "shape.secondary_radius", "corner_profile": "bottom_only",
					   "padding": Vector2i(8, 4)},
		},
	},
	"EditorHelpBitTooltipTitle": {
		"stylebox": {
			"normal": {"role": "button_normal", "border_role": "button_border",
					   "raised_intensity": 0, "border_width": 0,
					   "radius": 0, "padding": Vector2i(8, 4)},
		},
	},
	"EditorHelpBitTooltipContent": {
		"stylebox": {
			"normal": {"role": "button_normal", "border_role": "button_border",
					   "raised_intensity": 0, "border_width": 0,
					   "radius": 0, "padding": Vector2i(8, 4)},
		},
	},
	# 27. SpinBox — inherits LineEdit; Phase 4 ships button separation constants;
	# Plan 05-06 Task 2 wires the four official Godot 4.6 icon slots
	# (`up` / `up_disabled` / `down` / `down_disabled`). NOT `up_arrow` /
	# `down_arrow` (legacy names from earlier Godot — verifier explicitly
	# forbids those). Disabled variants REUSE the base SVG (Wave 3 CheckBox
	# `disabled_icon` reuse pattern); Godot tints them through the
	# disabled state at draw time so two SVGs cover all four slots.
	"SpinBox": {
		"color": {
			"up_icon_modulate":          {"role": "text_default"},
			"up_hover_icon_modulate":    {"role": "text_strong"},
			"up_pressed_icon_modulate":  {"role": "text_strong"},
			"up_disabled_icon_modulate": {"role": "text_muted", "disabled": true},
			"down_icon_modulate":          {"role": "text_default"},
			"down_hover_icon_modulate":    {"role": "text_strong"},
			"down_pressed_icon_modulate":  {"role": "text_strong"},
			"down_disabled_icon_modulate": {"role": "text_muted", "disabled": true},
		},
		"stylebox": {
			"up_background_hovered":   {"role": "button_hover", "border_role": "button_hover",
										"raised_intensity": 0, "border_width": 0,
										"radius": "shape.secondary_radius"},
			"up_background_pressed":   {"role": "button_pressed", "border_role": "button_pressed",
										"raised_intensity": 0, "border_width": 0,
										"radius": "shape.secondary_radius"},
			"down_background_hovered": {"role": "button_hover", "border_role": "button_hover",
										"raised_intensity": 0, "border_width": 0,
										"radius": "shape.secondary_radius"},
			"down_background_pressed": {"role": "button_pressed", "border_role": "button_pressed",
										"raised_intensity": 0, "border_width": 0,
										"radius": "shape.secondary_radius"},
		},
		"constant": {
			"buttons_vertical_separation": {"value": 2},
			"buttons_width":                {"value": 16, "mobile_value": 24},
			"field_and_buttons_separation":{"value": 4},
		},
		"icon": {
			"up":           {"icon": "spinbox_up"},
			"up_disabled":  {"icon": "spinbox_up"},
			"down":         {"icon": "spinbox_down"},
			"down_disabled":{"icon": "spinbox_down"},
			# Keep the legacy composite slot empty so SpinBox draws the separate
			# up/down icons centered inside their own half-buttons.
			"updown":          {"icon": "empty"},
			"updown_disabled": {"icon": "empty"},
		},
	},
	# 28. TabBar — official Godot 4.6.2 tab strip slots. Shared tab state
	# recipes intentionally mirror TabContainer for every overlapping tab_* stylebox
	# (D-08); overflow button slots are compact icon-button surfaces, not primary buttons.
	"TabBar": {
		"stylebox": {
			"button_highlight": {"role": "button_hover", "border_role": "button_border_hover",
									"raised_intensity": 0, "border_width": 0,
									"radius": "shape.secondary_radius", "padding": Vector2i(4, 4), "mobile_padding": Vector2i(8, 14)},
			"button_pressed":   {"role": "button_pressed", "border_role": "button_border_pressed",
									"raised_intensity": 0, "border_width": 0,
									"radius": "shape.secondary_radius", "padding": Vector2i(4, 4), "mobile_padding": Vector2i(8, 14)},
			# Phase 12 C2' (D-12.06/07): 2px top accent stripe via role_primary border_role.
			# Vector4i layout = (left, top, right, bottom) per _resolve_recipe lines 5386-5389.
			"tab_selected":     {"role": "button_pressed", "border_role": "role_primary",
									"raised_intensity": 0,
									"border_widths": Vector4i(0, 2, 0, 0),
									"radius": "shape.tab_radius", "corner_profile": "tab_connected",
									"padding": Vector2i(12, 6), "mobile_padding": Vector2i(18, 14)},
			"tab_unselected":   {"role": "button_normal", "border_role": "button_border",
									"raised_intensity": 0, "border_width": 0,
									"radius": "shape.tab_radius", "corner_profile": "tab_connected",
									"padding": Vector2i(12, 5), "mobile_padding": Vector2i(18, 14)},
			"tab_hovered":      {"role": "button_hover", "border_role": "button_border_hover",
									"raised_intensity": 0, "border_width": 0,
									"radius": "shape.tab_radius", "corner_profile": "tab_connected",
									"padding": Vector2i(12, 5), "mobile_padding": Vector2i(18, 14)},
			"tab_disabled":     {"role": "button_disabled", "disabled": true, "border_width": 0,
									"raised_intensity": 0,
									"radius": "shape.tab_radius", "corner_profile": "tab_connected",
									"padding": Vector2i(12, 5), "mobile_padding": Vector2i(18, 14)},
			"tab_focus":        {"role": "focus_ring", "radius": "shape.tab_radius",
									"corner_profile": "tab_connected"},
		},
		"color": {
			"font_selected_color":   {"role": "text_strong"},
			"font_unselected_color": {"role": "text_muted"},
			"font_hovered_color":    {"role": "text_strong"},
			"font_outline_color":    {"role": "outline_color"},
			"font_disabled_color":   {"role": "text_muted", "disabled": true},
			"icon_selected_color":   {"role": "text_strong"},
			"icon_unselected_color": {"role": "text_muted"},
			"icon_hovered_color":    {"role": "text_strong"},
			"icon_disabled_color":   {"role": "text_muted", "disabled": true},
			"drop_mark_color":       {"role": "role_primary"},
		},
		"constant": {
			"h_separation":           {"value": 2},
			"hover_switch_wait_msec": {"value": 180},
			"icon_max_width":         {"value": 0},
			"outline_size":           {"value": 0},
		},
		"font_size": {
			"font_size": {"value": "tokens.body"},
		},
		"icon": {
			"close":               {"icon": "close"},
			"increment":           {"icon": "tab_increment", "mobile_svg_scale": 0.75},
			"increment_highlight": {"icon": "tab_increment", "mobile_svg_scale": 0.75},
			"decrement":           {"icon": "tab_decrement", "mobile_svg_scale": 0.75},
			"decrement_highlight": {"icon": "tab_decrement", "mobile_svg_scale": 0.75},
			"drop_mark":           {"icon": "tab_drop_mark"},
		},
	},
	# 29. TabContainer — shared TabBar tab_* recipes plus content panel and menu icons.
	"TabContainer": {
		"stylebox": {
			# Phase 12 C2' (D-12.06/07): 2px top accent stripe (matches TabBar tab_selected idiom).
			"tab_selected":     {"role": "button_pressed", "border_role": "role_primary",
									"raised_intensity": 0,
									"border_widths": Vector4i(0, 2, 0, 0),
									"radius": "shape.tab_radius", "corner_profile": "tab_connected",
									"padding": Vector2i(12, 6), "mobile_padding": Vector2i(18, 14)},
			"tab_unselected":   {"role": "button_normal", "border_role": "button_border",
									"raised_intensity": 0, "border_width": 0,
									"radius": "shape.tab_radius", "corner_profile": "tab_connected",
									"padding": Vector2i(12, 5), "mobile_padding": Vector2i(18, 14)},
			"tab_hovered":      {"role": "button_hover", "border_role": "button_border_hover",
									"raised_intensity": 0, "border_width": 0,
									"radius": "shape.tab_radius", "corner_profile": "tab_connected",
									"padding": Vector2i(12, 5), "mobile_padding": Vector2i(18, 14)},
			"tab_disabled":     {"role": "button_disabled", "disabled": true, "border_width": 0,
									"raised_intensity": 0,
									"radius": "shape.tab_radius", "corner_profile": "tab_connected",
									"padding": Vector2i(12, 5), "mobile_padding": Vector2i(18, 14)},
			"tab_focus":        {"role": "focus_ring", "radius": "shape.tab_radius",
									"corner_profile": "tab_connected"},
			"panel":            {"role": "surface_panel", "border_role": "surface_panel_edge",
								  "raised_intensity": "shape.raised_lifts.panel", "raised_face_edge": true},
			"tabbar_background":{"role": "surface_base",  "raised_intensity": 0,
								  "border_width": 0, "radius": 0, "padding": Vector2i(0, 0)},
		},
		"color": {
			"font_selected_color":   {"role": "text_strong"},
			"font_unselected_color": {"role": "text_muted"},
			"font_hovered_color":    {"role": "text_strong"},
			"font_outline_color":    {"role": "outline_color"},
			"font_disabled_color":   {"role": "text_muted", "disabled": true},
			"icon_selected_color":   {"role": "text_strong"},
			"icon_unselected_color": {"role": "text_muted"},
			"icon_hovered_color":    {"role": "text_strong"},
			"icon_disabled_color":   {"role": "text_muted", "disabled": true},
			"drop_mark_color":       {"role": "role_primary"},
		},
		"constant": {
			"icon_max_width":   {"value": 0},
			"icon_separation":  {"value": 6},
			"outline_size":     {"value": 0},
			"side_margin":      {"value": 0},
			"tab_separation":   {"value": 0},
		},
		"font_size": {
			"font_size": {"value": "tokens.body"},
		},
		"icon": {
			"increment":           {"icon": "tab_increment", "mobile_svg_scale": 0.75},
			"increment_highlight": {"icon": "tab_increment", "mobile_svg_scale": 0.75},
			"decrement":           {"icon": "tab_decrement", "mobile_svg_scale": 0.75},
			"decrement_highlight": {"icon": "tab_decrement", "mobile_svg_scale": 0.75},
			"drop_mark":           {"icon": "tab_drop_mark"},
			"menu":                {"icon": "tab_menu"},
			"menu_highlight":      {"icon": "tab_menu"},
		},
	},
	"TabContainerOdd": {
		"stylebox": {
			"tab_selected":     {"role": "button_pressed", "border_role": "button_border_pressed",
									"raised_intensity": 0, "border_width": 0,
									"radius": "shape.tab_radius", "corner_profile": "tab_connected",
									"padding": Vector2i(12, 6)},
			"tab_unselected":   {"role": "button_normal", "border_role": "button_border",
									"raised_intensity": 0, "border_width": 0,
									"radius": "shape.tab_radius", "corner_profile": "tab_connected",
									"padding": Vector2i(12, 5)},
			"tab_hovered":      {"role": "button_hover", "border_role": "button_border_hover",
									"raised_intensity": 0, "border_width": 0,
									"radius": "shape.tab_radius", "corner_profile": "tab_connected",
									"padding": Vector2i(12, 5)},
			"tab_disabled":     {"role": "button_disabled", "disabled": true, "border_width": 0,
									"raised_intensity": 0,
									"radius": "shape.tab_radius", "corner_profile": "tab_connected",
									"padding": Vector2i(12, 5)},
			"tab_focus":        {"role": "focus_ring", "radius": "shape.tab_radius",
									"corner_profile": "tab_connected"},
			"panel":            {"role": "surface_base", "border_role": "surface_base",
								  "raised_intensity": 0, "border_width": 0},
			"tabbar_background":{"role": "surface_base", "raised_intensity": 0,
								  "border_width": 0, "radius": 0, "padding": Vector2i(0, 0)},
		},
		"color": {
			"font_selected_color":   {"role": "text_strong"},
			"font_unselected_color": {"role": "text_muted"},
			"font_hovered_color":    {"role": "text_strong"},
			"font_outline_color":    {"role": "outline_color"},
			"font_disabled_color":   {"role": "text_muted", "disabled": true},
			"icon_selected_color":   {"role": "text_strong"},
			"icon_unselected_color": {"role": "text_muted"},
			"icon_hovered_color":    {"role": "text_strong"},
			"icon_disabled_color":   {"role": "text_muted", "disabled": true},
			"drop_mark_color":       {"role": "role_primary"},
		},
		"constant": {
			"icon_max_width":   {"value": 0},
			"icon_separation":  {"value": 6},
			"outline_size":     {"value": 0},
			"side_margin":      {"value": 0},
			"tab_separation":   {"value": 0},
		},
		"font_size": {
			"font_size": {"value": "tokens.body"},
		},
		"icon": {
			"increment":           {"icon": "tab_increment", "mobile_svg_scale": 0.75},
			"increment_highlight": {"icon": "tab_increment", "mobile_svg_scale": 0.75},
			"decrement":           {"icon": "tab_decrement", "mobile_svg_scale": 0.75},
			"decrement_highlight": {"icon": "tab_decrement", "mobile_svg_scale": 0.75},
			"drop_mark":           {"icon": "tab_drop_mark"},
			"menu":                {"icon": "tab_menu"},
			"menu_highlight":      {"icon": "tab_menu"},
		},
	},
	"TabContainerInner": {
		"stylebox": {
			"tab_selected":     {"role": "button_pressed", "border_role": "button_pressed",
								 "raised_intensity": 0, "border_width": 0,
								 "radius": "shape.tab_radius", "corner_profile": "tab_connected",
								 "padding": Vector2i(10, 5), "mobile_padding": Vector2i(14, 14)},
			"tab_unselected":   {"role": "surface_base", "border_role": "surface_base",
								 "raised_intensity": 0, "border_width": 0,
								 "radius": "shape.tab_radius", "corner_profile": "tab_connected",
								 "padding": Vector2i(10, 4), "mobile_padding": Vector2i(14, 14)},
			"tab_hovered":      {"role": "button_hover", "border_role": "button_hover",
								 "raised_intensity": 0, "border_width": 0,
								 "radius": "shape.tab_radius", "corner_profile": "tab_connected",
								 "padding": Vector2i(10, 4), "mobile_padding": Vector2i(14, 14)},
			"tab_disabled":     {"role": "button_disabled", "disabled": true,
								 "raised_intensity": 0, "border_width": 0,
								 "radius": "shape.tab_radius", "corner_profile": "tab_connected",
								 "padding": Vector2i(10, 4), "mobile_padding": Vector2i(14, 14)},
			"tab_focus":        {"role": "focus_ring", "radius": "shape.tab_radius",
								 "corner_profile": "tab_connected"},
			"panel":            {"role": "surface_base", "border_role": "surface_base",
								  "raised_intensity": 0, "border_width": 0},
			"tabbar_background":{"role": "surface_base", "raised_intensity": 0,
								  "border_width": 0, "radius": 0, "padding": Vector2i(0, 0)},
		},
	},
	"TabBarInner": {
		"stylebox": {
			"tab_selected":   {"role": "button_pressed", "border_role": "button_pressed",
							   "raised_intensity": 0, "border_width": 0,
							   "radius": "shape.tab_radius", "corner_profile": "tab_connected",
							   "padding": Vector2i(10, 5), "mobile_padding": Vector2i(14, 14)},
			"tab_unselected": {"role": "surface_base", "border_role": "surface_base",
							   "raised_intensity": 0, "border_width": 0,
							   "radius": "shape.tab_radius", "corner_profile": "tab_connected",
							   "padding": Vector2i(10, 4), "mobile_padding": Vector2i(14, 14)},
			"tab_hovered":    {"role": "button_hover", "border_role": "button_hover",
							   "raised_intensity": 0, "border_width": 0,
							   "radius": "shape.tab_radius", "corner_profile": "tab_connected",
							   "padding": Vector2i(10, 4), "mobile_padding": Vector2i(14, 14)},
			"tab_disabled":   {"role": "button_disabled", "disabled": true,
							   "raised_intensity": 0, "border_width": 0,
							   "radius": "shape.tab_radius", "corner_profile": "tab_connected",
							   "padding": Vector2i(10, 4), "mobile_padding": Vector2i(14, 14)},
			"tab_focus":      {"role": "focus_ring", "radius": "shape.tab_radius",
							   "corner_profile": "tab_connected"},
		},
	},
	"BottomPanel": {
		"stylebox": {
			"tab_selected":     {"role": "button_pressed", "border_role": "button_border_pressed",
									"raised_intensity": 0, "border_width": 0,
									"radius": "shape.tab_radius", "corner_profile": "bottom_only",
									"padding": Vector2i(12, 6)},
			"tab_unselected":   {"role": "surface_base", "border_role": "surface_base",
									"raised_intensity": 0, "border_width": 0,
									"radius": "shape.tab_radius", "corner_profile": "bottom_only",
									"padding": Vector2i(12, 5)},
			"tab_hovered":      {"role": "button_hover", "border_role": "button_border_hover",
									"raised_intensity": 0, "border_width": 0,
									"radius": "shape.tab_radius", "corner_profile": "bottom_only",
									"padding": Vector2i(12, 5)},
			"tab_focus":        {"role": "focus_ring", "radius": "shape.tab_radius",
									"corner_profile": "bottom_only"},
			"panel":            {"role": "surface_panel", "border_role": "surface_panel_edge",
								  "raised_intensity": "shape.raised_lifts.panel",
								  "raised_face_edge": true, "content_margins": Vector4i(0, 0, 0, 0)},
			"tabbar_background":{"role": "surface_base", "raised_intensity": 0,
								  "border_width": 0, "radius": 0, "content_margins": Vector4i(4, 2, 4, 0)},
		},
		"color": {
			"font_selected_color":   {"role": "text_strong"},
			"font_unselected_color": {"role": "text_default"},
			"font_hovered_color":    {"role": "text_strong"},
			"icon_hover_color":      {"role": "text_strong"},
			"icon_hover_pressed_color": {"role": "role_primary"},
		},
		"constant": {
			"tab_separation": {"value": 0},
			"side_margin": {"value": 0},
			"outline_size": {"value": 0},
		},
	},
	"EditorStyles": {
		"stylebox": {
			"Background": {"role": "surface_base", "border_role": "surface_base",
						   "raised_intensity": 0, "border_width": 0},
			"BottomPanel": {"role": "surface_panel", "border_role": "surface_panel_edge",
							"raised_intensity": "shape.raised_lifts.panel",
							"raised_face_edge": true, "content_margins": Vector4i(0, 0, 0, 0)},
			"Content": {"role": "surface_base", "border_role": "surface_base",
						"raised_intensity": 0, "border_width": 0},
			"ContextualToolbar": {"role": "surface_overlay", "border_role": "surface_overlay",
								  "raised_intensity": 0, "border_width": 0},
			"DebuggerPanel": {"role": "surface_panel", "border_role": "surface_panel_edge",
							  "raised_intensity": 0, "border_width": 1,
							  "content_margins": Vector4i(6, 5, 6, 5)},
			"Focus": {"role": "focus_ring"},
			"FocusViewport": {"role": "focus_ring", "radius": 0},
			"Information3dViewport": {"role": "surface_panel", "border_role": "surface_panel_edge",
									  "raised_intensity": 0, "border_width": 1,
									  "alpha": 0.88, "padding": Vector2i(6, 4)},
			"LaunchPadMovieMode": {"role": "role_primary", "border_role": "role_primary",
								   "raised_intensity": 0, "alpha": 0.20,
								   "border_alpha": 0.70, "border_width": 1},
			"LaunchPadRecoveryMode": {"role": "role_warning", "border_role": "role_warning",
									  "raised_intensity": 0, "alpha": 0.16,
									  "border_alpha": 0.70, "border_width": 1},
			"MovieWriterButtonNormal": {"role": "surface_panel", "raised_intensity": 0,
										"alpha": 0.0, "border_width": 0,
										"radius": "shape.secondary_radius", "padding": Vector2i(0, 0)},
			"MovieWriterButtonPressed": {"role": "role_primary", "border_role": "role_primary",
										 "raised_intensity": 0, "alpha": 0.80,
										 "border_width": 0, "radius": "shape.secondary_radius",
										 "padding": Vector2i(0, 0)},
			"ObjectDBContentWrapper": {"role": "surface_low", "border_role": "surface_low_edge",
									   "raised_intensity": 0, "border_width": 0,
									   "radius": "shape.secondary_radius", "padding": Vector2i(8, 6)},
			"ObjectDBTitle": {"role": "surface_high", "border_role": "surface_high_edge",
							  "raised_intensity": 0, "border_width": 0,
							  "radius": "shape.secondary_radius", "padding": Vector2i(6, 4)},
			"PanelForeground": {"role": "surface_panel", "border_role": "surface_panel_edge",
								"raised_intensity": 0, "border_width": 0},
			"RecoveryModeButton": {"role": "role_warning", "border_role": "role_warning",
								   "raised_intensity": 0, "alpha": 0.18,
								   "border_alpha": 0.70, "border_width": 1,
								   "radius": "shape.secondary_radius", "padding": Vector2i(8, 4)},
			"TextureRegionPreviewBG": {"role": "code_background", "border_role": "surface_high_edge",
									   "raised_intensity": 0, "alpha": 0.72,
									   "border_alpha": 0.55, "border_width": 1},
			"ThemeEditorPreviewBG": {"role": "code_background", "border_role": "code_background",
									 "raised_intensity": 0, "border_width": 0},
			"ThemeEditorPreviewFG": {"role": "surface_panel", "border_role": "surface_panel_edge",
									 "raised_intensity": 0, "border_width": 0},
			"sub_inspector_property_bg1": {"role": "button_normal", "border_role": "button_border",
										   "raised_intensity": 0, "border_width": 0},
			"sub_inspector_property_bg9": {"role": "button_normal", "border_role": "button_border",
										   "raised_intensity": 0, "border_width": 0},
			"DictionaryAddItem1": {"role": "button_normal", "border_role": "button_border", "raised_intensity": 0, "border_width": 0},
			"DictionaryAddItem2": {"role": "button_normal", "border_role": "button_border", "raised_intensity": 0, "border_width": 0},
			"DictionaryAddItem3": {"role": "button_normal", "border_role": "button_border", "raised_intensity": 0, "border_width": 0},
			"DictionaryAddItem4": {"role": "button_normal", "border_role": "button_border", "raised_intensity": 0, "border_width": 0},
			"DictionaryAddItem5": {"role": "button_normal", "border_role": "button_border", "raised_intensity": 0, "border_width": 0},
			"DictionaryAddItem6": {"role": "button_normal", "border_role": "button_border", "raised_intensity": 0, "border_width": 0},
			"DictionaryAddItem7": {"role": "button_normal", "border_role": "button_border", "raised_intensity": 0, "border_width": 0},
			"DictionaryAddItem8": {"role": "button_normal", "border_role": "button_border", "raised_intensity": 0, "border_width": 0},
			"DictionaryAddItem9": {"role": "button_normal", "border_role": "button_border", "raised_intensity": 0, "border_width": 0},
			"DictionaryAddItem10": {"role": "button_normal", "border_role": "button_border", "raised_intensity": 0, "border_width": 0},
			"DictionaryAddItem11": {"role": "button_normal", "border_role": "button_border", "raised_intensity": 0, "border_width": 0},
			"DictionaryAddItem12": {"role": "button_normal", "border_role": "button_border", "raised_intensity": 0, "border_width": 0},
			"DictionaryAddItem13": {"role": "button_normal", "border_role": "button_border", "raised_intensity": 0, "border_width": 0},
			"DictionaryAddItem14": {"role": "button_normal", "border_role": "button_border", "raised_intensity": 0, "border_width": 0},
			"DictionaryAddItem15": {"role": "button_normal", "border_role": "button_border", "raised_intensity": 0, "border_width": 0},
			"DictionaryAddItem16": {"role": "button_normal", "border_role": "button_border", "raised_intensity": 0, "border_width": 0},
			"sub_inspector_bg1": {"role": "surface_high", "border_role": "surface_high_edge", "raised_intensity": 0, "border_width": 1},
			"sub_inspector_bg2": {"role": "surface_high", "border_role": "surface_high_edge", "raised_intensity": 0, "border_width": 1},
			"sub_inspector_bg3": {"role": "surface_high", "border_role": "surface_high_edge", "raised_intensity": 0, "border_width": 1},
			"sub_inspector_bg4": {"role": "surface_high", "border_role": "surface_high_edge", "raised_intensity": 0, "border_width": 1},
			"sub_inspector_bg5": {"role": "surface_high", "border_role": "surface_high_edge", "raised_intensity": 0, "border_width": 1},
			"sub_inspector_bg6": {"role": "surface_high", "border_role": "surface_high_edge", "raised_intensity": 0, "border_width": 1},
			"sub_inspector_bg7": {"role": "surface_high", "border_role": "surface_high_edge", "raised_intensity": 0, "border_width": 1},
			"sub_inspector_bg8": {"role": "surface_high", "border_role": "surface_high_edge", "raised_intensity": 0, "border_width": 1},
			"sub_inspector_bg9": {"role": "surface_high", "border_role": "surface_high_edge", "raised_intensity": 0, "border_width": 1},
			"sub_inspector_bg10": {"role": "surface_high", "border_role": "surface_high_edge", "raised_intensity": 0, "border_width": 1},
			"sub_inspector_bg11": {"role": "surface_high", "border_role": "surface_high_edge", "raised_intensity": 0, "border_width": 1},
			"sub_inspector_bg12": {"role": "surface_high", "border_role": "surface_high_edge", "raised_intensity": 0, "border_width": 1},
			"sub_inspector_bg13": {"role": "surface_high", "border_role": "surface_high_edge", "raised_intensity": 0, "border_width": 1},
			"sub_inspector_bg14": {"role": "surface_high", "border_role": "surface_high_edge", "raised_intensity": 0, "border_width": 1},
			"sub_inspector_bg15": {"role": "surface_high", "border_role": "surface_high_edge", "raised_intensity": 0, "border_width": 1},
			"sub_inspector_bg16": {"role": "surface_high", "border_role": "surface_high_edge", "raised_intensity": 0, "border_width": 1},
		},
		"color": {
			"sub_inspector_property_color": {"role": "text_default"},
		},
	},
	"PanelForeground": {
		"stylebox": {
			"panel": {"role": "surface_panel", "border_role": "surface_panel_edge",
					  "raised_intensity": 0, "border_width": 0},
		},
	},
	"EditorInspectorForeground": {
		"stylebox": {
			"panel": {"role": "surface_panel", "border_role": "surface_panel_edge",
					  "raised_intensity": 0, "border_width": 0},
		},
	},
	"ProjectManager": {
		"stylebox": {
			"panel_container": {"role": "surface_panel", "border_role": "surface_panel_edge",
								"raised_intensity": 0, "border_width": 0},
			"project_list": {"role": "surface_low", "border_role": "surface_low_edge",
							 "raised_intensity": 0, "border_width": 0},
			"quick_settings_panel": {"role": "surface_panel", "border_role": "surface_panel_edge",
									 "raised_intensity": 0, "border_width": 0},
		},
	},
	"AssetLib": {
		"stylebox": {
			"panel": {"role": "surface_panel", "border_role": "surface_panel_edge",
					  "raised_intensity": 0, "border_width": 0},
			"downloads": {"role": "surface_panel", "border_role": "surface_panel_edge",
						  "raised_intensity": 0, "border_width": 0},
		},
	},
	"ThemeEditor": {
		"stylebox": {
			"preview_picker_label": {"role": "surface_panel", "border_role": "surface_panel_edge",
									 "raised_intensity": 0, "border_width": 0,
									 "radius": "shape.secondary_radius", "padding": Vector2i(6, 4)},
			"preview_picker_overlay": {"role": "surface_overlay", "border_role": "role_primary",
									   "raised_intensity": 0, "alpha": 0.26,
									   "border_alpha": 0.70, "border_width": 1},
		},
	},
	"TileSetEditor": {
		"stylebox": {
			"expand_panel": {"role": "surface_panel", "border_role": "surface_panel_edge",
							 "raised_intensity": 0, "border_width": 0},
		},
	},
	"EditorInspectorArray": {
		"color": {
			"bg": {"role": "surface_base"},
		},
	},
	"AnimationTrackEdit": {
		"stylebox": {
			"focus": {"role": "focus_ring"},
			"hover": {"role": "button_hover", "border_role": "button_hover",
					  "raised_intensity": 0, "border_width": 0},
			"odd": {"role": "surface_base", "border_role": "surface_base",
					"raised_intensity": 0, "border_width": 0},
		},
	},
	"AnimationTrackEditGroup": {
		"stylebox": {
			"header": {"role": "surface_high", "border_role": "surface_high",
					   "raised_intensity": 0, "border_width": 0},
			"hover": {"role": "button_hover", "border_role": "button_hover",
					  "raised_intensity": 0, "border_width": 0},
		},
		"color": {
			"bg_color": {"role": "surface_base"},
		},
	},
	"EditorAudioBus": {
		"stylebox": {
			"focus": {"role": "focus_ring"},
			"normal": {"role": "surface_panel", "border_role": "surface_panel_edge",
					   "raised_intensity": 0, "border_width": 1},
			"master": {"role": "surface_high", "border_role": "surface_high_edge",
					   "raised_intensity": 0, "border_width": 1},
		},
	},
	"EditorAudioBusEffectsTree": {
		"stylebox": {
			"panel": {"role": "surface_panel", "border_role": "surface_panel_edge",
					  "raised_intensity": 0, "border_width": 0},
		},
		"constant": {
			"h_separation": {"value": 0},
		},
	},
	"EditorDebuggerInspector": {
		"stylebox": {
			"panel": {"role": "surface_panel", "border_role": "surface_panel_edge",
					  "raised_intensity": 0, "border_width": 0},
		},
	},
	"EditorInspector": {
		"stylebox": {
			"panel": {"role": "surface_panel", "border_role": "surface_panel_edge",
					  "raised_intensity": 0, "border_width": 0},
		},
	},
	"EditorInspectorFlatButton": {
		"stylebox": {
			"normal": {"role": "surface_panel", "raised_intensity": 0,
					  "alpha": 0.0, "border_width": 0, "radius": "shape.secondary_radius",
					  "content_margins": Vector4i(6, 4, 6, 4),
					  "mobile_padding": Vector2i(16, 16)},
			"hover": {"role": "button_hover", "raised_intensity": 0,
					  "radius": "shape.secondary_radius",
					  "content_margins": Vector4i(6, 4, 6, 4),
					  "mobile_padding": Vector2i(16, 16), "border_width": 0},
			"pressed": {"role": "button_pressed", "raised_intensity": 0,
						"radius": "shape.secondary_radius",
						"content_margins": Vector4i(6, 4, 6, 4),
						"mobile_padding": Vector2i(16, 16), "border_width": 0},
			"hover_pressed": {"role": "button_pressed", "raised_intensity": 0,
							  "radius": "shape.secondary_radius",
							  "content_margins": Vector4i(6, 4, 6, 4),
							  "mobile_padding": Vector2i(16, 16), "border_width": 0},
			"disabled": {"role": "surface_panel", "raised_intensity": 0,
						 "alpha": 0.0, "border_width": 0, "radius": "shape.secondary_radius",
						 "content_margins": Vector4i(6, 4, 6, 4),
						 "mobile_padding": Vector2i(16, 16)},
		},
	},
	"EditorValidationPanel": {
		"stylebox": {
			"panel": {"role": "surface_panel", "border_role": "surface_panel_edge",
					  "raised_intensity": 0, "border_width": 0},
		},
	},
	"GamePanel": {
		"stylebox": {
			"panel": {"role": "surface_base", "border_role": "surface_base",
					  "raised_intensity": 0, "border_width": 0},
		},
	},
	"PanelContainerTabbarInner": {
		"stylebox": {
			"panel": {"role": "surface_base", "border_role": "surface_base",
					  "raised_intensity": 0, "border_width": 0},
		},
	},
	"ScrollContainerSecondary": {
		"stylebox": {
			"panel": {"role": "surface_panel", "border_role": "surface_panel",
					  "raised_intensity": 0, "border_width": 0},
		},
	},
	"TreeLineEdit": {
		"stylebox": {
			"normal": {"role": "button_normal", "border_role": "button_border",
					   "raised_intensity": 0, "border_width": 0,
					   "radius": "shape.secondary_radius", "padding": Vector2i(8, 4)},
			"focus": {"role": "focus_ring"},
		},
	},
	# 29a. Editor dock tab containers — FileSystem/Scene/Inspector docks are DockTabContainer
	# subclasses, not authored scenes with themeable toolbar panels. Godot's FileSystemDock
	# builds a VBoxContainer with HBoxContainer toolbar rows; those containers cannot draw a
	# stylebox, so the dock panel must own the inset while painting the background underneath.
	"DockTabContainer": {
		"stylebox": {
			"panel": {"role": "surface_panel", "border_role": "surface_panel_edge",
					  "raised_intensity": "shape.raised_lifts.panel", "raised_face_edge": true,
					  "content_margins": Vector4i(6, 5, 6, 5)},
			"tabbar_background": {"role": "surface_base", "raised_intensity": 0,
					  "border_width": 0, "radius": 0, "content_margins": Vector4i(4, 2, 4, 0)},
		},
	},
	"SideDockTabContainer": {
		"stylebox": {
			"panel": {"role": "surface_panel", "border_role": "surface_panel_edge",
					  "raised_intensity": "shape.raised_lifts.panel", "raised_face_edge": true,
					  "content_margins": Vector4i(6, 5, 6, 5)},
			"tabbar_background": {"role": "surface_base", "raised_intensity": 0,
					  "border_width": 0, "radius": 0, "content_margins": Vector4i(4, 2, 4, 0)},
		},
	},
	"BottomSideDockTabContainer": {
		"stylebox": {
			"panel": {"role": "surface_panel", "border_role": "surface_panel_edge",
					  "raised_intensity": "shape.raised_lifts.panel", "raised_face_edge": true,
					  "content_margins": Vector4i(6, 5, 6, 5)},
			"tabbar_background": {"role": "surface_base", "raised_intensity": 0,
					  "border_width": 0, "radius": 0, "content_margins": Vector4i(4, 2, 4, 0)},
		},
	},
	# 30. TextEdit — 3 stylebox set
	"TextEdit": {
		"stylebox": {
			"normal":    {"role": "button_normal", "border_role": "button_border",
						  "radius": "shape.secondary_radius", "raised_intensity": 0,
						  "padding": Vector2i(10, 7)},
			"focus":     {"role": "focus_ring"},
			"read_only": {"role": "button_disabled", "disabled": true,
						  "radius": "shape.secondary_radius", "border_width": 0,
						  "padding": Vector2i(10, 7)},
		},
		"color": {
			"font_color":            {"role": "text_default"},
			"font_placeholder_color":{"role": "text_muted"},
			"font_readonly_color":   {"role": "text_muted",  "disabled": true},
			"font_selected_color":   {"role": "text_on_accent_offset"},
			"caret_color":           {"role": "role_primary"},
			"selection_color":       {"role": "accent_offset"},
			"current_line_color":    {"role": "surface_panel"},
		},
	},
	# 31. TooltipLabel — readable tooltip text with no offset shadow.
	"TooltipLabel": {
		"color": {
			"font_color":         {"role": "text_strong"},
			"font_outline_color": {"role": "outline_color"},
			"font_shadow_color":  {"role": "surface_base", "alpha": 0.0},
		},
		"constant": {
			"outline_size":    {"value": 0},
			"shadow_offset_x": {"value": 0},
			"shadow_offset_y": {"value": 0},
		},
	},
	# 32. TooltipPanel — compact first-class tooltip structure.
	"TooltipPanel": {
		"stylebox": {
			"panel": {"role": "button_normal", "border_role": "button_border",
					  "offset_role": "button_normal_offset",
					  "raised_intensity": "shape.raised_lifts.dialog",
					  "radius": "shape.secondary_radius",
					  "raised_face_edge": true, "border_width": 1, "padding": Vector2i(4, 2),
					  "mobile_padding": Vector2i(8, 6)},
		},
	},
	# 33. Tree — official Godot 4.6.2 styleboxes per CANONICAL_SLOT_NAMES.
	"Tree": {
		"stylebox": {
			"panel":                  {"role": "button_normal", "border_role": "button_border",
										"raised_intensity": 0, "border_width": 1},
			"focus":                  {"role": "focus_ring"},
			"title_button_normal":    {"role": "button_normal", "border_role": "button_normal",
										"raised_intensity": 0, "border_width": 0},
			"title_button_pressed":   {"role": "button_pressed", "raised_intensity": 0,
										"border_role": "button_pressed", "border_width": 0},
			"title_button_hover":     {"role": "button_hover",   "raised_intensity": 0,
										"border_role": "button_hover", "border_width": 0},
			"button_hover":           {"role": "button_hover",   "raised_intensity": 0,
										"border_role": "button_hover", "border_width": 0,
										"content_margins": Vector4i(6, 0, 6, 0)},
			"button_pressed":         {"role": "button_pressed", "raised_intensity": 0,
										"border_role": "button_pressed", "border_width": 0,
										"content_margins": Vector4i(6, 0, 6, 0)},
			"custom_button":          {"role": "button_normal", "border_role": "button_normal",
										"raised_intensity": 0, "border_width": 0,
										"content_margins": Vector4i(6, 0, 6, 0)},
			"hovered":                {"role": "button_hover",  "raised_intensity": 0,
										"border_role": "button_hover", "border_width": 0},
			"hovered_dimmed":         {"role": "button_hover",  "raised_intensity": 0,
										"border_role": "button_hover", "alpha": 0.55, "border_width": 0},
			# Phase 12 C2' (D-12.06/07): 3px left accent stripe (matches ItemList.selected idiom).
			"selected":               {"role": "button_pressed", "raised_intensity": 0,
										"border_role": "role_primary",
										"border_widths": Vector4i(3, 0, 0, 0)},
			# Phase 12 C2' (D-12.06/07): 3px left accent stripe.
			"selected_focus":         {"role": "button_pressed", "raised_intensity": 0,
										"border_role": "role_primary",
										"border_widths": Vector4i(3, 0, 0, 0)},
			"hovered_selected":       {"role": "button_pressed", "raised_intensity": 0,
										"border_role": "button_pressed", "border_width": 0},
			"hovered_selected_focus": {"role": "button_pressed", "raised_intensity": 0,
										"border_role": "button_pressed", "border_width": 0},
			"custom_button_hover":    {"role": "button_hover",  "raised_intensity": 0,
										"border_role": "button_hover", "border_width": 0,
										"content_margins": Vector4i(6, 0, 6, 0)},
			"custom_button_pressed":  {"role": "button_pressed", "raised_intensity": 0,
										"border_role": "button_pressed", "border_width": 0,
										"content_margins": Vector4i(6, 0, 6, 0)},
			"cursor":                 {"role": "button_hover",  "raised_intensity": 0,
										"border_role": "button_hover", "alpha": 0.72, "border_width": 0},
			"cursor_unfocused":       {"role": "button_hover",  "raised_intensity": 0,
										"border_role": "button_hover", "alpha": 0.46, "border_width": 0},
		},
		"color": {
			"children_hl_line_color":      {"role": "text_muted", "alpha": 0.34},
			"custom_button_font_highlight":{"role": "role_primary"},
			"drop_position_color":         {"role": "role_primary"},
			"font_color":                  {"role": "text_default"},
			"font_disabled_color":         {"role": "text_default", "disabled": true},
			"font_hovered_color":          {"role": "text_strong"},
			"font_hovered_dimmed_color":   {"role": "text_muted"},
			"font_hovered_selected_color": {"role": "role_primary"},
			"font_outline_color":          {"role": "outline_color"},
			"font_selected_color":         {"role": "role_primary"},
			"guide_color":                 {"role": "surface_low", "alpha": 0.0},
			"parent_hl_line_color":        {"role": "text_muted", "alpha": 0.58},
			"relationship_line_color":     {"role": "text_muted", "alpha": 0.28},
			"scroll_hint_color":           {"role": "scroll_shadow"},
			"title_button_color":          {"role": "text_strong"},
		},
		"constant": {
			"button_margin":             {"value": 4},
			"check_h_separation":        {"value": 6},
			"children_hl_line_width":    {"value": 1},
			"dragging_unfold_wait_msec": {"value": 1000},
			"draw_guides":               {"value": 0},
			"draw_relationship_lines":   {"value": 1},
			"h_separation":              {"value": 8},
			"icon_h_separation":         {"value": 6},
			"icon_max_width":            {"value": 0},
			"inner_item_margin_bottom":  {"value": 2},
			"inner_item_margin_left":    {"value": 4},
			"inner_item_margin_right":   {"value": 4},
			"inner_item_margin_top":     {"value": 2},
			"item_margin":               {"value": 18},
			"outline_size":              {"value": 0},
			"parent_hl_line_margin":     {"value": 3},
			"parent_hl_line_width":      {"value": 1},
			"relationship_line_width":   {"value": 0},
			"scroll_border":             {"value": 18},
			"scroll_speed":              {"value": 12},
			"scrollbar_h_separation":    {"value": 4},
			"scrollbar_margin_bottom":   {"value": 0},
			"scrollbar_margin_left":     {"value": 0},
			"scrollbar_margin_right":    {"value": 0},
			"scrollbar_margin_top":      {"value": 0},
			"scrollbar_v_separation":    {"value": 4},
			"v_separation":              {"value": 2, "mobile_value": 29},
		},
		"font_size": {
			"font_size":              {"value": "tokens.body"},
			"title_button_font_size": {"value": "tokens.body"},
		},
		"icon": {
			"arrow":                     {"icon": "disclosure_expanded"},
			"arrow_collapsed":           {"icon": "disclosure_collapsed"},
			"arrow_collapsed_mirrored":  {"icon": "disclosure_collapsed_mirrored"},
			"checked":                   {"icon": "checkbox_checked"},
			"checked_disabled":          {"icon": "checkbox_checked"},
			"indeterminate":             {"icon": "tree_indeterminate"},
			"indeterminate_disabled":    {"icon": "tree_indeterminate"},
			"scroll_hint":               {"icon": "tree_scroll_hint"},
			"select_arrow":              {"icon": "tree_select_arrow"},
			"unchecked":                 {"icon": "checkbox_unchecked"},
			"unchecked_disabled":        {"icon": "checkbox_unchecked"},
			"updown":                    {"icon": "tree_updown"},
		},
	},
	"TreeSecondary": {
		"stylebox": {
			"panel":               {"role": "button_normal", "border_role": "button_border",
									"raised_intensity": 0, "border_width": 1},
			"title_button_normal": {"role": "surface_panel", "border_role": "surface_panel",
									"raised_intensity": 0, "border_width": 0},
			"title_button_hover":  {"role": "button_hover", "border_role": "button_hover",
									"raised_intensity": 0, "border_width": 0},
			"title_button_pressed":{"role": "button_pressed", "border_role": "button_pressed",
									"raised_intensity": 0, "border_width": 0},
		},
	},
	"TreeTable": {
		"stylebox": {
			"panel": {"role": "button_normal", "border_role": "button_border",
					  "raised_intensity": 0, "border_width": 1},
			"button_hover": {"role": "button_hover", "border_role": "button_hover",
							 "raised_intensity": 0, "border_widths": Vector4i(1, 0, 1, 0),
							 "border_alpha": 0.0, "content_margins": Vector4i(4, 0, 4, 0)},
			"button_pressed": {"role": "button_pressed", "border_role": "button_pressed",
							   "raised_intensity": 0, "border_widths": Vector4i(1, 0, 1, 0),
							   "border_alpha": 0.0, "content_margins": Vector4i(4, 0, 4, 0)},
			"custom_button_hover": {"role": "button_hover", "border_role": "button_hover",
									"raised_intensity": 0, "border_widths": Vector4i(1, 0, 1, 0),
									"border_alpha": 0.0, "content_margins": Vector4i(4, 0, 4, 0)},
			"custom_button_pressed": {"role": "button_pressed", "border_role": "button_pressed",
									  "raised_intensity": 0, "border_widths": Vector4i(1, 0, 1, 0),
									  "border_alpha": 0.0, "content_margins": Vector4i(4, 0, 4, 0)},
			"hovered": {"role": "button_hover", "border_role": "button_hover",
						"raised_intensity": 0, "border_width": 0},
			"hovered_dimmed": {"role": "button_hover", "border_role": "button_hover",
							   "raised_intensity": 0, "alpha": 0.55, "border_width": 0},
			"selected": {"role": "button_pressed", "border_role": "button_pressed",
						 "raised_intensity": 0, "border_width": 0},
			"hovered_selected": {"role": "button_pressed", "border_role": "button_pressed",
								 "raised_intensity": 0, "border_width": 0},
			"title_button_normal": {"role": "surface_panel", "border_role": "surface_panel",
									"raised_intensity": 0, "border_width": 0},
			"title_button_hover":  {"role": "button_hover", "border_role": "button_hover",
									"raised_intensity": 0, "border_width": 0},
			"title_button_pressed":{"role": "button_pressed", "border_role": "button_pressed",
									"raised_intensity": 0, "border_width": 0},
		},
		"color": {
			"title_button_color": {"role": "text_strong"},
		},
		"constant": {
			"button_margin": {"value": 0},
			"h_separation": {"value": 0},
			"inner_item_margin_bottom": {"value": 4},
			"inner_item_margin_left": {"value": 12},
			"inner_item_margin_right": {"value": 12},
			"inner_item_margin_top": {"value": 4},
			"item_margin": {"value": 16},
		},
	},
	# 34. VScrollBar — mirror of HScrollBar with vertical directional icons.
	"VScrollBar": {
		"stylebox": {
			"scroll":            {"role": "surface_low",   "raised_intensity": 0,
								  "alpha": 0.0, "border_width": 0, "radius": 0,
								  "padding": Vector2i(4, 0), "mobile_padding": Vector2i(3, 0)},
			"scroll_focus":      {"role": "surface_low",   "raised_intensity": 0,
								  "alpha": 0.0, "border_width": 0, "radius": 0,
								  "padding": Vector2i(4, 0), "mobile_padding": Vector2i(3, 0)},
			"grabber":           {"role": "text_muted", "raised_intensity": 0,
								  "alpha": 0.32, "border_width": 0,
								  "radius": "shape.secondary_radius",
								  "padding": Vector2i(4, 4), "mobile_padding": Vector2i(3, 3)},
			"grabber_highlight": {"role": "text_strong", "raised_intensity": 0,
								  "alpha": 0.50, "radius": "shape.secondary_radius",
								  "padding": Vector2i(4, 4), "mobile_padding": Vector2i(3, 3),
								  "border_width": 0},
			"grabber_pressed":   {"role": "text_strong", "raised_intensity": 0,
								  "alpha": 0.50, "radius": "shape.secondary_radius",
								  "padding": Vector2i(4, 4), "mobile_padding": Vector2i(3, 3),
								  "border_width": 0},
		},
		"constant": {
			"padding_left":  {"value": 0},
			"padding_right": {"value": 0},
		},
		"icon": {
			"decrement":           {"icon": "empty"},
			"decrement_highlight": {"icon": "empty"},
			"decrement_pressed":   {"icon": "empty"},
			"increment":           {"icon": "empty"},
			"increment_highlight": {"icon": "empty"},
			"increment_pressed":   {"icon": "empty"},
		},
	},
	# 35. VSlider — transposed mirror of HSlider.
	"VSlider": {
		"stylebox": {
			"slider":                 {"role": "surface_low",   "raised_intensity": 0, "padding": Vector2i(2, 0),
										"mobile_padding": Vector2i(4, 0)},
			"grabber_area":           {"role": "role_primary",  "raised_intensity": 0, "padding": Vector2i(2, 0),
										"mobile_padding": Vector2i(4, 0)},
			"grabber_area_highlight": {"role": "accent_offset", "raised_intensity": 0, "padding": Vector2i(2, 0),
										"mobile_padding": Vector2i(4, 0)},
		},
		"constant": {
			"center_grabber": {"value": 1},
			"grabber_offset": {"value": 0},
			"tick_offset":    {"value": 8},
		},
		"icon": {
			"grabber":           {"generated_icon": "slider_grabber"},
			"grabber_disabled":  {"generated_icon": "slider_grabber"},
			"grabber_highlight": {"generated_icon": "slider_grabber", "highlight": true},
			"tick":              {"icon": "slider_tick"},
		},
	},
	# 36. VSplitContainer — mirror of HSplitContainer with vertical affordance icons.
	"VSplitContainer": {
		"stylebox": {
			"split_bar_background": {"empty": true},
		},
		"constant": {
			"autohide":               {"value": 1},
			"separation":             {"value": 6},
			"minimum_grab_thickness": {"value": 6},
		},
		"icon": {
			"grabber":       {"generated_icon": "split_grabber", "orientation": "horizontal"},
			"touch_dragger": {"icon": "split_touch_dragger_v"},
		},
	},
	# 36a. Layout-only containers — constants only; no fake surfaces.
	"MarginContainer": {
		"constant": {
			"margin_bottom": {"value": 0},
			"margin_left":   {"value": 0},
			"margin_right":  {"value": 0},
			"margin_top":    {"value": 0},
		},
	},
	"EditorDock": {
		"constant": {
			"margin_bottom": {"value": 6},
			"margin_left":   {"value": 6},
			"margin_right":  {"value": 6},
			"margin_top":    {"value": 6},
		},
	},
	"NoBorderHorizontalBottom": {
		"constant": {
			"margin_top": {"value": 4},
		},
	},
	"HBoxContainer": {
		"constant": {
			"separation": {"value": 2},
		},
	},
	"VBoxContainer": {
		"constant": {
			"separation": {"value": 2},
		},
	},
	"FlowContainer": {
		"constant": {
			"h_separation": {"value": 4},
			"v_separation": {"value": 4},
		},
	},
	"GridContainer": {
		"constant": {
			"h_separation": {"value": 4},
			"v_separation": {"value": 4},
		},
	},
	# 36b. Separators — outline-color rules with modest spacing only.
	"HSeparator": {
		"stylebox": {
			"separator": {"role": "outline_color", "raised_intensity": 0, "padding": Vector2i(0, 0)},
		},
		"constant": {
			"separation": {"value": 4},
		},
	},
	"VSeparator": {
		"stylebox": {
			"separator": {"role": "outline_color", "raised_intensity": 0, "padding": Vector2i(0, 0)},
		},
		"constant": {
			"separation": {"value": 4},
		},
	},
	# 37. Window — embedded chrome complete, quiet, and popup-boundary safe.
	"Window": {
		"stylebox": {
			"embedded_border":          {"role": "button_normal", "border_role": "button_border",
										 "offset_role": "button_normal_offset",
										 "raised_intensity": "shape.raised_lifts.dialog",
										 "radius": "shape.secondary_radius",
										 "border_width": 1, "raised_face_edge": true,
										 "content_margins": Vector4i(10, 28, 10, 8),
										 "expand_margins": Vector4i(8, 32, 8, 6)},
			"embedded_unfocused_border":{"role": "button_normal", "border_role": "button_border",
										 "offset_role": "button_normal_offset",
										 "raised_intensity": "shape.raised_lifts.dialog",
										 "radius": "shape.secondary_radius",
										 "border_width": 1, "raised_face_edge": true,
										 "content_margins": Vector4i(10, 28, 10, 8),
										 "expand_margins": Vector4i(8, 32, 8, 6)},
		},
		"color": {
			"title_color":            {"role": "text_strong"},
			"title_outline_modulate": {"role": "outline_color"},
		},
		"constant": {
			"close_h_offset":    {"value": 18, "mobile_value": 36},
			"close_v_offset":    {"value": 24, "mobile_value": 40},
			"resize_margin":     {"value": 4},
			"title_height":      {"value": 36, "mobile_value": 48},
			"title_outline_size":{"value": 0},
		},
		"icon": {
			"close":         {"icon": "close", "mobile_svg_scale": 1.0},
			"close_pressed": {"icon": "close", "mobile_svg_scale": 1.0},
		},
	},
	# ─── TYPEVAR-01 button variations (Plan 05-03 Task 1) ──────────────────────────────────────
	# Variation chrome flows through BINDING_TABLE recipes per D-01 (additive iteration only),
	# D-02 (per-direction shape via STYLE_PERSONALITY.shape), D-03 (recipe schema reads
	# `shape.<key>` lookups via _lookup_shape), D-04 (closed-enum strategy dispatch via
	# _apply_primary_strategy / _apply_ghost_strategy added by Plan 05-02 Task 2), and D-07
	# (focus is the official `focus` overlay only — no pressed_focus / checked_focus / etc.).
	#
	# Each variation populates the canonical 6-state Button slot set
	# (normal/hover/pressed/focus/disabled/hover_pressed) plus font_color slots so Godot's
	# Button renderer reads them. Phase 4 already wires explicit set_font + set_font_size for
	# these variations (see _regenerate_theme() lines 205-226) — Plan 05-03 only adds chrome.
	# 38. PrimaryButton — primary brand action, accent fill via shape.primary_strategy.
	#
	# Per-direction recipe data wiring:
	#   - radius:           shape.primary_radius     (Pulse 0 / Slate 14 / Bubble 999 pill /
	#                                                 Daybreak 8 / Burst 28 oversized)
	#   - padding:          shape.primary_padding    (Vector2i per FOUND-02; Pulse 14×10 /
	#                                                 Slate 16×11 / Bubble 20×14 / Daybreak
	#                                                 18×12 / Burst 20×14)
	#   - raised_intensity: shape.raised_lifts.primary (Pulse 3 / Slate 2 / Bubble 6 /
	#                                                   Daybreak 3 / Burst 5)
	#   - strategy:         shape.primary_strategy   (5 closed-enum dispatchers in
	#                                                 _apply_primary_strategy)
	# `pressed` and `disabled` skip strategy dispatch (sink/disable states stay literal so
	# the user's mental model of "pressed = darker" stays consistent across directions).
	"PrimaryButton": {
		"stylebox": {
			"normal":        {"role": "primary_button_normal", "border_role": "primary_button_border",
								"raised_intensity": "shape.raised_lifts.primary",
								"radius": "shape.primary_radius", "padding": "shape.primary_padding",
								"mobile_padding": Vector2i(18, 14),
								"offset_role": "primary_button_offset", "raised_face_edge": true},
			"hover":         {"role": "primary_button_hover", "border_role": "primary_button_border_hover",
								"raised_intensity": "shape.raised_lifts.primary",
								"radius": "shape.primary_radius", "padding": "shape.primary_padding",
								"mobile_padding": Vector2i(18, 14),
								"offset_role": "primary_button_hover_offset", "raised_face_edge": true},
			"pressed":       {"role": "primary_button_pressed", "border_role": "primary_button_border_pressed",
								"raised_intensity": 0,
								"radius": "shape.primary_radius", "padding": "shape.primary_padding",
								"mobile_padding": Vector2i(18, 14),
								"offset_role": "primary_button_pressed_offset"},
			"focus":         {"role": "focus_ring",
								"radius": "shape.primary_radius"},
			"disabled":      {"role": "primary_button_disabled", "disabled": true, "raised_intensity": 0,
								"radius": "shape.primary_radius", "padding": "shape.primary_padding",
								"mobile_padding": Vector2i(18, 14),
								"border_width": 0},
			"hover_pressed":{"role": "primary_button_pressed", "border_role": "primary_button_border_pressed",
								"raised_intensity": 0,
								"radius": "shape.primary_radius", "padding": "shape.primary_padding",
								"mobile_padding": Vector2i(18, 14),
								"offset_role": "primary_button_pressed_offset"},
		},
		"color": {
			"font_color":              {"role": "text_on_primary_button"},
			"font_hover_color":        {"role": "text_on_primary_button"},
			"font_pressed_color":      {"role": "text_on_primary_button"},
			"font_focus_color":        {"role": "text_on_primary_button"},
			"font_disabled_color":     {"role": "text_on_primary_button", "disabled": true},
			"font_hover_pressed_color":{"role": "text_on_primary_button"},
			"icon_normal_color":       {"role": "text_on_primary_button"},
			"icon_hover_color":        {"role": "text_on_primary_button"},
			"icon_pressed_color":      {"role": "text_on_primary_button"},
			"icon_focus_color":        {"role": "text_on_primary_button"},
			"icon_disabled_color":     {"role": "text_on_primary_button", "disabled": true},
			"icon_hover_pressed_color":{"role": "text_on_primary_button"},
		},
		"constant": {
			"h_separation": {"value": "tokens.tapPadding"},
		},
	},
	# 39. GhostButton — outlined / transparent bg via shape.ghost_strategy.
	# Surface_panel as the recipe `role` provides a non-null bg_color to start from; the ghost
	# strategy overrides bg_color = TRANSPARENT and applies the per-direction outline
	# (Pulse 2px accent / Slate 1px accent / Bubble 2px accent + radius 999 / Daybreak 1px
	# outline_color / Burst 2px accent). Padding mirrors PrimaryButton for visual rhythm.
	"GhostButton": {
		"stylebox": {
			"normal":        {"role": "surface_panel", "raised_intensity": "shape.raised_lifts.ghost",
								"radius": "shape.secondary_radius", "padding": "shape.primary_padding",
								"mobile_padding": Vector2i(18, 14),
								"strategy": "shape.ghost_strategy",
								"offset_role": "role_primary_offset", "raised_face_edge": true},
			"hover":         {"role": "surface_panel", "raised_intensity": "shape.raised_lifts.ghost",
								"radius": "shape.secondary_radius", "padding": "shape.primary_padding",
								"mobile_padding": Vector2i(18, 14),
								"strategy": "shape.ghost_strategy", "state_layer_role": "role_primary",
								"state_layer_alpha": 0.08,
								"offset_role": "role_primary_offset", "raised_face_edge": true},
			"pressed":       {"role": "surface_panel", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "padding": "shape.primary_padding",
								"mobile_padding": Vector2i(18, 14),
								"strategy": "shape.ghost_strategy", "state_layer_role": "role_primary",
								"state_layer_alpha": 0.12},
			"focus":         {"role": "focus_ring",
								"radius": "shape.secondary_radius"},
			"disabled":      {"role": "surface_panel", "disabled": true, "raised_intensity": 0,
								"radius": "shape.secondary_radius", "padding": "shape.primary_padding",
								"mobile_padding": Vector2i(18, 14),
								"strategy": "shape.ghost_strategy"},
			"hover_pressed":{"role": "surface_panel", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "padding": "shape.primary_padding",
								"mobile_padding": Vector2i(18, 14),
								"strategy": "shape.ghost_strategy", "state_layer_role": "role_primary",
								"state_layer_alpha": 0.12},
		},
		"color": {
			"font_color":              {"role": "role_primary"},
			"font_hover_color":        {"role": "role_primary"},
			"font_pressed_color":      {"role": "role_primary"},
			"font_focus_color":        {"role": "role_primary"},
			"font_disabled_color":     {"role": "role_primary", "disabled": true},
			"font_hover_pressed_color":{"role": "role_primary"},
			"icon_normal_color":       {"role": "role_primary"},
			"icon_hover_color":        {"role": "role_primary"},
			"icon_pressed_color":      {"role": "role_primary"},
			"icon_focus_color":        {"role": "role_primary"},
			"icon_disabled_color":     {"role": "role_primary", "disabled": true},
			"icon_hover_pressed_color":{"role": "role_primary"},
		},
		"constant": {
			"h_separation": {"value": "tokens.tapPadding"},
		},
	},
	# 41. DangerButton — destructive action; bg = role_danger (DESIGN_TOKENS §7.1 #FF6E6E
	# default; per-direction overrides plug into STYLE_PERSONALITY.shape.* in v2 per
	# Plan 05-02 Task 2 docstring). Plan 05-02 added role_danger to role_table so this
	# binding does NOT silently fall back to surface_panel (review HIGH gate).
	# DangerButton uses primary radius/padding (the danger CTA is a primary-grade action).
	"DangerButton": {
		"stylebox": {
			"normal":        {"role": "danger_button_normal", "border_role": "danger_button_border",
								"raised_intensity": "shape.raised_lifts.primary",
								"radius": "shape.primary_radius", "padding": "shape.primary_padding",
								"mobile_padding": Vector2i(18, 14),
								"offset_role": "danger_button_offset", "raised_face_edge": true},
			"hover":         {"role": "danger_button_hover", "border_role": "danger_button_border_hover",
								"raised_intensity": "shape.raised_lifts.primary",
								"radius": "shape.primary_radius", "padding": "shape.primary_padding",
								"mobile_padding": Vector2i(18, 14),
								"offset_role": "danger_button_hover_offset", "raised_face_edge": true},
			"pressed":       {"role": "danger_button_pressed", "border_role": "danger_button_border_pressed",
								"raised_intensity": 0,
								"radius": "shape.primary_radius", "padding": "shape.primary_padding",
								"mobile_padding": Vector2i(18, 14),
								"offset_role": "danger_button_pressed_offset"},
			"focus":         {"role": "focus_ring",
								"radius": "shape.primary_radius"},
			"disabled":      {"role": "danger_button_disabled", "disabled": true, "raised_intensity": 0,
								"radius": "shape.primary_radius", "padding": "shape.primary_padding",
								"mobile_padding": Vector2i(18, 14),
								"border_width": 0},
			"hover_pressed":{"role": "danger_button_pressed", "border_role": "danger_button_border_pressed",
								"raised_intensity": 0,
								"radius": "shape.primary_radius", "padding": "shape.primary_padding",
								"mobile_padding": Vector2i(18, 14),
								"offset_role": "danger_button_pressed_offset"},
		},
		"color": {
			"font_color":              {"role": "text_on_danger"},
			"font_hover_color":        {"role": "text_on_danger"},
			"font_pressed_color":      {"role": "text_on_danger"},
			"font_focus_color":        {"role": "text_on_danger"},
			"font_disabled_color":     {"role": "text_on_danger", "disabled": true},
			"font_hover_pressed_color":{"role": "text_on_danger"},
			"icon_normal_color":       {"role": "text_on_danger"},
			"icon_hover_color":        {"role": "text_on_danger"},
			"icon_pressed_color":      {"role": "text_on_danger"},
			"icon_focus_color":        {"role": "text_on_danger"},
			"icon_disabled_color":     {"role": "text_on_danger", "disabled": true},
			"icon_hover_pressed_color":{"role": "text_on_danger"},
		},
		"constant": {
			"h_separation": {"value": "tokens.tapPadding"},
		},
	},
	# 42. IconButton — compact, borderless square chrome optimised for an icon glyph.
	# Uses tokens.tapPadding directly (NOT shape.primary_padding) so the icon stays
	# centered in a square hit area regardless of direction. Shape.secondary_radius
	# provides the per-direction corner softness (Pulse 0 rectangular / Slate 14 / Bubble 26 /
	# Daybreak 8 / Burst 18). Lifts at shape.raised_lifts.ghost so it reads as a "subtle"
	# affordance compared to primary chrome.
	"IconButton": {
		"stylebox": {
			"normal":        {"role": "button_normal", "border_role": "button_border", "raised_face_edge": true,
								"raised_intensity": "shape.raised_lifts.ghost",
								"radius": "shape.secondary_radius", "padding": Vector2i(8, 8),
								"mobile_padding": Vector2i(16, 16)},
			"hover":         {"role": "button_hover", "border_role": "button_border_hover", "raised_face_edge": true,
								"raised_intensity": "shape.raised_lifts.ghost",
								"radius": "shape.secondary_radius", "padding": Vector2i(8, 8),
								"mobile_padding": Vector2i(16, 16)},
			"pressed":       {"role": "button_pressed", "border_role": "button_border_pressed",
								"raised_intensity": 0,
								"radius": "shape.secondary_radius", "padding": Vector2i(8, 8),
								"mobile_padding": Vector2i(16, 16)},
			"focus":         {"role": "focus_ring",
								"radius": "shape.secondary_radius"},
			"disabled":      {"role": "button_disabled", "border_width": 0, "raised_intensity": 0,
								"radius": "shape.secondary_radius", "padding": Vector2i(8, 8),
								"mobile_padding": Vector2i(16, 16)},
			"hover_pressed":{"role": "button_pressed", "border_role": "button_border_pressed", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "padding": Vector2i(8, 8),
								"mobile_padding": Vector2i(16, 16)},
		},
		"color": {
			"font_color":              {"role": "text_strong"},
			"font_hover_color":        {"role": "text_strong"},
			"font_pressed_color":      {"role": "text_strong"},
			"font_focus_color":        {"role": "text_strong"},
			"font_disabled_color":     {"role": "text_strong", "disabled": true},
			"font_hover_pressed_color":{"role": "text_strong"},
			"icon_normal_color":       {"role": "text_default"},
			"icon_hover_color":        {"role": "role_primary"},
			"icon_pressed_color":      {"role": "role_primary"},
			"icon_focus_color":        {"role": "role_primary"},
			"icon_disabled_color":     {"role": "text_muted",  "disabled": true},
			"icon_hover_pressed_color":{"role": "role_primary"},
		},
		"constant": {
			"h_separation": {"value": 0},
		},
	},
	# 43. FlatButton — borderless / fully transparent normal state; visible only on hover/
	# pressed/focus. Godot's editor and Minimal Theme both keep these "flat" controls
	# visually empty but still reserve wider side padding, so the shared variation uses
	# that spacing in both runtime and editor. Compact icon buttons should use a separate
	# explicit variation instead of making editor/runtime disagree.
	# Never lifts (raised_intensity=0 across all states) — flat by definition.
	"FlatButton": {
		"stylebox": {
			"normal":        {"role": "surface_panel", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "content_margins": Vector4i(6, 4, 6, 4),
								"mobile_padding": Vector2i(16, 18),
								"alpha": 0.0, "border_width": 0},
			"normal_mirrored":{"role": "surface_panel", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "content_margins": Vector4i(6, 4, 6, 4),
								"mobile_padding": Vector2i(16, 18),
								"alpha": 0.0, "border_width": 0},
			"hover":         {"role": "button_hover", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "content_margins": Vector4i(6, 4, 6, 4),
								"mobile_padding": Vector2i(16, 18),
								"border_width": 0},
			"hover_mirrored":{"role": "button_hover", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "content_margins": Vector4i(6, 4, 6, 4),
								"mobile_padding": Vector2i(16, 18),
								"border_width": 0},
			"pressed":       {"role": "button_pressed", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "content_margins": Vector4i(6, 4, 6, 4),
								"mobile_padding": Vector2i(16, 18),
								"border_width": 0},
			"pressed_mirrored":{"role": "button_pressed", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "content_margins": Vector4i(6, 4, 6, 4),
								"mobile_padding": Vector2i(16, 18),
								"border_width": 0},
			"focus":         {"role": "focus_ring",
								"radius": "shape.secondary_radius"},
			"disabled":      {"role": "surface_panel", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "content_margins": Vector4i(6, 4, 6, 4),
								"mobile_padding": Vector2i(16, 18),
								"alpha": 0.0, "border_width": 0},
			"disabled_mirrored":{"role": "surface_panel", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "content_margins": Vector4i(6, 4, 6, 4),
								"mobile_padding": Vector2i(16, 18),
								"alpha": 0.0, "border_width": 0},
			"hover_pressed":{"role": "button_pressed", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "content_margins": Vector4i(6, 4, 6, 4),
								"mobile_padding": Vector2i(16, 18),
								"border_width": 0},
			"hover_pressed_mirrored":{"role": "button_pressed", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "content_margins": Vector4i(6, 4, 6, 4),
								"mobile_padding": Vector2i(16, 18),
								"border_width": 0},
		},
		"color": {
			"font_color":              {"role": "text_default"},
			"font_hover_color":        {"role": "text_strong"},
			"font_pressed_color":      {"role": "text_strong"},
			"font_focus_color":        {"role": "text_strong"},
			"font_disabled_color":     {"role": "text_default", "disabled": true},
			"font_hover_pressed_color":{"role": "text_strong"},
			"icon_normal_color":       {"role": "text_default"},
			"icon_hover_color":        {"role": "text_strong"},
			"icon_pressed_color":      {"role": "role_primary"},
			"icon_focus_color":        {"role": "text_strong"},
			"icon_disabled_color":     {"role": "text_default", "disabled": true},
			"icon_hover_pressed_color":{"role": "role_primary"},
		},
		"constant": {
			"h_separation": {"value": 4},
		},
	},
	# 43a. FlatMenuButton — menu-capable sibling of FlatButton. It keeps the same
	# transparent-at-rest wide spacing so menu buttons, toolbar buttons, and runtime
	# flat icon buttons align consistently unless a consumer opts into a compact variant.
	"FlatMenuButton": {
		"stylebox": {
			"normal":        {"role": "surface_panel", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "content_margins": Vector4i(6, 4, 6, 4),
								"mobile_padding": Vector2i(16, 18),
								"alpha": 0.0, "border_width": 0},
			"normal_mirrored":{"role": "surface_panel", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "content_margins": Vector4i(6, 4, 6, 4),
								"mobile_padding": Vector2i(16, 18),
								"alpha": 0.0, "border_width": 0},
			"hover":         {"role": "button_hover", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "content_margins": Vector4i(6, 4, 6, 4),
								"mobile_padding": Vector2i(16, 18),
								"border_width": 0},
			"hover_mirrored":{"role": "button_hover", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "content_margins": Vector4i(6, 4, 6, 4),
								"mobile_padding": Vector2i(16, 18),
								"border_width": 0},
			"pressed":       {"role": "button_pressed", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "content_margins": Vector4i(6, 4, 6, 4),
								"mobile_padding": Vector2i(16, 18),
								"border_width": 0},
			"pressed_mirrored":{"role": "button_pressed", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "content_margins": Vector4i(6, 4, 6, 4),
								"mobile_padding": Vector2i(16, 18),
								"border_width": 0},
			"focus":         {"role": "surface_panel", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "content_margins": Vector4i(6, 4, 6, 4),
								"mobile_padding": Vector2i(16, 18),
								"alpha": 0.0, "border_width": 0},
			"disabled":      {"role": "surface_panel", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "content_margins": Vector4i(6, 4, 6, 4),
								"mobile_padding": Vector2i(16, 18),
								"alpha": 0.0, "border_width": 0},
			"disabled_mirrored":{"role": "surface_panel", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "content_margins": Vector4i(6, 4, 6, 4),
								"mobile_padding": Vector2i(16, 18),
								"alpha": 0.0, "border_width": 0},
			"hover_pressed":{"role": "button_pressed", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "content_margins": Vector4i(6, 4, 6, 4),
								"mobile_padding": Vector2i(16, 18),
								"border_width": 0},
			"hover_pressed_mirrored":{"role": "button_pressed", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "content_margins": Vector4i(6, 4, 6, 4),
								"mobile_padding": Vector2i(16, 18),
								"border_width": 0},
		},
		"color": {
			"font_color":              {"role": "text_default"},
			"font_hover_color":        {"role": "text_strong"},
			"font_pressed_color":      {"role": "text_strong"},
			"font_focus_color":        {"role": "text_strong"},
			"font_disabled_color":     {"role": "text_default", "disabled": true},
			"font_hover_pressed_color":{"role": "text_strong"},
			"icon_normal_color":       {"role": "text_default"},
			"icon_hover_color":        {"role": "text_strong"},
			"icon_pressed_color":      {"role": "role_primary"},
			"icon_focus_color":        {"role": "text_strong"},
			"icon_disabled_color":     {"role": "text_default", "disabled": true},
			"icon_hover_pressed_color":{"role": "role_primary"},
		},
		"constant": {
			"h_separation": {"value": 4},
		},
	},
	"MainMenuBar": {
		"stylebox": {
			"normal":        {"role": "surface_base", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "content_margins": Vector4i(6, 3, 6, 2),
								"mobile_padding": Vector2i(14, 14),
								"alpha": 0.0, "border_width": 0},
			"hover":         {"role": "button_hover", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "content_margins": Vector4i(6, 3, 6, 2),
								"mobile_padding": Vector2i(14, 14),
								"border_width": 0},
			"pressed":       {"role": "button_pressed", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "content_margins": Vector4i(6, 3, 6, 2),
								"mobile_padding": Vector2i(14, 14),
								"border_width": 0},
			"hover_pressed": {"role": "button_pressed", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "content_margins": Vector4i(6, 3, 6, 2),
								"mobile_padding": Vector2i(14, 14),
								"border_width": 0},
		},
	},
	"PanelBackgroundButton": {
		"stylebox": {
			"normal":   {"role": "button_normal", "border_role": "button_border",
						 "raised_intensity": 0, "border_width": 1,
						 "radius": "shape.secondary_radius", "padding": Vector2i(8, 4),
						 "mobile_padding": Vector2i(12, 16)},
			"hover":    {"role": "button_hover", "border_role": "button_border_hover",
						 "raised_intensity": 0, "border_width": 1,
						 "radius": "shape.secondary_radius", "padding": Vector2i(8, 4),
						 "mobile_padding": Vector2i(12, 16)},
			"pressed":  {"role": "button_pressed", "border_role": "button_border_pressed",
						 "raised_intensity": 0, "border_width": 1,
						 "radius": "shape.secondary_radius", "padding": Vector2i(8, 4),
						 "mobile_padding": Vector2i(12, 16)},
			"disabled": {"role": "button_disabled", "raised_intensity": 0,
						 "border_width": 0, "radius": "shape.secondary_radius",
						 "padding": Vector2i(8, 4), "mobile_padding": Vector2i(12, 16)},
		},
	},
	"ProjectTagButton": {
		"stylebox": {
			"normal":  {"role": "button_normal", "border_role": "button_border",
						"raised_intensity": 0, "border_width": 1,
						"radius": "shape.secondary_radius", "padding": Vector2i(8, 4)},
			"hover":   {"role": "button_hover", "border_role": "button_border_hover",
						"raised_intensity": 0, "border_width": 1,
						"radius": "shape.secondary_radius", "padding": Vector2i(8, 4)},
			"pressed": {"role": "button_pressed", "border_role": "button_border_pressed",
						"raised_intensity": 0, "border_width": 1,
						"radius": "shape.secondary_radius", "padding": Vector2i(8, 4)},
		},
	},
	"BottomPanelButton": {
		"stylebox": {
			"normal":        {"role": "surface_panel", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "content_margins": Vector4i(8, 5, 8, 5),
								"mobile_padding": Vector2i(14, 14),
								"alpha": 0.0, "border_width": 0},
			"hover":         {"role": "button_hover", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "content_margins": Vector4i(8, 5, 8, 5),
								"mobile_padding": Vector2i(14, 14),
								"border_width": 0},
			"pressed":       {"role": "button_pressed", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "content_margins": Vector4i(8, 5, 8, 5),
								"mobile_padding": Vector2i(14, 14),
								"border_width": 0},
			"focus":         {"role": "surface_panel", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "content_margins": Vector4i(8, 5, 8, 5),
								"mobile_padding": Vector2i(14, 14),
								"alpha": 0.0, "border_width": 0},
			"disabled":      {"role": "surface_panel", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "content_margins": Vector4i(8, 5, 8, 5),
								"mobile_padding": Vector2i(14, 14),
								"alpha": 0.0, "border_width": 0},
			"hover_pressed":{"role": "button_pressed", "raised_intensity": 0,
								"radius": "shape.secondary_radius", "content_margins": Vector4i(8, 5, 8, 5),
								"mobile_padding": Vector2i(14, 14),
								"border_width": 0},
		},
		"color": {
			"font_color":              {"role": "text_default"},
			"font_hover_color":        {"role": "text_strong"},
			"font_pressed_color":      {"role": "text_strong"},
			"font_focus_color":        {"role": "text_strong"},
			"font_disabled_color":     {"role": "text_default", "disabled": true},
			"font_hover_pressed_color":{"role": "text_strong"},
			"icon_normal_color":       {"role": "text_default"},
			"icon_hover_color":        {"role": "text_strong"},
			"icon_pressed_color":      {"role": "role_primary"},
			"icon_focus_color":        {"role": "text_strong"},
			"icon_disabled_color":     {"role": "text_default", "disabled": true},
			"icon_hover_pressed_color":{"role": "role_primary"},
		},
		"constant": {
			"h_separation": {"value": 4},
		},
	},
	"EditorLogFilterButton": {
		"stylebox": {
			"normal":        {"role": "button_normal", "border_role": "button_border",
								"raised_intensity": 0, "border_width": 0,
								"radius": "shape.secondary_radius", "padding": Vector2i(8, 5),
								"mobile_padding": Vector2i(12, 14)},
			"hover":         {"role": "button_hover", "border_role": "button_border_hover",
								"raised_intensity": 0, "border_width": 0,
								"radius": "shape.secondary_radius", "padding": Vector2i(8, 5),
								"mobile_padding": Vector2i(12, 14)},
			"pressed":       {"role": "button_pressed", "border_role": "button_border_pressed",
								"raised_intensity": 0, "border_width": 0,
								"radius": "shape.secondary_radius", "padding": Vector2i(8, 5),
								"mobile_padding": Vector2i(12, 14)},
			"focus":         {"role": "focus_ring", "radius": "shape.secondary_radius"},
			"disabled":      {"role": "button_disabled", "disabled": true,
								"raised_intensity": 0, "border_width": 0,
								"radius": "shape.secondary_radius", "padding": Vector2i(8, 5),
								"mobile_padding": Vector2i(12, 14)},
			"hover_pressed":{"role": "button_pressed", "border_role": "button_border_pressed",
								"raised_intensity": 0, "border_width": 0,
								"radius": "shape.secondary_radius", "padding": Vector2i(8, 5),
								"mobile_padding": Vector2i(12, 14)},
		},
		"color": {
			"font_color":              {"role": "text_strong"},
			"font_hover_color":        {"role": "text_strong"},
			"font_pressed_color":      {"role": "role_primary"},
			"font_focus_color":        {"role": "text_strong"},
			"font_disabled_color":     {"role": "text_strong", "disabled": true},
			"font_hover_pressed_color":{"role": "role_primary"},
			"icon_normal_color":       {"role": "text_strong"},
			"icon_hover_color":        {"role": "text_strong"},
			"icon_pressed_color":      {"role": "role_primary"},
			"icon_focus_color":        {"role": "text_strong"},
			"icon_disabled_color":     {"role": "text_strong", "disabled": true},
			"icon_hover_pressed_color":{"role": "role_primary"},
		},
		"constant": {
			"h_separation": {"value": 4},
		},
	},
	# ─── Phase 5 Plan 05-04: Type-variation rows (TYPEVAR-02..05 + Kicker D-09) ───
	# These rows extend BINDING_TABLE with the 7 NeoCade text/label/RTL type
	# variations whose chrome is owned by Plan 05-04 Task 2. The 6 button-family
	# variations (PrimaryButton..FlatMenuButton) are owned by Plan 05-03 (sibling
	# wave) and live in the rows above. The 2 panel variations (CardPanel,
	# HeroPanel) plus PanelContainer are owned by Plan 05-04 Task 3 and follow
	# this section.
	#
	# D-04 invariant: variations not in BINDING_TABLE remain untouched at
	# regenerate. This section is the variation-side parallel of the 37-row
	# canonical scorecard above.
	#
	# 44. HeaderLarge — Label variation (TYPEVAR-02). Phase 4 set font + size;
	#     Phase 5 adds explicit font_color via BINDING_TABLE so per-direction
	#     palette refresh propagates to headings.
	"HeaderLarge": {
		"color": {
			"font_color": {"role": "text_strong"},
		},
	},
	# 45. HeaderMedium — Label variation (TYPEVAR-02).
	"HeaderMedium": {
		"color": {
			"font_color": {"role": "text_strong"},
		},
	},
	# 46. HeaderSmall — Label variation (TYPEVAR-02).
	"HeaderSmall": {
		"color": {
			"font_color": {"role": "text_strong"},
		},
	},
	# 47. Caption — Label variation (TYPEVAR-02). Caption is the small-body
	#     supporting label; uses text_default (one tonal step softer than
	#     text_strong) to read as secondary content.
	"Caption": {
		"color": {
			"font_color": {"role": "text_default"},
		},
	},
	# 48. CodeLabel — Label variation (TYPEVAR-02). CodeLabel ships in
	#     Inter Body weight per FONT-04 stricken / FONT-09 (b); consumer can
	#     swap a mono via the Theme Editor `font` slot. Color uses text_strong
	#     (code reads as primary content even when small).
	"CodeLabel": {
		"color": {
			"font_color": {"role": "text_strong"},
		},
	},
	# 49. Kicker — Label variation (TYPEVAR-02 + D-09). The kicker_style
	#     dispatch (D-04 closed enum sourced verbatim from DESIGN_TOKENS §8.6)
	#     drives per-direction font_color via _apply_kicker_style():
	#       Pulse / Bubble  ("uppercase-tracked-accent")    -> role_primary
	#       Slate           ("small-caps-subtle")           -> text_muted
	#       Daybreak        ("sentence-case-accent")        -> role_primary
	#       Burst           ("uppercase-bold-larger-scale") -> role_primary
	#     Tracking / case-transform / per-direction wght+1 size delta is
	#     CONTENT-side per the research finding (no Theme-level letter_spacing
	#     constant in Godot 4.6 Label). Phase 5 verifier
	#     assert_no_letter_spacing_claim asserts this restraint at the source
	#     level; assert_kicker_chrome asserts the resolved color matches the
	#     direction's kicker_style enum end-to-end.
	"Kicker": {
		"color": {
			"font_color": {"kicker_style": "shape.kicker_style"},
		},
	},
	# 50. InfoText — RichTextLabel variation (TYPEVAR-03). Per D-16 / BL-02,
	#     RTL reads `normal_font` and `normal_font_size` (set in
	#     _regenerate_theme above), and `default_color` for body text +
	#     `selection_color` for highlights. font_selected_color is the body
	#     color when text is inside a user selection (text_strong for contrast
	#     against the accent_offset highlight).
	"InfoText": {
		"color": {
			"default_color":         {"role": "text_default"},
			"selection_color":       {"role": "accent_offset"},
			"font_selected_color":   {"role": "text_on_accent_offset"},
		},
	},
	# 51. PanelContainer — Phase 4 omitted this base class from BINDING_TABLE
	#     (only Panel was wired); Phase 5 Plan 05-04 Task 3 adds it so
	#     per-direction surface_alpha_panels and raised_lifts.panel propagate.
	#     CardPanel and HeroPanel both extend PanelContainer.
	"PanelContainer": {
		"stylebox": {
			"panel": {
				"role":             "surface_panel",
				"border_role":      "surface_panel_edge",
				"alpha":            "shape.surface_alpha_panels",
				"raised_intensity": "shape.raised_lifts.panel",
				"raised_face_edge": true,
				"padding":          Vector2i(10, 8),
			},
		},
	},
	# 52. WindowContentPanel — full-rect content surface inside embedded Window.
	#     No border or padding; Window.embedded_border owns the chrome, and the
	#     wrapped MarginContainer owns content spacing.
	"WindowContentPanel": {
		"stylebox": {
			"panel": {
				"role":             "surface_low",
				"raised_intensity": 0,
				"border_width":     0,
				"radius":           0,
				"padding":          Vector2i(0, 0),
			},
		},
	},
	# 53. CardPanel — PanelContainer variation (TYPEVAR-04). Uses
	#     shape.card_radius for per-direction radius personality (Pulse 0,
	#     Slate 14, Bubble 26, Daybreak 8, Burst 18) plus the panel
	#     surface_alpha and raised lift.
	"CardPanel": {
		"stylebox": {
			"panel": {
				"role":             "surface_panel",
				"border_role":      "surface_panel_edge",
				"radius":           "shape.card_radius",
				"alpha":            "shape.surface_alpha_panels",
				"raised_intensity": "shape.raised_lifts.panel",
				"raised_face_edge": true,
				"padding":          Vector2i(12, 10),
			},
		},
		"color": {
			"font_color": {"role": "text_strong"},
		},
	},
	# 54. HeroPanel — PanelContainer variation (TYPEVAR-04). Uses
	#     shape.hero_radius (sibling to card_radius; v1 ships matching pairs
	#     per direction, but the schema lets v2 differentiate hero from card
	#     for any direction). Surface role is surface_high (one tonal step
	#     above CardPanel) so a Hero stack reads above a Card in the
	#     extruded-flat layer order.
	"HeroPanel": {
		"stylebox": {
			"panel": {
				"role":             "surface_high",
				"border_role":      "surface_high_edge",
				"radius":           "shape.hero_radius",
				"alpha":            "shape.surface_alpha_panels",
				"raised_intensity": "shape.raised_lifts.panel",
				"raised_face_edge": true,
				"padding":          Vector2i(14, 12),
			},
		},
		"color": {
			"font_color": {"role": "text_strong"},
		},
	},
	# 55. SuccessLabel — Label variation (Phase 13 § C1). Opt-in only; default
	#     Label.font_color remains text_strong at line 3147 — SC#3 invariant.
	"SuccessLabel": {
		"color": {
			"font_color": {"role": "role_success"},
		},
	},
	# 56. WarningLabel — Label variation (Phase 13 § C1).
	"WarningLabel": {
		"color": {
			"font_color": {"role": "role_warning"},
		},
	},
	# 57. DangerLabel — Label variation (Phase 13 § C1).
	"DangerLabel": {
		"color": {
			"font_color": {"role": "role_danger"},
		},
	},
	# 58. InfoLabel — Label variation (Phase 13 § C1).
	"InfoLabel": {
		"color": {
			"font_color": {"role": "role_info"},
		},
	},
	# 59. AccentPanel — PanelContainer variation (Phase 13 § C3). 6%-mix tint
	#     of role_primary over the per-direction panel chrome. Opt-in only;
	#     default PanelContainer.panel at lines 5011-5022 stays unchanged — SC#3.
	"AccentPanel": {
		"stylebox": {
			"panel": {
				"role":             "role_primary",
				"alpha":            0.06,
				"border_role":      "surface_panel_edge",
				"radius":           "shape.card_radius",
				"raised_intensity": "shape.raised_lifts.panel",
				"raised_face_edge": true,
				"padding":          Vector2i(12, 10),
			},
		},
	},
	# 60. InfoPanel — PanelContainer variation (Phase 13 § C3).
	"InfoPanel": {
		"stylebox": {
			"panel": {
				"role":             "role_info",
				"alpha":            0.06,
				"border_role":      "surface_panel_edge",
				"radius":           "shape.card_radius",
				"raised_intensity": "shape.raised_lifts.panel",
				"raised_face_edge": true,
				"padding":          Vector2i(12, 10),
			},
		},
	},
	# 61. WarningPanel — PanelContainer variation (Phase 13 § C3).
	"WarningPanel": {
		"stylebox": {
			"panel": {
				"role":             "role_warning",
				"alpha":            0.06,
				"border_role":      "surface_panel_edge",
				"radius":           "shape.card_radius",
				"raised_intensity": "shape.raised_lifts.panel",
				"raised_face_edge": true,
				"padding":          Vector2i(12, 10),
			},
		},
	},
	# 62. DangerPanel — PanelContainer variation (Phase 13 § C3).
	"DangerPanel": {
		"stylebox": {
			"panel": {
				"role":             "role_danger",
				"alpha":            0.06,
				"border_role":      "surface_panel_edge",
				"radius":           "shape.card_radius",
				"raised_intensity": "shape.raised_lifts.panel",
				"raised_face_edge": true,
				"padding":          Vector2i(12, 10),
			},
		},
	},
	# 63. SuccessPanel — PanelContainer variation (Phase 13 § C3).
	"SuccessPanel": {
		"stylebox": {
			"panel": {
				"role":             "role_success",
				"alpha":            0.06,
				"border_role":      "surface_panel_edge",
				"radius":           "shape.card_radius",
				"raised_intensity": "shape.raised_lifts.panel",
				"raised_face_edge": true,
				"padding":          Vector2i(12, 10),
			},
		},
	},
}


# ─── Recipe resolution (Plan 04-05 iteration engine helper) ─────────────────────────────────

## Walks `style_personality.shape.<dotted_path>` against the active style's shape sub-block.
##
## Plan 05-02 Task 2 (D-03). Recipes reference shape values as strings like
## `"shape.primary_radius"` or `"shape.raised_lifts.primary"`; this helper splits on `.`
## and walks the shape Dictionary one key at a time. Returns the leaf value (int / float /
## Vector2i / StringName / Dictionary) or `null` if any segment is missing.
##
## For approved style personality blocks, missing shape keys are verifier failures (D-02 mandate);
## the only acceptable null path is when `style_personality` lacks a `shape` block entirely (custom
## NeoCadeTheme.new() consumers — those use STYLE_PERSONALITY_DEFAULT.shape per D-13).
func _lookup_shape(style_personality: Dictionary, dotted_path: String) -> Variant:
	if not (dotted_path is String) or not dotted_path.begins_with("shape."):
		return null
	if not style_personality.has("shape"):
		return null
	var current: Variant = style_personality["shape"]
	var segments: PackedStringArray = dotted_path.substr(6).split(".")  # strip "shape."
	for seg in segments:
		if seg == "":
			return null
		if typeof(current) != TYPE_DICTIONARY:
			return null
		var d: Dictionary = current
		if not d.has(seg):
			return null
		current = d[seg]
	return current


## Sets all four StyleBoxFlat corner_radius_* fields to the same int radius.
## Plan 05-02 Task 2 helper (D-03): factored out so `radius: shape.<key>` recipes
## can apply uniformly without inlining 4 setters at every call site.
func _set_radius_all(sb: StyleBoxFlat, r: int) -> void:
	sb.corner_radius_top_left = r
	sb.corner_radius_top_right = r
	sb.corner_radius_bottom_left = r
	sb.corner_radius_bottom_right = r


## Selected tabs should visually attach to the TabContainer panel: top corners keep the
## direction tab radius, bottom corners are square so the tab reads as part of the content.
func _set_tab_connected_radius(sb: StyleBoxFlat, r: int) -> void:
	sb.corner_radius_top_left = r
	sb.corner_radius_top_right = r
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0


func _set_top_only_radius(sb: StyleBoxFlat, r: int) -> void:
	sb.corner_radius_top_left = r
	sb.corner_radius_top_right = r
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0


func _set_bottom_only_radius(sb: StyleBoxFlat, r: int) -> void:
	sb.corner_radius_top_left = 0
	sb.corner_radius_top_right = 0
	sb.corner_radius_bottom_left = r
	sb.corner_radius_bottom_right = r


## Sets StyleBoxFlat content_margin_* from a Vector2i where x=horizontal, y=vertical.
## Plan 05-02 Task 2 helper (D-03): `padding: shape.<key>` recipes call this so the
## Vector2i convention (x→left/right, y→top/bottom) is enforced in one place. Phase 4
## FOUND-02 lock makes Vector2i the canonical paired-x/y type.
func _set_content_margin_from_padding(sb: StyleBoxFlat, padding: Vector2i) -> void:
	sb.content_margin_left = padding.x
	sb.content_margin_right = padding.x
	sb.content_margin_top = padding.y
	sb.content_margin_bottom = padding.y


func _set_content_margins(sb: StyleBoxFlat, margins: Vector4i) -> void:
	sb.content_margin_left = margins.x
	sb.content_margin_top = margins.y
	sb.content_margin_right = margins.z
	sb.content_margin_bottom = margins.w


func _set_expand_margins(sb: StyleBoxFlat, margins: Vector4i) -> void:
	sb.expand_margin_left = margins.x
	sb.expand_margin_top = margins.y
	sb.expand_margin_right = margins.z
	sb.expand_margin_bottom = margins.w


func _apply_outline_border(sb: StyleBoxFlat, color: Color, width: int = -1) -> void:
	var resolved_width := outline_width if width < 0 else width
	sb.border_color = color
	sb.border_width_left = resolved_width
	sb.border_width_top = resolved_width
	sb.border_width_right = resolved_width
	sb.border_width_bottom = resolved_width


func _reserve_bottom_depth_height(sb: StyleBoxFlat) -> void:
	var face_width: int = maxi(sb.border_width_left, maxi(sb.border_width_top, sb.border_width_right))
	var bottom_extra: int = maxi(0, sb.border_width_bottom - face_width)
	sb.content_margin_bottom += bottom_extra


func _apply_raised_depth_border(sb: StyleBoxFlat, offset_color: Color, intensity: int,
								 keep_face_edge: bool = false, reserve_height: bool = false) -> void:
	var depth := maxi(1, intensity)
	if keep_face_edge:
		sb.border_color = offset_color
		var face_width: int = maxi(1, maxi(sb.border_width_left, maxi(sb.border_width_top, sb.border_width_right)))
		sb.border_width_left = face_width
		sb.border_width_top = face_width
		sb.border_width_right = face_width
		sb.border_width_bottom = maxi(depth, face_width + 1)
		if reserve_height:
			_reserve_bottom_depth_height(sb)
		return
	sb.border_color = offset_color
	sb.border_width_left = 0
	sb.border_width_top = 0
	sb.border_width_right = 0
	sb.border_width_bottom = depth
	if reserve_height:
		_reserve_bottom_depth_height(sb)


## Applies the per-direction primary_strategy mutation to a StyleBoxFlat representing
## the primary-button bg. Plan 05-02 Task 2 (D-04 first-class enum dispatch).
##
## Strategies are sourced VERBATIM from DESIGN_TOKENS §5.1-§5.5:
##   "bold-accent-fill"        — Pulse: bg=role_primary (accent), thin outline matches accent.
##   "quiet-pill"              — Slate: bg=surface_panel, thin role_primary border (1px).
##   "pillowy-fully-rounded"   — Bubble: bg=role_primary, radius forced to 999 (pill) AFTER
##                               any prior radius set so shape.primary_radius=999 wins.
##   "friendly-generous"       — Daybreak: bg=role_primary, generous padding already applied
##                               by `padding: shape.primary_padding` recipe row.
##   "oversized-statement"     — Burst: bg=role_primary, larger radius applied via shape
##                               (28 vs base 18); padding already 20×14 from shape.
##
## Strategies are CLOSED enums — adding a 6th approved direction in v2 = adding a strategy
## entry HERE, not editing 14 BINDING_TABLE recipe rows (D-04). Unknown strategy = no-op
## (verifier asserts the closed-enum invariant; typos surface as PHASE5_GROUP_FAIL).
func _apply_primary_strategy(sb: StyleBoxFlat, strategy_name: StringName, role_table: Dictionary, style_personality: Dictionary) -> void:
	# Strategy values are the StringName literals from STYLE_PERSONALITY.shape.primary_strategy
	# per direction (sourced verbatim from DESIGN_TOKENS §5.1-§5.5 "primary_strategy" rows).
	match String(strategy_name):
		"bold-accent-fill":
			# Pulse: solid accent fill, accent-tinted outline.
			sb.bg_color = role_table.get("role_primary", role_table.surface_panel)
			sb.border_color = role_table.get("accent_rim", role_table.outline_color)
		"quiet-pill":
			# Slate: muted surface bg + thin accent border (the "iOS quiet pill" read).
			sb.bg_color = role_table.get("surface_panel", role_table.surface_panel)
			sb.border_color = role_table.get("role_primary", role_table.outline_color)
			sb.border_width_left = 1
			sb.border_width_top = 1
			sb.border_width_right = 1
			sb.border_width_bottom = 1
		"pillowy-fully-rounded":
			# Bubble: accent fill + radius locked to 999 regardless of prior radius set.
			sb.bg_color = role_table.get("role_primary", role_table.surface_panel)
			_set_radius_all(sb, 999)
			sb.border_color = role_table.get("accent_rim", role_table.outline_color)
		"friendly-generous":
			# Daybreak: accent fill; padding/radius already applied by shape.* recipe rows.
			sb.bg_color = role_table.get("role_primary", role_table.surface_panel)
			sb.border_color = role_table.get("accent_rim", role_table.outline_color)
		"oversized-statement":
			# Burst: accent fill; oversized radius (28) applied via shape.primary_radius.
			sb.bg_color = role_table.get("role_primary", role_table.surface_panel)
			sb.border_color = role_table.get("accent_rim", role_table.outline_color)
		_:
			# Unknown strategy — Phase 5 verifier flags this as a typo; no mutation here
			# so the bg from the recipe's `role` lookup stays in place (D-04 escape hatch).
			pass


## Applies the per-direction ghost_strategy mutation to a StyleBoxFlat representing
## a ghost-button bg. Plan 05-02 Task 2 (D-04 first-class enum dispatch).
##
## Strategies are sourced VERBATIM from DESIGN_TOKENS §5.1-§5.5:
##   "accent-outlined-accent-text"   — Pulse: transparent bg + 2px accent border.
##   "thin-accent-outline"           — Slate: transparent bg + 1px accent border.
##   "rounded-ghost-thicker-outline" — Bubble: transparent bg + 2px accent border + radius 999.
##   "soft-outline"                  — Daybreak / DEFAULT: transparent bg + 1px outline_color.
##   "normal-accent-ghost"           — Burst: transparent bg + 2px accent border.
func _apply_ghost_strategy(sb: StyleBoxFlat, strategy_name: StringName, role_table: Dictionary, style_personality: Dictionary) -> void:
	# Default to transparent bg; specific strategies override border color/thickness.
	sb.bg_color = Color(0, 0, 0, 0)
	match String(strategy_name):
		"accent-outlined-accent-text":
			# Pulse ghost: transparent bg + 2px accent border.
			sb.border_color = role_table.get("role_primary", role_table.outline_color)
			sb.border_width_left = 2
			sb.border_width_top = 2
			sb.border_width_right = 2
			sb.border_width_bottom = 2
		"thin-accent-outline":
			# Slate ghost: 1px accent.
			sb.border_color = role_table.get("role_primary", role_table.outline_color)
			sb.border_width_left = 1
			sb.border_width_top = 1
			sb.border_width_right = 1
			sb.border_width_bottom = 1
		"rounded-ghost-thicker-outline":
			# Bubble ghost: 2px accent + force radius 999 (pill) to read with the
			# pillowy primary nearby.
			sb.border_color = role_table.get("role_primary", role_table.outline_color)
			sb.border_width_left = 2
			sb.border_width_top = 2
			sb.border_width_right = 2
			sb.border_width_bottom = 2
			_set_radius_all(sb, 999)
		"soft-outline":
			# Daybreak / DEFAULT ghost: 1px outline_color (calmer than accent).
			sb.border_color = role_table.get("outline_color", role_table.outline_color)
			sb.border_width_left = 1
			sb.border_width_top = 1
			sb.border_width_right = 1
			sb.border_width_bottom = 1
		"normal-accent-ghost":
			# Burst ghost: 2px accent border.
			sb.border_color = role_table.get("role_primary", role_table.outline_color)
			sb.border_width_left = 2
			sb.border_width_top = 2
			sb.border_width_right = 2
			sb.border_width_bottom = 2
		_:
			# Unknown strategy — verifier flags this; no mutation (D-04 escape hatch).
			pass


## Resolves the kicker font_color for the active direction per `kicker_style`.
## Plan 05-02 Task 2 (D-09 closes DESIGN_TOKENS §8.6 todo; Plan 05-04 actually wires
## Kicker into BINDING_TABLE and TYPE_VARIATIONS — this helper exists now so Task 2's
## verifier `assert_shape_recipe_resolution` finds it; the actual Kicker entry binding
## happens in Plan 05-04).
##
## Styles sourced VERBATIM from DESIGN_TOKENS §8.6:
##   "uppercase-tracked-accent"      — Pulse / Bubble: accent font_color.
##   "small-caps-subtle"             — Slate: text_muted font_color.
##   "sentence-case-accent"          — Daybreak / DEFAULT: accent font_color.
##   "uppercase-bold-larger-scale"   — Burst: accent font_color (size+weight handled
##                                     by Plan 05-04's set_font_size / FontVariation wght).
##
## Returns the resolved Color so Plan 05-04's color-recipe path can use it directly.
func _apply_kicker_style(kicker_style: StringName, role_table: Dictionary) -> Color:
	match String(kicker_style):
		"uppercase-tracked-accent":
			return role_table.get("role_primary", role_table.text_strong)
		"small-caps-subtle":
			return role_table.get("text_muted", role_table.text_strong)
		"sentence-case-accent":
			return role_table.get("role_primary", role_table.text_strong)
		"uppercase-bold-larger-scale":
			return role_table.get("role_primary", role_table.text_strong)
		_:
			return role_table.get("text_strong", Color.WHITE)


## Resolves a BINDING_TABLE recipe to a concrete value, given the precomputed derivation block.
## `data_type` is "stylebox", "color", "constant", "font_size", or "icon".
##   (Cross-AI Cycle 2 N1 fix: NO "font" branch — per-Control fonts are handled by
##   theme.default_font + the 14 explicit set_font calls on type variations in Task 1.)
##
## Plan 05-02 Task 2 (D-03): stylebox branch supports `empty: true`,
## `radius: "shape.<key>"`, `padding: "shape.<key>"`,
## `alpha: "shape.<key>"`, `raised_intensity: "shape.<key>"`,
## and `strategy: "shape.<strategy_key>"` — values are dereferenced through `_lookup_shape()`
## against the active direction's `shape` sub-block. The `disabled: true` carry-over is
## preserved (Cycle 2 C2). Strategy dispatch is closed-enum per D-04: unknown strategies
## leave the recipe-default bg in place (D-04 escape hatch) and the verifier flags typos.
##
## Returns null if the recipe references an unknown role or icon (caller skips silently — D-04).
func _resolve_recipe(recipe: Dictionary, data_type: String, role_table: Dictionary,
					  tokens: Dictionary, style_personality: Dictionary) -> Variant:
	if data_type == "stylebox":
		if bool(recipe.get("empty", false)):
			return StyleBoxEmpty.new()
		var role: String = recipe.get("role", "surface_panel")
		# raised_intensity may be either an int literal or a `shape.<key>` lookup string.
		var raised_intensity_raw: Variant = recipe.get("raised_intensity", 0)
		var raised_intensity: int = 0
		if typeof(raised_intensity_raw) == TYPE_STRING and (raised_intensity_raw as String).begins_with("shape."):
			var lifted: Variant = _lookup_shape(style_personality, raised_intensity_raw)
			if lifted != null and (typeof(lifted) == TYPE_INT or typeof(lifted) == TYPE_FLOAT):
				raised_intensity = int(lifted)
		else:
			raised_intensity = int(raised_intensity_raw)
		# Cross-AI Cycle 2 C2 fix: disabled flag pulls per-direction alpha from style_personality,
		# NOT a hard-coded literal. Recipes carrying "disabled": true get style_personality.disabled_opacity.
		var is_disabled: bool = recipe.get("disabled", false)
		# Plan 05-02 Task 2 (D-03): alpha may be a literal float or a `shape.<key>` lookup.
		var alpha_raw: Variant = recipe.get("alpha", 1.0)
		var alpha: float = 1.0
		if typeof(alpha_raw) == TYPE_STRING and (alpha_raw as String).begins_with("shape."):
			var alpha_lookup: Variant = _lookup_shape(style_personality, alpha_raw)
			if alpha_lookup != null and (typeof(alpha_lookup) == TYPE_FLOAT or typeof(alpha_lookup) == TYPE_INT):
				alpha = float(alpha_lookup)
		else:
			alpha = float(alpha_raw)
		if is_disabled:
			alpha = style_personality.disabled_opacity
		if role == "focus_ring":
			# Focus ring is a special stylebox: transparent bg, accent border, expand outside corner.
			# Plan 05-02 Task 2: focus_offset comes from shape per D-08 (per-direction gap).
			var focus_sb := StyleBoxFlat.new()
			focus_sb.bg_color = Color(0, 0, 0, 0)
			focus_sb.border_color = role_table.role_primary
			focus_sb.border_width_left = focus_thickness
			focus_sb.border_width_top = focus_thickness
			focus_sb.border_width_right = focus_thickness
			focus_sb.border_width_bottom = focus_thickness
			# Per-direction shape.primary_radius drives the focus ring radius if the
			# recipe specifies `radius: "shape.<key>"`; otherwise stay on the @export
			# corner_radius. Plan 05-03 wires the radius lookup for variation-specific
			# focus rings; the base focus_ring keeps the @export default.
			var fr_radius: int = corner_radius
			var fr_radius_raw: Variant = recipe.get("radius", null)
			if fr_radius_raw != null and typeof(fr_radius_raw) == TYPE_STRING and (fr_radius_raw as String).begins_with("shape."):
				var fr_r_lookup: Variant = _lookup_shape(style_personality, fr_radius_raw)
				if fr_r_lookup != null and (typeof(fr_r_lookup) == TYPE_INT or typeof(fr_r_lookup) == TYPE_FLOAT):
					fr_radius = int(fr_r_lookup)
			elif fr_radius_raw != null and (typeof(fr_radius_raw) == TYPE_INT or typeof(fr_radius_raw) == TYPE_FLOAT):
				fr_radius = int(fr_radius_raw)
			var focus_corner_profile: String = str(recipe.get("corner_profile", ""))
			if focus_corner_profile == "tab_connected":
				_set_tab_connected_radius(focus_sb, fr_radius)
			elif focus_corner_profile == "top_only":
				_set_top_only_radius(focus_sb, fr_radius)
			elif focus_corner_profile == "bottom_only":
				_set_bottom_only_radius(focus_sb, fr_radius)
			else:
				_set_radius_all(focus_sb, fr_radius)
			# Per-direction focus_offset (DESIGN_TOKENS §8.2): Pulse=0, Burst=1, others=2.
			var focus_offset_v: Variant = _lookup_shape(style_personality, "shape.focus_offset")
			var focus_offset_int: int = 2
			if focus_offset_v != null and (typeof(focus_offset_v) == TYPE_INT or typeof(focus_offset_v) == TYPE_FLOAT):
				focus_offset_int = int(focus_offset_v)
			focus_sb.expand_margin_left = focus_offset_int
			focus_sb.expand_margin_top = focus_offset_int
			focus_sb.expand_margin_right = focus_offset_int
			focus_sb.expand_margin_bottom = focus_offset_int
			focus_sb.shadow_size = 0
			return focus_sb
		var bg_color: Color = role_table.get(role, role_table.surface_panel)
		if alpha < 1.0:
			bg_color = Color(bg_color.r, bg_color.g, bg_color.b, alpha)
		# Pick the matching offset color (per §6.3) for the bg's family.
		var offset_role: String = recipe.get("offset_role", role + "_offset")
		var offset_color: Color = role_table.get(offset_role, role_table.get(role + "_offset", role_table.surface_panel_offset))
		var sb_intensity: int = (raised_strength * raised_intensity) if raised else 0
		var sb := _make_raised_stylebox(bg_color, offset_color, sb_intensity)
		# Plan 05-02 Task 2 (D-03): radius may be either the @export `corner_radius` baseline
		# (no recipe override), an int literal, or a `shape.<key>` lookup. _set_radius_all
		# applies uniformly. The @export `corner_radius` is the variation-agnostic baseline;
		# recipes opting into shape.* pin to per-direction values from DESIGN_TOKENS §5.1-§5.5.
		var radius_raw: Variant = recipe.get("radius", null)
		var resolved_radius: int = corner_radius
		if radius_raw != null:
			if typeof(radius_raw) == TYPE_STRING and (radius_raw as String).begins_with("shape."):
				var r_lookup: Variant = _lookup_shape(style_personality, radius_raw)
				if r_lookup != null and (typeof(r_lookup) == TYPE_INT or typeof(r_lookup) == TYPE_FLOAT):
					resolved_radius = int(r_lookup)
			elif typeof(radius_raw) == TYPE_INT or typeof(radius_raw) == TYPE_FLOAT:
				resolved_radius = int(radius_raw)
		# Phase 12 C6 Bubble: floor (not clamp) every resolved radius to >= min_radius_floor.
		# Pitfall 4: use maxi, NOT mini — Bubble's primary_radius=999 must remain 999.
		var min_floor_raw: Variant = _lookup_shape(style_personality, "shape.min_radius_floor")
		if min_floor_raw != null and (typeof(min_floor_raw) == TYPE_INT or typeof(min_floor_raw) == TYPE_FLOAT):
			var floor_v: int = int(min_floor_raw)
			if floor_v > 0:
				resolved_radius = maxi(resolved_radius, floor_v)
		_set_radius_all(sb, resolved_radius)
		var corner_profile: String = str(recipe.get("corner_profile", ""))
		if corner_profile == "tab_connected":
			_set_tab_connected_radius(sb, resolved_radius)
		elif corner_profile == "top_only":
			_set_top_only_radius(sb, resolved_radius)
		elif corner_profile == "bottom_only":
			_set_bottom_only_radius(sb, resolved_radius)
		var border_width: int = int(recipe.get("border_width", outline_width))
		var border_role: String = recipe.get("border_role", "outline_color")
		var border_color: Color = role_table.get(border_role, role_table.outline_color)
		var border_alpha: float = float(recipe.get("border_alpha", 1.0))
		if border_alpha < 1.0:
			border_color = Color(border_color.r, border_color.g, border_color.b, border_color.a * border_alpha)
		var border_widths_raw: Variant = recipe.get("border_widths", null)
		if border_widths_raw != null and typeof(border_widths_raw) == TYPE_VECTOR4I:
			var widths := border_widths_raw as Vector4i
			sb.border_color = border_color
			sb.border_width_left = maxi(0, widths.x)
			sb.border_width_top = maxi(0, widths.y)
			sb.border_width_right = maxi(0, widths.z)
			sb.border_width_bottom = maxi(0, widths.w)
		else:
			# Phase 12 C6 Slate: when shape.hairline_thickness > 0, force border_width to it
			# for any recipe carrying a border_role (= chrome-with-border, not structural empty).
			# Pitfall 5: shape.hairline_thickness defaults to 0 for non-Slate directions, so
			# this is a no-op everywhere except Style.SLATE.
			var hairline_raw: Variant = _lookup_shape(style_personality, "shape.hairline_thickness")
			var hairline_resolved: int = 0
			if hairline_raw != null and (typeof(hairline_raw) == TYPE_INT or typeof(hairline_raw) == TYPE_FLOAT):
				hairline_resolved = int(hairline_raw)
			if hairline_resolved > 0 and recipe.has("border_role"):
				border_width = hairline_resolved
			_apply_outline_border(sb, border_color, maxi(0, border_width))
		# Plan 05-02 Task 2 (D-03): padding may be a `shape.<key>` Vector2i lookup
		# or an explicit Vector2i. Unspecified padding is zero; structural styleboxes must
		# opt into content margins instead of inheriting giant global chrome.
		var content_margins_raw: Variant = recipe.get("content_margins", null)
		var padding_raw: Variant = recipe.get("padding", null)
		var mobile_padding_raw: Variant = recipe.get("mobile_padding", null)
		var applied_padding: bool = false
		if tokens.get("densityScale", 1.0) > 1.0 and mobile_padding_raw != null and typeof(mobile_padding_raw) == TYPE_VECTOR2I:
			_set_content_margin_from_padding(sb, mobile_padding_raw as Vector2i)
			applied_padding = true
		elif content_margins_raw != null and typeof(content_margins_raw) == TYPE_VECTOR4I:
			var density: float = tokens.get("densityScale", 1.0)
			var margins := content_margins_raw as Vector4i
			_set_content_margins(sb, Vector4i(
				int(round(margins.x * density)),
				int(round(margins.y * density)),
				int(round(margins.z * density)),
				int(round(margins.w * density))
			))
			applied_padding = true
		elif padding_raw != null and typeof(padding_raw) == TYPE_STRING and (padding_raw as String).begins_with("shape."):
			var pad_lookup: Variant = _lookup_shape(style_personality, padding_raw)
			if pad_lookup != null and typeof(pad_lookup) == TYPE_VECTOR2I:
				var density: float = tokens.get("densityScale", 1.0)
				_set_content_margin_from_padding(sb, Vector2i(int(round(pad_lookup.x * density)), int(round(pad_lookup.y * density))))
				applied_padding = true
		elif padding_raw != null and typeof(padding_raw) == TYPE_VECTOR2I:
			var density: float = tokens.get("densityScale", 1.0)
			_set_content_margin_from_padding(sb, Vector2i(int(round((padding_raw as Vector2i).x * density)), int(round((padding_raw as Vector2i).y * density))))
			applied_padding = true
		if not applied_padding:
			_set_content_margin_from_padding(sb, Vector2i.ZERO)
		# Phase 12 C6 Burst: floor primary-button content_margin sum to shape.primary_min_height
		# when set; gated on strategy ending in .primary_strategy so only primary buttons grow.
		# D-12.11 spec: 56 desktop / 64 mobile. Mobile override via primary_min_height_mobile,
		# resolved when densityScale > 1.0 (per _platform_tokens MOBILE path).
		if recipe.has("strategy") and String(recipe.get("strategy", "")).ends_with(".primary_strategy"):
			var min_h_raw: Variant = _lookup_shape(style_personality, "shape.primary_min_height")
			var min_h_resolved: int = 0
			if min_h_raw != null and (typeof(min_h_raw) == TYPE_INT or typeof(min_h_raw) == TYPE_FLOAT):
				min_h_resolved = int(min_h_raw)
			# Apply mobile override (D-12.11): use primary_min_height_mobile when on mobile density.
			if tokens.get("densityScale", 1.0) > 1.0:
				var min_h_mobile_raw: Variant = _lookup_shape(style_personality, "shape.primary_min_height_mobile")
				if min_h_mobile_raw != null and (typeof(min_h_mobile_raw) == TYPE_INT or typeof(min_h_mobile_raw) == TYPE_FLOAT):
					var mobile_val: int = int(min_h_mobile_raw)
					if mobile_val > 0:
						min_h_resolved = mobile_val
			if min_h_resolved > 0:
				var content_h: int = int(tokens.get("body", 14))
				var current_min: int = sb.content_margin_top + content_h + sb.content_margin_bottom
				if current_min < min_h_resolved:
					var extra: int = min_h_resolved - current_min
					var half_extra: int = extra / 2
					sb.content_margin_top += half_extra
					sb.content_margin_bottom += (extra - half_extra)
		var expand_margins_raw: Variant = recipe.get("expand_margins", null)
		if expand_margins_raw != null and typeof(expand_margins_raw) == TYPE_VECTOR4I:
			var expand_density: float = tokens.get("densityScale", 1.0)
			var expand := expand_margins_raw as Vector4i
			_set_expand_margins(sb, Vector4i(
				int(round(expand.x * expand_density)),
				int(round(expand.y * expand_density)),
				int(round(expand.z * expand_density)),
				int(round(expand.w * expand_density))
			))
		# Plan 05-02 Task 2 (D-04): strategy dispatch (closed-enum, sourced VERBATIM
		# from DESIGN_TOKENS §5.1-§5.5). Recipes opt-in via `strategy: "shape.primary_strategy"`
		# (or `"shape.ghost_strategy"`); _apply_primary_strategy / _apply_ghost_strategy
		# mutate the StyleBoxFlat in place per the active direction's strategy enum.
		var strategy_raw: Variant = recipe.get("strategy", null)
		if strategy_raw != null and typeof(strategy_raw) == TYPE_STRING:
			var strat_lookup: Variant = _lookup_shape(style_personality, strategy_raw)
			if strat_lookup != null:
				var strat_name: StringName = strat_lookup if typeof(strat_lookup) == TYPE_STRING_NAME else StringName(String(strat_lookup))
				# Dispatch via path: shape.primary_strategy → primary; shape.ghost_strategy → ghost.
				if (strategy_raw as String).ends_with(".primary_strategy"):
					_apply_primary_strategy(sb, strat_name, role_table, style_personality)
				elif (strategy_raw as String).ends_with(".ghost_strategy"):
					_apply_ghost_strategy(sb, strat_name, role_table, style_personality)
				# Other strategy paths (kicker_style etc.) are NOT dispatched on stylebox;
				# they're color-recipe territory handled below.
		# Phase 12 C6 Daybreak: 1px flat accent outline at 3px offset for primary buttons,
		# gated on raised=true (SC#1) and primary-strategy recipes only.
		# Pitfall 3: full alpha mandatory (no border_alpha < 1.0); GL Compat over-renders intermediate alpha.
		if raised and strategy_raw != null and typeof(strategy_raw) == TYPE_STRING and (strategy_raw as String).ends_with(".primary_strategy"):
			var outline_width_v: Variant = _lookup_shape(style_personality, "shape.primary_outline_width")
			var outline_width_resolved: int = 0
			if outline_width_v != null and (typeof(outline_width_v) == TYPE_INT or typeof(outline_width_v) == TYPE_FLOAT):
				outline_width_resolved = int(outline_width_v)
			if outline_width_resolved > 0:
				var outline_color_key_v: Variant = _lookup_shape(style_personality, "shape.primary_outline_color")
				var outline_color_key: String = "role_primary"
				if outline_color_key_v != null:
					outline_color_key = String(outline_color_key_v)
				var outline_color_c: Color = role_table.get(outline_color_key, role_table.role_primary)
				# Override the strategy-applied border with the outline (full alpha — Pitfall 3).
				sb.border_color = outline_color_c
				sb.border_width_left = outline_width_resolved
				sb.border_width_top = outline_width_resolved
				sb.border_width_right = outline_width_resolved
				sb.border_width_bottom = outline_width_resolved
				# Push the border outside the control rect via expand_margin (3px offset).
				# CR-01: skip this overwrite when the recipe itself supplied `expand_margins`;
				# composing both would silently replace recipe-author intent. No current
				# primary-strategy recipe carries expand_margins, but guard prevents future
				# silent regression. See REVIEW.md CR-01 (2026-05-11).
				if not recipe.has("expand_margins"):
					var outline_offset_v: Variant = _lookup_shape(style_personality, "shape.primary_outline_offset")
					var outline_offset_resolved: int = 0
					if outline_offset_v != null and (typeof(outline_offset_v) == TYPE_INT or typeof(outline_offset_v) == TYPE_FLOAT):
						outline_offset_resolved = int(outline_offset_v)
					sb.expand_margin_left = outline_offset_resolved
					sb.expand_margin_top = outline_offset_resolved
					sb.expand_margin_right = outline_offset_resolved
					sb.expand_margin_bottom = outline_offset_resolved
		if recipe.has("state_layer_role"):
			var layer_role: String = recipe.get("state_layer_role", "role_primary")
			var layer_color: Color = role_table.get(layer_role, role_table.role_primary)
			var layer_alpha := clampf(float(recipe.get("state_layer_alpha", 0.0)), 0.0, 1.0)
			sb.bg_color = Color(layer_color.r, layer_color.g, layer_color.b, layer_alpha)
		if sb_intensity > 0:
			var keep_face_edge: bool = bool(recipe.get("raised_face_edge", false))
			var reserve_height: bool = bool(recipe.get("reserve_raised_depth", true))
			_apply_raised_depth_border(sb, offset_color, sb_intensity, keep_face_edge, reserve_height)
		return sb
	elif data_type == "color":
		var role: String = recipe.get("role", "text_strong")
		# Cross-AI Cycle 2 C2 fix: disabled flag pulls per-direction alpha from style_personality.
		var is_disabled: bool = recipe.get("disabled", false)
		# Plan 05-02 Task 2 (D-03): alpha may be a literal or shape.<key> lookup here too.
		var alpha_raw: Variant = recipe.get("alpha", 1.0)
		var alpha: float = 1.0
		if typeof(alpha_raw) == TYPE_STRING and (alpha_raw as String).begins_with("shape."):
			var alpha_lookup: Variant = _lookup_shape(style_personality, alpha_raw)
			if alpha_lookup != null and (typeof(alpha_lookup) == TYPE_FLOAT or typeof(alpha_lookup) == TYPE_INT):
				alpha = float(alpha_lookup)
		else:
			alpha = float(alpha_raw)
		if is_disabled:
			alpha = style_personality.disabled_opacity
		# Plan 05-02 Task 2 (D-09 prep): recipes can reference `kicker_style: "shape.kicker_style"`
		# to dispatch per-direction Kicker color. Plan 05-04 wires the actual Kicker
		# variation entry; the helper is registered here.
		var kicker_style_raw: Variant = recipe.get("kicker_style", null)
		if kicker_style_raw != null and typeof(kicker_style_raw) == TYPE_STRING and (kicker_style_raw as String).begins_with("shape."):
			var kstyle_lookup: Variant = _lookup_shape(style_personality, kicker_style_raw)
			if kstyle_lookup != null:
				var kname: StringName = kstyle_lookup if typeof(kstyle_lookup) == TYPE_STRING_NAME else StringName(String(kstyle_lookup))
				var kcolor: Color = _apply_kicker_style(kname, role_table)
				if alpha < 1.0:
					kcolor = Color(kcolor.r, kcolor.g, kcolor.b, alpha)
				return kcolor
		var c: Color = role_table.get(role, role_table.text_strong)
		if alpha < 1.0:
			c = Color(c.r, c.g, c.b, alpha)
		return c
	elif data_type == "constant" or data_type == "font_size":
		var value_ref = recipe.get("value", 0)
		if tokens.get("densityScale", 1.0) > 1.0 and recipe.has("mobile_value"):
			value_ref = recipe.get("mobile_value", value_ref)
		if typeof(value_ref) == TYPE_STRING and (value_ref as String).begins_with("tokens."):
			var key: String = (value_ref as String).substr(7)
			return tokens.get(key, 0)
		# Plan 05-02 Task 2 (D-03): constants/font_sizes can also pull from shape.* (e.g.,
		# `value: "shape.focus_offset"` for outline widths or focus expand metadata).
		if typeof(value_ref) == TYPE_STRING and (value_ref as String).begins_with("shape."):
			var shape_v: Variant = _lookup_shape(style_personality, value_ref)
			if shape_v != null and (typeof(shape_v) == TYPE_INT or typeof(shape_v) == TYPE_FLOAT):
				return int(shape_v)
			return 0
		return int(value_ref)
	elif data_type == "icon":
		var generated_icon_name: String = recipe.get("generated_icon", "")
		if generated_icon_name == "split_grabber":
			return _make_split_grabber_icon(recipe.get("orientation", "vertical") == "vertical", role_table, style_personality)
		if generated_icon_name == "slider_grabber":
			return _make_slider_grabber_icon(bool(recipe.get("highlight", false)), role_table, style_personality, tokens)
		if generated_icon_name == "color_hue":
			return _make_color_hue_texture()
		if generated_icon_name == "search":
			var search_scale := 0.75
			if tokens.get("densityScale", 1.0) > 1.0 and recipe.has("mobile_svg_scale"):
				search_scale = float(recipe.get("mobile_svg_scale", 0.75))
			return _make_search_icon(search_scale)
		if generated_icon_name == "popup_selection_checkbox":
			var checkbox_popup_scale := 0.0
			if tokens.get("densityScale", 1.0) > 1.0 and recipe.has("mobile_svg_scale"):
				checkbox_popup_scale = float(recipe.get("mobile_svg_scale", 0.0))
			if use_runtime_popup_selection_icons:
				return _make_popup_selection_checkbox_icon(
					bool(recipe.get("checked", false)),
					bool(recipe.get("disabled", false)),
					role_table,
					0.75 if checkbox_popup_scale <= 0.0 else checkbox_popup_scale
				)
			return _load_icon("checkbox_checked" if bool(recipe.get("checked", false)) else "checkbox_unchecked", checkbox_popup_scale)
		if generated_icon_name == "popup_selection_radio":
			var radio_popup_scale := 0.0
			if tokens.get("densityScale", 1.0) > 1.0 and recipe.has("mobile_svg_scale"):
				radio_popup_scale = float(recipe.get("mobile_svg_scale", 0.0))
			if use_runtime_popup_selection_icons:
				return _make_popup_selection_radio_icon(
					bool(recipe.get("checked", false)),
					bool(recipe.get("disabled", false)),
					role_table,
					0.75 if radio_popup_scale <= 0.0 else radio_popup_scale
				)
			return _load_icon("radio_checked" if bool(recipe.get("checked", false)) else "radio_unchecked", radio_popup_scale)
		var icon_name: String = recipe.get("icon", "")
		if icon_name == "":
			return null
		if icon_name == "empty":
			return _empty_icon()
		var mobile_svg_scale := 0.0
		if tokens.get("densityScale", 1.0) > 1.0 and recipe.has("mobile_svg_scale"):
			mobile_svg_scale = float(recipe.get("mobile_svg_scale", 0.0))
		return _load_icon(icon_name, mobile_svg_scale)
	# Cross-AI Cycle 2 N1 fix: any unrecognized data_type (including the now-removed "font")
	# falls through to null — caller skips silently per D-04 escape hatch.
	return null


func _load_icon(icon_name: String, svg_scale: float = 0.0) -> Texture2D:
	var cache_key := "%s@%.3f" % [icon_name, svg_scale] if svg_scale > 0.0 else icon_name
	var cached: Texture2D = _active_icon_cache.get(cache_key)
	if cached != null:
		return cached
	var path := "res://addons/neocade_theme/icons/" + icon_name + ".svg"
	if svg_scale > 0.0:
		var svg := FileAccess.get_file_as_string(path)
		if not svg.is_empty():
			var image := Image.new()
			var error := image.load_svg_from_string(svg, svg_scale)
			if error == OK:
				var texture := ImageTexture.create_from_image(image)
				_active_icon_cache[cache_key] = texture
				return texture
	var icon := load(path) as Texture2D
	if icon != null:
		_active_icon_cache[cache_key] = icon
	return icon


func _empty_icon() -> Texture2D:
	const CACHE_KEY := "__empty"
	var cached: Texture2D = _active_generated_texture_cache.get(CACHE_KEY)
	if cached != null:
		return cached
	var icon := ImageTexture.new()
	_active_generated_texture_cache[CACHE_KEY] = icon
	return icon


func _make_split_grabber_icon(vertical_indicator: bool, role_table: Dictionary, style_personality: Dictionary) -> Texture2D:
	const THICKNESS := 6
	const LENGTH := 48
	var width := THICKNESS if vertical_indicator else LENGTH
	var height := LENGTH if vertical_indicator else THICKNESS
	var shape_radius: int = corner_radius
	var radius_lookup: Variant = _lookup_shape(style_personality, "shape.secondary_radius")
	if radius_lookup != null and (typeof(radius_lookup) == TYPE_INT or typeof(radius_lookup) == TYPE_FLOAT):
		shape_radius = int(radius_lookup)
	var radius: float = float(clampi(shape_radius, 0, int(THICKNESS / 2)))
	var grabber_color: Color = role_table.get("text_muted", Color.WHITE)
	grabber_color = Color(grabber_color.r, grabber_color.g, grabber_color.b, grabber_color.a * 0.72)
	var cache_key := "split:%s:%d:%s" % ["v" if vertical_indicator else "h", int(radius), grabber_color.to_html(true)]
	var cached: Texture2D = _active_generated_texture_cache.get(cache_key)
	if cached != null:
		return cached

	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in range(height):
		for x in range(width):
			var coverage := 1.0
			if radius > 0.0:
				var px := float(x) + 0.5
				var py := float(y) + 0.5
				var nearest_x := clampf(px, radius, float(width) - radius)
				var nearest_y := clampf(py, radius, float(height) - radius)
				var dist := Vector2(px - nearest_x, py - nearest_y).length() - radius
				coverage = clampf(1.0 - dist, 0.0, 1.0)
			if coverage > 0.0:
				image.set_pixel(x, y, Color(grabber_color.r, grabber_color.g, grabber_color.b, grabber_color.a * coverage))
	var texture := ImageTexture.create_from_image(image)
	_active_generated_texture_cache[cache_key] = texture
	return texture


func _make_slider_grabber_icon(highlight: bool, role_table: Dictionary, style_personality: Dictionary, tokens: Dictionary) -> Texture2D:
	var mobile: bool = tokens.get("densityScale", 1.0) > 1.0
	var size := 48 if mobile else 16
	var shape_radius: int = corner_radius
	var radius_lookup: Variant = _lookup_shape(style_personality, "shape.secondary_radius")
	if radius_lookup != null and (typeof(radius_lookup) == TYPE_INT or typeof(radius_lookup) == TYPE_FLOAT):
		shape_radius = int(radius_lookup)
	var outer_radius := float(clampi(shape_radius, 0, 8 if mobile else 5))
	var inner_radius := float(clampi(shape_radius, 0, 6 if mobile else 3))
	var knob_size := 20 if mobile else 10
	var ring_size := 30 if mobile else 14
	var knob_origin := int((size - knob_size) / 2)
	var ring_origin := int((size - ring_size) / 2)
	var knob_color: Color = role_table.get("text_muted", Color.WHITE)
	knob_color = Color(knob_color.r, knob_color.g, knob_color.b, 0.92)
	var ring_color: Color = role_table.get("role_primary", Color.WHITE)
	ring_color = Color(ring_color.r, ring_color.g, ring_color.b, 0.95)
	var cache_key := "slider:%s:%d:%d:%d:%d:%d:%s:%s" % [
		"highlight" if highlight else "normal",
		size,
		knob_size,
		ring_size,
		int(outer_radius),
		int(inner_radius),
		knob_color.to_html(true),
		ring_color.to_html(true),
	]
	var cached: Texture2D = _active_generated_texture_cache.get(cache_key)
	if cached != null:
		return cached
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	if highlight:
		_fill_round_rect(image, Rect2i(ring_origin, ring_origin, ring_size, ring_size), outer_radius, ring_color)
		_fill_round_rect(image, Rect2i(knob_origin, knob_origin, knob_size, knob_size), inner_radius, knob_color)
	else:
		_fill_round_rect(image, Rect2i(knob_origin, knob_origin, knob_size, knob_size), inner_radius, knob_color)
	var texture := ImageTexture.create_from_image(image)
	_active_generated_texture_cache[cache_key] = texture
	return texture


func _make_color_hue_texture() -> Texture2D:
	const WIDTH := 800
	const HEIGHT := 6
	const CACHE_KEY := "color_hue"
	var cached: Texture2D = _active_generated_texture_cache.get(CACHE_KEY)
	if cached != null:
		return cached
	# Compute one 800x1 row, then blit it into each of HEIGHT rows of the target
	# image via Image.blit_rect (one same-format memcpy per row in the engine).
	# Replaces a 800x6 nested set_pixel loop where 5 of every 6 writes copied an
	# identical RGBA8 value to a different Y. Pixel output is byte-identical
	# (verified via Image.get_data() comparison).
	var row := Image.create(WIDTH, 1, false, Image.FORMAT_RGBA8)
	for x in range(WIDTH):
		row.set_pixel(x, 0, Color.from_hsv(float(x) / float(WIDTH - 1), 1.0, 1.0))
	var image := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	for y in range(HEIGHT):
		image.blit_rect(row, Rect2i(0, 0, WIDTH, 1), Vector2i(0, y))
	var texture := ImageTexture.create_from_image(image)
	_active_generated_texture_cache[CACHE_KEY] = texture
	return texture


func _make_search_icon(svg_scale: float = 0.75) -> Texture2D:
	var cache_key := "search:%.3f" % svg_scale
	var cached: Texture2D = _active_generated_texture_cache.get(cache_key)
	if cached != null:
		return cached
	var svg := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"32\" height=\"32\" viewBox=\"0 0 32 32\" fill=\"none\"><circle cx=\"14\" cy=\"14\" r=\"7\" stroke=\"#FFFFFF\" stroke-width=\"3\"/><path d=\"M19.5 19.5 L26 26\" stroke=\"#FFFFFF\" stroke-width=\"3\" stroke-linecap=\"round\"/></svg>"
	return _make_svg_icon_texture(svg, cache_key, svg_scale)


func _popup_selection_fill(checked: bool, disabled: bool, role_table: Dictionary) -> Color:
	var fill: Color = role_table.get("role_primary", Color.WHITE) if checked else role_table.get("selection_control_off", Color(0.70, 0.74, 0.86))
	if disabled:
		fill = _mix(fill, role_table.get("surface_base", Color.BLACK), 0.58)
	return fill


func _make_popup_selection_checkbox_icon(checked: bool, disabled: bool, role_table: Dictionary, svg_scale: float = 0.75) -> Texture2D:
	var fill_color := _popup_selection_fill(checked, disabled, role_table)
	var cache_key := "popup_checkbox:%s:%s:%s:%.3f" % ["checked" if checked else "unchecked", "disabled" if disabled else "enabled", fill_color.to_html(true), svg_scale]
	var cached: Texture2D = _active_generated_texture_cache.get(cache_key)
	if cached != null:
		return cached
	var check_path := ""
	if checked:
		check_path = "<path d=\"M9 16.5 L14 21.5 L23 11\" stroke=\"#000000\" stroke-width=\"3\" stroke-linecap=\"round\" stroke-linejoin=\"round\" fill=\"none\"/>"
	var svg := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"32\" height=\"32\" viewBox=\"0 0 32 32\" fill=\"none\"><rect x=\"4\" y=\"4\" width=\"24\" height=\"24\" rx=\"3\" fill=\"%s\"/>%s</svg>" % [_color_to_svg_hex(fill_color), check_path]
	return _make_svg_icon_texture(svg, cache_key, svg_scale)


func _make_popup_selection_radio_icon(checked: bool, disabled: bool, role_table: Dictionary, svg_scale: float = 0.75) -> Texture2D:
	var fill_color := _popup_selection_fill(checked, disabled, role_table)
	var cache_key := "popup_radio:%s:%s:%s:%.3f" % ["checked" if checked else "unchecked", "disabled" if disabled else "enabled", fill_color.to_html(true), svg_scale]
	var cached: Texture2D = _active_generated_texture_cache.get(cache_key)
	if cached != null:
		return cached
	var knob_circle := ""
	if checked:
		knob_circle = "<circle cx=\"16\" cy=\"16\" r=\"5\" fill=\"#000000\"/>"
	var svg := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"32\" height=\"32\" viewBox=\"0 0 32 32\" fill=\"none\"><circle cx=\"16\" cy=\"16\" r=\"12\" fill=\"%s\"/>%s</svg>" % [_color_to_svg_hex(fill_color), knob_circle]
	return _make_svg_icon_texture(svg, cache_key, svg_scale)


func _make_svg_icon_texture(svg: String, cache_key: String, svg_scale: float = 0.75) -> Texture2D:
	var image := Image.new()
	var error := image.load_svg_from_string(svg, svg_scale)
	if error != OK:
		push_warning("NeoCadeTheme: failed to rasterize generated SVG icon.")
		image = Image.create(24, 24, false, Image.FORMAT_RGBA8)
		image.fill(Color(0, 0, 0, 0))
	var texture := ImageTexture.create_from_image(image)
	_active_generated_texture_cache[cache_key] = texture
	return texture


func _color_to_svg_hex(color: Color) -> String:
	return "#%02X%02X%02X" % [
		int(roundf(clampf(color.r, 0.0, 1.0) * 255.0)),
		int(roundf(clampf(color.g, 0.0, 1.0) * 255.0)),
		int(roundf(clampf(color.b, 0.0, 1.0) * 255.0)),
	]


func _fill_round_rect(image: Image, rect: Rect2i, radius: float, color: Color) -> void:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var coverage := 1.0
			if radius > 0.0:
				var px := float(x - rect.position.x) + 0.5
				var py := float(y - rect.position.y) + 0.5
				var max_x := float(rect.size.x) - radius
				var max_y := float(rect.size.y) - radius
				var nearest_x := clampf(px, radius, max_x)
				var nearest_y := clampf(py, radius, max_y)
				var dist := Vector2(px - nearest_x, py - nearest_y).length() - radius
				coverage = clampf(1.0 - dist, 0.0, 1.0)
			if coverage > 0.0:
				image.set_pixel(x, y, Color(color.r, color.g, color.b, color.a * coverage))
