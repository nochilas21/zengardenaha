extends Window
class_name GridWindow

# A "shelf" (kệ): one transparent, borderless, always-on-top OS window holding
# DEFAULT_SLOTS..MAX_SLOTS plot slots. Drag it anywhere on the desktop by its
# title bar. Built entirely in code (no .tscn) — create with GridWindow.new(),
# add_child() it, THEN call setup().
# Requires Project Settings → Display → Window → Subwindows → Embed Subwindows = Off.

signal sunlight_charges_changed(remaining: int)
signal music_state_changed(current_wind: float, max_wind: float, is_playing: bool)
signal plot_clicked(plot: Plot)
signal drag_finished()
signal slots_changed()

const PLOT_SCENE = preload("res://scenes/plot.tscn")
const DEFAULT_SLOTS: int = 3
const MAX_SLOTS: int = 5
const SLOT_UNLOCK_COST: Dictionary = {4: 200, 5: 400}   # placeholder prices for slot 4 and 5

var shelf_index: int = 1
var plot_container: GridContainer

var _root_panel: PanelContainer
var _title_label: Label
var _add_slot_button: Button
var _dragging: bool = false
var _drag_offset: Vector2i = Vector2i.ZERO

var sunlight_charges_remaining: int = 0

# Music is a shared, shelf-level background process: the wind level lives here
# and keeps draining whether or not any viewer window is open. The shelf only
# reports whether music is playing — each Plot counts its own continuous
# listening time and satisfies its own music need (see Plot._tick_music_need).
var music_current_wind: float = 0.0
var music_max_wind: float = 100.0
var music_drain_per_sec: float = 4.0       # ~25s to fully drain from max if left alone
var music_wind_per_click: float = 30.0     # each "Wind Up" click adds this much
var music_box_window: Control = null       # the currently-open viewer, or null if closed

func _init() -> void:
	# Window flags must be set before the OS window is created (i.e. before add_child)
	borderless = true
	transparent = true
	transparent_bg = true
	always_on_top = true
	unresizable = true

func _ready() -> void:
	_build_ui()

func setup(index: int, start_pos: Vector2i) -> void:
	shelf_index = index
	title = "Shelf %d" % index
	_title_label.text = "  Shelf %d   (drag here)" % index
	position = start_pos
	while get_plots().size() < DEFAULT_SLOTS:
		_add_plot()
	_refresh_add_slot_button()
	call_deferred("_fit_to_content")

# ---------------------------------------------------------------- UI building

func _build_ui() -> void:
	_root_panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.36, 0.25, 0.16, 0.85)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	_root_panel.add_theme_stylebox_override("panel", style)
	add_child(_root_panel)

	var vbox = VBoxContainer.new()
	_root_panel.add_child(vbox)

	# Title bar = drag handle (plots themselves are NOT draggable, so clicking a
	# plot never moves the shelf by accident)
	_title_label = Label.new()
	_title_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_title_label.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_title_label.gui_input.connect(_on_handle_input)
	vbox.add_child(_title_label)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vbox.add_child(row)

	plot_container = GridContainer.new()
	plot_container.columns = MAX_SLOTS
	plot_container.add_theme_constant_override("h_separation", 10)
	row.add_child(plot_container)

	_add_slot_button = Button.new()
	_add_slot_button.custom_minimum_size = Vector2(40, 80)
	_add_slot_button.pressed.connect(_on_add_slot_pressed)
	row.add_child(_add_slot_button)

func _fit_to_content() -> void:
	var min_size = _root_panel.get_combined_minimum_size()
	size = Vector2i(ceili(min_size.x), ceili(min_size.y))
	_root_panel.size = Vector2(size)

func _clamp_to_screen() -> void:
	var rect = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	position = Vector2i(
		clampi(position.x, rect.position.x, maxi(rect.position.x, rect.end.x - size.x)),
		clampi(position.y, rect.position.y, maxi(rect.position.y, rect.end.y - size.y))
	)

# ---------------------------------------------------------------- slots

func get_plots() -> Array[Plot]:
	var result: Array[Plot] = []
	for child in plot_container.get_children():
		if child is Plot and not child.is_queued_for_deletion():
			result.append(child)
	return result

func _add_plot() -> Plot:
	var plot: Plot = PLOT_SCENE.instantiate()
	plot_container.add_child(plot)   # add to tree first so @onready vars resolve
	plot.need_became_due.connect(_on_any_plot_need_due.bind(plot))
	plot.clicked.connect(_on_plot_clicked)
	return plot

func _on_plot_clicked(plot: Plot) -> void:
	plot_clicked.emit(plot)

func _on_add_slot_pressed() -> void:
	var next_slot = get_plots().size() + 1
	if next_slot > MAX_SLOTS:
		return
	if not EconomyManager.spend(SLOT_UNLOCK_COST.get(next_slot, 0)):
		return
	_add_plot()
	_refresh_add_slot_button()
	call_deferred("_fit_to_content")
	slots_changed.emit()

func _refresh_add_slot_button() -> void:
	var next_slot = get_plots().size() + 1
	if next_slot > MAX_SLOTS:
		_add_slot_button.visible = false
	else:
		_add_slot_button.visible = true
		_add_slot_button.text = "+\n%d" % SLOT_UNLOCK_COST.get(next_slot, 0)
		_add_slot_button.tooltip_text = "Buy slot %d for %d gold" % [next_slot, SLOT_UNLOCK_COST.get(next_slot, 0)]

# ---------------------------------------------------------------- dragging

func _on_handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_dragging = true
		_drag_offset = DisplayServer.mouse_get_position() - position

func _process(delta: float) -> void:
	if _dragging:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			position = DisplayServer.mouse_get_position() - _drag_offset
		else:
			_dragging = false
			drag_finished.emit()

	if music_current_wind > 0.0:
		music_current_wind = max(0.0, music_current_wind - music_drain_per_sec * delta)
		music_state_changed.emit(music_current_wind, music_max_wind, is_music_playing())

# ---------------------------------------------------------------- sunlight

func apply_mini_sun(charges: int = 3) -> void:
	sunlight_charges_remaining = charges
	sunlight_charges_changed.emit(sunlight_charges_remaining)
	_satisfy_all_due_sunlight_needs()

func _satisfy_all_due_sunlight_needs() -> void:
	# A need that was already due before charges were applied already fired
	# its need_became_due signal once and won't fire again, so the live
	# _on_any_plot_need_due hook alone would never resolve it. Catch it here
	# the moment charges become available.
	for plot in get_plots():
		if sunlight_charges_remaining <= 0:
			break
		if plot.plant_data != null and plot.is_need_due("sunlight"):
			plot.satisfy_need("sunlight")
			sunlight_charges_remaining -= 1
			sunlight_charges_changed.emit(sunlight_charges_remaining)

func _on_any_plot_need_due(need_id: String, plot: Plot) -> void:
	# Only sunlight auto-resolves on becoming due. Music is handled per-plot.
	if need_id == "sunlight" and sunlight_charges_remaining > 0:
		plot.satisfy_need("sunlight")
		sunlight_charges_remaining -= 1
		sunlight_charges_changed.emit(sunlight_charges_remaining)

# ---------------------------------------------------------------- music

func is_music_playing() -> bool:
	return music_current_wind > 0.0

func wind_music(amount: float) -> void:
	# Only adds wind. Music needs are NOT satisfied here — each Plot must hear
	# music continuously for its need's required_continuous_play_sec.
	music_current_wind = min(music_max_wind, music_current_wind + amount)
	music_state_changed.emit(music_current_wind, music_max_wind, is_music_playing())

func open_music_box_ui() -> void:
	if music_box_window != null and is_instance_valid(music_box_window):
		return  # already open — nothing to do, it's already showing live state
	music_box_window = preload("res://scenes/ui/music_box.tscn").instantiate()
	get_tree().root.add_child(music_box_window)
	music_box_window.setup(self)
	music_box_window.tree_exiting.connect(func(): music_box_window = null)

# ---------------------------------------------------------------- save / load

func to_dict() -> Dictionary:
	var plots_data = []
	for plot in get_plots():
		plots_data.append(plot.to_dict())
	return {
		"screen_pos": [position.x, position.y],
		"slot_count": get_plots().size(),
		"plots": plots_data,
		"music_current_wind": music_current_wind,
	}

func from_dict(data: Dictionary, plant_lookup: Dictionary) -> void:
	var slot_count = clampi(int(data.get("slot_count", DEFAULT_SLOTS)), DEFAULT_SLOTS, MAX_SLOTS)
	while get_plots().size() < slot_count:
		_add_plot()
	var pos = data.get("screen_pos", [position.x, position.y])
	position = Vector2i(int(pos[0]), int(pos[1]))
	music_current_wind = float(data.get("music_current_wind", 0.0))
	var plots = get_plots()
	var plots_data = data.get("plots", [])
	for i in range(min(plots.size(), plots_data.size())):
		plots[i].from_dict(plots_data[i], plant_lookup)
	_refresh_add_slot_button()
	call_deferred("_fit_to_content")
	call_deferred("_clamp_to_screen")   # in case the save came from a bigger/other monitor
