extends Control
class_name NeedPopup

signal pressed(need_id: String)

var need_id: String = ""

@onready var icon: TextureRect = $Icon
@onready var button: Button = $Button
@onready var animation_player: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	# Bounce from the center so the popup doesn't grow past the slot edge
	pivot_offset = custom_minimum_size / 2.0
	button.pressed.connect(func(): pressed.emit(need_id))
	animation_player.play("bounce")

func setup(id: String, texture: Texture2D) -> void:
	need_id = id
	icon.texture = texture

# Greyed-out + unclickable when disabled (used by the special-event popup cooldown)
func set_enabled(value: bool) -> void:
	button.disabled = not value
	modulate = Color(1, 1, 1) if value else Color(0.45, 0.45, 0.45)
	if value:
		animation_player.play("bounce")
	else:
		animation_player.pause()

# Clock-style progress ring drawn over the icon (e.g. seconds of music heard).
# progress < 0 hides it.
var _ring: ClockRing = null

func set_progress(progress: float) -> void:
	if progress < 0.0:
		if _ring != null:
			_ring.visible = false
		return
	if _ring == null:
		_ring = ClockRing.new()
		_ring.draw_background = false
		_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_ring)   # added last → drawn on top of the icon
	_ring.visible = true
	_ring.progress = progress
