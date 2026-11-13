extends Control
class_name Plot

signal need_became_due(need_id: String)
signal need_satisfied(need_id: String)
signal wilted(need_id: String)
signal unwilted()
signal matured()

@onready var plant_sprite: TextureRect = $PlantSprite
@onready var need_popup_container: HBoxContainer = $NeedPopupContainer
@onready var place_pot_button: Button = $PlacePotButton

var plant_data: PlantData = null
var pot_id: String = ""
var growth_progress: float = 0.0
var required_growth: float = 0.0
var growth_stage: int = 0
var is_wilted_visual: bool = false
var wilt_incident_count: int = 0
var is_permanently_unhealthy: bool = false

var thresholds: Dictionary = {}
var next_threshold_index: Dictionary = {}
var due_since: Dictionary = {}
var wilted_needs: Dictionary = {}
var active_popups: Dictionary = {}   # need_id -> NeedPopup instance

func _ready() -> void:
    place_pot_button.pressed.connect(_on_place_pot_pressed)
    place_pot_button.visible = (pot_id == "")

func can_plant(data: PlantData, grid_tag: String = "") -> bool:
    if grid_tag != "" and grid_tag == data.required_pot_id:
        return true
    return pot_id != "" and pot_id == data.required_pot_id

func place_pot(new_pot: PotData) -> bool:
    if plant_data != null:
        return false
    pot_id = new_pot.pot_id
    place_pot_button.visible = false
    return true

func _on_place_pot_pressed() -> void:
    # Debug stand-in for the real shop click-to-select flow (Phase 8 wires the real shop)
    var dirt: PotData = load("res://resources/pots/dirt_pot.tres")
    place_pot(dirt)

func plant(data: PlantData) -> bool:
    if not can_plant(data):
        return false
    plant_data = data
    growth_progress = 0.0
    required_growth = data.growth_time_sec
    growth_stage = 0
    is_wilted_visual = false
    wilt_incident_count = 0
    is_permanently_unhealthy = false
    thresholds.clear()
    next_threshold_index.clear()
    due_since.clear()
    wilted_needs.clear()
    for need in data.needs:
        thresholds[need.need_id] = _generate_thresholds(need.needed_count, need.randomization_pct)
        next_threshold_index[need.need_id] = 0
        due_since[need.need_id] = 0.0
        wilted_needs[need.need_id] = false
    _update_growth_stage()
    return true

func _generate_thresholds(count: int, jitter: float) -> Array[float]:
    var result: Array[float] = []
    var segment = 1.0 / (count + 1)
    for i in range(1, count + 1):
        var base = segment * i
        var jittered = base + randf_range(-jitter, jitter) * segment
        result.append(clamp(jittered, 0.02, 0.98))
    result.sort()
    return result

func satisfy_need(need_id: String) -> void:
    var was_wilted = wilted_needs.get(need_id, false)
    due_since[need_id] = 0.0
    wilted_needs[need_id] = false
    next_threshold_index[need_id] = next_threshold_index.get(need_id, 0) + 1
    need_satisfied.emit(need_id)
    _refresh_wilted_visual_flag()
    if was_wilted and not is_wilted_visual:
        unwilted.emit()
    _hide_need_popup_if_matching(need_id)

func _find_need(need_id: String) -> NeedData:
    for need in plant_data.needs:
        if need.need_id == need_id:
            return need
    return null

func _process(delta: float) -> void:
    if plant_data == null or growth_progress >= required_growth:
        return

    var now = Time.get_unix_time_from_system()
    var effective_rate = 1.0
    var any_wilted = false
    var progress_pct = growth_progress / required_growth

    for need in plant_data.needs:
        var idx = next_threshold_index[need.need_id]
        if idx >= need.needed_count:
            continue

        var threshold = thresholds[need.need_id][idx]
        if progress_pct >= threshold and due_since[need.need_id] == 0.0:
            due_since[need.need_id] = now
            _show_need_popup(need)
            need_became_due.emit(need.need_id)

        if due_since[need.need_id] > 0.0:
            var elapsed = now - due_since[need.need_id]
            if elapsed < need.grace_sec:
                effective_rate = min(effective_rate, need.slow_multiplier)
            else:
                any_wilted = true
                if not wilted_needs[need.need_id]:
                    wilted_needs[need.need_id] = true
                    required_growth += need.wilt_penalty_sec
                    wilt_incident_count += 1
                    if wilt_incident_count >= 2:
                        is_permanently_unhealthy = true
                    wilted.emit(need.need_id)

    if any_wilted:
        effective_rate = 0.0

    var was_wilted_visual = is_wilted_visual
    _refresh_wilted_visual_flag()
    if was_wilted_visual and not is_wilted_visual:
        unwilted.emit()

    growth_progress += delta * effective_rate
    _update_growth_stage()

    if growth_progress >= required_growth:
        matured.emit()

func _refresh_wilted_visual_flag() -> void:
    is_wilted_visual = false
    for w in wilted_needs.values():
        if w:
            is_wilted_visual = true
            break

func _update_growth_stage() -> void:
    var stage_count = plant_data.stage_textures.size()
    var pct = clamp(growth_progress / required_growth, 0.0, 1.0)
    var target_stage = clamp(int(pct * stage_count), 0, stage_count - 1)
    growth_stage = target_stage

    if is_wilted_visual:
        if plant_data.wilted_stage_textures.size() > growth_stage:
            plant_sprite.texture = plant_data.wilted_stage_textures[growth_stage]
    elif is_permanently_unhealthy and growth_stage >= 1 and plant_data.unhealthy_stage_textures.size() > growth_stage:
        plant_sprite.texture = plant_data.unhealthy_stage_textures[growth_stage]
    elif plant_data.stage_textures.size() > growth_stage:
        plant_sprite.texture = plant_data.stage_textures[growth_stage]

func harvest() -> int:
    var value = plant_data.sell_value
    if is_permanently_unhealthy:
        value = int(value * 0.7)  # placeholder penalty, tune later
    elif plant_data.lucky_variant_mature_textures.size() > 0 and randf() < plant_data.lucky_variant_chance:
        value = int(value * plant_data.lucky_variant_sell_bonus)
    plant_data = null
    growth_progress = 0.0
    required_growth = 0.0
    plant_sprite.texture = null
    return value

func _show_need_popup(need: NeedData) -> void:
    if need.need_id in active_popups:
        return
    var popup: NeedPopup = preload("res://scenes/ui/need_popup.tscn").instantiate()
    need_popup_container.add_child(popup)   # add to tree first so @onready vars resolve
    popup.setup(need.need_id, need.icon)
    popup.pressed.connect(_on_need_popup_pressed)
    active_popups[need.need_id] = popup

func _hide_need_popup_if_matching(need_id: String) -> void:
    if need_id in active_popups:
        active_popups[need_id].queue_free()
        active_popups.erase(need_id)

func is_need_due(need_id: String) -> bool:
    return due_since.get(need_id, 0.0) > 0.0

func _find_grid_window() -> GridWindow:
    var node = get_parent()
    while node != null:
        if node is GridWindow:
            return node
        node = node.get_parent()
    return null

func _on_need_popup_pressed(need_id: String) -> void:
    match need_id:
        "water":
            satisfy_need("water")
        "fertilizer":
            if EconomyManager.use_fertilizer():
                satisfy_need("fertilizer")
        "insects":
            _launch_insect_minigame()
        "music":
            # Music is a shared grid-level background process (see grid_window.gd),
            # not a per-plant minigame — clicking just opens/reopens the shared
            # viewer. If the box is already playing, this need will already have
            # auto-resolved via GridWindow, so clicking here is mainly for the
            # case where it's not playing yet and needs winding up.
            var grid = _find_grid_window()
            if grid != null:
                grid.open_music_box_ui()
        # "sunlight" is still handled externally (grid-wide mini-sun), since it
        # auto-resolves on its own rather than being a popup-click minigame

func _launch_insect_minigame() -> void:
    var minigame = preload("res://scenes/ui/insect_minigame.tscn").instantiate()
    get_tree().root.add_child(minigame)
    minigame.bug_caught.connect(func(): satisfy_need("insects"))

func to_dict() -> Dictionary:
    if plant_data == null:
        return {"pot_id": pot_id, "plant_id": "", "growth_progress": 0.0}
    return {
        "pot_id": pot_id,
        "plant_id": plant_data.id,
        "growth_progress": growth_progress,
        "required_growth": required_growth,
        "wilt_incident_count": wilt_incident_count,
        "is_permanently_unhealthy": is_permanently_unhealthy,
        "thresholds": thresholds,
        "next_threshold_index": next_threshold_index,
        "due_since": due_since,
        "wilted_needs": wilted_needs,
    }

func from_dict(data: Dictionary, plant_lookup: Dictionary) -> void:
    pot_id = data.get("pot_id", "")
    place_pot_button.visible = (pot_id == "")
    var plant_id = data.get("plant_id", "")
    if plant_id == "":
        return
    plant_data = plant_lookup.get(plant_id)
    if plant_data == null:
        return
    growth_progress = data.get("growth_progress", 0.0)
    required_growth = data.get("required_growth", plant_data.growth_time_sec)
    wilt_incident_count = data.get("wilt_incident_count", 0)
    is_permanently_unhealthy = data.get("is_permanently_unhealthy", false)
    thresholds = data.get("thresholds", {})
    next_threshold_index = data.get("next_threshold_index", {})
    due_since = data.get("due_since", {})
    wilted_needs = data.get("wilted_needs", {})
    _update_growth_stage()
