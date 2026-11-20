extends Node

# Autoload "UiScale": one scale factor for EVERY window the game opens
# (shelves, menu light, pickers, inventory, scale, bugs, drag ghosts...).
#
# Every window is designed at 100% (in "design pixels"). On a high-DPI /
# high-resolution screen the whole thing is drawn bigger with Godot's
# Window.content_scale_factor, and the OS window size is multiplied too, so
# layouts never change — only the size on screen does.
#
#   factor = the player's choice in Settings, or "Auto" (from the screen's DPI)
#
# For a simple window with a fixed design size:
#   UiScale.track(window, Vector2(360, 420))   # sets it now and on every change
# Windows that size themselves (shelves, menu light) read UiScale.factor in
# their own layout code and listen to UiScale.changed.
# Converting between screen pixels and a window's content:
#   UiScale.to_content(window, screen_pos)  /  UiScale.to_screen(window, content_pos)

signal changed(factor: float)

const MIN_FACTOR: float = 0.75
const MAX_FACTOR: float = 3.0

var factor: float = 1.0
var override: float = 0.0   # 0 = Auto

var _tracked: Array = []    # [{"win": WeakRef, "size": Vector2}]

func _ready() -> void:
	factor = auto_factor()

# Auto: Windows reports DPI (96 = 100%); macOS / Wayland report a scale directly.
func auto_factor() -> float:
	var screen = DisplayServer.window_get_current_screen()
	var f = DisplayServer.screen_get_scale(screen)
	if f <= 1.0:
		var dpi = DisplayServer.screen_get_dpi(screen)
		if dpi > 0:
			f = dpi / 96.0
	# Very large screens with a 100% OS setting (e.g. 4K at 100%) still get bigger
	var height = DisplayServer.screen_get_size(screen).y
	if height > 0:
		f = max(f, height / 1080.0)
	return clamp(snappedf(f, 0.25), MIN_FACTOR, MAX_FACTOR)

# value 0 = Auto, otherwise e.g. 1.25 for 125%
func set_override(value: float) -> void:
	override = value
	var new_factor = clamp(value, MIN_FACTOR, MAX_FACTOR) if value > 0.0 else auto_factor()
	if is_equal_approx(new_factor, factor):
		return
	factor = new_factor
	_apply_tracked()
	changed.emit(factor)

func size_for(design_size: Vector2) -> Vector2i:
	return Vector2i(ceili(design_size.x * factor), ceili(design_size.y * factor))

# Scales a window that has one fixed design size, now and on every change.
func track(win: Window, design_size: Vector2) -> void:
	_tracked.append({"win": weakref(win), "size": design_size})
	_apply(win, design_size)

func _apply(win: Window, design_size: Vector2) -> void:
	win.content_scale_factor = factor
	win.size = size_for(design_size)

func _apply_tracked() -> void:
	var alive: Array = []
	for entry in _tracked:
		var win = entry["win"].get_ref()
		if win != null and is_instance_valid(win):
			_apply(win, entry["size"])
			alive.append(entry)
	_tracked = alive

func to_content(win: Window, screen_pos: Vector2i) -> Vector2:
	return Vector2(screen_pos - win.position) / max(0.01, win.content_scale_factor)

func to_screen(win: Window, content_pos: Vector2) -> Vector2i:
	return win.position + Vector2i(content_pos * win.content_scale_factor)
