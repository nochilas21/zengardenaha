extends Control
class_name Plot

signal need_became_due(need_id: String)
signal need_satisfied(need_id: String)
signal wilted(need_id: String)
signal unwilted()
signal matured()
signal clicked(plot: Plot)   # player clicked this slot (used to select it for the shop)
signal special_event_changed()   # event appeared / won / lost / forfeited (hook for autosave)

@onready var plant_sprite: TextureRect = $PlantSprite
@onready var need_popup_container: HBoxContainer = $NeedPopupContainer
@onready var place_pot_button: Button = $PlacePotButton

const EVENT_ICON = preload("res://graphics/ui/event_icon.png")
const EVENT_POPUP_ID: String = "event"

# Special event (e.g. Memoria Moonflower's jump-and-run). Only plants whose
# PlantData.special_event_id is set have one.
#   NONE      → normal needs still running; plant can't mature yet
#   PENDING   → all other needs done, "(!)" popup shown; plant can't mature yet
#   WON       → plant may mature; on maturity it rolls special_form_chance
#   FORFEITED → lost max times; plant matures normally, never special
enum EventState { NONE, PENDING, WON, FORFEITED }

const POT_COLORS: Dictionary = {
	"dirt": Color(0.45, 0.28, 0.15),
	"water": Color(0.25, 0.55, 0.85),
	"cloud": Color(0.85, 0.9, 1.0),
}

var plant_data: PlantData = null
var pot_id: String = ""
var growth_progress: float = 0.0
var required_growth: float = 0.0
var growth_stage: int = 0
var is_wilted_visual: bool = false
var wilt_incident_count: int = 0
var is_permanently_unhealthy: bool = false
var is_selected: bool = false

var thresholds: Dictionary = {}
var next_threshold_index: Dictionary = {}
var due_since: Dictionary = {}
var wilted_needs: Dictionary = {}
var active_popups: Dictionary = {}   # need_id -> NeedPopup instance
var music_play_progress: float = 0.0   # seconds of continuous music heard for the current music need
var active_swarm: InsectSwarm = null   # bugs currently running on the desktop for this plot

var event_state: EventState = EventState.NONE
var event_losses: int = 0
var event_cooldown_until: float = 0.0   # unix time; popup greyed out until then
var is_special_form: bool = false
var special_form_rolled: bool = false
var _active_event: Node = null          # the running minigame, if any

func _ready() -> void:
	place_pot_button.pressed.connect(_on_place_pot_pressed)
	place_pot_button.visible = (pot_id == "")
	place_pot_button.text = "Empty"
	# Popups stack from the right edge so they stay inside the slot
	need_popup_container.alignment = BoxContainer.ALIGNMENT_END
	need_popup_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

# ---------------------------------------------------------------- selection / drawing

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)

func _on_place_pot_pressed() -> void:
	# The empty-slot button now just selects the slot; the shop places the pot.
	clicked.emit(self)

func set_selected(value: bool) -> void:
	is_selected = value
	place_pot_button.text = "Selected" if is_selected else "Empty"
	queue_redraw()

func _draw() -> void:
	# Slot background so every slot position is visible on the shelf
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.25))
	# Placeholder pot: a colored strip at the bottom (until real pot art exists)
	if pot_id != "":
		draw_rect(Rect2(0, size.y - 14, size.x, 14), POT_COLORS.get(pot_id, Color(0.5, 0.5, 0.5)))
	if is_selected:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.85, 0.2), false, 3.0)

# ---------------------------------------------------------------- pot / plant

func can_plant(data: PlantData, grid_tag: String = "") -> bool:
	if grid_tag != "" and grid_tag == data.required_pot_id:
		return true
	return pot_id != "" and pot_id == data.required_pot_id

func place_pot(new_pot: PotData) -> bool:
	if plant_data != null or pot_id != "":
		return false   # slot already has a pot (or a plant)
	pot_id = new_pot.pot_id
	place_pot_button.visible = false
	queue_redraw()
	return true

func plant(data: PlantData) -> bool:
	if plant_data != null:
		return false   # never plant over a growing plant
	if not can_plant(data):
		return false
	_reset_plant_state()
	plant_data = data
	required_growth = data.growth_time_sec
	for need in data.needs:
		thresholds[need.need_id] = _generate_thresholds(need.needed_count, need.randomization_pct)
		next_threshold_index[need.need_id] = 0
		due_since[need.need_id] = 0.0
		wilted_needs[need.need_id] = false
	_update_growth_stage()
	return true

func _reset_plant_state() -> void:
	growth_progress = 0.0
	required_growth = 0.0
	growth_stage = 0
	is_wilted_visual = false
	wilt_incident_count = 0
	is_permanently_unhealthy = false
	thresholds.clear()
	next_threshold_index.clear()
	due_since.clear()
	wilted_needs.clear()
	music_play_progress = 0.0
	_clear_swarm()
	for need_id in active_popups.keys():
		_hide_need_popup_if_matching(need_id)
	event_state = EventState.NONE
	event_losses = 0
	event_cooldown_until = 0.0
	is_special_form = false
	special_form_rolled = false
	_close_active_event()
	plant_sprite.modulate = Color(1, 1, 1)

func _generate_thresholds(count: int, jitter: float) -> Array[float]:
	var result: Array[float] = []
	var segment = 1.0 / (count + 1)
	for i in range(1, count + 1):
		var base = segment * i
		var jittered = base + randf_range(-jitter, jitter) * segment
		result.append(clamp(jittered, 0.02, 0.98))
	result.sort()
	return result

# ---------------------------------------------------------------- needs

func satisfy_need(need_id: String) -> void:
	if not is_need_due(need_id):
		return   # not due (e.g. a second click / second minigame) — don't skip a threshold
	var was_wilted = wilted_needs.get(need_id, false)
	due_since[need_id] = 0.0
	if need_id == "music":
		music_play_progress = 0.0
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

	_update_event_cooldown()
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

		if need.need_id == "music" and due_since[need.need_id] > 0.0:
			if _tick_music_need(need, delta):
				continue   # just satisfied — skip grace/wilt checks for this need

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

	if _event_blocks_maturity():
		# Hold just below maturity until the special event is won or forfeited
		growth_progress = min(growth_progress, required_growth * 0.999)
		if event_state == EventState.NONE and _all_regular_needs_done():
			_start_special_event()

	_update_growth_stage()

	if growth_progress >= required_growth:
		_roll_special_form()
		matured.emit()

func _refresh_wilted_visual_flag() -> void:
	is_wilted_visual = false
	for w in wilted_needs.values():
		if w:
			is_wilted_visual = true
			break

func _update_growth_stage() -> void:
	if plant_data == null or required_growth <= 0.0:
		return
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

	# Special form (only once mature and not wilted)!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	var show_special = is_special_form and growth_stage == stage_count - 1 and not is_wilted_visual
	if show_special and plant_data.special_form_mature_textures.size() > 0:
		plant_sprite.texture = plant_data.special_form_mature_textures[0]
		plant_sprite.modulate = Color(1, 1, 1)
	elif show_special:
		plant_sprite.modulate = Color(0.6, 0.8, 1.6)   # placeholder blue glow until real art exists
	else:
		plant_sprite.modulate = Color(1, 1, 1)

func is_mature() -> bool:
	return plant_data != null and growth_progress >= required_growth

func harvest() -> int:
	var value = plant_data.sell_value
	if is_permanently_unhealthy:
		value = int(value * 0.7)  # placeholder penalty, tune later
	elif plant_data.lucky_variant_mature_textures.size() > 0 and randf() < plant_data.lucky_variant_chance:
		value = int(value * plant_data.lucky_variant_sell_bonus)
	plant_data = null   # lucky roll above must stay BEFORE this line
	_reset_plant_state()
	plant_sprite.texture = null
	queue_redraw()
	return value

func _show_need_popup(need: NeedData) -> void:
	_spawn_popup(need.need_id, need.icon)

func _spawn_popup(id: String, icon: Texture2D) -> NeedPopup:
	if id in active_popups:
		return active_popups[id]
	var popup: NeedPopup = preload("res://scenes/ui/need_popup.tscn").instantiate()
	need_popup_container.add_child(popup)   # add to tree first so @onready vars resolve
	popup.setup(id, icon)
	popup.pressed.connect(_on_need_popup_pressed)
	active_popups[id] = popup
	return popup

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

func _tick_music_need(need: NeedData, delta: float) -> bool:
	# Music must play CONTINUOUSLY for need.required_continuous_play_sec.
	# If the shared music box runs out of wind, progress resets to 0.
	var grid = _find_grid_window()
	if grid != null and grid.is_music_playing():
		music_play_progress += delta
	else:
		music_play_progress = 0.0
	if music_play_progress >= need.required_continuous_play_sec:
		satisfy_need("music")
		return true
	return false

func _on_need_popup_pressed(need_id: String) -> void:
	match need_id:
		"water":
			satisfy_need("water")
		"fertilizer":
			if EconomyManager.use_fertilizer():
				satisfy_need("fertilizer")
		"insects":
			_launch_insect_minigame()
		EVENT_POPUP_ID:
			_launch_special_event()
		"music":
			# Clicking only opens/reopens the shared music box viewer. The need
			# is satisfied later by _tick_music_need once the plant has heard
			# music continuously for long enough.
			var grid = _find_grid_window()
			if grid != null:
				grid.open_music_box_ui()
		# "sunlight" is still handled externally (shelf-wide mini-sun), since it
		# auto-resolves on its own rather than being a popup-click minigame

# ---------------------------------------------------------------- insects

func _launch_insect_minigame() -> void:
	# Bugs are already running for this plot — don't spawn a second swarm
	# (prevents satisfying the same insects need twice).
	if active_swarm != null and is_instance_valid(active_swarm):
		return
	var need = _find_need("insects")
	if need == null:
		return
	var swarm = InsectSwarm.new()
	get_tree().root.add_child(swarm)   # add to tree first, then start
	swarm.start(need, _get_screen_center())
	swarm.all_caught.connect(_on_swarm_all_caught)
	active_swarm = swarm

func _on_swarm_all_caught() -> void:
	active_swarm = null
	if plant_data != null and is_need_due("insects"):
		satisfy_need("insects")

func _clear_swarm() -> void:
	if active_swarm != null and is_instance_valid(active_swarm):
		active_swarm.queue_free()
	active_swarm = null

func _get_screen_center() -> Vector2i:
	# This plot's center in desktop (screen) pixel coordinates
	var local_center = get_global_rect().get_center()
	return get_window().position + Vector2i(local_center)

# ---------------------------------------------------------------- special event

func _has_special_event() -> bool:
	return plant_data != null and plant_data.special_event_id != ""

func _event_blocks_maturity() -> bool:
	return _has_special_event() and (event_state == EventState.NONE or event_state == EventState.PENDING)

func _all_regular_needs_done() -> bool:
	for need in plant_data.needs:
		if next_threshold_index.get(need.need_id, 0) < need.needed_count:
			return false
	return true

func _start_special_event() -> void:
	event_state = EventState.PENDING
	_show_event_popup()
	special_event_changed.emit()

func _show_event_popup() -> void:
	var popup = _spawn_popup(EVENT_POPUP_ID, EVENT_ICON)
	popup.set_enabled(not _is_event_on_cooldown())

func _is_event_on_cooldown() -> bool:
	return event_cooldown_until > Time.get_unix_time_from_system()

func _update_event_cooldown() -> void:
	if event_state == EventState.PENDING and event_cooldown_until > 0.0 and not _is_event_on_cooldown():
		event_cooldown_until = 0.0
		if EVENT_POPUP_ID in active_popups:
			active_popups[EVENT_POPUP_ID].set_enabled(true)

func get_event_cooldown_left() -> float:
	return max(0.0, event_cooldown_until - Time.get_unix_time_from_system())

func _launch_special_event() -> void:
	if event_state != EventState.PENDING or _is_event_on_cooldown():
		return
	if _active_event != null and is_instance_valid(_active_event):
		return   # already playing
	match plant_data.special_event_id:
		"memoria_run":
			_active_event = MemoriaRun.open_in_window(get_tree().root, false)   # no in-game retry: caught = loss
		_:
			push_warning("Unknown special_event_id: %s" % plant_data.special_event_id)
			return
	_active_event.finished.connect(_on_special_event_finished)

func _on_special_event_finished(success: bool) -> void:
	_active_event = null
	if plant_data == null or event_state != EventState.PENDING:
		return
	if success:
		event_state = EventState.WON
		_hide_need_popup_if_matching(EVENT_POPUP_ID)
	else:
		event_losses += 1
		if event_losses >= plant_data.special_event_max_losses:
			event_state = EventState.FORFEITED   # event gone for good; plant matures normally
			_hide_need_popup_if_matching(EVENT_POPUP_ID)
		else:
			event_cooldown_until = Time.get_unix_time_from_system() + plant_data.special_event_cooldown_sec
			if EVENT_POPUP_ID in active_popups:
				active_popups[EVENT_POPUP_ID].set_enabled(false)
	special_event_changed.emit()

func _roll_special_form() -> void:
	if event_state != EventState.WON or special_form_rolled:
		return
	special_form_rolled = true
	is_special_form = randf() < plant_data.special_form_chance
	_update_growth_stage()

func _close_active_event() -> void:
	if _active_event != null and is_instance_valid(_active_event):
		var win = _active_event.get_parent()
		_active_event = null
		if win is Window:
			win.queue_free()
	_active_event = null

# ---------------------------------------------------------------- save / load

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
		"event_state": event_state,
		"event_losses": event_losses,
		"event_cooldown_until": event_cooldown_until,
		"is_special_form": is_special_form,
		"special_form_rolled": special_form_rolled,
	}

func from_dict(data: Dictionary, plant_lookup: Dictionary) -> void:
	_reset_plant_state()
	plant_data = null
	plant_sprite.texture = null
	pot_id = str(data.get("pot_id", ""))
	place_pot_button.visible = (pot_id == "")
	queue_redraw()

	var plant_id = str(data.get("plant_id", ""))
	if plant_id == "":
		return
	plant_data = plant_lookup.get(plant_id)
	if plant_data == null:
		return
	growth_progress = float(data.get("growth_progress", 0.0))
	required_growth = float(data.get("required_growth", plant_data.growth_time_sec))
	wilt_incident_count = int(data.get("wilt_incident_count", 0))
	is_permanently_unhealthy = bool(data.get("is_permanently_unhealthy", false))

	# JSON gives back floats and untyped arrays — convert explicitly.
	var saved_thresholds: Dictionary = data.get("thresholds", {})
	var saved_index: Dictionary = data.get("next_threshold_index", {})
	var saved_due: Dictionary = data.get("due_since", {})
	var saved_wilted: Dictionary = data.get("wilted_needs", {})
	for need in plant_data.needs:
		var id = need.need_id
		var arr: Array[float] = []
		for v in saved_thresholds.get(id, []):
			arr.append(float(v))
		if arr.size() != need.needed_count:
			arr = _generate_thresholds(need.needed_count, need.randomization_pct)
		thresholds[id] = arr
		next_threshold_index[id] = int(saved_index.get(id, 0))
		due_since[id] = float(saved_due.get(id, 0.0))
		wilted_needs[id] = bool(saved_wilted.get(id, false))

	event_state = int(data.get("event_state", EventState.NONE)) as EventState
	event_losses = int(data.get("event_losses", 0))
	event_cooldown_until = float(data.get("event_cooldown_until", 0.0))
	is_special_form = bool(data.get("is_special_form", false))
	special_form_rolled = bool(data.get("special_form_rolled", false))

	_refresh_wilted_visual_flag()
	_update_growth_stage()
	if event_state == EventState.PENDING:
		_show_event_popup()

	# need_became_due is not re-emitted on load, so re-show popups for any need
	# that was already due when the game was saved.
	for need in plant_data.needs:
		if is_need_due(need.need_id):
			_show_need_popup(need)
