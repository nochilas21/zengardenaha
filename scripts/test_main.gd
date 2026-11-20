extends Node2D

# Temporary main scene (replaced by MainController in Phase 10).
# Owns the shelves (GridWindow), plot selection, shelf purchase, save/load,
# the fairy menu (FairyMenu) and the Inventory / Shop windows it opens, and
# the cross-window drags (pot from Inventory → shelf, sun from menu → shelf).

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
var fairy_menu: FairyMenu
var inventory_window: Window
var inventory_panel: InventoryPanel
var shop_window: Window
var settings_window: Window
var settings_panel: SettingsPanel
var settings: Dictionary = {}
var hide_all: bool = false          # "hide everything" (Settings, or click the menu light 3 times)
var plant_catalog: Array[PlantData] = []
var _seed_picker: SeedPicker = null
var _sell_scale: SellScale = null

func _ready() -> void:
	settings = SettingsPanel.load_settings()
	SettingsPanel.apply_audio(settings)
	EconomyManager.add_fertilizer(5)
	EconomyManager.currency_changed.connect(func(_c): _refresh_hud())
	EconomyManager.fertilizer_changed.connect(func(_c): _refresh_hud())
	apply_sunlight_button.text = "Apply Mini Sun (selected shelf)"
	_build_extra_buttons()

	var pots = _load_pots()
	plant_catalog = _load_catalog_plants()
	shop.set_catalog(pots, plant_catalog)
	_build_menu_and_windows(pots)
	Inventory.changed.connect(_on_inventory_changed)
	Inventory.skin_equipped.connect(_on_skin_equipped)

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

	var memoria_button = Button.new()
	memoria_button.text = "Play Memoria Run (debug)"
	memoria_button.pressed.connect(_on_memoria_run_pressed)
	row.add_child(memoria_button)

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
	return Vector2i(rect.position.x + 40, rect.position.y + 40 + (index - 1) * 190)

func _spawn_shelf(index: int, data: Dictionary = {}, lookup: Dictionary = {}) -> GridWindow:
	var shelf = GridWindow.new()
	add_child(shelf)   # add to tree first, then setup
	shelf.setup(index, _default_shelf_position(index))
	shelf.plot_clicked.connect(_on_plot_clicked)
	shelf.plot_plant_requested.connect(_open_seed_picker)
	shelf.plot_harvest_requested.connect(_harvest_plot)
	shelf.plot_pot_drag_started.connect(_start_shelf_pot_drag)
	shelf.skin_requested.connect(_open_shelf_skin_picker)
	shelf.always_on_top = bool(settings.get("shelves_on_top", true))
	shelves[index] = shelf
	if not data.is_empty():
		shelf.from_dict(data, lookup)
	shelf.reveal(not hide_all and not shelf.user_hidden)   # shows it after its first layout
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
	if plot.pot_id != "":
		_open_pot_skin_picker(plot)   # clicking a pot = choose its look
		return
	if plot == selected_plot:
		_select_plot(null)   # click the selected slot again to unselect it
		status_label.text = "Nothing selected."
		return
	_select_plot(plot)
	var shelf = plot._find_grid_window()
	status_label.text = "Selected Shelf %d, Slot %d  (click again or Esc to unselect)" % [shelf.shelf_index, plot.get_index() + 1]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and selected_plot != null:
		_select_plot(null)
		status_label.text = "Nothing selected."

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
	MusicManager.open_ui()   # one global music box for every shelf

func _on_harvest_pressed() -> void:
	if selected_plot == null or not is_instance_valid(selected_plot) or selected_plot.plant_data == null:
		status_label.text = "Select a slot with a plant first."
		return
	if not selected_plot.is_mature():
		status_label.text = "Not mature yet."
		return
	_harvest_plot(selected_plot)

func _on_memoria_run_pressed() -> void:
	# Debug launcher: plays the Memoria Moonflower event without a plant
	var run = MemoriaRun.open_in_window(self)
	run.finished.connect(func(success): status_label.text = "Memoria Run: %s" % ("WON" if success else "lost / gave up"))

# ---------------------------------------------------------------- menu + windows

func _build_menu_and_windows(pots: Array[PotData]) -> void:
	fairy_menu = FairyMenu.new()
	add_child(fairy_menu)
	var rect = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	fairy_menu.position = Vector2i(rect.end.x - 380, rect.position.y + 40)
	_register_menu_items()
	fairy_menu.item_activated.connect(_on_menu_item)
	fairy_menu.tool_drag_started.connect(_on_menu_item)
	fairy_menu.hide_all_toggled.connect(func(): _set_hide_all(not hide_all))
	fairy_menu.skin_requested.connect(_open_icon_skin_picker)

	settings_window = _make_panel_window("Settings", Vector2i(380, 520))
	settings_panel = SettingsPanel.new()
	settings_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_window.add_child(settings_panel)
	settings_panel.shelves_on_top_changed.connect(_set_shelves_on_top)
	settings_panel.hide_all_changed.connect(_set_hide_all)
	settings_panel.shelf_visibility_changed.connect(_on_shelf_visibility_changed)
	settings_panel.plot_visibility_changed.connect(func(plot, shown): plot.set_user_hidden(not shown))
	settings_panel.save_requested.connect(_on_save_pressed)
	settings_panel.quit_requested.connect(_save_and_quit)

	inventory_window = _make_panel_window("Inventory", Vector2i(360, 420))
	inventory_panel = InventoryPanel.new()
	inventory_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	inventory_window.add_child(inventory_panel)
	inventory_panel.set_pot_catalog(pots)
	inventory_panel.set_plant_catalog(plant_catalog)
	inventory_panel.pot_drag_started.connect(_start_pot_drag)
	inventory_panel.sell_scale_requested.connect(_open_sell_scale)

	# The shop node from the scene moves into its own window
	shop_window = _make_panel_window("Shop", Vector2i(360, 620))
	remove_child(shop)
	shop_window.add_child(shop)
	shop.position = Vector2(10, 10)

# ---- Menu items: ADD A NEW FEATURE HERE ----
# 1) one line in MENU_ITEMS: [id, label, glyph, is_tool, skin_category]
#    (is_tool = press & drag onto a shelf, like Sun/Shovel; an unknown glyph
#     just shows the label's first letter until there is art)
# 2) one entry in _menu_actions() with what it does.
const MENU_ITEMS: Array = [
	["inventory", "Inventory", "inventory", false, ""],
	["shop", "Shop", "shop", false, ""],
	["shovel", "Shovel", "shovel", true, ""],
	["music_box", "Music", "music_box", false, "music_box"],
	["sun", "Sun", "sun", true, ""],
	["settings", "Settings", "settings", false, ""],
]

func _menu_actions() -> Dictionary:
	return {
		"inventory": func(): _toggle_panel_window(inventory_window),
		"shop": func(): _toggle_panel_window(shop_window),
		"shovel": _start_shovel_drag,
		"music_box": func(): MusicManager.open_ui(),
		"sun": _start_sun_drag,
		"settings": _toggle_settings,
	}

func _register_menu_items() -> void:
	for def in MENU_ITEMS:
		fairy_menu.register_item(def[0], def[1], def[2], def[3], def[4])

func _on_menu_item(id: String) -> void:
	var action = _menu_actions().get(id)
	if action is Callable and action.is_valid():
		action.call()
	else:
		push_warning("Menu item '%s' has no action in _menu_actions()" % id)

func _make_panel_window(window_title: String, window_size: Vector2i) -> Window:
	var win = Window.new()
	win.title = window_title
	win.size = window_size
	win.always_on_top = true
	win.visible = false
	win.close_requested.connect(func(): win.hide())
	add_child(win)
	return win

func _toggle_panel_window(win: Window) -> void:
	if win.visible:
		win.hide()
		return
	# open next to the fairy menu, kept on screen
	var rect = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var pos = fairy_menu.position + Vector2i(0, fairy_menu.size.y + 30)
	pos.x = clampi(pos.x, rect.position.x, rect.end.x - win.size.x)
	pos.y = clampi(pos.y, rect.position.y, rect.end.y - win.size.y)
	win.position = pos
	win.show()

func _on_inventory_changed() -> void:
	pass   # windows refresh themselves; skins are applied in _on_skin_equipped / pickers

# Inventory → Skins → Equip = "use this look everywhere" (and for new things).
# Clicking a single shelf / pot changes only that one (see the pickers below).
func _on_skin_equipped(category: String, skin_id: String) -> void:
	var skin = Inventory.get_skin(category, skin_id)
	if category == "shelf" and skin is ShelfSkinData:
		for shelf in shelves.values():
			shelf.apply_skin(skin)
	elif category == "pot" and skin is PotSkinData:
		for shelf in shelves.values():
			for plot in shelf.get_plots():
				if plot.pot_id == skin.pot_id:
					plot.set_pot_skin(skin_id)

# ---------------------------------------------------------------- skin pickers (click a thing)

func _open_shelf_skin_picker(shelf: GridWindow) -> void:
	var current = shelf.skin.id if shelf.skin != null else ""
	SkinPicker.open(self, "shelf", current, func(skin): shelf.apply_skin(skin), DisplayServer.mouse_get_position())

func _open_pot_skin_picker(plot: Plot) -> void:
	SkinPicker.open(self, "pot", plot.pot_skin_id, func(skin): plot.set_pot_skin(skin.id), DisplayServer.mouse_get_position(), plot.pot_id)

func _open_icon_skin_picker(category: String) -> void:
	var current = Inventory.get_equipped_skin(category)
	SkinPicker.open(self, category, current.id if current != null else "", func(skin): Inventory.equip_skin(category, skin.id), DisplayServer.mouse_get_position())

# ---------------------------------------------------------------- settings / hiding

func _toggle_settings() -> void:
	if not settings_window.visible:
		_refresh_settings_panel()
	_toggle_panel_window(settings_window)

func _refresh_settings_panel() -> void:
	var list = []
	var keys = shelves.keys()
	keys.sort()
	for k in keys:
		list.append(shelves[k])
	settings_panel.refresh(list, hide_all, settings)

func _set_hide_all(value: bool) -> void:
	hide_all = value
	_apply_visibility()
	status_label.text = "Everything hidden — click the menu light 3 times to show it again." if hide_all else "Everything visible."
	if settings_window.visible:
		_refresh_settings_panel()

# A shelf is shown only if neither "hide everything" nor its own hide is on.
# Hidden shelves/pots keep growing; only the drawing is hidden.
func _apply_visibility() -> void:
	for shelf in shelves.values():
		shelf.visible = not hide_all and not shelf.user_hidden

func _on_shelf_visibility_changed(shelf: GridWindow, shown: bool) -> void:
	shelf.user_hidden = not shown
	_apply_visibility()

func _set_shelves_on_top(on_top: bool) -> void:
	settings["shelves_on_top"] = on_top
	for shelf in shelves.values():
		shelf.always_on_top = on_top

func _save_and_quit() -> void:
	SaveManager.save_game(_gather_save_state())
	get_tree().quit()

# ---------------------------------------------------------------- drags (cross-window)

func _shelf_at(screen_pos: Vector2i) -> GridWindow:
	for shelf in shelves.values():
		if shelf.contains_screen_point(screen_pos):
			return shelf
	return null

func _start_pot_drag(pot_id: String) -> void:
	if Inventory.get_pot_count(pot_id) <= 0:
		return
	# A slot is selected and empty → place the pot there right away (no drag needed)
	if selected_plot != null and is_instance_valid(selected_plot) and selected_plot.pot_id == "" and selected_plot.plant_data == null:
		var shelf = selected_plot._find_grid_window()
		_place_pot_on(selected_plot, shelf, pot_id)
		return
	DragGhost.start(self, _make_pot_ghost(pot_id), _on_pot_dropped.bind(pot_id), _on_pot_drag_hover)
	status_label.text = "Drop the pot on a shelf slot (Esc / right click to cancel)."

func _make_pot_ghost(pot_id: String) -> Control:
	var ghost_icon = TextureRect.new()
	ghost_icon.custom_minimum_size = Vector2(56, 56)
	ghost_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var skin = Inventory.get_pot_skin(pot_id)
	if skin != null:
		ghost_icon.texture = skin.preview if skin.preview != null else skin.texture
	return ghost_icon

func _pot_data(pot_id: String) -> PotData:
	for pot in shop.all_pots:
		if pot.pot_id == pot_id:
			return pot
	return null

func _on_pot_drag_hover(screen_pos: Vector2i) -> void:
	for shelf in shelves.values():
		shelf.set_drop_hover(screen_pos, true)

func _on_pot_dropped(screen_pos: Vector2i, pot_id: String) -> void:
	var shelf = _shelf_at(screen_pos)
	if shelf == null:
		status_label.text = "Not on a shelf — the pot stays in your inventory."
		return
	var plot = shelf.get_plot_at_screen(screen_pos)
	if plot != null and plot.pot_id != "":
		# dropped onto a pot: swap it (only if nothing is planted in it)
		if plot.plant_data != null:
			status_label.text = "Something is growing in that pot — dig it up with the Shovel first."
		elif plot.pot_id == pot_id:
			status_label.text = "That's already the same kind of pot."
		else:
			_swap_pot(plot, shelf, pot_id)
		return
	if plot == null:
		plot = shelf.get_first_empty_plot()
	if plot == null:
		plot = shelf.add_slot()   # full shelf grows by one slot (max 5)
	if plot == null:
		status_label.text = "Shelf %d is full (%d pots max)." % [shelf.shelf_index, GridWindow.MAX_SLOTS]
		return
	_place_pot_on(plot, shelf, pot_id)

# Old pot goes back to the bag, the new one takes its place.
func _swap_pot(plot: Plot, shelf: GridWindow, new_pot_id: String) -> void:
	var new_data = _pot_data(new_pot_id)
	if new_data == null or not Inventory.take_pot(new_pot_id):
		return
	var old_id = plot.remove_pot()
	Inventory.add_pot(old_id)
	plot.place_pot(new_data)
	status_label.text = "Swapped the pot on Shelf %d, Slot %d (old pot is back in your bag)." % [shelf.shelf_index, plot.get_index() + 1]

# ---------------------------------------------------------------- pot dragged off a shelf

func _start_shelf_pot_drag(plot: Plot) -> void:
	if plot.plant_data != null:
		status_label.text = "Something is growing in that pot — dig it up with the Shovel first."
		return
	_select_plot(null)
	plot.modulate.a = 0.35   # show that it's "picked up"
	DragGhost.start(self, _make_pot_ghost(plot.pot_id), _on_shelf_pot_dropped.bind(plot), _on_pot_drag_hover, func(): plot.modulate.a = 1.0)
	status_label.text = "Drop on the Inventory (or the menu light) to put it back, or on another slot to move it."

func _is_over_bag(screen_pos: Vector2i) -> bool:
	if inventory_window.visible and Rect2i(inventory_window.position, inventory_window.size).has_point(screen_pos):
		return true
	return Rect2i(fairy_menu.position, fairy_menu.size).has_point(screen_pos)

func _on_shelf_pot_dropped(screen_pos: Vector2i, plot: Plot) -> void:
	if not is_instance_valid(plot):
		return
	plot.modulate.a = 1.0
	if _is_over_bag(screen_pos):
		var pot_id = plot.remove_pot()   # leaves an empty slot
		if pot_id != "":
			Inventory.add_pot(pot_id)
			status_label.text = "Pot put back in your bag."
		return
	var shelf = _shelf_at(screen_pos)
	if shelf == null:
		return   # dropped nowhere: nothing changes
	var target = shelf.get_plot_at_screen(screen_pos)
	if target == null or target == plot:
		return
	if target.pot_id == "":
		var moved_id = plot.remove_pot()   # move to the empty slot
		target.place_pot(_pot_data(moved_id))
		status_label.text = "Pot moved."
	elif target.plant_data == null and target.pot_id != plot.pot_id:
		var a = plot.remove_pot()           # swap two empty pots
		var b = target.remove_pot()
		target.place_pot(_pot_data(a))
		plot.place_pot(_pot_data(b))
		status_label.text = "Pots swapped."

# ---------------------------------------------------------------- shovel

func _start_shovel_drag() -> void:
	var shovel = MenuIcon.new()
	shovel.glyph = "shovel"
	shovel.custom_minimum_size = Vector2(56, 56)
	DragGhost.start(self, shovel, _on_shovel_dropped, _on_shovel_hover)
	status_label.text = "Drop the shovel on a plant to dig it up (refund: half its seed price)."

func _on_shovel_hover(screen_pos: Vector2i) -> void:
	for shelf in shelves.values():
		var hovered = shelf.get_plot_at_screen(screen_pos)
		for plot in shelf.get_plots():
			plot.set_drop_highlight(plot == hovered and plot.plant_data != null)

# Digs up a growing plant: refund = half the seed price, rounded down.
func _on_shovel_dropped(screen_pos: Vector2i) -> void:
	var shelf = _shelf_at(screen_pos)
	var plot = shelf.get_plot_at_screen(screen_pos) if shelf != null else null
	if plot == null or plot.plant_data == null:
		status_label.text = "Drop the shovel on a plant."
		return
	if plot.is_mature():
		status_label.text = "This one is ready — click its sparkle to harvest it instead."
		return
	var plant = plot.uproot()
	var refund = int(floor(plant.plant_cost / 2.0))
	EconomyManager.add(refund)
	status_label.text = "Dug up %s: +%d gold." % [plant.display_name, refund]

func _place_pot_on(plot: Plot, shelf: GridWindow, pot_id: String) -> void:
	var pot_data: PotData = null
	for pot in shop.all_pots:
		if pot.pot_id == pot_id:
			pot_data = pot
	if pot_data == null or not Inventory.take_pot(pot_id):
		return
	plot.place_pot(pot_data)
	_select_plot(null)
	status_label.text = "Placed %s on Shelf %d, Slot %d — click its (+) to plant a seed." % [pot_data.display_name, shelf.shelf_index, plot.get_index() + 1]

# ---------------------------------------------------------------- planting / harvesting

func _open_seed_picker(plot: Plot) -> void:
	if _seed_picker != null and is_instance_valid(_seed_picker):
		_seed_picker.queue_free()
	_seed_picker = SeedPicker.open(self, plot, plant_catalog)
	_seed_picker.confirmed.connect(_on_seed_chosen.bind(plot))

func _on_seed_chosen(plant: PlantData, plot: Plot) -> void:
	if not is_instance_valid(plot) or plot.plant_data != null or not plot.can_plant(plant):
		return
	if not Inventory.take_seed(plant.id):
		status_label.text = "No %s seeds left." % plant.display_name
		return
	plot.plant(plant)
	status_label.text = "Planted %s." % plant.display_name

func _open_sell_scale() -> void:
	if _sell_scale != null and is_instance_valid(_sell_scale):
		_sell_scale.grab_focus()
		return
	_sell_scale = SellScale.open(self, plant_catalog)

func _harvest_plot(plot: Plot) -> void:
	if not is_instance_valid(plot) or not plot.is_mature():
		return
	var item = plot.harvest()
	Inventory.add_harvest(item["plant_id"], item["variant"])
	var variant_text = "" if item["variant"] == "normal" else " (%s)" % item["variant"]
	status_label.text = "Harvested %s%s into your bag — sell it on the scale in your Inventory." % [item["plant_id"], variant_text]

func _start_sun_drag() -> void:
	var sun = SunIcon.new()
	sun.custom_minimum_size = Vector2(56, 56)
	DragGhost.start(self, sun, _on_sun_dropped)
	status_label.text = "Drop the sun on a shelf (Esc / right click to cancel)."

func _on_sun_dropped(screen_pos: Vector2i) -> void:
	var shelf = _shelf_at(screen_pos)
	if shelf == null:
		status_label.text = "Drop the sun onto a shelf."
		return
	shelf.apply_mini_sun(3)
	status_label.text = "Mini sun on Shelf %d: 3 charges" % shelf.shelf_index

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
		"music_current_wind": MusicManager.current_wind,
		"inventory": Inventory.to_dict(),
		"fairy_menu": fairy_menu.to_dict(),
		"hide_all": hide_all,
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

	MusicManager.set_wind(float(state.get("music_current_wind", 0.0)))
	Inventory.from_dict(state.get("inventory", {}))
	if state.has("fairy_menu"):
		fairy_menu.from_dict(state["fairy_menu"])

	hide_all = bool(state.get("hide_all", false))
	_clear_shelves()
	for index in EconomyManager.unlocked_grids:
		_spawn_shelf(index, grid_data.get(str(index), {}), lookup)   # each shelf reveals itself
	_refresh_hud()
	status_label.text = "Loaded."
