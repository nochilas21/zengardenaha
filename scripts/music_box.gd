extends Control
class_name MusicBox

# A viewer/control panel onto GridWindow's shared music-wind state — not a
# standalone system of its own. Closing this window does NOT stop the drain;
# the state lives on the GridWindow and keeps ticking in the background.
# Reopen it anytime via GridWindow.open_music_box_ui().

var grid: GridWindow = null

@onready var meter: ProgressBar = $Panel/Meter
@onready var wind_button: Button = $Panel/WindButton
@onready var minimize_button: Button = $Panel/MinimizeButton
@onready var status_label: Label = $Panel/StatusLabel

func setup(grid_window: GridWindow) -> void:
    grid = grid_window
    grid.music_state_changed.connect(_on_music_state_changed)
    wind_button.pressed.connect(_on_wind_pressed)
    minimize_button.pressed.connect(_on_minimize_pressed)
    _on_music_state_changed(grid.music_current_wind, grid.music_max_wind, grid.is_music_playing())

func _on_wind_pressed() -> void:
    if grid != null:
        grid.wind_music(grid.music_wind_per_click)

func _on_minimize_pressed() -> void:
    queue_free()  # closes the viewer only — the grid keeps draining in the background

func _on_music_state_changed(current_wind: float, max_wind: float, is_playing: bool) -> void:
    meter.max_value = max_wind
    meter.value = current_wind
    if is_playing:
        status_label.text = "Playing — %.0f%%" % (current_wind / max_wind * 100.0)
        meter.modulate = Color(1, 1, 1).lerp(Color(1, 0.3, 0.3), 1.0 - (current_wind / max_wind))
    else:
        status_label.text = "Stopped — wind it up"
        meter.modulate = Color(0.6, 0.6, 0.6)
