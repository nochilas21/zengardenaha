extends Window
class_name GridWindow

# A "shelf" (kệ): one transparent, borderless, always-on-top OS window.
# Drawn from the equipped ShelfSkinData: LEFT tile + MIDDLE tiles + RIGHT tile,
# one tile per pot slot. It starts with DEFAULT_SLOTS (3) and grows by one
# middle tile each time a pot is dropped on a full shelf, up to MAX_SLOTS (5).
# Drag the shelf by its name tag or by the wood (anywhere that isn't a slot).
# Built entirely in code — create with GridWindow.new(), add_child() it, THEN setup().
# Requires Project Settings → Display → Window → Subwindows → Embed Subwindows = Off.

signal sunlight_charges_changed(remaining: int)
signal plot_clicked(plot: Plot)
signal drag_finished()
signal slots_changed()
signal plot_plant_requested(plot: Plot)
signal plot_harvest_requested(plot: Plot)
signal plot_pot_drag_started(plot: Plot)
signal skin_requested(shelf: GridWindow)   # the wood / name tag was clicked (not dragged)

const PLOT_SCENE = preload("res://scenes/plot.tscn")
const DEFAULT_SLOTS: int = 3
const MAX_SLOTS: int = 5

var shelf_index: int = 1
var skin: ShelfSkinData = null

var _root: Control
var _back_layer: Control
var _base_layer: Control
var _plot_layer: Control
var _front_layer: Control
var _name_tag: Label
var _sun_badge: Control
var _plots: Array[Plot] = []
var _dragging: bool = false
var _drag_offset: Vector2i = Vector2i.ZERO
var _press_mouse: Vector2i = Vector2i.ZERO
const CLICK_MAX_MOVE_PX: float = 5.0
var _hover_plot: Plot = null

var sunlight_charges_remaining: int = 0
var user_hidden: bool = false   # hidden from Settings → Hide items (its pots are hidden with it)

# Music is global — see the MusicManager autoload (one box for every shelf).

func _init() -> void:
	# Window flags must be set before the OS window is created (i.e. before add_child)
	borderless = true
	transparent = true
	transparent_bg = true
	always_on_top = true
	unresizable = true
	# Start hidden: the OS window is created with a default size, and a
	# transparent window shown before its first real layout can stay grey on
	# some systems. The owner shows it after layout (see reveal()).
	visible = false

func _ready() -> void:
	_build_layers()
	UiScale.changed.connect(func(_f): _relayout())

# Show the shelf once it has its real size/position. Waits a frame, then
# re-applies the size so the transparent window repaints properly.
func reveal(should_show: bool) -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var real_size = size
	size = real_size + Vector2i(1, 1)
	size = real_size
	visible = should_show

func setup(index: int, start_pos: Vector2i) -> void:
	shelf_index = index
	title = "Shelf %d" % index
	_name_tag.text = " Shelf %d " % index
	position = start_pos
	skin = Inventory.get_equipped_skin("shelf") as ShelfSkinData
	while _plots.size() < DEFAULT_SLOTS:
		_add_plot()
	_relayout()

func apply_skin(new_skin: ShelfSkinData) -> void:
	skin = new_skin
	_relayout()

# ---------------------------------------------------------------- building

func _build_layers() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_back_layer = _make_layer(Control.MOUSE_FILTER_IGNORE)
	_base_layer = _make_layer(Control.MOUSE_FILTER_STOP)   # the wood: press here to drag the shelf
	_base_layer.gui_input.connect(_on_drag_area_input)
	_plot_layer = _make_layer(Control.MOUSE_FILTER_IGNORE)
	_front_layer = _make_layer(Control.MOUSE_FILTER_IGNORE)

	_name_tag = Label.new()
	_name_tag.mouse_filter = Control.MOUSE_FILTER_STOP
	_name_tag.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_name_tag.add_theme_font_size_override("font_size", 12)
	var tag_style = StyleBoxFlat.new()
	tag_style.bg_color = Color(0, 0, 0, 0.35)
	tag_style.set_corner_radius_all(6)
	_name_tag.add_theme_stylebox_override("normal", tag_style)
	_name_tag.position = Vector2(4, 2)
	_name_tag.gui_input.connect(_on_drag_area_input)
	_root.add_child(_name_tag)

	_sun_badge = SunIcon.new()
	_sun_badge.custom_minimum_size = Vector2(26, 26)
	_sun_badge.size = Vector2(26, 26)
	_sun_badge.visible = false
	_root.add_child(_sun_badge)

func _make_layer(filter: int) -> Control:
	var layer = Control.new()
	layer.mouse_filter = filter
	_root.add_child(layer)
	return layer

func _relayout() -> void:
	if skin == null:
		skin = ShelfSkinData.new()   # no skin found: built-in defaults + fallback color
	var n = _plots.size()
	var s = skin.display_scale()
	var tile_w = skin.tile_display_width
	var top = skin.top_padding
	var total = Vector2(n * tile_w, top + skin.crop_bottom_y * s)
	_root.size = total
	for layer in [_back_layer, _base_layer, _front_layer]:
		layer.size = total
		for child in layer.get_children():
			layer.remove_child(child)
			child.queue_free()
	_plot_layer.size = total

	var slot_h = top + skin.surface_y * s   # slot bottom = shelf surface line
	for i in range(n):
		var x = i * tile_w
		_add_tile(_back_layer, skin.get_tile("back", i, n), x, top, tile_w, false)
		_add_tile(_base_layer, skin.get_tile("base", i, n), x, top, tile_w, true)
		_add_tile(_front_layer, skin.get_tile("front", i, n), x, top, tile_w, false)
		var plot = _plots[i]
		var slot_w = skin.slot_width
		plot.position = Vector2(x + skin.get_slot_x(i, n) * s - slot_w / 2.0, 0)
		plot.configure_slot(Vector2(slot_w, slot_h), s * skin.pot_scale)

	_sun_badge.position = Vector2(total.x - 32, 4)
	# Layout is in design pixels; the OS window and its content are scaled by UiScale
	content_scale_factor = UiScale.factor
	size = UiScale.size_for(total)
	slots_changed.emit()

func _add_tile(layer: Control, tex: Texture2D, x: float, top: float, tile_w: float, is_base: bool) -> void:
	if tex == null:
		if is_base:   # no art: draw a simple plank so the shelf is still usable
			var plank = ColorRect.new()
			plank.color = skin.fallback_color
			plank.mouse_filter = Control.MOUSE_FILTER_PASS
			plank.position = Vector2(x, top + skin.surface_y * skin.display_scale() - 6)
			plank.size = Vector2(tile_w, 16)
			layer.add_child(plank)
		return
	var rect = TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # smooth when 1024px art is shrunk
	rect.position = Vector2(x, top)
	rect.size = Vector2(tile_w, tile_w)   # tiles are square canvases
	rect.mouse_filter = Control.MOUSE_FILTER_PASS if is_base else Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)

# ---------------------------------------------------------------- slots

func get_plots() -> Array[Plot]:
	var result: Array[Plot] = []
	for plot in _plots:
		if is_instance_valid(plot) and not plot.is_queued_for_deletion():
			result.append(plot)
	return result

func _add_plot() -> Plot:
	var plot: Plot = PLOT_SCENE.instantiate()
	_plot_layer.add_child(plot)   # add to tree first so @onready vars resolve
	plot.need_became_due.connect(_on_any_plot_need_due.bind(plot))
	plot.clicked.connect(_on_plot_clicked)
	plot.plant_requested.connect(func(p): plot_plant_requested.emit(p))
	plot.harvest_requested.connect(func(p): plot_harvest_requested.emit(p))
	plot.pot_drag_started.connect(func(p): plot_pot_drag_started.emit(p))
	_plots.append(plot)
	return plot

func _on_plot_clicked(plot: Plot) -> void:
	plot_clicked.emit(plot)

func can_add_slot() -> bool:
	return _plots.size() < MAX_SLOTS

# Grows the shelf by one middle tile. Returns the new (empty) slot, or null if full.
func add_slot() -> Plot:
	if not can_add_slot():
		return null
	var plot = _add_plot()
	_relayout()
	return plot

func get_first_empty_plot() -> Plot:
	for plot in get_plots():
		if plot.pot_id == "" and plot.plant_data == null:
			return plot
	return null

func contains_screen_point(screen_pos: Vector2i) -> bool:
	return visible and Rect2i(position, size).has_point(screen_pos)

func get_plot_at_screen(screen_pos: Vector2i) -> Plot:
	if not contains_screen_point(screen_pos):
		return null
	var local = UiScale.to_content(self, screen_pos)
	for plot in get_plots():
		if Rect2(plot.position, plot.size).has_point(local):
			return plot
	return null

# Highlights the slot a dragged pot would land in (null/outside = clear).
func set_drop_hover(screen_pos: Vector2i, active: bool) -> void:
	var target: Plot = null
	if active and contains_screen_point(screen_pos):
		target = get_plot_at_screen(screen_pos)
		if target != null and target.plant_data != null:
			target = null   # a planted pot can't be swapped
		elif target == null:
			target = get_first_empty_plot()
	if _hover_plot != target:
		if _hover_plot != null and is_instance_valid(_hover_plot):
			_hover_plot.set_drop_highlight(false)
		_hover_plot = target
		if _hover_plot != null:
			_hover_plot.set_drop_highlight(true)

# ---------------------------------------------------------------- dragging the shelf

func _on_drag_area_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_dragging = true
		_press_mouse = DisplayServer.mouse_get_position()
		_drag_offset = _press_mouse - position

func _process(_delta: float) -> void:
	if _dragging:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			position = DisplayServer.mouse_get_position() - _drag_offset
		else:
			_dragging = false
			if Vector2(DisplayServer.mouse_get_position() - _press_mouse).length() <= CLICK_MAX_MOVE_PX:
				skin_requested.emit(self)   # a click, not a drag → choose this shelf's look
			else:
				drag_finished.emit()

func _clamp_to_screen() -> void:
	var rect = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	position = Vector2i(
		clampi(position.x, rect.position.x, maxi(rect.position.x, rect.end.x - size.x)),
		clampi(position.y, rect.position.y, maxi(rect.position.y, rect.end.y - size.y))
	)

# ---------------------------------------------------------------- sunlight

func apply_mini_sun(charges: int = 3) -> void:
	sunlight_charges_remaining = charges
	_update_sun_badge()
	sunlight_charges_changed.emit(sunlight_charges_remaining)
	_satisfy_all_due_sunlight_needs()

func _satisfy_all_due_sunlight_needs() -> void:
	# A need that was already due before charges were applied already fired
	# its need_became_due signal once and won't fire again, so catch it here.
	for plot in get_plots():
		if sunlight_charges_remaining <= 0:
			break
		if plot.plant_data != null and plot.is_need_due("sunlight"):
			plot.satisfy_need("sunlight")
			_use_sun_charge()

func _on_any_plot_need_due(need_id: String, plot: Plot) -> void:
	# Only sunlight auto-resolves on becoming due. Music is handled per-plot.
	if need_id == "sunlight" and sunlight_charges_remaining > 0:
		plot.satisfy_need("sunlight")
		_use_sun_charge()

func _use_sun_charge() -> void:
	sunlight_charges_remaining -= 1
	_update_sun_badge()
	sunlight_charges_changed.emit(sunlight_charges_remaining)

func _update_sun_badge() -> void:
	_sun_badge.visible = sunlight_charges_remaining > 0
	_sun_badge.set("charges", sunlight_charges_remaining)

# ---------------------------------------------------------------- save / load

func to_dict() -> Dictionary:
	var plots_data = []
	for plot in get_plots():
		plots_data.append(plot.to_dict())
	return {
		"screen_pos": [position.x, position.y],
		"slot_count": get_plots().size(),
		"plots": plots_data,
		"sunlight_charges": sunlight_charges_remaining,
		"hidden": user_hidden,
		"skin_id": skin.id if skin != null else "",
	}

func from_dict(data: Dictionary, plant_lookup: Dictionary) -> void:
	var saved_skin = Inventory.get_skin("shelf", str(data.get("skin_id", "")))
	if saved_skin is ShelfSkinData:
		skin = saved_skin   # each shelf remembers its own look
	var slot_count = clampi(int(data.get("slot_count", DEFAULT_SLOTS)), DEFAULT_SLOTS, MAX_SLOTS)
	while _plots.size() < slot_count:
		_add_plot()
	_relayout()
	var pos = data.get("screen_pos", [position.x, position.y])
	position = Vector2i(int(pos[0]), int(pos[1]))
	var plots = get_plots()
	var plots_data = data.get("plots", [])
	for i in range(min(plots.size(), plots_data.size())):
		plots[i].from_dict(plots_data[i], plant_lookup)
	user_hidden = bool(data.get("hidden", false))
	sunlight_charges_remaining = int(data.get("sunlight_charges", 0))
	_update_sun_badge()
	call_deferred("_clamp_to_screen")   # in case the save came from a bigger/other monitor
