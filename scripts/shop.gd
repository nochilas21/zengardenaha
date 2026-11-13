extends Control
class_name Shop

var all_pots: Array[PotData] = []
var all_plants: Array[PlantData] = []

var selected_plot: Plot = null   # set externally when the player clicks an empty/potted plot

func _ready() -> void:
    _rebuild_pot_rows()
    _rebuild_plant_rows()
    EconomyManager.currency_changed.connect(func(_c): _rebuild_pot_rows(); _rebuild_plant_rows())

func set_catalog(pots: Array[PotData], plants: Array[PlantData]) -> void:
    all_pots = pots
    all_plants = plants
    _rebuild_pot_rows()
    _rebuild_plant_rows()

func set_selected_plot(plot: Plot) -> void:
    selected_plot = plot
    _rebuild_plant_rows()

func _rebuild_pot_rows() -> void:
    for child in $PotsSection.get_children():
        child.queue_free()
    for pot in all_pots:
        var row = HBoxContainer.new()
        var label = Label.new()
        label.text = "%s" % pot.display_name
        row.add_child(label)
        if pot.pot_id in EconomyManager.unlocked_pot_types:
            var place_btn = Button.new()
            place_btn.text = "Place (%d)" % pot.place_cost
            place_btn.pressed.connect(_on_place_pot_pressed.bind(pot))
            row.add_child(place_btn)
        else:
            var unlock_btn = Button.new()
            unlock_btn.text = "Unlock (%d)" % pot.unlock_cost
            unlock_btn.pressed.connect(func(): EconomyManager.unlock_pot_type(pot))
            row.add_child(unlock_btn)
        $PotsSection.add_child(row)

func _rebuild_plant_rows() -> void:
    for child in $PlantsSection.get_children():
        child.queue_free()
    for plant in all_plants:
        # only offer plants matching the selected plot's pot type, per Section 4.4
        if selected_plot != null and plant.required_pot_id != selected_plot.pot_id:
            continue
        var row = HBoxContainer.new()
        var label = Label.new()
        label.text = "%s" % plant.display_name
        row.add_child(label)
        if plant.id in EconomyManager.unlocked_plants:
            var plant_btn = Button.new()
            plant_btn.text = "Plant (%d)" % plant.plant_cost
            plant_btn.pressed.connect(_on_plant_pressed.bind(plant))
            row.add_child(plant_btn)
        else:
            var unlock_btn = Button.new()
            unlock_btn.text = "Unlock (%d)" % plant.unlock_cost
            unlock_btn.pressed.connect(func(): EconomyManager.unlock_plant(plant))
            row.add_child(unlock_btn)
        $PlantsSection.add_child(row)

func _on_place_pot_pressed(pot: PotData) -> void:
    if selected_plot == null:
        return
    if EconomyManager.spend(pot.place_cost):
        selected_plot.place_pot(pot)

func _on_plant_pressed(plant: PlantData) -> void:
    if selected_plot == null:
        return
    if EconomyManager.spend(plant.plant_cost):
        selected_plot.plant(plant)

func buy_fertilizer() -> void:
    if EconomyManager.spend(15):
        EconomyManager.add_fertilizer(1)
