extends Node
class_name InsectSwarm

# All bugs for ONE plot's insects need. Picks the mode from the NeedData:
#   use_overlay = false → individual DesktopBug windows, limited by the global cap
#   use_overlay = true  → one BugOverlay window holding every bug (troll plants)
# Emits all_caught once every bug has been clicked, then frees itself.

signal all_caught()

var remaining: int = 0   # bugs not caught yet (on screen + still queued)
var pending: int = 0     # bugs queued because the global DesktopBug cap is full

var _texture: Texture2D
var _speed: float
var _origin: Vector2i
var _rect: Rect2i

# Call AFTER this node has been added to the tree.
# origin = screen position (pixels) the bugs start from, i.e. the plant.
func start(need: NeedData, origin: Vector2i) -> void:
	_texture = need.icon
	_speed = need.bug_speed
	_origin = origin
	_rect = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	remaining = max(need.bug_count, 1)

	if need.use_overlay:
		var overlay = BugOverlay.new()
		overlay.setup(remaining, _texture, _speed, _origin, _rect)
		overlay.bug_caught.connect(_on_bug_caught)
		add_child(overlay)
	else:
		pending = remaining
		_spawn_pending()

func _process(_delta: float) -> void:
	if pending > 0:
		_spawn_pending()   # a slot may have freed up since last frame

func _spawn_pending() -> void:
	while pending > 0 and DesktopBug.active_count < DesktopBug.MAX_DESKTOP_BUGS:
		var bug = DesktopBug.new()
		var jitter = Vector2i(randi_range(-20, 20), randi_range(-20, 20))
		bug.setup(_texture, _speed, _origin + jitter, _rect)
		bug.caught.connect(_on_bug_caught)
		add_child(bug)   # _enter_tree bumps DesktopBug.active_count immediately
		pending -= 1

func _on_bug_caught() -> void:
	remaining -= 1
	if remaining <= 0:
		all_caught.emit()
		queue_free()
