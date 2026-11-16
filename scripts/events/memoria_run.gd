extends Node2D
class_name MemoriaRun

# Memoria Moonflower event — a 25-second jump-and-run.
# Concept: a ghost of your past chases your present self through a fairy-tale
# forest on a blue-moon night. Obstacles: fallen branches, hands reaching up
# from the ground and down from the canopy. Memory fragments give ONE boosted
# jump (high or long) — some sections are impossible without the right one.
# At 25 s you reach home, the ghost collapses at the door, and the blue moon
# reaches its peak (zenith).
#
# Everything is drawn in code (placeholder art). Run this scene alone with F6,
# or open it in its own OS window with MemoriaRun.open_in_window(parent).
#
# Controls: Space / Up / W / left click = jump.  Esc = give up.
# R = retry after being caught (only when allow_retry is true, i.e. debug/F6;
# as a plant event, being caught ends the run and counts as a loss).

signal finished(success: bool)

const VIEW_W: float = 960.0
const VIEW_H: float = 540.0
const GROUND_Y: float = 440.0
const RUN_DURATION: float = 25.0
const INTRO_SEC: float = 1.8
const END_SEC: float = 6.5
const SCROLL_SPEED: float = 320.0

const PLAYER_HOME_X: float = 260.0
const PLAYER_W: float = 28.0
const PLAYER_H: float = 44.0
const GHOST_HOME_X: float = 70.0

# Jumps (all placeholders, tune by playtesting)
const GRAVITY: float = 2200.0
const JUMP_VELOCITY: float = -820.0          # normal: ~150 px high, ~240 px long
const HIGH_JUMP_VELOCITY: float = -1150.0    # memory "HIGH": ~300 px high
const LONG_JUMP_VELOCITY: float = -560.0     # memory "LONG": low floaty arc...
const LONG_JUMP_GRAVITY: float = 900.0
const LONG_JUMP_SPEED_MULT: float = 1.7      # ...plus a forward dash: ~670 px long

# Getting hit
const HIT_PUSHBACK: float = 50.0             # you stumble back toward the ghost
const HIT_GHOST_ADVANCE: float = 15.0        # the ghost closes in
const RECOVER_SPEED: float = 15.0            # px/s you regain while running clean
const GHOST_RECEDE_SPEED: float = 5.0
const INVULNERABLE_SEC: float = 1.4          # long enough to pass one obstacle
const CATCH_DISTANCE: float = 30.0
const COYOTE_SEC: float = 0.08
const JUMP_BUFFER_SEC: float = 0.12
const HITBOX_INSET: float = 6.0              # forgiving collisions

# Level layout in world pixels (320 px/s → 25 s ≈ 8000 px).
# Each memory fragment sits right before the section that needs it, with
# nothing in between, so the boosted jump isn't wasted on something else.
const LEVEL: Array = [
	{"type": "branch", "x": 1000.0},
	{"type": "hand_low", "x": 1500.0},
	{"type": "branch", "x": 2000.0},
	{"type": "hand_low", "x": 2300.0},
	{"type": "hand_top", "x": 2800.0, "w": 200.0},
	{"type": "branch", "x": 3150.0},
	{"type": "frag_high", "x": 3700.0},
	{"type": "hand_wall", "x": 4300.0},     # impossible without HIGH
	{"type": "hand_top", "x": 4800.0, "w": 220.0},
	{"type": "hand_low", "x": 5250.0},
	{"type": "frag_long", "x": 5650.0},
	{"type": "hand_pit", "x": 6200.0},      # impossible without LONG
	{"type": "branch", "x": 6950.0},
	{"type": "hand_top", "x": 7250.0, "w": 180.0},
	{"type": "hand_low", "x": 7550.0},
]

enum State { INTRO, RUNNING, ENDING, CAUGHT, DONE }

var allow_retry: bool = true
var state: State = State.INTRO
var elapsed: float = 0.0
var scroll: float = 0.0
var player_x: float = PLAYER_HOME_X
var player_y: float = GROUND_Y   # feet
var vel_y: float = 0.0
var buff: String = ""            # "", "high" or "long"
var ghost_x: float = GHOST_HOME_X

var _time: float = 0.0
var _intro_t: float = 0.0
var _end_t: float = 0.0
var _caught_t: float = 0.0
var _on_ground: bool = true
var _coyote_t: float = 0.0
var _jump_buffer_t: float = 0.0
var _long_jump_active: bool = false
var _invuln_t: float = 0.0
var _hit_flash_t: float = 0.0
var _player_alpha: float = 1.0
var _ghost_fade: float = 0.0
var _house_x: float = VIEW_W + 40.0

var _obstacles: Array = []   # {type, rect (world)}
var _fragments: Array = []   # {type, rect (world), taken}
var _stars: Array = []
var _far_trees: Array = []
var _near_trees: Array = []
var _fireflies: Array = []
var _font: Font

# ---------------------------------------------------------------- opening

# Opens the minigame in its own normal OS window, centered. The window closes
# itself when the run finishes; connect to the returned node's `finished`.
static func open_in_window(parent: Node, retry_allowed: bool = true) -> MemoriaRun:
	var win = Window.new()
	win.title = "Memoria Moonflower — Blue Moon Night"
	win.size = Vector2i(int(VIEW_W), int(VIEW_H))
	win.unresizable = true
	win.always_on_top = true
	win.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	parent.add_child(win)
	var run = MemoriaRun.new()
	run.allow_retry = retry_allowed
	win.add_child(run)
	run.finished.connect(func(_success): win.queue_free())
	win.close_requested.connect(run.give_up)
	return run

func _ready() -> void:
	_font = ThemeDB.fallback_font
	var rng = RandomNumberGenerator.new()
	rng.seed = 20261115   # same forest every time
	for i in range(70):
		_stars.append(Vector3(rng.randf_range(0, VIEW_W), rng.randf_range(0, 300), rng.randf_range(0, TAU)))
	var x = 0.0
	while x < VIEW_W + 300:
		_far_trees.append(Vector3(x, rng.randf_range(120, 220), rng.randf_range(50, 80)))
		x += rng.randf_range(70, 130)
	x = 0.0
	while x < VIEW_W + 300:
		_near_trees.append(Vector3(x, rng.randf_range(230, 330), rng.randf_range(80, 120)))
		x += rng.randf_range(160, 240)
	for i in range(18):
		_fireflies.append(Vector2(rng.randf_range(0, VIEW_W), rng.randf_range(250, GROUND_Y - 20)))
	_build_level()
	restart()

func _build_level() -> void:
	_obstacles.clear()
	_fragments.clear()
	for def in LEVEL:
		var t: String = def["type"]
		var x: float = def["x"]
		match t:
			"branch":
				_obstacles.append({"type": t, "rect": Rect2(x, GROUND_Y - 46, 90, 46)})
			"hand_low":
				_obstacles.append({"type": t, "rect": Rect2(x, GROUND_Y - 86, 64, 86)})
			"hand_wall":
				_obstacles.append({"type": t, "rect": Rect2(x, GROUND_Y - 230, 70, 230)})
			"hand_pit":
				_obstacles.append({"type": t, "rect": Rect2(x, GROUND_Y - 60, 420, 60)})
			"hand_top":
				_obstacles.append({"type": t, "rect": Rect2(x, 0, def.get("w", 200.0), GROUND_Y - 72)})
			"frag_high", "frag_long":
				_fragments.append({"type": t, "rect": Rect2(x - 14, GROUND_Y - 44, 28, 28), "taken": false})

func restart() -> void:
	state = State.INTRO
	elapsed = 0.0
	scroll = 0.0
	player_x = PLAYER_HOME_X
	player_y = GROUND_Y
	vel_y = 0.0
	buff = ""
	ghost_x = GHOST_HOME_X
	_intro_t = 0.0
	_end_t = 0.0
	_caught_t = 0.0
	_on_ground = true
	_coyote_t = 0.0
	_jump_buffer_t = 0.0
	_long_jump_active = false
	_invuln_t = 0.0
	_hit_flash_t = 0.0
	_player_alpha = 1.0
	_ghost_fade = 0.0
	_house_x = VIEW_W + 40.0
	for f in _fragments:
		f["taken"] = false

func give_up() -> void:
	if state == State.DONE:
		return
	state = State.DONE
	finished.emit(false)

# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE, KEY_UP, KEY_W:
				_request_jump()
			KEY_R:
				if state == State.CAUGHT and allow_retry:
					restart()
			KEY_ESCAPE:
				give_up()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_request_jump()

func _request_jump() -> void:
	if state == State.RUNNING:
		_jump_buffer_t = JUMP_BUFFER_SEC

func _do_jump() -> void:
	_jump_buffer_t = 0.0
	_coyote_t = 0.0
	_on_ground = false
	match buff:
		"high":
			vel_y = HIGH_JUMP_VELOCITY
		"long":
			vel_y = LONG_JUMP_VELOCITY
			_long_jump_active = true
		_:
			vel_y = JUMP_VELOCITY
	buff = ""   # a memory fragment powers exactly one jump

# ---------------------------------------------------------------- update

func _process(delta: float) -> void:
	_time += delta
	match state:
		State.INTRO:
			_intro_t += delta
			if _intro_t >= INTRO_SEC:
				state = State.RUNNING
		State.RUNNING:
			_update_running(delta)
		State.ENDING:
			_update_ending(delta)
		State.CAUGHT:
			_caught_t += delta
			if not allow_retry and _caught_t >= 2.5:
				state = State.DONE
				finished.emit(false)
	queue_redraw()

func _update_running(delta: float) -> void:
	elapsed += delta
	var speed = SCROLL_SPEED * (LONG_JUMP_SPEED_MULT if _long_jump_active else 1.0)
	scroll += speed * delta

	# Jump timing helpers: coyote time + input buffer
	_coyote_t = COYOTE_SEC if _on_ground else max(0.0, _coyote_t - delta)
	_jump_buffer_t = max(0.0, _jump_buffer_t - delta)
	if _jump_buffer_t > 0.0 and _coyote_t > 0.0:
		_do_jump()

	_apply_gravity(delta)

	# Slowly regain distance from the ghost while running clean
	player_x = move_toward(player_x, PLAYER_HOME_X, RECOVER_SPEED * delta)
	ghost_x = move_toward(ghost_x, GHOST_HOME_X, GHOST_RECEDE_SPEED * delta)
	_invuln_t = max(0.0, _invuln_t - delta)
	_hit_flash_t = max(0.0, _hit_flash_t - delta)

	var player_rect = _player_rect()
	if _invuln_t <= 0.0:
		for o in _obstacles:
			var r: Rect2 = o["rect"]
			var screen_rect = Rect2(r.position.x - scroll, r.position.y, r.size.x, r.size.y).grow(-HITBOX_INSET)
			if screen_rect.intersects(player_rect):
				_on_hit()
				break
	for f in _fragments:
		if f["taken"]:
			continue
		var fr: Rect2 = f["rect"]
		if Rect2(fr.position.x - scroll, fr.position.y, fr.size.x, fr.size.y).intersects(player_rect):
			f["taken"] = true
			buff = "high" if f["type"] == "frag_high" else "long"

	if player_x - ghost_x < CATCH_DISTANCE:
		state = State.CAUGHT
		return
	if elapsed >= RUN_DURATION:
		state = State.ENDING
		buff = ""
		_end_t = 0.0

func _apply_gravity(delta: float) -> void:
	var g = LONG_JUMP_GRAVITY if _long_jump_active else GRAVITY
	vel_y += g * delta
	player_y += vel_y * delta
	if player_y >= GROUND_Y:
		player_y = GROUND_Y
		vel_y = 0.0
		_on_ground = true
		_long_jump_active = false
	else:
		_on_ground = false

func _on_hit() -> void:
	_invuln_t = INVULNERABLE_SEC
	_hit_flash_t = 0.25
	player_x -= HIT_PUSHBACK
	ghost_x += HIT_GHOST_ADVANCE

func _update_ending(delta: float) -> void:
	_end_t += delta
	_long_jump_active = false
	_apply_gravity(delta)
	# The forest slows to a stop while home slides into view
	scroll += SCROLL_SPEED * max(0.0, 1.0 - _end_t / 1.2) * delta
	_house_x = lerp(VIEW_W + 40.0, 620.0, min(_end_t / 1.2, 1.0))
	var door_x = _house_x + 95.0
	if _end_t > 1.2:
		player_x = move_toward(player_x, door_x, 260.0 * delta)
		if absf(player_x - door_x) < 2.0:
			_player_alpha = max(0.0, _player_alpha - delta * 2.0)   # steps inside
	ghost_x = move_toward(ghost_x, door_x - 75.0, 240.0 * delta)
	if _end_t > 2.4:
		_ghost_fade = clamp((_end_t - 2.4) / 1.4, 0.0, 1.0)   # collapses at the door
	if _end_t >= END_SEC:
		state = State.DONE
		finished.emit(true)

func _player_rect() -> Rect2:
	return Rect2(player_x - PLAYER_W / 2.0, player_y - PLAYER_H, PLAYER_W, PLAYER_H)

# ---------------------------------------------------------------- drawing

func _draw() -> void:
	_draw_sky()
	_draw_moon()
	_draw_trees(_far_trees, 0.2, Color(0.06, 0.12, 0.26), GROUND_Y + 10)
	_draw_trees(_near_trees, 0.5, Color(0.02, 0.05, 0.13), GROUND_Y + 20)
	_draw_fireflies()
	# Ground
	draw_rect(Rect2(0, GROUND_Y, VIEW_W, VIEW_H - GROUND_Y), Color(0.03, 0.07, 0.1))
	draw_line(Vector2(0, GROUND_Y), Vector2(VIEW_W, GROUND_Y), Color(0.25, 0.4, 0.6), 2.0)
	if state == State.ENDING or state == State.DONE:
		_draw_house()
	_draw_obstacles()
	_draw_fragments()
	_draw_ghost(Vector2(ghost_x, GROUND_Y - 62 + sin(_time * 3.0) * 6.0))
	_draw_player()
	_draw_overlays()
	_draw_hud()

func _draw_sky() -> void:
	var top = Color(0.01, 0.02, 0.08)
	var horizon = Color(0.07, 0.15, 0.36)
	var bands = 14
	for i in range(bands):
		var y0 = GROUND_Y * i / bands
		draw_rect(Rect2(0, y0, VIEW_W, GROUND_Y / bands + 1), top.lerp(horizon, float(i) / bands))
	for s in _stars:
		var a = 0.4 + 0.4 * sin(_time * 2.0 + s.z)
		draw_circle(Vector2(s.x, s.y), 1.3, Color(0.8, 0.9, 1.0, a))

func _moon_progress() -> float:
	if state == State.ENDING or state == State.DONE:
		return 1.0
	return clamp(elapsed / RUN_DURATION, 0.0, 1.0)

func _draw_moon() -> void:
	# The blue moon climbs during the run and reaches its peak at the very end
	var p = _moon_progress()
	var eased = 1.0 - pow(1.0 - p, 2.0)
	var pos = Vector2(lerp(140.0, VIEW_W * 0.5, eased), lerp(390.0, 90.0, eased))
	var radius = lerp(34.0, 48.0, p)
	var glow_strength = 1.0 + (2.0 if state == State.ENDING and _end_t > 2.6 else 0.0)
	for i in range(7):
		draw_circle(pos, radius + i * 14.0, Color(0.45, 0.65, 1.0, 0.045 * glow_strength))
	draw_circle(pos, radius, Color(0.62, 0.8, 1.0))
	draw_circle(pos + Vector2(-10, -8), radius * 0.25, Color(0.52, 0.7, 0.95))
	draw_circle(pos + Vector2(12, 10), radius * 0.15, Color(0.52, 0.7, 0.95))

func _draw_trees(trees: Array, factor: float, color: Color, base_y: float) -> void:
	var span = VIEW_W + 300.0
	for t in trees:
		var x = fposmod(t.x - scroll * factor, span) - 150.0
		_draw_pine(x, base_y, t.y, t.z, color)

func _draw_pine(x: float, base_y: float, h: float, w: float, color: Color) -> void:
	draw_rect(Rect2(x - 5, base_y - h * 0.25, 10, h * 0.25), color)
	for i in range(3):
		var tier_bottom = base_y - h * 0.2 - i * h * 0.22
		var tier_w = w * (1.0 - i * 0.25)
		draw_colored_polygon(PackedVector2Array([
			Vector2(x - tier_w / 2.0, tier_bottom),
			Vector2(x + tier_w / 2.0, tier_bottom),
			Vector2(x, tier_bottom - h * 0.4),
		]), color)

func _draw_fireflies() -> void:
	for i in range(_fireflies.size()):
		var f: Vector2 = _fireflies[i]
		var x = fposmod(f.x - scroll * 0.7 + sin(_time + i) * 10.0, VIEW_W + 40.0) - 20.0
		var y = f.y + sin(_time * 1.5 + i * 0.7) * 8.0
		var a = 0.35 + 0.35 * sin(_time * 3.0 + i)
		draw_circle(Vector2(x, y), 4.0, Color(0.5, 1.0, 0.8, a * 0.3))
		draw_circle(Vector2(x, y), 1.8, Color(0.7, 1.0, 0.85, a))

func _draw_obstacles() -> void:
	var hand_color = Color(0.78, 0.83, 0.96)
	for o in _obstacles:
		var r: Rect2 = o["rect"]
		var x = r.position.x - scroll
		if x > VIEW_W + 50.0 or x + r.size.x < -50.0:
			continue
		match o["type"]:
			"branch":
				_draw_branch(Rect2(x, r.position.y, r.size.x, r.size.y))
			"hand_low", "hand_pit":
				var count = max(1, int(r.size.x / 32.0))
				for i in range(count):
					var hx = x + 16.0 + i * (r.size.x - 32.0) / max(1, count - 1)
					var reach = r.size.y - 14.0 + sin(_time * 4.0 + i) * 4.0
					_draw_hand(Vector2(hx, GROUND_Y), reach, -1.0, hand_color)
			"hand_wall":
				for i in range(5):
					var hx2 = x + 14.0 + (i % 2) * 40.0
					var reach2 = r.size.y - 14.0 - i * 18.0 + sin(_time * 3.0 + i) * 5.0
					_draw_hand(Vector2(hx2, GROUND_Y), reach2, -1.0, hand_color.darkened(i * 0.06))
			"hand_top":
				var count3 = max(1, int(r.size.x / 40.0))
				for i in range(count3):
					var hx3 = x + 20.0 + i * (r.size.x - 40.0) / max(1, count3 - 1)
					var reach3 = r.size.y - 14.0 + sin(_time * 3.5 + i) * 6.0
					_draw_hand(Vector2(hx3, 0.0), reach3, 1.0, hand_color)

func _draw_hand(base: Vector2, length: float, dir: float, color: Color) -> void:
	# dir = -1: reaching up from the ground; +1: reaching down from the canopy
	var tip = base + Vector2(0, dir * length)
	draw_line(base, tip, color.darkened(0.25), 8.0)
	draw_circle(tip, 11.0, color)
	for i in range(4):
		var fx = -9.0 + i * 6.0
		draw_line(tip + Vector2(fx, 0), tip + Vector2(fx * 1.3, dir * 18.0), color, 4.0)
	draw_line(tip + Vector2(-9, dir * -2.0), tip + Vector2(-18, dir * 6.0), color, 4.0)   # thumb

func _draw_branch(r: Rect2) -> void:
	var bark = Color(0.24, 0.17, 0.13)
	draw_colored_polygon(PackedVector2Array([
		Vector2(r.position.x, r.end.y),
		Vector2(r.position.x + 8, r.position.y + 14),
		Vector2(r.position.x + r.size.x * 0.5, r.position.y + 6),
		Vector2(r.end.x - 6, r.position.y + 16),
		Vector2(r.end.x, r.end.y),
	]), bark)
	draw_line(Vector2(r.position.x + 30, r.position.y + 10), Vector2(r.position.x + 22, r.position.y - 6), bark, 3.0)
	draw_line(Vector2(r.position.x + 60, r.position.y + 12), Vector2(r.position.x + 70, r.position.y - 4), bark, 3.0)

func _draw_fragments() -> void:
	for f in _fragments:
		if f["taken"]:
			continue
		var r: Rect2 = f["rect"]
		var c = r.get_center() - Vector2(scroll, 0) + Vector2(0, sin(_time * 4.0) * 4.0)
		if c.x < -40.0 or c.x > VIEW_W + 40.0:
			continue
		var is_high = f["type"] == "frag_high"
		var color = Color(1.0, 0.85, 0.4) if is_high else Color(0.5, 0.9, 1.0)
		var s = 13.0 + sin(_time * 6.0) * 1.5
		draw_circle(c, s + 8.0, Color(color.r, color.g, color.b, 0.2))
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.7, 0), c + Vector2(0, s), c + Vector2(-s * 0.7, 0)]), color)
		var dark = Color(0.1, 0.1, 0.2)
		if is_high:   # up arrow
			draw_line(c + Vector2(0, 6), c + Vector2(0, -6), dark, 2.0)
			draw_line(c + Vector2(0, -6), c + Vector2(-4, -2), dark, 2.0)
			draw_line(c + Vector2(0, -6), c + Vector2(4, -2), dark, 2.0)
		else:         # right arrow
			draw_line(c + Vector2(-6, 0), c + Vector2(6, 0), dark, 2.0)
			draw_line(c + Vector2(6, 0), c + Vector2(2, -4), dark, 2.0)
			draw_line(c + Vector2(6, 0), c + Vector2(2, 4), dark, 2.0)

func _draw_ghost(pos: Vector2) -> void:
	var alpha = 1.0 - _ghost_fade
	if alpha <= 0.0:
		return
	var p = pos + Vector2(0, _ghost_fade * 30.0)   # sinks as it collapses
	var c = Color(0.72, 0.86, 1.0, 0.6 * alpha)
	for i in range(5):
		draw_circle(p + Vector2(-14 - i * 10, 8 + i * 2), 14.0 - i * 2.0, Color(c.r, c.g, c.b, c.a * 0.3 * (1.0 - i / 5.0)))
	draw_circle(p, 22.0, c)
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(-22, 0), p + Vector2(22, 0), p + Vector2(18, 40), p + Vector2(8, 32),
		p + Vector2(0, 42), p + Vector2(-8, 32), p + Vector2(-18, 40),
	]), c)
	draw_circle(p + Vector2(-7, -4), 3.5, Color(0.05, 0.08, 0.2, alpha))
	draw_circle(p + Vector2(7, -4), 3.5, Color(0.05, 0.08, 0.2, alpha))
	if _ghost_fade <= 0.0:   # reaching for you
		draw_line(p + Vector2(18, 8), p + Vector2(40, 2 + sin(_time * 6.0) * 4.0), c, 5.0)

func _draw_player() -> void:
	if _player_alpha <= 0.0:
		return
	if _invuln_t > 0.0 and int(_time * 12.0) % 2 == 0:
		return   # blink while invulnerable
	var a = _player_alpha
	var body = Color(0.95, 0.92, 0.84, a)
	var x = player_x
	var y = player_y
	var run_phase = sin(_time * 16.0) if _on_ground and state != State.INTRO else 0.4
	draw_line(Vector2(x - 4, y - 10), Vector2(x - 4 + run_phase * 7.0, y), body, 4.0)
	draw_line(Vector2(x + 4, y - 10), Vector2(x + 4 - run_phase * 7.0, y), body, 4.0)
	draw_rect(Rect2(x - 10, y - 34, 20, 26), body)
	draw_circle(Vector2(x, y - 40), 9.0, body)
	# scarf flowing behind
	draw_line(Vector2(x - 6, y - 32), Vector2(x - 22, y - 30 + sin(_time * 10.0) * 3.0), Color(0.35, 0.55, 1.0, a), 4.0)
	draw_circle(Vector2(x + 4, y - 41), 1.6, Color(0.1, 0.1, 0.2, a))

func _draw_house() -> void:
	var x = _house_x
	var wall = Color(0.16, 0.13, 0.2)
	var warm = Color(1.0, 0.8, 0.45)
	draw_rect(Rect2(x, GROUND_Y - 120, 150, 120), wall)
	draw_colored_polygon(PackedVector2Array([Vector2(x - 15, GROUND_Y - 120), Vector2(x + 165, GROUND_Y - 120), Vector2(x + 75, GROUND_Y - 190)]), wall.darkened(0.3))
	draw_rect(Rect2(x + 20, GROUND_Y - 95, 34, 28), warm)
	draw_circle(Vector2(x + 95, GROUND_Y - 30), 45.0, Color(1.0, 0.8, 0.45, 0.08))
	draw_rect(Rect2(x + 77, GROUND_Y - 62, 36, 62), warm)

func _draw_overlays() -> void:
	# Blue haze on the left when the ghost is close
	var gap = player_x - ghost_x
	var danger = clamp(1.0 - (gap - CATCH_DISTANCE) / 160.0, 0.0, 1.0)
	if state == State.RUNNING and danger > 0.0:
		for i in range(6):
			draw_rect(Rect2(i * 25.0, 0, 25, VIEW_H), Color(0.4, 0.6, 1.0, 0.18 * danger * (1.0 - i / 6.0)))
	if _hit_flash_t > 0.0:
		draw_rect(Rect2(0, 0, VIEW_W, VIEW_H), Color(0.6, 0.75, 1.0, _hit_flash_t))
	# Moon-peak flash at the end
	if state == State.ENDING or state == State.DONE:
		var flash = clamp(1.0 - absf(_end_t - 3.3) / 0.9, 0.0, 1.0)
		draw_rect(Rect2(0, 0, VIEW_W, VIEW_H), Color(0.7, 0.85, 1.0, 0.45 * flash))
	if state == State.CAUGHT:
		draw_rect(Rect2(0, 0, VIEW_W, VIEW_H), Color(0.02, 0.03, 0.1, 0.7))

func _draw_center_text(text: String, y: float, size: int, color: Color) -> void:
	draw_string(_font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, VIEW_W, size, color)

func _draw_hud() -> void:
	var white = Color(0.9, 0.95, 1.0)
	# Time bar (how long until home)
	draw_rect(Rect2(20, 16, VIEW_W - 40, 8), Color(1, 1, 1, 0.12))
	draw_rect(Rect2(20, 16, (VIEW_W - 40) * _moon_progress(), 8), Color(0.55, 0.75, 1.0))
	if buff != "":
		var txt = "Memory: HIGH JUMP" if buff == "high" else "Memory: LONG JUMP"
		var col = Color(1.0, 0.85, 0.4) if buff == "high" else Color(0.5, 0.9, 1.0)
		draw_string(_font, Vector2(20, 50), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col)
	match state:
		State.INTRO:
			_draw_center_text("A ghost of your past is right behind you...", 200, 26, white)
			_draw_center_text("RUN HOME", 245, 40, Color(0.6, 0.8, 1.0))
			_draw_center_text("Space / Click to jump", 285, 18, Color(white, 0.7))
		State.RUNNING:
			if elapsed < 4.0:
				_draw_center_text("Space / Click to jump  —  grab memory fragments for a stronger jump", 80, 16, Color(white, 0.6))
		State.CAUGHT:
			_draw_center_text("The past caught up with you.", 230, 30, white)
			if allow_retry:
				_draw_center_text("R: try again      Esc: give up", 275, 20, Color(white, 0.8))
		State.ENDING, State.DONE:
			if _end_t > 3.6:
				var a = clamp((_end_t - 3.6) / 0.8, 0.0, 1.0)
				_draw_center_text("You made it home. The ghost fades at your door.", 150, 24, Color(white, a))
				_draw_center_text("Memoria Moonflower blooms under the blue moon.", 190, 22, Color(0.6, 0.8, 1.0, a))
