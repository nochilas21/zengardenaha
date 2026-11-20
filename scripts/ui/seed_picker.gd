extends Window
class_name SeedPicker

# Opened by the (+) popup on an empty pot: lists the seeds in your bag that can
# grow in THIS pot. Click one, then Confirm (or double-click it) to plant it.
#   SeedPicker.open(parent, plot, plant_catalog) → emits confirmed(plant) / closed

signal confirmed(plant: PlantData)

var _plot: Plot
var _catalog: Array[PlantData] = []
var _selected: PlantData = null
var _list: VBoxContainer
var _confirm: Button
var _hint: Label
var _rows: Dictionary = {}   # plant_id -> PanelContainer

static func open(parent: Node, plot: Plot, catalog: Array[PlantData]) -> SeedPicker:
	var picker = SeedPicker.new()
	picker._plot = plot
	picker._catalog = catalog
	parent.add_child(picker)
	return picker

func _init() -> void:
	title = "Choose a seed"
	UiScale.track(self, Vector2(320, 380))
	unresizable = true
	always_on_top = true
	initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	close_requested.connect(queue_free)

func _ready() -> void:
	# open next to the slot that asked for it
	var near = _plot._get_screen_center() + Vector2i(80, -size.y / 2)
	var rect = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	position = Vector2i(clampi(near.x, rect.position.x, rect.end.x - size.x), clampi(near.y, rect.position.y, rect.end.y - size.y))

	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var vbox = VBoxContainer.new()
	margin.add_child(vbox)

	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_hint)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	var buttons = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(buttons)
	var cancel = Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(queue_free)
	buttons.add_child(cancel)
	_confirm = Button.new()
	_confirm.text = "Plant"
	_confirm.disabled = true
	_confirm.pressed.connect(_on_confirm)
	buttons.add_child(_confirm)

	_build_list()

func _build_list() -> void:
	var any = false
	for plant in _catalog:
		if plant.required_pot_id != _plot.pot_id:
			continue   # this seed can't grow in this pot type
		var count = Inventory.get_seed_count(plant.id)
		if count <= 0:
			continue
		any = true
		_list.add_child(_make_row(plant, count))
	_hint.text = "Pick a seed for this pot:" if any else "No seeds for this pot in your bag.\nBuy seeds in the Shop."

func _make_row(plant: PlantData, count: int) -> Control:
	var row = PanelContainer.new()
	var hbox = HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hbox)
	var icon = TextureRect.new()
	icon.custom_minimum_size = Vector2(36, 36)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if plant.stage_textures.size() > 0:
		icon.texture = plant.stage_textures[plant.stage_textures.size() - 1]
	hbox.add_child(icon)
	var label = Label.new()
	label.text = "%s  x%d   [%s]" % [plant.display_name, count, plant.rarity]
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(label)
	row.gui_input.connect(_on_row_input.bind(plant))
	_rows[plant.id] = row
	return row

func _on_row_input(event: InputEvent, plant: PlantData) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_select(plant)
		if event.double_click:
			_on_confirm()

func _select(plant: PlantData) -> void:
	_selected = plant
	for id in _rows:
		_rows[id].modulate = Color(1.3, 1.25, 0.8) if id == plant.id else Color(1, 1, 1)
	_confirm.disabled = false

func _on_confirm() -> void:
	if _selected == null:
		return
	confirmed.emit(_selected)
	queue_free()
