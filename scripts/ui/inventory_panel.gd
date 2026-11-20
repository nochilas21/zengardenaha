extends Control
class_name InventoryPanel

# Content of the Inventory window.
#   Pots   — unplaced pots you own. Press and drag a row onto a shelf slot
#            (or click it, then click the shelf). A full shelf grows (max 5).
#   Items  — fertilizer etc.
#   Skins  — every skin you own, per category, with an Equip button.
# The actual drop (which shelf/slot) is handled by whoever connects
# pot_drag_started (test_main → MainController later).

signal pot_drag_started(pot_id: String)
signal sell_scale_requested()

var _list: VBoxContainer
var _pot_lookup: Dictionary = {}   # pot_id -> PotData (for display names)
var _plant_lookup: Dictionary = {} # plant_id -> PlantData

func _ready() -> void:
	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	Inventory.changed.connect(refresh)
	EconomyManager.fertilizer_changed.connect(func(_c): refresh())
	refresh()

func set_pot_catalog(pots: Array[PotData]) -> void:
	_pot_lookup.clear()
	for pot in pots:
		_pot_lookup[pot.pot_id] = pot
	refresh()

func set_plant_catalog(plants: Array[PlantData]) -> void:
	_plant_lookup.clear()
	for plant in plants:
		_plant_lookup[plant.id] = plant
	refresh()

func _plant_name(plant_id: String) -> String:
	return _plant_lookup[plant_id].display_name if _plant_lookup.has(plant_id) else plant_id

func refresh() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()

	_add_header("Pots  (drag onto a shelf)")
	var any_pot = false
	for pot_id in Inventory.pots:
		var count = Inventory.get_pot_count(pot_id)
		if count <= 0:
			continue
		any_pot = true
		_list.add_child(_make_pot_row(pot_id, count))
	if not any_pot:
		_add_note("No pots. Buy some in the Shop.")

	_add_header("Seeds  (plant with the + on an empty pot)")
	var any_seed = false
	for plant_id in Inventory.seeds:
		var count = Inventory.get_seed_count(plant_id)
		if count > 0:
			any_seed = true
			_add_note("%s seed  x%d" % [_plant_name(plant_id), count])
	if not any_seed:
		_add_note("No seeds. Buy some in the Shop.")

	_add_header("Harvest")
	var any_harvest = false
	for key in Inventory.harvested:
		var count = int(Inventory.harvested[key])
		if count > 0:
			any_harvest = true
			var parts = Inventory.split_harvest_key(key)
			var variant_text = "" if parts[1] == "normal" else " (%s)" % parts[1]
			_add_note("%s%s  x%d" % [_plant_name(parts[0]), variant_text, count])
	if not any_harvest:
		_add_note("Nothing harvested yet.")
	else:
		var sell_btn = Button.new()
		sell_btn.text = "Weigh & Sell plants..."
		sell_btn.pressed.connect(func(): sell_scale_requested.emit())
		_list.add_child(sell_btn)

	_add_header("Items")
	_add_note("Fertilizer x%d" % EconomyManager.fertilizer_count)

	_add_header("Skins")
	for category in Inventory.CATEGORIES:
		for skin in Inventory.get_all_skins(category):
			if Inventory.owns_skin(category, skin.id):
				_list.add_child(_make_skin_row(category, skin))

func _add_header(text: String) -> void:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	_list.add_child(label)

func _add_note(text: String) -> void:
	var label = Label.new()
	label.text = "   " + text
	_list.add_child(label)

func _make_pot_row(pot_id: String, count: int) -> Control:
	var row = PanelContainer.new()
	row.mouse_default_cursor_shape = Control.CURSOR_DRAG
	row.tooltip_text = "Drag onto a shelf slot"
	var hbox = HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hbox)
	var icon = TextureRect.new()
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var skin = Inventory.get_pot_skin(pot_id)
	if skin != null:
		icon.texture = skin.preview if skin.preview != null else skin.texture
	hbox.add_child(icon)
	var label = Label.new()
	var pot_name = _pot_lookup[pot_id].display_name if _pot_lookup.has(pot_id) else pot_id
	label.text = "%s   x%d" % [pot_name, count]
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(label)
	row.gui_input.connect(_on_pot_row_input.bind(pot_id))
	return row

func _on_pot_row_input(event: InputEvent, pot_id: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pot_drag_started.emit(pot_id)

func _make_skin_row(category: String, skin: SkinData) -> Control:
	var row = HBoxContainer.new()
	var label = Label.new()
	label.text = "   [%s] %s" % [category, skin.display_name if skin.display_name != "" else skin.id]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var button = Button.new()
	if Inventory.is_equipped(category, skin.id):
		button.text = "Equipped"
		button.disabled = true
	else:
		button.text = "Equip"
		button.pressed.connect(func(): Inventory.equip_skin(category, skin.id))
	row.add_child(button)
	return row
