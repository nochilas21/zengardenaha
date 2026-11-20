extends RefCounted
class_name HarvestCursor

# Turns the mouse cursor into a hand while it is over a plant that can be
# harvested (open hand), and a grabbing hand while harvesting (closed hand).
# Only the plot that set the cursor can clear it, so moving quickly from one
# plot to another doesn't flicker back to the arrow.

const OPEN = preload("res://graphics/ui/cursor_hand_open.png")
const CLOSED = preload("res://graphics/ui/cursor_hand_closed.png")
const HOTSPOT: Vector2 = Vector2(20, 14)   # roughly the middle of the fingers

static var _state: String = ""
static var _owner_id: int = 0

# state: "open", "closed" or "" (normal arrow)
static func set_state(owner: Object, state: String) -> void:
	var id = owner.get_instance_id()
	if state == "" and id != _owner_id:
		return   # someone else owns the cursor now
	if state == _state and id == _owner_id:
		return
	_state = state
	_owner_id = id if state != "" else 0
	match state:
		"open":
			_apply(OPEN)
		"closed":
			_apply(CLOSED)
		_:
			_apply(null)

static func _apply(texture: Texture2D) -> void:
	# Arrow and pointing-hand both, so it also shows over buttons/popups
	Input.set_custom_mouse_cursor(texture, Input.CURSOR_ARROW, HOTSPOT if texture != null else Vector2.ZERO)
	Input.set_custom_mouse_cursor(texture, Input.CURSOR_POINTING_HAND, HOTSPOT if texture != null else Vector2.ZERO)
