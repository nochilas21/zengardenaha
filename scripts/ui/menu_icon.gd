extends Control
class_name MenuIcon

# Round icon used by the fairy menu. Shows a skin texture if one is given,
# otherwise draws a built-in placeholder glyph:
#   "fairy"     — glowing firefly/fairy light (the menu button itself)
#   "inventory" — little bag
#   "shop"      — little stall with awning
#   "music_box" — music note
#   "sun"       — cute sun (uses SunIcon drawing)
#   "settings"  — little gear
#   "shovel"    — little garden shovel
# Emits pressed() on click and press_started() on mouse-down (used to start drags).

signal pressed()
signal press_started()
signal right_clicked()   # used to open the skin picker for this icon

var glyph: String = "fairy"
var label_text: String = ""
var icon: Texture2D = null
var glow_color: Color = Color(0.75, 1.0, 0.7)
var tint: Color = Color(1, 1, 1)
var _t: float = 0.0
var _hover: bool = false
var _sun: SunIcon = null

# Fairy only: set by FairyMenu while the player drags it
var dragging: bool = false
var drag_velocity: Vector2 = Vector2.ZERO   # screen px / s
var fixed_center: Vector2 = Vector2(-1, -1)  # where the icon is drawn (default: middle)

# Fairy only: after being dropped it falls, bumps the "ground", then floats back up
const LAND_FALL_SEC: float = 0.28
const LAND_IMPACT_SEC: float = 0.12
const LAND_RISE_SEC: float = 0.7
const LAND_DROP_PX: float = 32.0
var _landing_t: float = -1.0

func _init() -> void:
	custom_minimum_size = Vector2(56, 64)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _ready() -> void:
	mouse_entered.connect(func(): _hover = true)
	mouse_exited.connect(func(): _hover = false)
	if glyph == "sun" and icon == null:
		_sun = SunIcon.new()
		_sun.position = Vector2((custom_minimum_size.x - 40) / 2.0, 2)
		_sun.size = Vector2(40, 40)
		add_child(_sun)

func apply_icon_skin(skin: IconSkinData) -> void:
	if skin == null:
		return
	icon = skin.icon
	glow_color = skin.glow_color
	tint = skin.tint
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		right_clicked.emit()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			press_started.emit()
		else:
			pressed.emit()

func _process(delta: float) -> void:
	_t += delta
	if _landing_t >= 0.0:
		_landing_t += delta
		if _landing_t > LAND_FALL_SEC + LAND_IMPACT_SEC + LAND_RISE_SEC:
			_landing_t = -1.0
	queue_redraw()

func start_landing() -> void:
	_landing_t = 0.0

# [y offset, scale] for the drop → bump → float back up animation
func _landing_pose() -> Array:
	var t = _landing_t
	if t < 0.0:
		return [0.0, Vector2.ONE]
	if t < LAND_FALL_SEC:                       # falling, a bit stretched
		var k = t / LAND_FALL_SEC
		return [LAND_DROP_PX * k * k, Vector2(0.9, 1.12)]
	t -= LAND_FALL_SEC
	if t < LAND_IMPACT_SEC:                     # squash on impact
		var q = sin(t / LAND_IMPACT_SEC * PI)
		return [LAND_DROP_PX, Vector2(1.0 + 0.4 * q, 1.0 - 0.35 * q)]
	t -= LAND_IMPACT_SEC                        # float back up with a small overshoot
	var r = clamp(t / LAND_RISE_SEC, 0.0, 1.0)
	var up = 1.0 - pow(1.0 - r, 3.0)
	var overshoot = sin(r * PI) * 4.0
	return [LAND_DROP_PX * (1.0 - up) - overshoot, Vector2(1.0, 1.0 + 0.06 * sin(r * PI))]

func _icon_center() -> Vector2:
	if fixed_center.x >= 0.0:
		return fixed_center
	return Vector2(size.x / 2.0, 22.0) if label_text != "" else size / 2.0

func _draw() -> void:
	var c = _icon_center()
	var r = 18.0
	if glyph != "fairy":
		draw_circle(c, r + 3.0, Color(0.1, 0.12, 0.2, 0.75 if _hover else 0.6))
		draw_arc(c, r + 3.0, 0, TAU, 32, Color(glow_color, 0.7), 1.5)
	if icon != null:
		var s = r * 2.0
		draw_texture_rect(icon, Rect2(c - Vector2(s, s) / 2.0, Vector2(s, s)), false, tint)
	else:
		match glyph:
			"fairy":
				_draw_fairy(c)
			"inventory":
				_draw_bag(c)
			"shop":
				_draw_shop(c)
			"music_box":
				_draw_note(c)
			"settings":
				_draw_gear(c)
			"shovel":
				_draw_shovel(c)
			_:
				# unknown glyph (a new menu item without art yet): first letter of its label
				if label_text != "":
					draw_string(ThemeDB.fallback_font, c + Vector2(-r, 7), label_text.substr(0, 1).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 20, Color(1, 1, 1, 0.9))
	if label_text != "":
		draw_string(ThemeDB.fallback_font, Vector2(0, size.y - 4), label_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 11, Color(1, 1, 1, 0.9))

func _draw_fairy(c: Vector2) -> void:
	if dragging:
		_draw_fairy_dragged(c)
		return
	# Idle: floats gently up and down, soft pulsing light, tiny wings and sparkles.
	# Right after a drop it falls, squashes on the "ground", then floats back up.
	var pose = _landing_pose()
	var landing = _landing_t >= 0.0
	var bob = 0.0 if landing else sin(_t * 2.2) * 3.0
	var center = c + Vector2(0, bob + pose[0])
	if landing and _landing_t >= LAND_FALL_SEC and _landing_t < LAND_FALL_SEC + LAND_IMPACT_SEC + 0.25:
		var puff = (_landing_t - LAND_FALL_SEC) / (LAND_IMPACT_SEC + 0.25)   # dust puffs on impact
		for side in [-1.0, 1.0]:
			for i in range(3):
				var p = c + Vector2(side * (8.0 + puff * (14.0 + i * 6.0)), LAND_DROP_PX + 8.0 - puff * 6.0 - i * 2.0)
				draw_circle(p, 3.0 - i * 0.6, Color(1, 1, 0.9, 0.5 * (1.0 - puff)))
	draw_set_transform(center, 0.0, pose[1])
	var pulse = 0.85 + 0.15 * sin(_t * 3.0)
	for i in range(6):
		var rr = (26.0 - i * 4.0) * pulse
		draw_circle(Vector2.ZERO, rr, Color(glow_color, 0.07 + i * 0.03))
	var wing = Color(1, 1, 1, 0.35 + 0.15 * sin(_t * (30.0 if landing else 12.0)))
	draw_circle(Vector2(-7, -5), 5.0, wing)
	draw_circle(Vector2(7, -5), 5.0, wing)
	draw_circle(Vector2.ZERO, 6.0 * pulse, Color(1, 1, 0.85))
	if landing and _landing_t < LAND_FALL_SEC + LAND_IMPACT_SEC + 0.2:
		draw_circle(Vector2(-2, -1), 1.3, Color(0.2, 0.25, 0.2))   # surprised wide eyes
		draw_circle(Vector2(2, -1), 1.3, Color(0.2, 0.25, 0.2))
	else:
		draw_circle(Vector2(-2, -1), 0.9, Color(0.2, 0.25, 0.2))   # sleepy little eyes
		draw_circle(Vector2(2, -1), 0.9, Color(0.2, 0.25, 0.2))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in range(3):   # sparkles orbiting
		var a = _t * 1.5 + i * TAU / 3.0
		draw_circle(center + Vector2.from_angle(a) * 16.0, 1.5, Color(1, 1, 0.8, 0.8))

func _draw_fairy_dragged(c: Vector2) -> void:
	# Being dragged: it struggles a little like a caught creature — the light
	# stretches along the drag, it wiggles, squints (> <) and flaps hard.
	var speed = clamp(drag_velocity.length() / 900.0, 0.0, 1.0)
	var angle = drag_velocity.angle() if drag_velocity.length() > 5.0 else PI / 2.0
	var stretch = 0.15 + 0.35 * speed
	var wiggle = sin(_t * 32.0) * 0.18
	# stretched glow (trail)
	draw_set_transform(c, angle, Vector2(1.0 + stretch, 1.0 - stretch * 0.5))
	for i in range(6):
		draw_circle(Vector2.ZERO, 24.0 - i * 4.0, Color(glow_color, 0.06 + i * 0.03))
	# squished body, wiggling against the drag
	draw_set_transform(c, wiggle, Vector2(1.15, 0.85))
	var flap = 0.4 + 0.6 * absf(sin(_t * 40.0))
	draw_circle(Vector2(-9, -6), 6.0 * flap, Color(1, 1, 1, 0.5))
	draw_circle(Vector2(9, -6), 6.0 * flap, Color(1, 1, 1, 0.5))
	draw_circle(Vector2.ZERO, 7.0, Color(1, 1, 0.8))
	var face = Color(0.25, 0.2, 0.15)
	draw_line(Vector2(-4, -3), Vector2(-1.5, -1.5), face, 1.2)   # >
	draw_line(Vector2(-4, 0), Vector2(-1.5, -1.5), face, 1.2)
	draw_line(Vector2(4, -3), Vector2(1.5, -1.5), face, 1.2)     # <
	draw_line(Vector2(4, 0), Vector2(1.5, -1.5), face, 1.2)
	draw_arc(Vector2(0, 3), 2.0, PI, TAU, 6, face, 1.0)          # little frown
	for side in [-1.0, 1.0]:                                      # flailing legs
		var swing = sin(_t * 25.0 + side) * 4.0
		draw_line(Vector2(side * 3, 6), Vector2(side * 5 + swing, 12), Color(1, 1, 0.8, 0.9), 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in range(3):   # sweat drops / sparkles flying off
		var a = _t * 6.0 + i * TAU / 3.0
		draw_circle(c + Vector2.from_angle(a) * (18.0 + 4.0 * sin(_t * 9.0 + i)), 1.6, Color(0.8, 0.95, 1.0, 0.8))

func _draw_bag(c: Vector2) -> void:
	var bag = Color(0.85, 0.6, 0.35) * tint
	draw_rect(Rect2(c + Vector2(-10, -6), Vector2(20, 16)), bag)
	draw_arc(c + Vector2(0, -6), 6.0, PI, TAU, 12, bag.darkened(0.3), 2.5)
	draw_line(c + Vector2(-10, 0), c + Vector2(10, 0), bag.darkened(0.25), 2.0)

func _draw_shop(c: Vector2) -> void:
	var awning = Color(0.95, 0.45, 0.45) * tint
	for i in range(4):
		var x = c.x - 12 + i * 6
		draw_rect(Rect2(Vector2(x, c.y - 10), Vector2(6, 7)), awning if i % 2 == 0 else Color(1, 1, 1))
	draw_rect(Rect2(c + Vector2(-10, -3), Vector2(20, 13)), Color(0.75, 0.55, 0.35) * tint)
	draw_rect(Rect2(c + Vector2(-3, 2), Vector2(6, 8)), Color(0.35, 0.22, 0.12))

func _draw_note(c: Vector2) -> void:
	var note = Color(0.75, 0.6, 1.0) * tint
	draw_line(c + Vector2(4, -10), c + Vector2(4, 6), note, 2.5)
	draw_line(c + Vector2(4, -10), c + Vector2(11, -6), note, 2.5)
	draw_circle(c + Vector2(0, 7), 4.5, note)

func _draw_gear(c: Vector2) -> void:
	var col = Color(0.8, 0.85, 0.95) * tint
	for i in range(8):
		var a = i * TAU / 8.0 + _t * 0.3
		draw_line(c + Vector2.from_angle(a) * 7.0, c + Vector2.from_angle(a) * 12.0, col, 4.0)
	draw_circle(c, 8.5, col)
	draw_circle(c, 3.5, Color(0.1, 0.12, 0.2))

func _draw_shovel(c: Vector2) -> void:
	var wood = Color(0.7, 0.5, 0.3) * tint
	var metal = Color(0.75, 0.8, 0.85) * tint
	draw_line(c + Vector2(-9, -10), c + Vector2(3, 2), wood, 3.5)            # handle
	draw_line(c + Vector2(-12, -12), c + Vector2(-6, -8), wood.darkened(0.2), 5.0)   # grip
	draw_colored_polygon(PackedVector2Array([                               # blade
		c + Vector2(1, 0), c + Vector2(6, -3), c + Vector2(12, 4),
		c + Vector2(10, 12), c + Vector2(3, 10), c + Vector2(-1, 5),
	]), metal)
	draw_line(c + Vector2(3, 2), c + Vector2(8, 7), metal.darkened(0.3), 1.0)
