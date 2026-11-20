extends Control
class_name SettingsPanel

# Content of the Settings window (opened from the fairy menu).
#   Audio      — Master / Music / SFX volume (buses are created if missing)
#   Display    — keep shelves always on top; hide everything (shortcut: click
#                the menu light 3 times)
#   Hide items — show/hide each shelf, and each pot on it (hiding a shelf hides
#                all its pots). Hidden plants keep growing.
#   Game       — Save now, Quit game (saves first)
# Audio + "always on top" are stored in user://settings.cfg; what is hidden is
# stored in the save game.

signal shelves_on_top_changed(on_top: bool)
signal hide_all_changed(hidden: bool)
signal shelf_visibility_changed(shelf: GridWindow, shown: bool)
signal plot_visibility_changed(plot: Plot, shown: bool)
signal save_requested()
signal quit_requested()

const SETTINGS_PATH: String = "user://settings.cfg"
const BUSES: Array[String] = ["Master", "Music", "SFX"]

var _list: VBoxContainer
var _shelves: Array = []
var _hide_all: bool = false
var _settings: Dictionary = {}

# ---------------------------------------------------------------- settings file

static func load_settings() -> Dictionary:
	var cfg = ConfigFile.new()
	cfg.load(SETTINGS_PATH)   # missing file → defaults below
	var result = {"shelves_on_top": cfg.get_value("display", "shelves_on_top", true)}
	for bus in BUSES:
		result["volume_" + bus] = cfg.get_value("audio", bus, 80.0)
	return result

static func save_settings(settings: Dictionary) -> void:
	var cfg = ConfigFile.new()
	cfg.set_value("display", "shelves_on_top", settings.get("shelves_on_top", true))
	for bus in BUSES:
		cfg.set_value("audio", bus, settings.get("volume_" + bus, 80.0))
	cfg.save(SETTINGS_PATH)

static func apply_audio(settings: Dictionary) -> void:
	for bus in BUSES:
		var idx = _ensure_bus(bus)
		var volume = float(settings.get("volume_" + bus, 80.0)) / 100.0
		AudioServer.set_bus_mute(idx, volume <= 0.0)
		AudioServer.set_bus_volume_db(idx, linear_to_db(max(volume, 0.0001)))

static func _ensure_bus(bus_name: String) -> int:
	var idx = AudioServer.get_bus_index(bus_name)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	return idx

# ---------------------------------------------------------------- UI

func _ready() -> void:
	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var margin = MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	scroll.add_child(margin)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	margin.add_child(_list)

# Called by the owner whenever the window opens or something changed
func refresh(shelves: Array, hide_all: bool, settings: Dictionary) -> void:
	_shelves = shelves
	_hide_all = hide_all
	_settings = settings
	if _list == null:
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()

	_header("Audio")
	for bus in BUSES:
		_list.add_child(_volume_row(bus))

	_header("Display")
	var on_top = CheckBox.new()
	on_top.text = "Shelves always on top"
	on_top.button_pressed = bool(_settings.get("shelves_on_top", true))
	on_top.toggled.connect(_on_on_top_toggled)
	_list.add_child(on_top)
	var hide_box = CheckBox.new()
	hide_box.text = "Hide everything  (shortcut: click the menu light 3 times)"
	hide_box.button_pressed = _hide_all
	hide_box.toggled.connect(func(v): hide_all_changed.emit(v))
	_list.add_child(hide_box)

	_header("Hide items  (hidden plants keep growing)")
	for shelf in _shelves:
		_list.add_child(_shelf_rows(shelf))

	_header("Game")
	var buttons = HBoxContainer.new()
	var save_btn = Button.new()
	save_btn.text = "Save now"
	save_btn.pressed.connect(func(): save_requested.emit())
	buttons.add_child(save_btn)
	var quit_btn = Button.new()
	quit_btn.text = "Save & Quit game"
	quit_btn.pressed.connect(func(): quit_requested.emit())
	buttons.add_child(quit_btn)
	_list.add_child(buttons)

func _header(text: String) -> void:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	_list.add_child(label)

func _volume_row(bus: String) -> Control:
	var row = HBoxContainer.new()
	var label = Label.new()
	label.text = bus
	label.custom_minimum_size = Vector2(70, 0)
	row.add_child(label)
	var slider = HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = float(_settings.get("volume_" + bus, 80.0))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value_label = Label.new()
	value_label.text = "%d" % slider.value
	value_label.custom_minimum_size = Vector2(32, 0)
	slider.value_changed.connect(_on_volume_changed.bind(bus, value_label))
	row.add_child(slider)
	row.add_child(value_label)
	return row

func _on_volume_changed(value: float, bus: String, value_label: Label) -> void:
	value_label.text = "%d" % value
	_settings["volume_" + bus] = value
	apply_audio(_settings)
	save_settings(_settings)

func _shelf_rows(shelf: GridWindow) -> Control:
	var box = VBoxContainer.new()
	var shelf_check = CheckBox.new()
	shelf_check.text = "Shelf %d" % shelf.shelf_index
	shelf_check.button_pressed = not shelf.user_hidden
	box.add_child(shelf_check)
	var pot_checks: Array = []
	for plot in shelf.get_plots():
		if plot.pot_id == "":
			continue
		var check = CheckBox.new()
		var what = plot.plant_data.display_name if plot.plant_data != null else "empty pot"
		check.text = "      Slot %d: %s" % [plot.get_index() + 1, what]
		check.button_pressed = not plot.user_hidden
		check.disabled = shelf.user_hidden   # a hidden shelf hides all its pots
		check.toggled.connect(func(v): plot_visibility_changed.emit(plot, v))
		box.add_child(check)
		pot_checks.append(check)
	shelf_check.toggled.connect(_on_shelf_toggled.bind(shelf, pot_checks))
	return box

func _on_on_top_toggled(value: bool) -> void:
	_settings["shelves_on_top"] = value
	save_settings(_settings)
	shelves_on_top_changed.emit(value)

func _on_shelf_toggled(value: bool, shelf: GridWindow, pot_checks: Array) -> void:
	for c in pot_checks:
		c.disabled = not value
	shelf_visibility_changed.emit(shelf, value)
