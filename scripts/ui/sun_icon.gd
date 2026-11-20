extends Control
class_name SunIcon

# A cute little sun drawn in code (placeholder until there is sun art).
# Shows "xN" when charges > 0 (used as the badge on a shelf).

var charges: int = 0:
	set(value):
		charges = value
		queue_redraw()
var show_face: bool = true
var _t: float = 0.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(32, 32)

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var c = size / 2.0
	var r = min(size.x, size.y) * 0.28
	var core = Color(1.0, 0.82, 0.25)
	var ray = Color(1.0, 0.68, 0.2)
	draw_circle(c, r * 1.9, Color(1.0, 0.85, 0.3, 0.18))   # glow
	for i in range(8):
		var a = _t * 0.6 + i * TAU / 8.0
		var inner = c + Vector2.from_angle(a) * (r * 1.2)
		var outer = c + Vector2.from_angle(a) * (r * 1.75)
		draw_line(inner, outer, ray, max(2.0, r * 0.28))
	draw_circle(c, r, core)
	if show_face and r >= 6.0:
		var eye = Color(0.45, 0.25, 0.05)
		draw_circle(c + Vector2(-r * 0.35, -r * 0.1), r * 0.11, eye)
		draw_circle(c + Vector2(r * 0.35, -r * 0.1), r * 0.11, eye)
		draw_arc(c + Vector2(0, r * 0.1), r * 0.35, 0.2, PI - 0.2, 10, eye, max(1.0, r * 0.1))
		draw_circle(c + Vector2(-r * 0.6, r * 0.25), r * 0.13, Color(1.0, 0.55, 0.45, 0.6))   # blush
		draw_circle(c + Vector2(r * 0.6, r * 0.25), r * 0.13, Color(1.0, 0.55, 0.45, 0.6))
	if charges > 0:
		var font = ThemeDB.fallback_font
		draw_string(font, Vector2(size.x * 0.55, size.y), "x%d" % charges, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1))
