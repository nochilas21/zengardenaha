extends Node

# Global music box (autoload "MusicManager"), shared by ALL shelves.
# While it has wind, EVERY plant with a due music need — on any shelf — gains
# listening time at the same time. If the wind runs out, each plant's
# continuous-listening progress resets to 0 (see Plot._tick_music_need).

signal music_state_changed(current_wind: float, max_wind: float, is_playing: bool)

const MUSIC_BOX_SCENE = preload("res://scenes/ui/music_box.tscn")

var current_wind: float = 0.0
var max_wind: float = 100.0
var drain_per_sec: float = 4.0       # ~25s to fully drain from max if left alone (placeholder)
var wind_per_click: float = 30.0     # each "Wind Up" click adds this much (placeholder)

var _viewer: Control = null          # the open music box window, or null

func _process(delta: float) -> void:
	if current_wind > 0.0:
		current_wind = max(0.0, current_wind - drain_per_sec * delta)
		music_state_changed.emit(current_wind, max_wind, is_playing())

func is_playing() -> bool:
	return current_wind > 0.0

func wind(amount: float = -1.0) -> void:
	if amount < 0.0:
		amount = wind_per_click
	current_wind = min(max_wind, current_wind + amount)
	music_state_changed.emit(current_wind, max_wind, is_playing())

func set_wind(value: float) -> void:
	# Used by save/load
	current_wind = clamp(value, 0.0, max_wind)
	music_state_changed.emit(current_wind, max_wind, is_playing())

func open_ui() -> void:
	if _viewer != null and is_instance_valid(_viewer):
		var existing = _viewer.get_window()
		if existing != null:
			existing.grab_focus()
		return   # already open
	# The music box gets its own small OS window, so it works even when the
	# main window is hidden. Closing it (or "Minimize") only closes the viewer;
	# the music keeps playing/draining here.
	var win = Window.new()
	win.title = "Music Box"
	win.unresizable = true
	win.always_on_top = true
	UiScale.track(win, Vector2(400, 300))
	win.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	get_tree().root.add_child(win)
	_viewer = MUSIC_BOX_SCENE.instantiate()
	win.add_child(_viewer)
	var panel = _viewer.get_node_or_null("Panel")
	if panel is Control:
		panel.position = Vector2(10, 10)
	_viewer.tree_exiting.connect(_on_viewer_closed.bind(win))
	win.close_requested.connect(_close_viewer)
	_fit_window.call_deferred(win)

func _on_viewer_closed(win: Window) -> void:
	_viewer = null
	if is_instance_valid(win):
		win.queue_free()

func _close_viewer() -> void:
	if _viewer != null and is_instance_valid(_viewer):
		_viewer.queue_free()

func _fit_window(win: Window) -> void:
	if _viewer == null or not is_instance_valid(win):
		return
	var panel = _viewer.get_node_or_null("Panel")
	if panel is Control:
		UiScale.track(win, Vector2(panel.position.x + panel.size.x + 10, panel.position.y + panel.size.y + 10))

# Every plot (any shelf) whose music need is currently due.
func get_listening_plots() -> Array:
	var result: Array = []
	for node in get_tree().get_nodes_in_group("plots"):
		if node is Plot and node.plant_data != null and node.is_need_due("music"):
			result.append(node)
	return result
