extends Control
class_name MusicBox

# Viewer for the global MusicManager. Closing this window does NOT stop the
# music draining — the state lives in MusicManager. Reopen via MusicManager.open_ui().
# Lists every plant currently waiting for music (any shelf) with a clock
# showing how many seconds of continuous music it has heard.

const LIST_REFRESH_SEC: float = 0.1

@onready var meter: ProgressBar = $Panel/Meter
@onready var wind_button: Button = $Panel/WindButton
@onready var minimize_button: Button = $Panel/MinimizeButton
@onready var status_label: Label = $Panel/StatusLabel
var listen_list: VBoxContainer   # built in code if the scene doesn't have it

var _refresh_t: float = 0.0
var _showing_empty: bool = false
var _built: bool = false

func _ready() -> void:
	_ensure_listen_list()
	MusicManager.music_state_changed.connect(_on_music_state_changed)
	wind_button.pressed.connect(func(): MusicManager.wind())
	minimize_button.pressed.connect(queue_free)   # closes the viewer only
	_on_music_state_changed(MusicManager.current_wind, MusicManager.max_wind, MusicManager.is_playing())
	_refresh_listeners()

func _process(delta: float) -> void:
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = LIST_REFRESH_SEC
		_refresh_listeners()

func _on_music_state_changed(current_wind: float, max_wind: float, is_playing: bool) -> void:
	meter.max_value = max_wind
	meter.value = current_wind
	if is_playing:
		status_label.text = "Playing — %.0f%%" % (current_wind / max_wind * 100.0)
		meter.modulate = Color(1, 1, 1).lerp(Color(1, 0.3, 0.3), 1.0 - (current_wind / max_wind))
	else:
		status_label.text = "Stopped — wind it up"
		meter.modulate = Color(0.6, 0.6, 0.6)

func _refresh_listeners() -> void:
	var plots = MusicManager.get_listening_plots()
	# Rebuild only when the list shape changes; otherwise just update values
	var needs_rebuild = not _built or plots.is_empty() != _showing_empty or (not plots.is_empty() and listen_list.get_child_count() != plots.size())
	if needs_rebuild:
		for child in listen_list.get_children():
			listen_list.remove_child(child)
			child.queue_free()
		_built = true
		_showing_empty = plots.is_empty()
		if _showing_empty:
			var empty = Label.new()
			empty.text = "No plant needs music right now."
			empty.modulate = Color(1, 1, 1, 0.6)
			listen_list.add_child(empty)
		else:
			for i in range(plots.size()):
				listen_list.add_child(_make_row())
	if _showing_empty:
		return
	for i in range(plots.size()):
		var plot: Plot = plots[i]
		var row = listen_list.get_child(i)
		var ring: ClockRing = row.get_child(0)
		var label: Label = row.get_child(1)
		var heard = plot.get_music_progress()
		var required = plot.get_music_required()
		ring.progress = heard / required if required > 0.0 else 0.0
		label.text = "%s  %s   %.1f / %.0fs" % [plot.get_location_text(), plot.plant_data.display_name, heard, required]

# The listening list is created in code, so music_box.tscn can stay as the
# team designs it in the editor. If the scene already has
# Panel/ListenScroll/ListenList, that one is used instead.
func _ensure_listen_list() -> void:
	var existing = get_node_or_null("Panel/ListenScroll/ListenList")
	if existing is VBoxContainer:
		listen_list = existing
		return
	var panel: Control = $Panel
	var top = minimize_button.position.y + minimize_button.size.y + 8.0
	var width = max(panel.size.x, 380.0)
	var title = Label.new()
	title.text = "Plants listening (continuous seconds):"
	title.position = Vector2(10, top)
	title.size = Vector2(width - 20.0, 22)
	panel.add_child(title)
	var scroll = ScrollContainer.new()
	scroll.name = "ListenScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.position = Vector2(10, top + 24.0)
	scroll.size = Vector2(width - 20.0, 130)
	panel.add_child(scroll)
	listen_list = VBoxContainer.new()
	listen_list.name = "ListenList"
	listen_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(listen_list)
	panel.size = Vector2(width, top + 24.0 + 130.0 + 10.0)

func _make_row() -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var ring = ClockRing.new()
	ring.custom_minimum_size = Vector2(24, 24)
	row.add_child(ring)
	var label = Label.new()
	row.add_child(label)
	return row
