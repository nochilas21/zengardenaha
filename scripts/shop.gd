extends Control
class_name Shop

const FERTILIZER_COST: int = 15   # placeholder

@onready var pots_section: VBoxContainer = $Scroll/Content/PotsSection
@onready var plants_section: VBoxContainer = $Scroll/Content/PlantsSection
@onready var misc_section: VBoxContainer = $Scroll/Content/MiscSection

var all_pots: Array[PotData] = []
var all_plants: Array[PlantData] = []

var selected_plot: Plot = null   # set externally when the player clicks a slot on a shelf

func _ready() -> void:
	_build_misc_rows()
	_rebuild_all()
	EconomyManager.currency_changed.connect(func(_c): _rebuild_all())

func set_catalog(pots: Array[PotData], plants: Array[PlantData]) -> void:
	all_pots = pots
	all_plants = plants
	_rebuild_all()

func set_selected_plot(plot: Plot) -> void:
	selected_plot = plot
	_rebuild_all()

func _rebuild_all() -> void:
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
			var place_btn = Button.new()
			place_btn.text = "Place (%d)" % pot.place_cost
			place_btn.disabled = not _has_selection() or selected_plot.pot_id != ""
			place_btn.pressed.connect(_on_place_pot_pressed.bind(pot))
			row.add_child(place_btn)
		else:
			var unlock_btn = Button.new()
			unlock_btn.text = "Unlock (%d)" % pot.unlock_cost
			unlock_btn.pressed.connect(func(): EconomyManager.unlock_pot_type(pot))
			row.add_child(unlock_btn)
		pots_section.add_child(row)

func _rebuild_plant_rows() -> void:
	for child in plants_section.get_children():
		child.queue_free()
	if _has_selection() and selected_plot.pot_id == "":
		var hint = Label.new()
		hint.text = "Place a pot on this slot first."
		plants_section.add_child(hint)
		return
	for plant in all_plants:
		# only offer plants matching the selected slot's pot type
		if _has_selection() and plant.required_pot_id != selected_plot.pot_id:
			continue
		var row = HBoxContainer.new()
		var label = Label.new()
		label.text = "%s [%s]" % [plant.display_name, plant.rarity]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		if plant.id in EconomyManager.unlocked_plants:
			var plant_btn = Button.new()
			plant_btn.text = "Plant (%d)" % plant.plant_cost
			plant_btn.disabled = not _has_selection() or selected_plot.plant_data != null
			plant_btn.pressed.connect(_on_plant_pressed.bind(plant))
			row.add_child(plant_btn)
		else:
			var unlock_btn = Button.new()
			unlock_btn.text = "Unlock (%d)" % plant.unlock_cost
			unlock_btn.pressed.connect(func(): EconomyManager.unlock_plant(plant))
			row.add_child(unlock_btn)
		plants_section.add_child(row)

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

func _on_place_pot_pressed(pot: PotData) -> void:
	# Check BEFORE spending so gold is never taken for an occupied slot
	if not _has_selection() or selected_plot.pot_id != "" or selected_plot.plant_data != null:
		return
	if EconomyManager.spend(pot.place_cost):
		selected_plot.place_pot(pot)
	_rebuild_all()   # spend() already rebuilt once, but before the pot existed

func _on_plant_pressed(plant: PlantData) -> void:
	if not _has_selection() or selected_plot.plant_data != null or not selected_plot.can_plant(plant):
		return
	if EconomyManager.spend(plant.plant_cost):
		selected_plot.plant(plant)
	_rebuild_all()

func buy_fertilizer() -> void:
	if EconomyManager.spend(FERTILIZER_COST):
		EconomyManager.add_fertilizer(1)
