extends Window
class_name FairyMenu

# The menu button: a small glowing fairy / firefly light that floats on the
# desktop (transparent, borderless, always on top).
#   Click        → open / close the menu. Items fan out in half circles below it.
#   Drag         → move it. It struggles while held; when let go it drops,
#                  bumps the "ground" and floats back up.
#   Click 3×     → hide / show everything on screen (hide_all_toggled).
#
# The menu knows nothing about what its items do. Items are REGISTERED by the
# owner, which also handles them:
#   register_item("shop", "Shop", "shop")                      # normal item → item_activated("shop")
#   register_item("sun", "Sun", "sun", true)                   # tool (press & drag) → tool_drag_started("sun")
#   register_item("music_box", "Music", "music_box", false, "music_box")   # look from the equipped skin
#   register_item("quests", "Quests", "", false, "", my_icon)  # any texture as icon
# Up to MAX_PER_RING items share one half circle; more items open a second,
# wider ring, and so on — adding features never needs layout changes.

signal item_activated(id: String)
signal tool_drag_started(id: String)
signal hide_all_toggled()
signal skin_requested(category: String)   # right-click the light ("menu") or a skinnable item

const FAIRY_BOX: Vector2 = Vector2(80, 120)       # fairy area: extra room below for the drop animation
const FAIRY_CENTER: Vector2 = Vector2(40, 40)     # where the light sits inside FAIRY_BOX
const ITEM_SIZE: Vector2 = Vector2(58, 64)
const ARC_RADIUS: float = 108.0                   # first half circle of items below the fairy
const RING_STEP: float = 72.0                     # extra radius for each further ring
const MAX_PER_RING: int = 7
const OPEN_TWEEN_SEC: float = 0.22
const TRIPLE_CLICK_SEC: float = 0.8
const DRAG_THRESHOLD_PX: float = 5.0

var is_open: bool = false
var _root: Control
var _fairy: MenuIcon
var _items: Array[Dictionary] = []   # {id, icon: MenuIcon, is_tool, skin_category}
var _pressing: bool = false
var _dragging: bool = false
var _press_mouse: Vector2i
var _press_window_pos: Vector2i
var _last_pos: Vector2i
var _velocity: Vector2 = Vector2.ZERO
var _click_times: Array[float] = []
var _tween: Tween = null

func _init() -> void:
	borderless = true
	transparent = true
	transparent_bg = true
	always_on_top = true
	unresizable = true
	title = "Menu"
	visible = false   # shown after the first layout (see _reveal)

func _ready() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_fairy = MenuIcon.new()
	_fairy.glyph = "fairy"
	_fairy.custom_minimum_size = FAIRY_BOX
	_fairy.size = FAIRY_BOX
	_fairy.fixed_center = FAIRY_CENTER
	_fairy.press_started.connect(_on_fairy_press)
	_fairy.right_clicked.connect(func(): skin_requested.emit("menu"))
	_root.add_child(_fairy)

	Inventory.changed.connect(apply_skins)
	apply_skins()
	_apply_layout(false, false)
	_reveal()

func _reveal() -> void:
	await get_tree().process_frame
	var real_size = size
	size = real_size + Vector2i(1, 1)
	size = real_size
	visible = true

# ---------------------------------------------------------------- items

func register_item(id: String, label: String, glyph: String, is_tool: bool = false, skin_category: String = "", icon: Texture2D = null) -> void:
	if has_item(id):
		return
	var item = MenuIcon.new()
	item.glyph = glyph
	item.label_text = label
	item.icon = icon
	item.custom_minimum_size = ITEM_SIZE
	item.size = ITEM_SIZE
	item.pivot_offset = ITEM_SIZE / 2.0
	item.visible = is_open
	if is_tool:
		item.press_started.connect(func(): tool_drag_started.emit(id))
	else:
		item.pressed.connect(func(): item_activated.emit(id))
	if skin_category != "":
		item.right_clicked.connect(func(): skin_requested.emit(skin_category))
	_root.add_child(item)
	_root.move_child(_fairy, -1)   # the fairy always draws on top of the items
	_items.append({"id": id, "icon": item, "is_tool": is_tool, "skin_category": skin_category})
	apply_skins()
	if is_open:
		_apply_layout(true, false)

func remove_item(id: String) -> void:
	for i in range(_items.size()):
		if _items[i]["id"] == id:
			_items[i]["icon"].queue_free()
			_items.remove_at(i)
			if is_open:
				_apply_layout(true, false)
			return

func has_item(id: String) -> bool:
	for entry in _items:
		if entry["id"] == id:
			return true
	return false

func apply_skins() -> void:
	if _fairy == null:
		return
	_fairy.apply_icon_skin(Inventory.get_equipped_skin("menu") as IconSkinData)
	for entry in _items:
		if entry["skin_category"] != "":
			entry["icon"].apply_icon_skin(Inventory.get_equipped_skin(entry["skin_category"]) as IconSkinData)

# ---------------------------------------------------------------- open / close

func toggle() -> void:
	_set_open(not is_open)

func _set_open(value: bool) -> void:
	if value == is_open:
		return
	_apply_layout(value, true)

func _ring_count() -> int:
	return maxi(1, ceili(_items.size() / float(MAX_PER_RING)))

func _open_size() -> Vector2:
	var outer = ARC_RADIUS + (_ring_count() - 1) * RING_STEP
	return Vector2(2.0 * outer + ITEM_SIZE.x + 8.0, FAIRY_CENTER.y + outer + ITEM_SIZE.y / 2.0 + 14.0)

# Target position of item i: rings of up to MAX_PER_RING items, each spread
# evenly over a half circle from the left (PI) through straight down to the right (0).
func _item_target(i: int, center: Vector2) -> Vector2:
	var ring = i / MAX_PER_RING
	var first = ring * MAX_PER_RING
	var in_ring = mini(MAX_PER_RING, _items.size() - first)
	var slot = i - first
	var a = PI / 2.0 if in_ring == 1 else PI - slot * PI / float(in_ring - 1)
	var r = ARC_RADIUS + ring * RING_STEP
	return center + Vector2.from_angle(a) * r - ITEM_SIZE / 2.0

# Closed: the window is just the fairy box. Open: the window grows around the
# fairy (the fairy stays at the same spot on screen) and the items fly out.
func _apply_layout(open: bool, animate: bool) -> void:
	var was_open = _fairy.position.x > 0.0   # the fairy is offset only while open
	is_open = open
	var big = _open_size()
	var fairy_pos_open = Vector2((big.x - FAIRY_BOX.x) / 2.0, 0.0)
	if open:
		if was_open:
			position += Vector2i(int(_fairy.position.x), 0)   # undo the old shift (ring count may have changed)
		position -= Vector2i(int(fairy_pos_open.x), 0)
		size = Vector2i(big)
		_fairy.position = fairy_pos_open
	else:
		if was_open:
			position += Vector2i(int(_fairy.position.x), 0)
		size = Vector2i(FAIRY_BOX)
		_fairy.position = Vector2.ZERO
	var center = _fairy.position + FAIRY_CENTER
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if open and animate:
		_tween = create_tween().set_parallel(true)
	for i in range(_items.size()):
		var item: MenuIcon = _items[i]["icon"]
		item.visible = open
		if not open:
			continue
		var target = _item_target(i, center)
		if animate:
			item.position = center - ITEM_SIZE / 2.0
			item.scale = Vector2(0.3, 0.3)
			_tween.tween_property(item, "position", target, OPEN_TWEEN_SEC).set_delay(i * 0.03).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_tween.tween_property(item, "scale", Vector2.ONE, OPEN_TWEEN_SEC).set_delay(i * 0.03)
		else:
			item.position = target
			item.scale = Vector2.ONE

# ---------------------------------------------------------------- click / drag the fairy

func _on_fairy_press() -> void:
	_pressing = true
	_dragging = false
	_press_mouse = DisplayServer.mouse_get_position()
	_press_window_pos = position

func _process(delta: float) -> void:
	# smoothed drag speed → the fairy's "struggling" pose
	if delta > 0.0:
		_velocity = _velocity.lerp(Vector2(position - _last_pos) / delta, 0.3)
	_last_pos = position
	_fairy.dragging = _dragging
	_fairy.drag_velocity = _velocity
	if not _pressing:
		return
	var mouse = DisplayServer.mouse_get_position()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if not _dragging and Vector2(mouse - _press_mouse).length() > DRAG_THRESHOLD_PX:
			_dragging = true
		if _dragging:
			position = _press_window_pos + (mouse - _press_mouse)
	else:
		_pressing = false
		if _dragging:
			_dragging = false
			_fairy.start_landing()   # drop → bump → float back up
		else:
			_on_fairy_clicked()

func _on_fairy_clicked() -> void:
	var now = Time.get_ticks_msec() / 1000.0
	_click_times.append(now)
	while _click_times.size() > 3:
		_click_times.pop_front()
	if _click_times.size() == 3 and now - _click_times[0] <= TRIPLE_CLICK_SEC:
		_click_times.clear()
		_set_open(false)
		hide_all_toggled.emit()
		return
	toggle()

# ---------------------------------------------------------------- save / load

# Saved as the fairy's own screen position (same whether the menu is open or not)
func to_dict() -> Dictionary:
	var p = position + Vector2i(_fairy.position)
	return {"screen_pos": [p.x, p.y]}

func from_dict(data: Dictionary) -> void:
	_apply_layout(false, false)
	var pos = data.get("screen_pos", [position.x, position.y])
	position = Vector2i(int(pos[0]), int(pos[1]))
