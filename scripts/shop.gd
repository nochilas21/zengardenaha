extends Control
class_name Shop

const FERTILIZER_COST: int = 15   # placeholder

@onready var pots_section: VBoxContainer = $Scroll/Content/PotsSection
@onready var plants_section: VBoxContainer = $Scroll/Content/PlantsSection
@onready var misc_section: VBoxContainer = $Scroll/Content/MiscSection

var all_pots: Array[PotData] = []
var all_plants: Array[PlantData] = []

var selected_plot: Plot = null   # kept for compatibility; planting now uses the (+) popup on a pot
var sell_section: VBoxContainer   # built in code so shop.tscn doesn't need changes
var _plant_lookup: Dictionary = {}   # plant_id -> PlantData

const POT_NAMES: Dictionary = {"dirt": "Dirt", "water": "Aquatic", "cloud": "Cloud"}

func _ready() -> void:
	var content = $Scroll/Content
	var plants_label = get_node_or_null("Scroll/Content/PlantsLabel")
	if plants_label is Label:
		plants_label.text = "Seeds  (unlock once, then buy seeds)"
	# Selling moved to the Inventory → "Weigh & Sell" scale (SellScale).
	sell_section = VBoxContainer.new()   # kept (empty) so older code paths stay valid
	_build_misc_rows()
	_rebuild_all()
	EconomyManager.currency_changed.connect(func(_c): _rebuild_all())
	Inventory.changed.connect(_rebuild_all)

func set_catalog(pots: Array[PotData], plants: Array[PlantData]) -> void:
	all_pots = pots
	all_plants = plants
	_plant_lookup.clear()
	for plant in plants:
		_plant_lookup[plant.id] = plant
	_rebuild_all()

func set_selected_plot(plot: Plot) -> void:
	selected_plot = plot
	_rebuild_all()

func _rebuild_all() -> void:
	if sell_section == null:
		return   # not ready yet
	_rebuild_pot_rows()
	_rebuild_plant_rows()

func _has_selection() -> bool:
	return selected_plot != null and is_instance_valid(selected_plot)

func _rebuild_pot_rows() -> void:
	for child in pots_section.get_children():
		child.queue_free()
	for pot in all_pots:
		var row = HBoxContainer.new()
		var label = Label.new()
		label.text = pot.display_name
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		if pot.pot_id in EconomyManager.unlocked_pot_types:
			# Bought pots go to the Inventory; drag them from there onto a shelf
			var owned = Label.new()
			owned.text = "x%d " % Inventory.get_pot_count(pot.pot_id)
			row.add_child(owned)
			var buy_btn = Button.new()
			buy_btn.text = "Buy (%d)" % pot.place_cost
			buy_btn.pressed.connect(_on_buy_pot_pressed.bind(pot))
			row.add_child(buy_btn)
		else:
			var unlock_btn = Button.new()
			unlock_btn.text = "Unlock (%d)" % pot.unlock_cost
			unlock_btn.pressed.connect(func(): EconomyManager.unlock_pot_type(pot))
			row.add_child(unlock_btn)
		pots_section.add_child(row)

# Seeds: unlock a plant once, then buy seeds into the bag. Planting happens
# from the (+) popup on an empty pot.
func _rebuild_plant_rows() -> void:
	for child in plants_section.get_children():
		child.queue_free()
	for plant in all_plants:
		var row = HBoxContainer.new()
		var label = Label.new()
		label.text = "%s [%s, %s pot]" % [plant.display_name, plant.rarity, POT_NAMES.get(plant.required_pot_id, plant.required_pot_id)]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		if plant.id in EconomyManager.unlocked_plants:
			var owned = Label.new()
			owned.text = "x%d " % Inventory.get_seed_count(plant.id)
			row.add_child(owned)
			var buy_btn = Button.new()
			buy_btn.text = "Seed (%d)" % plant.plant_cost
			buy_btn.pressed.connect(_on_buy_seed_pressed.bind(plant))
			row.add_child(buy_btn)
		else:
			var unlock_btn = Button.new()
			unlock_btn.text = "Unlock (%d)" % plant.unlock_cost
			unlock_btn.pressed.connect(func(): EconomyManager.unlock_plant(plant))
			row.add_child(unlock_btn)
		plants_section.add_child(row)

# Sell price of one harvested plant (all multipliers are placeholders).
# Used by the Weigh & Sell scale (SellScale).
static func get_sell_price(plant: PlantData, variant: String) -> int:
	var value = float(plant.sell_value)
	match variant:
		"unhealthy":
			value *= 0.7
		"lucky":
			value *= plant.lucky_variant_sell_bonus
		"special":
			value *= plant.special_form_sell_multiplier
	return int(value)

func _build_misc_rows() -> void:
	var row = HBoxContainer.new()
	var label = Label.new()
	label.text = "Fertilizer x1"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var buy_btn = Button.new()
	buy_btn.text = "Buy (%d)" % FERTILIZER_COST
	buy_btn.pressed.connect(buy_fertilizer)
	row.add_child(buy_btn)
	misc_section.add_child(row)

func _on_buy_pot_pressed(pot: PotData) -> void:
	if EconomyManager.spend(pot.place_cost):
		Inventory.add_pot(pot.pot_id)
	_rebuild_all()

func _on_buy_seed_pressed(plant: PlantData) -> void:
	if EconomyManager.spend(plant.plant_cost):
		Inventory.add_seed(plant.id)
	_rebuild_all()

func buy_fertilizer() -> void:
	if EconomyManager.spend(FERTILIZER_COST):
		EconomyManager.add_fertilizer(1)
