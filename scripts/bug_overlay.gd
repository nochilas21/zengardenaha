extends Window
class_name BugOverlay

# Mode 2 (troll plants with many bugs): ONE transparent overlay window covering
# the usable screen; every bug is just a TextureButton inside it. Mouse clicks
# pass through everywhere except the bugs, via mouse_passthrough_polygon.
# Does NOT count toward DesktopBug.MAX_DESKTOP_BUGS.

signal bug_caught()

const HIT_PADDING: float = 8.0                 # bigger click area, covers movement between updates
const PASSTHROUGH_UPDATE_SEC: float = 1.0 / 30.0

var _bugs: Dictionary = {}   # TextureButton -> BugMotion
var _passthrough_timer: float = 0.0

# Call BEFORE add_child.
func setup(count: int, texture: Texture2D, bug_speed: float, origin: Vector2i, screen_rect: Rect2i) -> void:
	borderless = true
	transparent = true
	transparent_bg = true
	always_on_top = true
	unresizable = true
	position = screen_rect.position
	size = screen_rect.size   # usable rect (excludes taskbar), so not treated as exclusive fullscreen

	var local_area = Rect2i(Vector2i.ZERO, screen_rect.size)
	var local_origin = Vector2(origin - screen_rect.position)
	var bug_size = Vector2(DesktopBug.BUG_SIZE, DesktopBug.BUG_SIZE)
	for i in range(count):
		var button = TextureButton.new()
		button.texture_normal = texture
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		button.size = bug_size
		var jitter = Vector2(randf_range(-20, 20), randf_range(-20, 20))
		var motion = BugMotion.new(local_origin + jitter, bug_speed, local_area, bug_size)
		button.position = motion.pos
		button.pressed.connect(_on_bug_pressed.bind(button))
		add_child(button)
		_bugs[button] = motion

func _ready() -> void:
	_update_passthrough()

func _process(delta: float) -> void:
	for button in _bugs:
		button.position = _bugs[button].step(delta)
	_passthrough_timer -= delta
	if _passthrough_timer <= 0.0:
		_update_passthrough()
		_passthrough_timer = PASSTHROUGH_UPDATE_SEC

func _on_bug_pressed(button: TextureButton) -> void:
	_bugs.erase(button)
	button.queue_free()
	bug_caught.emit()
	if _bugs.is_empty():
		# Never keep an empty overlay alive: an EMPTY passthrough polygon means
		# the whole window catches the mouse and blocks the user's desktop.
		queue_free()
	else:
		_update_passthrough()

func _update_passthrough() -> void:
	# One polygon covering every bug: start at a corner, go out to each bug's
	# rectangle, trace it, and come back along the same line. The connecting
	# lines have zero width, so only the bug rectangles are clickable.
	# (Where two bugs overlap, that overlap may become click-through.)
	var poly = PackedVector2Array()
	poly.append(Vector2.ZERO)
	for button in _bugs:
		var r = Rect2(button.position, button.size).grow(HIT_PADDING)
		poly.append(r.position)
		poly.append(Vector2(r.end.x, r.position.y))
		poly.append(r.end)
		poly.append(Vector2(r.position.x, r.end.y))
		poly.append(r.position)
		poly.append(Vector2.ZERO)
	mouse_passthrough_polygon = poly
