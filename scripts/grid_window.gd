extends Control
class_name GridWindow

signal sunlight_charges_changed(remaining: int)
signal music_state_changed(current_wind: float, max_wind: float, is_playing: bool)

@onready var plot_container: HBoxContainer = $PlotContainer

var sunlight_charges_remaining: int = 0

# Music is a shared, grid-level background process (same shape as sunlight's
# charges) rather than a per-plant minigame: the wind level lives here and
# keeps draining whether or not any viewer window is open. Any plot's music
# need auto-resolves the instant it's due, as long as wind > 0.
var music_current_wind: float = 0.0
var music_max_wind: float = 100.0
var music_drain_per_sec: float = 4.0       # ~25s to fully drain from max if left alone
var music_wind_per_click: float = 30.0     # each "Wind Up" click adds this much
var music_box_window: Control = null       # the currently-open viewer, or null if closed

func _ready() -> void:
    for plot in get_plots():
        plot.need_became_due.connect(_on_any_plot_need_due.bind(plot))

func _process(delta: float) -> void:
    if music_current_wind > 0.0:
        music_current_wind = max(0.0, music_current_wind - music_drain_per_sec * delta)
        music_state_changed.emit(music_current_wind, music_max_wind, is_music_playing())

func get_plots() -> Array[Plot]:
    var result: Array[Plot] = []
    for child in plot_container.get_children():
        if child is Plot:
            result.append(child)
    return result

func apply_mini_sun(charges: int = 3) -> void:
    sunlight_charges_remaining = charges
    sunlight_charges_changed.emit(sunlight_charges_remaining)
    _satisfy_all_due_sunlight_needs()

func _satisfy_all_due_sunlight_needs() -> void:
    # Same retroactive-catch pattern as music: a need that was already due
    # before charges were applied already fired its need_became_due signal
    # once and won't fire again, so the live _on_any_plot_need_due hook alone
    # would never resolve it. Catch it here the moment charges become available.
    for plot in get_plots():
        if sunlight_charges_remaining <= 0:
            break
        if plot.plant_data != null and plot.is_need_due("sunlight"):
            plot.satisfy_need("sunlight")
            sunlight_charges_remaining -= 1
            sunlight_charges_changed.emit(sunlight_charges_remaining)

func is_music_playing() -> bool:
    return music_current_wind > 0.0

func wind_music(amount: float) -> void:
    var was_playing = is_music_playing()
    music_current_wind = min(music_max_wind, music_current_wind + amount)
    music_state_changed.emit(music_current_wind, music_max_wind, is_music_playing())
    if not was_playing and is_music_playing():
        _satisfy_all_due_music_needs()

func _satisfy_all_due_music_needs() -> void:
    # Catches any plot whose music need was already due before playback
    # started — not just needs that become due afterward (those are caught
    # live by _on_any_plot_need_due below).
    for plot in get_plots():
        if plot.plant_data != null and plot.is_need_due("music"):
            plot.satisfy_need("music")

func open_music_box_ui() -> void:
    if music_box_window != null and is_instance_valid(music_box_window):
        return  # already open — nothing to do, it's already showing live state
    music_box_window = preload("res://scenes/ui/music_box.tscn").instantiate()
    get_tree().root.add_child(music_box_window)
    music_box_window.setup(self)
    music_box_window.tree_exiting.connect(func(): music_box_window = null)

func _on_any_plot_need_due(need_id: String, plot: Plot) -> void:
    if need_id == "sunlight" and sunlight_charges_remaining > 0:
        plot.satisfy_need("sunlight")
        sunlight_charges_remaining -= 1
        sunlight_charges_changed.emit(sunlight_charges_remaining)
    elif need_id == "music" and is_music_playing():
        plot.satisfy_need("music")

func to_dict() -> Dictionary:
    var plots_data = []
    for plot in get_plots():
        plots_data.append(plot.to_dict())
    return {
        "screen_pos": [position.x, position.y],
        "plots": plots_data,
        "music_current_wind": music_current_wind,
    }

func from_dict(data: Dictionary, plant_lookup: Dictionary) -> void:
    var pos = data.get("screen_pos", [0, 0])
    position = Vector2(pos[0], pos[1])
    music_current_wind = data.get("music_current_wind", 0.0)
    var plots = get_plots()
    var plots_data = data.get("plots", [])
    for i in range(min(plots.size(), plots_data.size())):
        plots[i].from_dict(plots_data[i], plant_lookup)
