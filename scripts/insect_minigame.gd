extends Control

signal bug_caught()

@onready var bug_button: TextureButton = $BugButton

func _ready() -> void:
    var margin = 40
    var parent_size = get_viewport_rect().size
    bug_button.position = Vector2(
        randf_range(margin, parent_size.x - margin),
        randf_range(margin, parent_size.y - margin)
    )
    bug_button.pressed.connect(_on_bug_pressed)

func _on_bug_pressed() -> void:
    bug_caught.emit()
    queue_free()
