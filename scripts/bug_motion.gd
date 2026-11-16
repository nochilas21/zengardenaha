extends RefCounted
class_name BugMotion

# Shared wandering movement for one bug. Used by both DesktopBug (one OS
# window per bug) and BugOverlay (many bugs inside one overlay window).

var pos: Vector2
var velocity: Vector2 = Vector2.ZERO
var speed: float
var _min: Vector2
var _max: Vector2
var _turn_timer: float = 0.0

# area = the rectangle the bug may move in; body_size = the bug's own size.
func _init(start_pos: Vector2, move_speed: float, area: Rect2i, body_size: Vector2) -> void:
	speed = move_speed
	_min = Vector2(area.position)
	_max = Vector2(area.end) - body_size
	pos = start_pos.clamp(_min, _max)
	_pick_new_direction()

func step(delta: float) -> Vector2:
	_turn_timer -= delta
	if _turn_timer <= 0.0:
		_pick_new_direction()
	pos += velocity * delta
	if pos.x < _min.x or pos.x > _max.x:
		velocity.x = -velocity.x
		pos.x = clamp(pos.x, _min.x, _max.x)
	if pos.y < _min.y or pos.y > _max.y:
		velocity.y = -velocity.y
		pos.y = clamp(pos.y, _min.y, _max.y)
	return pos

func _pick_new_direction() -> void:
	velocity = Vector2.from_angle(randf() * TAU) * speed
	_turn_timer = randf_range(0.8, 2.0)
