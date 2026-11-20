extends Window
class_name DragGhost

# A small floating window that follows the mouse across the desktop, used to
# drag things between windows (a pot from the Inventory onto a shelf, the sun
# from the menu onto a shelf). Godot's built-in drag & drop doesn't work
# across separate OS windows, so this does it by screen position instead.
#
#   DragGhost.start(parent, content_control, on_drop, on_hover)
#     on_drop(screen_pos: Vector2i)  — called once when the item is dropped
#     on_hover(screen_pos: Vector2i) — called every frame while dragging (optional)
#     on_cancel()                     — optional, Esc / right click
#
# Press-and-drag: drops when the mouse button is released.
# Quick click (no drag): the item sticks to the cursor; click again to drop it.

const STICKY_MOVE_PX: float = 6.0

var _on_drop: Callable
var _on_hover: Callable
var _on_cancel: Callable
var _start_mouse: Vector2i
var _sticky: bool = false
var _was_pressed: bool = true
var _done: bool = false

static func start(parent: Node, content: Control, on_drop: Callable, on_hover: Callable = Callable(), on_cancel: Callable = Callable()) -> DragGhost:
	var ghost = DragGhost.new()
	ghost._on_drop = on_drop
	ghost._on_hover = on_hover
	ghost._on_cancel = on_cancel
	var design = Vector2(max(16.0, content.custom_minimum_size.x), max(16.0, content.custom_minimum_size.y))
	ghost.content_scale_factor = UiScale.factor
	ghost.size = UiScale.size_for(design)
	content.size = design
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.add_child(content)
	parent.add_child(ghost)
	return ghost

func _init() -> void:
	borderless = true
	transparent = true
	transparent_bg = true
	always_on_top = true
	unresizable = true
	unfocusable = true
	mouse_passthrough = true   # clicks go to the window underneath
	_start_mouse = DisplayServer.mouse_get_position()
	position = _start_mouse - Vector2i(16, 16)

func _process(_delta: float) -> void:
	if _done:
		return
	var mouse = DisplayServer.mouse_get_position()
	position = mouse - size / 2
	if _on_hover.is_valid():
		_on_hover.call(mouse)
	if Input.is_key_pressed(KEY_ESCAPE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_finish(false, mouse)
		return
	var pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if not _sticky:
		if not pressed:
			if Vector2(mouse - _start_mouse).length() < STICKY_MOVE_PX:
				_sticky = true   # it was just a click: follow the cursor until the next click
				_was_pressed = false
			else:
				_finish(true, mouse)
	else:
		if pressed and not _was_pressed:
			_finish(true, mouse)
		_was_pressed = pressed

func _finish(drop: bool, mouse: Vector2i) -> void:
	_done = true
	if _on_hover.is_valid():
		_on_hover.call(Vector2i(-100000, -100000))   # clear any highlight
	if drop and _on_drop.is_valid():
		_on_drop.call(mouse)
	elif not drop and _on_cancel.is_valid():
		_on_cancel.call()
	queue_free()
