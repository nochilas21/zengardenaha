extends Control
class_name NeedPopup

signal pressed(need_id: String)

var need_id: String = ""

@onready var icon: TextureRect = $Icon
@onready var button: Button = $Button
@onready var animation_player: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
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
