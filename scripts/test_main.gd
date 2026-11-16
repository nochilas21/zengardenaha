extends Node2D

# Temporary main scene (replaced by MainController in Phase 10).
# Owns the shelves (GridWindow), plot selection, shelf purchase, save/load.

const MAX_SHELVES: int = 5
const SHELF_UNLOCK_COST: Dictionary = {2: 500, 3: 1500, 4: 3000, 5: 5000}   # placeholder; shelf 1 is free
const INCLUDE_TEST_PLANTS: bool = true   # show test_*.tres plants in the shop (debug)

@onready var shop: Shop = $Shop
@onready var currency_label: Label = $CurrencyLabel
@onready var status_label: Label = $StatusLabel
@onready var apply_sunlight_button: Button = $ApplySunlightButton

var shelves: Dictionary = {}   # shelf index (int) -> GridWindow
var selected_plot: Plot = null
var buy_shelf_button: Button

func _ready() -> void:
	EconomyManager.add_fertilizer(5)
	EconomyManager.currency_changed.connect(func(_c): _refresh_hud())
	EconomyManager.fertilizer_changed.connect(func(_c): _refresh_hud())
	apply_sunlight_button.text = "Apply Mini Sun (selected shelf)"
	_build_extra_buttons()

	shop.set_catalog(_load_pots(), _load_catalog_plants())

	if SaveManager.has_save():
		_load_game()
	else:
		_spawn_shelf(1)   # first shelf is free
	_refresh_hud()

# ---------------------------------------------------------------- catalog

func _load_pots() -> Array[PotData]:
	var pots: Array[PotData] = [
		load("res://resources/pots/dirt_pot.tres"),
		load("res://resources/pots/water_pot.tres"),
		load("res://resources/pots/cloud_pot.tres"),
	]
	return pots

func _list_plant_files() -> Array[String]:
	# In an exported .exe, .tres files are listed as "*.tres.remap" — strip that.
	var files: Array[String] = []
	var dir = DirAccess.open("res://resources/plants/")
	if dir == null:
		return files
	for raw_name in dir.get_files():
		var file_name = raw_name.trim_suffix(".remap")
		if file_name.ends_with(".tres"):
			files.append(file_name)
	return files

func _load_catalog_plants() -> Array[PlantData]:
	var plants: Array[PlantData] = []
	for file_name in _list_plant_files():
		if file_name.begins_with("test_") and not INCLUDE_TEST_PLANTS:
			continue
		var res = load("res://resources/plants/" + file_name)
		if res is PlantData:
			plants.append(res)
	plants.sort_custom(_compare_plants)
	return plants

func _compare_plants(a: PlantData, b: PlantData) -> bool:
	# Group by pot type, then alphabetical
	if a.required_pot_id != b.required_pot_id:
		return a.required_pot_id < b.required_pot_id
	return a.display_name < b.display_name

func _build_plant_lookup() -> Dictionary:
	var lookup = {}
	for file_name in _list_plant_files():
		var res = load("res://resources/plants/" + file_name)
		if res is PlantData:
			lookup[res.id] = res
	return lookup

# ---------------------------------------------------------------- HUD / buttons

func _build_extra_buttons() -> void:
	var row = HBoxContainer.new()
	row.position = Vector2(40, 255)
	add_child(row)

	buy_shelf_button = Button.new()
	buy_shelf_button.pressed.connect(_on_buy_shelf_pressed)
	row.add_child(buy_shelf_button)

	var harvest_button = Button.new()
	harvest_button.text = "Harvest Selected"
	harvest_button.pressed.connect(_on_harvest_pressed)
	row.add_child(harvest_button)

func _refresh_hud() -> void:
	currency_label.text = "Gold: %d    Fertilizer: %d" % [EconomyManager.currency, EconomyManager.fertilizer_count]
	var next = shelves.size() + 1
	if next > MAX_SHELVES:
		buy_shelf_button.text = "All %d shelves owned" % MAX_SHELVES
		buy_shelf_button.disabled = true
	else:
		buy_shelf_button.text = "Buy Shelf %d (%d gold)" % [next, SHELF_UNLOCK_COST.get(next, 0)]
		buy_shelf_button.disabled = false

func _on_give_gold_pressed() -> void:
	EconomyManager.add(1000)

# ---------------------------------------------------------------- shelves

func _default_shelf_position(index: int) -> Vector2i:
	var rect = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	return Vector2i(rect.position.x + 40, rect.position.y + 40 + (index - 1) * 150)

func _spawn_shelf(index: int, data: Dictionary = {}, lookup: Dictionary = {}) -> GridWindow:
	var shelf = GridWindow.new()
	add_child(shelf)   # add to tree first, then setup
	shelf.setup(index, _default_shelf_position(index))
	shelf.plot_clicked.connect(_on_plot_clicked)
	shelves[index] = shelf
	if not data.is_empty():
		shelf.from_dict(data, lookup)
	return shelf

func _clear_shelves() -> void:
	_select_plot(null)
	for shelf in shelves.values():
		shelf.queue_free()
	shelves.clear()

func _on_buy_shelf_pressed() -> void:
	var next = shelves.size() + 1
	if next > MAX_SHELVES:
		status_label.text = "You already own all %d shelves." % MAX_SHELVES
		return
	var cost = SHELF_UNLOCK_COST.get(next, 0)
	if not EconomyManager.spend(cost):
		status_label.text = "Not enough gold for Shelf %d (needs %d)." % [next, cost]
		return
	if next not in EconomyManager.unlocked_grids:
		EconomyManager.unlocked_grids.append(next)
	_spawn_shelf(next)
	_refresh_hud()
	status_label.text = "Bought Shelf %d — drag it by its title bar." % next

# ---------------------------------------------------------------- selection

func _select_plot(plot: Plot) -> void:
	if selected_plot != null and is_instance_valid(selected_plot):
		selected_plot.set_selected(false)
	selected_plot = plot
	if plot != null:
		plot.set_selected(true)
	shop.set_selected_plot(plot)

func _on_plot_clicked(plot: Plot) -> void:
	_select_plot(plot)
	var shelf = plot._find_grid_window()
	status_label.text = "Selected Shelf %d, Slot %d" % [shelf.shelf_index, plot.get_index() + 1]

func _on_select_plot_pressed(index: int) -> void:
	# Old debug buttons: select a slot on Shelf 1
	if not shelves.has(1):
		return
	var plots = shelves[1].get_plots()
	if index < plots.size():
		_on_plot_clicked(plots[index])

func _selected_shelf() -> GridWindow:
	if selected_plot != null and is_instance_valid(selected_plot):
		return selected_plot._find_grid_window()
	return shelves.get(1)

func _on_apply_sunlight_pressed() -> void:
	var shelf = _selected_shelf()
	if shelf == null:
		return
	shelf.apply_mini_sun(3)
	status_label.text = "Mini sun applied to Shelf %d: 3 charges" % shelf.shelf_index

func _on_open_music_box_pressed() -> void:
	var shelf = _selected_shelf()
	if shelf != null:
		shelf.open_music_box_ui()

func _on_harvest_pressed() -> void:
	if selected_plot == null or not is_instance_valid(selected_plot) or selected_plot.plant_data == null:
		status_label.text = "Select a slot with a plant first."
		return
	if not selected_plot.is_mature():
		status_label.text = "Not mature yet."
		return
	var value = selected_plot.harvest()
	EconomyManager.add(value)
	shop.set_selected_plot(selected_plot)
	status_label.text = "Harvested for %d gold." % value

# ---------------------------------------------------------------- save / load

func _gather_save_state() -> Dictionary:
	var grids = {}
	for index in shelves:
		grids[str(index)] = shelves[index].to_dict()
	return {
		"currency": EconomyManager.currency,
		"fertilizer_count": EconomyManager.fertilizer_count,
		"unlocked_pot_types": EconomyManager.unlocked_pot_types,
		"unlocked_plants": EconomyManager.unlocked_plants,
		"unlocked_grids": EconomyManager.unlocked_grids,
		"grid_windows": grids,
	}

func _on_save_pressed() -> void:
	SaveManager.save_game(_gather_save_state())
	status_label.text = "Saved."

func _on_load_pressed() -> void:
	_load_game()

func _load_game() -> void:
	var state = SaveManager.load_game()
	if state.is_empty():
		status_label.text = "No save found."
		if shelves.is_empty():
			_spawn_shelf(1)
		return
	var lookup = _build_plant_lookup()
	EconomyManager.currency = int(state.get("currency", 0))
	EconomyManager.fertilizer_count = int(state.get("fertilizer_count", 0))
	# JSON arrays come back untyped — assign() converts them into the typed arrays
	EconomyManager.unlocked_pot_types.assign(state.get("unlocked_pot_types", ["dirt"]))
	EconomyManager.unlocked_plants.assign(state.get("unlocked_plants", []))
	var grids: Array[int] = []
	for g in state.get("unlocked_grids", [1]):
		grids.append(int(g))
	if grids.is_empty():
		grids.append(1)
	grids.sort()
	EconomyManager.unlocked_grids = grids
	EconomyManager.currency_changed.emit(EconomyManager.currency)
	EconomyManager.fertilizer_changed.emit(EconomyManager.fertilizer_count)

	var grid_data: Dictionary = state.get("grid_windows", {})
	if grid_data.is_empty() and state.has("grid_window"):
		grid_data = {"1": state["grid_window"]}   # save from the old single-grid version

	_clear_shelves()
	for index in EconomyManager.unlocked_grids:
		_spawn_shelf(index, grid_data.get(str(index), {}), lookup)
	_refresh_hud()
	status_label.text = "Loaded."
