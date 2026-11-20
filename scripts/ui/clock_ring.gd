extends Control
class_name ClockRing

# Small clock-style progress ring: a dark disc and a light-green arc that fills
# clockwise from 12 o'clock (no clock hand).
# Set `progress` (0..1). Used on the music need popup and in the music box list.

var progress: float = 0.0:
	set(value):
		progress = clamp(value, 0.0, 1.0)
		queue_redraw()

var ring_color: Color = Color(0.55, 0.95, 0.55)   # light green
var draw_background: bool = true

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(22, 22)

func _draw() -> void:
	var center = size / 2.0
	var radius = min(size.x, size.y) / 2.0 - 2.0
	if radius <= 0.0:
		return
	if draw_background:
		draw_circle(center, radius, Color(0, 0, 0, 0.45))
	draw_arc(center, radius, 0.0, TAU, 32, Color(1, 1, 1, 0.15), 2.0)
	if progress > 0.0:
		draw_arc(center, radius, -PI / 2.0, -PI / 2.0 + TAU * progress, 32, ring_color, 3.0)
