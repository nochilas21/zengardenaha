extends Window
class_name SellScale

# "Weigh & sell" window, opened from the Inventory.
# Put harvested plants on the scale (click a row, or drag it onto the plate),
# watch the plate sink and the needle swing, then press Sell. Like weighing
# ingredients in cooking / market games.
# Items stay in the Inventory until you press Sell.
#   SellScale.open(parent, plant_catalog)

const MAX_KG: float = 5.0          # full turn of the dial
const PLATE_DIP_PX: float = 14.0   # how far the plate sinks at MAX_KG
const SELL_ANIM_SEC: float = 0.6

var _plants: Dictionary = {}       # plant_id -> PlantData
var _on_scale: Array[String] = []  # harvest keys, one entry per plant on the plate
var _list: VBoxContainer
var _total_label: Label
var _sell_button: Button
var _view: ScaleView

static func open(parent: Node, catalog: Array[PlantData]) -> SellScale:
	var win = SellScale.new()
	for plant in catalog:
		win._plants[plant.id] = plant
	parent.add_child(win)
	return win

# Weight of one harvested plant (placeholder: bigger sell value = heavier)
static func weight_of(plant: PlantData, variant: String) -> float:
	var kg = 0.1 + plant.sell_value / 100.0
	if variant == "special":
		kg *= 1.2
	return kg

func _init() -> void:
	title = "Weigh & Sell"
	size = Vector2i(640, 420)
	unresizable = true
	always_on_top = true
	initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	close_requested.connect(queue_free)

func _ready() -> void:
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	margin.add_child(hbox)

	# left: what you harvested
	var left = VBoxContainer.new()
	left.custom_minimum_size = Vector2(220, 0)
	hbox.add_child(left)
	var title_label = Label.new()
	title_label.text = "Your harvest (click or drag →)"
	left.add_child(title_label)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	# right: the scale
	var right = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(right)
	_view = ScaleView.new()
	_view.owner_scale = self
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_view)
	_total_label = Label.new()
	_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_total_label.add_theme_font_size_override("font_size", 18)
	right.add_child(_total_label)
	var buttons = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_child(buttons)
	var take_off = Button.new()
	take_off.text = "Take one off"
	take_off.pressed.connect(_take_one_off)
	buttons.add_child(take_off)
	var clear = Button.new()
	clear.text = "Clear"
	clear.pressed.connect(_clear_scale)
	buttons.add_child(clear)
	_sell_button = Button.new()
	_sell_button.text = "Sell"
	_sell_button.pressed.connect(_sell)
	buttons.add_child(_sell_button)

	Inventory.changed.connect(_refresh)
	_refresh()

# ---------------------------------------------------------------- plate contents

func _count_on_scale(key: String) -> int:
	return _on_scale.count(key)

func add_to_scale(key: String) -> void:
	if _view.is_selling():
		return
	if _count_on_scale(key) >= int(Inventory.harvested.get(key, 0)):
		return   # can't put more on the scale than you own
	_on_scale.append(key)
	_refresh()

func _clear_scale() -> void:
	if not _view.is_selling():
		_on_scale.clear()
		_refresh()

func _take_one_off() -> void:
	if not _on_scale.is_empty() and not _view.is_selling():
		_on_scale.pop_back()
		_refresh()

func total_kg() -> float:
	var kg = 0.0
	for key in _on_scale:
		var parts = Inventory.split_harvest_key(key)
		var plant: PlantData = _plants.get(parts[0])
		if plant != null:
			kg += weight_of(plant, parts[1])
	return kg

func total_gold() -> int:
	var gold = 0
	for key in _on_scale:
		var parts = Inventory.split_harvest_key(key)
		var plant: PlantData = _plants.get(parts[0])
		if plant != null:
			gold += Shop.get_sell_price(plant, parts[1])
	return gold

func plate_icons() -> Array:
	var icons = []
	for key in _on_scale:
		icons.append(_icon_for(key))
	return icons

func _icon_for(key: String) -> Texture2D:
	var plant: PlantData = _plants.get(Inventory.split_harvest_key(key)[0])
	if plant != null and plant.stage_textures.size() > 0:
		return plant.stage_textures[plant.stage_textures.size() - 1]
	return null

func _sell() -> void:
	if _on_scale.is_empty() or _view.is_selling():
		return
	var gold = total_gold()
	var icons = plate_icons()          # capture before the plate empties
	var sold: Array[String] = _on_scale.duplicate()
	_on_scale.clear()
	for key in sold:
		Inventory.take_harvest(key)
	EconomyManager.add(gold)
	_view.play_sell(gold, icons)
	_refresh()

# ---------------------------------------------------------------- list

func _refresh() -> void:
	if _list == null:
		return
	# drop anything that is no longer owned (e.g. sold elsewhere)
	var keep: Array[String] = []
	for key in _on_scale:
		if keep.count(key) < int(Inventory.harvested.get(key, 0)):
			keep.append(key)
	_on_scale = keep

	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var any = false
	for key in Inventory.harvested:
		var owned = int(Inventory.harvested[key])
		if owned <= 0:
			continue
		var parts = Inventory.split_harvest_key(key)
		var plant: PlantData = _plants.get(parts[0])
		if plant == null:
			continue
		any = true
		var row = HarvestRow.new()
		row.key = key
		row.icon_texture = _icon_for(key)
		var variant_text = "" if parts[1] == "normal" else " (%s)" % parts[1]
		var left = owned - _count_on_scale(key)
		row.text = "%s%s  x%d   %.2f kg · %d g" % [plant.display_name, variant_text, left, weight_of(plant, parts[1]), Shop.get_sell_price(plant, parts[1])]
		row.disabled = left <= 0
		row.picked.connect(add_to_scale)
		_list.add_child(row)
	if not any:
		var hint = Label.new()
		hint.text = "Nothing harvested yet."
		_list.add_child(hint)
	_total_label.text = "%.2f kg   →   %d gold" % [total_kg(), total_gold()]
	_sell_button.disabled = _on_scale.is_empty()
	_view.queue_redraw()

# ---------------------------------------------------------------- one row in the list

class HarvestRow extends Button:
	signal picked(key: String)
	var key: String = ""
	var icon_texture: Texture2D

	func _init() -> void:
		alignment = HORIZONTAL_ALIGNMENT_LEFT
		custom_minimum_size = Vector2(0, 36)
		pressed.connect(func(): picked.emit(key))

	func _ready() -> void:
		icon = icon_texture
		expand_icon = true
		add_theme_constant_override("icon_max_width", 28)

	# Godot drag & drop works inside one window: drag a row onto the plate
	func _get_drag_data(_pos: Vector2) -> Variant:
		if disabled:
			return null
		var preview = TextureRect.new()
		preview.texture = icon
		preview.custom_minimum_size = Vector2(32, 32)
		set_drag_preview(preview)
		return {"harvest_key": key}

# ---------------------------------------------------------------- the scale drawing

class ScaleView extends Control:
	var owner_scale: SellScale
	var _needle: float = 0.0          # shown kg, eases toward the real total
	var _t: float = 0.0
	var _sell_t: float = -1.0
	var _sold_gold: int = 0
	var _sold_icons: Array = []

	func _init() -> void:
		custom_minimum_size = Vector2(360, 280)

	func is_selling() -> bool:
		return _sell_t >= 0.0

	func play_sell(gold: int, icons: Array) -> void:
		_sold_gold = gold
		_sold_icons = icons
		_sell_t = 0.0

	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("harvest_key")

	func _drop_data(_pos: Vector2, data: Variant) -> void:
		owner_scale.add_to_scale(data["harvest_key"])

	func _gui_input(event: InputEvent) -> void:
		# click the plate to take the last plant off
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			owner_scale._take_one_off()

	func _process(delta: float) -> void:
		_t += delta
		var target = 0.0 if is_selling() else owner_scale.total_kg()
		_needle = lerp(_needle, target, clamp(delta * 6.0, 0.0, 1.0))
		if _sell_t >= 0.0:
			_sell_t += delta
			if _sell_t >= SellScale.SELL_ANIM_SEC + 0.6:
				_sell_t = -1.0
		queue_redraw()

	func _draw() -> void:
		var w = size.x
		var h = size.y
		var cx = w / 2.0
		var wood = Color(0.55, 0.38, 0.22)
		var metal = Color(0.78, 0.8, 0.84)
		var dark = Color(0.2, 0.2, 0.25)
		var k = clamp(_needle / SellScale.MAX_KG, 0.0, 1.0)

		# dial (half circle gauge) at the bottom
		var dial_c = Vector2(cx, h - 30)
		var dial_r = 70.0
		draw_rect(Rect2(cx - 95, h - 110, 190, 95), wood, true)
		draw_circle(dial_c, dial_r, Color(0.96, 0.94, 0.86))
		draw_arc(dial_c, dial_r, PI, TAU, 32, dark, 2.0)
		for i in range(11):   # ticks every 0.5 kg
			var a = PI + i * PI / 10.0
			var inner = dial_r - (12.0 if i % 2 == 0 else 6.0)
			draw_line(dial_c + Vector2.from_angle(a) * inner, dial_c + Vector2.from_angle(a) * dial_r, dark, 2.0)
		var needle_a = PI + k * PI
		draw_line(dial_c, dial_c + Vector2.from_angle(needle_a) * (dial_r - 8), Color(0.85, 0.2, 0.2), 3.0)
		draw_circle(dial_c, 5.0, dark)
		draw_rect(Rect2(cx - 95, h - 30, 190, 22), wood.darkened(0.2), true)   # cover the lower half of the dial

		# column + plate (sinks with the weight, wobbles a bit)
		var dip = k * SellScale.PLATE_DIP_PX + sin(_t * 9.0) * (1.5 if _needle > 0.01 else 0.0) * (1.0 - k)
		var plate_y = 90.0 + dip
		draw_rect(Rect2(cx - 8, plate_y, 16, h - 110 - plate_y), metal.darkened(0.2), true)
		draw_colored_polygon(PackedVector2Array([
			Vector2(cx - 110, plate_y), Vector2(cx + 110, plate_y),
			Vector2(cx + 90, plate_y + 14), Vector2(cx - 90, plate_y + 14),
		]), metal)

		# plants piled on the plate
		var icons = _sold_icons if is_selling() else owner_scale.plate_icons()
		var lift = 0.0
		var alpha = 1.0
		if is_selling():
			var s = clamp(_sell_t / SellScale.SELL_ANIM_SEC, 0.0, 1.0)
			lift = 60.0 * s
			alpha = 1.0 - s
		var per_row = 6
		for i in range(min(icons.size(), 18)):
			var col = i % per_row
			var row = i / per_row
			var pos = Vector2(cx - 90 + col * 30 + (row % 2) * 12, plate_y - 30 - row * 16 - lift)
			if icons[i] != null:
				draw_texture_rect(icons[i], Rect2(pos, Vector2(32, 32)), false, Color(1, 1, 1, alpha))
			else:
				draw_circle(pos + Vector2(16, 16), 10.0, Color(0.5, 0.8, 0.4, alpha))
		if icons.size() > 18:
			draw_string(ThemeDB.fallback_font, Vector2(cx + 95, plate_y - 40), "+%d" % (icons.size() - 18), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, alpha))

		# readout
		var font = ThemeDB.fallback_font
		draw_string(font, Vector2(0, h - 116), "%.2f kg" % _needle, HORIZONTAL_ALIGNMENT_CENTER, w, 16, Color(1, 1, 1))
		if is_selling():
			var s2 = clamp(_sell_t / (SellScale.SELL_ANIM_SEC + 0.6), 0.0, 1.0)
			draw_string(font, Vector2(0, 60 - 30 * s2), "+%d gold" % _sold_gold, HORIZONTAL_ALIGNMENT_CENTER, w, 24, Color(1.0, 0.85, 0.3, 1.0 - s2))
		elif icons.is_empty():
			draw_string(font, Vector2(0, plate_y - 20), "Put plants here", HORIZONTAL_ALIGNMENT_CENTER, w, 14, Color(1, 1, 1, 0.5))
