extends Window
class_name DesktopBug

# Mode 1 (normal plants): one bug = one tiny transparent, borderless,
# always-on-top OS window. The total number alive at once is capped by
# MAX_DESKTOP_BUGS across ALL plots; extra bugs wait in their swarm's queue.
# Requires Project Settings → Display → Window → Subwindows → Embed Subwindows = Off.

signal caught()

const BUG_SIZE: int = 48
const MAX_DESKTOP_BUGS: int = 10   # placeholder, tune by playtesting

static var active_count: int = 0

var _motion: BugMotion

# Call BEFORE add_child: window flags should be set before the OS window is created.
func setup(texture: Texture2D, bug_speed: float, start_pos: Vector2i, screen_rect: Rect2i) -> void:
	borderless = true
	transparent = true
	transparent_bg = true
	always_on_top = true
	unresizable = true
	content_scale_factor = UiScale.factor
	size = UiScale.size_for(Vector2(BUG_SIZE, BUG_SIZE))
	_motion = BugMotion.new(Vector2(start_pos), bug_speed, screen_rect, Vector2(size))
	position = Vector2i(_motion.pos)

	var button = TextureButton.new()
	button.texture_normal = texture
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.pressed.connect(_on_pressed)
	add_child(button)

func _enter_tree() -> void:
	active_count += 1

func _exit_tree() -> void:
	active_count -= 1

func _process(delta: float) -> void:
	position = Vector2i(_motion.step(delta))

func _on_pressed() -> void:
	caught.emit()
	queue_free()
