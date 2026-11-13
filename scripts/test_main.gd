extends Node2D

@onready var grid_window: GridWindow = $GridWindow
@onready var shop: Shop = $Shop
@onready var currency_label: Label = $CurrencyLabel
@onready var status_label: Label = $StatusLabel

func _ready() -> void:
	EconomyManager.add_fertilizer(5)
	EconomyManager.currency_changed.connect(_on_currency_changed)
	_on_currency_changed(EconomyManager.currency)

	var all_pots: Array[PotData] = [
		load("res://resources/pots/dirt_pot.tres"),
		load("res://resources/pots/water_pot.tres"),
	]
	var all_plants: Array[PlantData] = [
		load("res://resources/plants/sunflower.tres"),
		load("res://resources/plants/lotus.tres"),
		load("res://resources/plants/test_full_needs_debug.tres"),  # has all 5 needs, for testing
	]
	shop.set_catalog(all_pots, all_plants)

	if SaveManager.has_save():
		_load_game()

func _on_currency_changed(amount: int) -> void:
	currency_label.text = "Gold: %d" % amount

func _on_give_gold_pressed() -> void:
	EconomyManager.add(1000)

func _on_select_plot_pressed(index: int) -> void:
	var plots = grid_window.get_plots()
	if index < plots.size():
		shop.set_selected_plot(plots[index])
		status_label.text = "Selected Plot %d" % (index + 1)

func _on_apply_sunlight_pressed() -> void:
	grid_window.apply_mini_sun(3)
	status_label.text = "Mini sun applied: 3 charges"

func _on_open_music_box_pressed() -> void:
	grid_window.open_music_box_ui()

func _build_plant_lookup() -> Dictionary:
	var lookup = {}
	var dir = DirAccess.open("res://resources/plants/")
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var res: PlantData = load("res://resources/plants/" + file_name)
			lookup[res.id] = res
		file_name = dir.get_next()
	return lookup

func _gather_save_state() -> Dictionary:
	return {
		"currency": EconomyManager.currency,
		"fertilizer_count": EconomyManager.fertilizer_count,
		"unlocked_pot_types": EconomyManager.unlocked_pot_types,
		"unlocked_plants": EconomyManager.unlocked_plants,
		"unlocked_grids": EconomyManager.unlocked_grids,
		"grid_window": grid_window.to_dict(),
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
		return
	var lookup = _build_plant_lookup()
	EconomyManager.currency = state.get("currency", 0)
	EconomyManager.fertilizer_count = state.get("fertilizer_count", 0)
	EconomyManager.unlocked_pot_types = state.get("unlocked_pot_types", ["dirt"])
	EconomyManager.unlocked_plants = state.get("unlocked_plants", [])
	EconomyManager.unlocked_grids = state.get("unlocked_grids", [1])
	EconomyManager.currency_changed.emit(EconomyManager.currency)
	EconomyManager.fertilizer_changed.emit(EconomyManager.fertilizer_count)
	grid_window.from_dict(state.get("grid_window", {}), lookup)
	status_label.text = "Loaded."
