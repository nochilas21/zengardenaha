extends Control
class_name Plot

signal need_became_due(need_id: String)
signal need_satisfied(need_id: String)
signal wilted(need_id: String)
signal unwilted()
signal matured()
signal clicked(plot: Plot)   # player clicked this slot (used to select it for the shop)
signal special_event_changed()   # event appeared / won / lost / forfeited (hook for autosave)
signal plant_requested(plot: Plot)     # (+) popup on an empty pot was clicked → choose a seed
signal harvest_requested(plot: Plot)   # mature plant clicked with the hand cursor → into the bag
signal pot_drag_started(plot: Plot)    # player pressed on an empty pot and dragged it (move / swap / back to bag)

# PlantSprite should be a Sprite2D with the plant_sway shader. If the scene still
# has the old TextureRect, a Sprite2D is created in code instead (so an older
# plot.tscn never crashes the game).
@onready var _plant_node: Node = $PlantSprite
var plant_sprite: Sprite2D
@onready var need_popup_container: HBoxContainer = $NeedPopupContainer
@onready var place_pot_button: Button = $PlacePotButton

const PLANT_TARGET_HEIGHT: float = 90.0   # max height of the plant drawn in the slot
const SWAY_SHADER_PATH: String = "res://graphics/shaders/plant_sway.gdshader"
const DRAG_START_PX: float = 6.0          # mouse must move this far before a pot drag starts
const HARVEST_ANIM_SEC: float = 0.35      # plant pops up and fades while the cursor hand is closed
const POT_STRIP_HEIGHT: float = 14.0      # plant base height when there is no pot art
const FALLBACK_POT_CANVAS: Vector2 = Vector2(380, 330)   # placeholder pot size (in pot-canvas px) when a pot type has no art
const WILT_TWEEN_SEC: float = 0.6

const WATER_ID: String = "water"
const WATER_DUE_LEVEL: float = 30.0   # water need becomes due when the water bar drops to this %
const WATER_FULL: float = 100.0
const SHOW_WATER_BAR: bool = false   # bar is hidden; water logic (due at 30%) still runs. Set true to debug.

const EVENT_ICON = preload("res://graphics/ui/event_icon.png")
const EVENT_POPUP_ID: String = "event"
const PLANT_POPUP_ID: String = "plant"       # (+) on an empty pot
const HARVEST_POPUP_ID: String = "harvest"   # (✓) on a mature plant
const PLANT_ICON = preload("res://graphics/ui/plant_plus_icon.png")
const HARVEST_ICON = preload("res://graphics/ui/harvest_check_icon.png")

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
var need_counts: Dictionary = {}        # need_id -> how many times it appears THIS planting (rolled from PlantData.need_count_ranges)
var water_level: float = WATER_FULL    # 0..100 water bar; drains by PlantData.water_decay_per_sec
var active_swarm: InsectSwarm = null   # bugs currently running on the desktop for this plot

var event_state: EventState = EventState.NONE
var event_losses: int = 0
var event_cooldown_until: float = 0.0   # unix time; popup greyed out until then
var is_special_form: bool = false
var special_form_rolled: bool = false
var _active_event: Node = null          # the running minigame, if any
var _overlay: Control = null            # drawn ABOVE the plant sprite (water bar, selection border)
var _wilt_visual_applied: bool = false  # what the shader currently shows (droop/desaturate)
var _wilt_tween: Tween = null

# Pot visuals (skins). The shelf tells each slot how big pot art should be drawn.
var pot_skin_id: String = ""            # which PotSkinData this pot uses ("" = equipped one)
var pot_display_scale: float = 0.12     # screen px per pot-canvas px (set by the shelf)
var _pot_sprite: Sprite2D = null
var _drop_highlight: bool = false       # a dragged pot is hovering over this slot
var user_hidden: bool = false           # hidden from Settings → Hide items (keeps growing)

func _ready() -> void:
	_setup_plant_sprite()
	place_pot_button.pressed.connect(_on_place_pot_pressed)
	place_pot_button.visible = false   # empty slots are drawn as a marker; clicking the slot selects it
	# Pot sprite lives behind the plant
	_pot_sprite = Sprite2D.new()
	_pot_sprite.centered = false
	_pot_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_pot_sprite)
	move_child(_pot_sprite, 0)
	# Each plot gets its own copy of the sway material, with a random phase so
	# plants on the same shelf don't sway in sync.
	if plant_sprite.material is ShaderMaterial:
		plant_sprite.material = plant_sprite.material.duplicate()
		plant_sprite.material.set_shader_parameter("phase", randf() * TAU)
	plant_sprite.centered = false
	# Popups stack from the right edge so they stay inside the slot
	need_popup_container.alignment = BoxContainer.ALIGNMENT_END
	need_popup_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("plots")   # lets the global MusicManager find every plot
	mouse_entered.connect(func(): _hovered = true)
	mouse_exited.connect(func(): _hovered = false)
	# Overlay layer on top of PlantSprite so the plant art can't hide the
	# water bar or the selection border. Popups are moved above it.
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	move_child(need_popup_container, -1)   # popups stay clickable and on top

func _setup_plant_sprite() -> void:
	if _plant_node is Sprite2D:
		plant_sprite = _plant_node
		return
	# Old scene (TextureRect): hide it and draw the plant with our own Sprite2D
	plant_sprite = Sprite2D.new()
	plant_sprite.name = "PlantSpriteRuntime"
	if _plant_node is CanvasItem:
		_plant_node.visible = false
		if _plant_node.material is ShaderMaterial:
			plant_sprite.material = _plant_node.material
	if plant_sprite.material == null and ResourceLoader.exists(SWAY_SHADER_PATH):
		var mat = ShaderMaterial.new()
		mat.shader = load(SWAY_SHADER_PATH)
		plant_sprite.material = mat
	add_child(plant_sprite)

# ---------------------------------------------------------------- input: select / drag pot / harvest

var _pressing: bool = false
var _press_mouse: Vector2i
var _drag_sent: bool = false

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_mature() and _harvest_anim_t < 0.0:
			_start_harvest_anim()   # the cursor is already a hand here: click = grab
			return
		# select on release (so a press-and-drag can move the pot instead)
		_pressing = true
		_drag_sent = false
		_press_mouse = DisplayServer.mouse_get_position()

func _update_press() -> void:
	if not _pressing:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_pressing = false
		if not _drag_sent:
			clicked.emit(self)
		return
	if not _drag_sent and pot_id != "" and Vector2(DisplayServer.mouse_get_position() - _press_mouse).length() > DRAG_START_PX:
		_drag_sent = true
		pot_drag_started.emit(self)   # the owner decides (a planted pot can't be moved)

func _on_place_pot_pressed() -> void:
	# The empty-slot button now just selects the slot; the shop places the pot.
	clicked.emit(self)

func set_selected(value: bool) -> void:
	is_selected = value
	_redraw()

func set_user_hidden(value: bool) -> void:
	user_hidden = value
	visible = not value   # _process still runs while hidden, so the plant keeps growing

func set_drop_highlight(value: bool) -> void:
	if _drop_highlight != value:
		_drop_highlight = value
		_redraw()

# Called by the shelf whenever its layout or skin changes.
func configure_slot(slot_size: Vector2, pot_scale_px: float) -> void:
	custom_minimum_size = slot_size
	size = slot_size
	pot_display_scale = pot_scale_px
	_refresh_pot_visual()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_refresh_pot_visual()

func _current_pot_skin() -> PotSkinData:
	if pot_id == "":
		return null
	return Inventory.get_pot_skin(pot_id, pot_skin_id)

func _refresh_pot_visual() -> void:
	if _pot_sprite == null:
		return
	var skin = _current_pot_skin()
	if skin != null and skin.texture != null:
		_pot_sprite.visible = true
		_pot_sprite.texture = skin.texture
		_pot_sprite.hframes = max(1, skin.hframes)   # sprite-sheet pots animate (see _update_pot_anim)
		_pot_sprite.vframes = max(1, skin.vframes)
		_pot_sprite.frame = 0
		_pot_sprite.scale = Vector2.ONE * pot_display_scale * skin.scale
		_pot_sprite.offset = Vector2(-skin.center_x, -skin.bottom_y)
		_pot_sprite.position = Vector2(size.x / 2.0, size.y)
	else:
		_pot_sprite.visible = false
	_fit_plant_sprite()
	_redraw()

var _pot_anim_t: float = 0.0

func _update_pot_anim(delta: float) -> void:
	if _pot_sprite == null or not _pot_sprite.visible:
		return
	var skin = _current_pot_skin()
	if skin == null or skin.total_frames() <= 1:
		return
	_pot_anim_t += delta
	_pot_sprite.frame = int(_pot_anim_t * skin.fps) % skin.total_frames()

# y (in this slot) where the plant comes out of the soil
func _plant_base_y() -> float:
	var skin = _current_pot_skin()
	if skin != null and skin.texture != null:
		return size.y - (skin.bottom_y - skin.soil_y) * pot_display_scale * skin.scale
	if pot_id != "":
		return size.y - _fallback_pot_size().y + 4.0
	return size.y - POT_STRIP_HEIGHT

func _fallback_pot_size() -> Vector2:
	return FALLBACK_POT_CANVAS * pot_display_scale

func _draw() -> void:
	# Under the plant: empty-slot marker, or a placeholder pot if the pot type has no art
	var base = Vector2(size.x / 2.0, size.y)
	if pot_id == "":
		# dotted outline where a pot will stand, the size of a real pot
		var marker = Color(1, 1, 1, 0.4)
		var r = _fallback_pot_size().x / 2.0
		for i in range(12):
			var a0 = PI + i * PI / 12.0
			draw_arc(base - Vector2(0, 3), r, a0, a0 + PI / 24.0, 3, marker, 2.0)
		draw_line(base + Vector2(-r, -3), base + Vector2(r, -3), marker, 2.0)
	elif not _pot_sprite.visible:
		var w = _fallback_pot_size().x
		var h = _fallback_pot_size().y
		var color = POT_COLORS.get(pot_id, Color(0.5, 0.5, 0.5))
		draw_colored_polygon(PackedVector2Array([
			base + Vector2(-w / 2.0, -h), base + Vector2(w / 2.0, -h),
			base + Vector2(w * 0.35, 0), base + Vector2(-w * 0.35, 0),
		]), color)
		draw_rect(Rect2(base + Vector2(-w / 2.0 - 3, -h - 6), Vector2(w + 6, 8)), color.darkened(0.2))

func _draw_overlay() -> void:
	# Above the plant: water bar + selection border
	if SHOW_WATER_BAR and plant_data != null and _has_need(WATER_ID) and not is_mature():
		var bar = Rect2(4, size.y - 10, size.x - 8, 6)
		_overlay.draw_rect(bar.grow(1), Color(0, 0, 0, 0.7))
		var fill_color = Color(0.3, 0.65, 1.0) if water_level > WATER_DUE_LEVEL else Color(1.0, 0.45, 0.3)
		_overlay.draw_rect(Rect2(bar.position, Vector2(bar.size.x * water_level / WATER_FULL, bar.size.y)), fill_color)
		var mark_x = bar.position.x + bar.size.x * WATER_DUE_LEVEL / WATER_FULL
		_overlay.draw_line(Vector2(mark_x, bar.position.y - 2), Vector2(mark_x, bar.end.y + 2), Color(1, 1, 1, 0.8), 1.0)
	if is_selected:
		_overlay.draw_rect(Rect2(Vector2(1.5, 1.5), size - Vector2(3, 3)), Color(1.0, 0.85, 0.2), false, 3.0)
	_draw_harvest_fx()
	if _drop_highlight:
		_overlay.draw_rect(Rect2(Vector2(1.5, 1.5), size - Vector2(3, 3)), Color(0.5, 1.0, 0.6, 0.9), false, 3.0)
		_overlay.draw_rect(Rect2(Vector2.ZERO, size), Color(0.5, 1.0, 0.6, 0.12))

# ---------------------------------------------------------------- plant visuals (shader)

func _set_wilt_visual(wilted: bool) -> void:
	# Smoothly droop + desaturate the plant via the plant_sway shader
	_wilt_visual_applied = wilted
	var m := plant_sprite.material as ShaderMaterial
	if m == null:
		return
	if _wilt_tween != null and _wilt_tween.is_valid():
		_wilt_tween.kill()
	_wilt_tween = create_tween().set_parallel(true)
	_wilt_tween.tween_property(m, "shader_parameter/droop", 1.0 if wilted else 0.0, WILT_TWEEN_SEC)
	_wilt_tween.tween_property(m, "shader_parameter/desaturate", 0.7 if wilted else 0.0, WILT_TWEEN_SEC)

func _apply_wilt_visual_instant(wilted: bool) -> void:
	_wilt_visual_applied = wilted
	if _wilt_tween != null and _wilt_tween.is_valid():
		_wilt_tween.kill()
	var m := plant_sprite.material as ShaderMaterial
	if m != null:
		m.set_shader_parameter("droop", 1.0 if wilted else 0.0)
		m.set_shader_parameter("desaturate", 0.7 if wilted else 0.0)

func _fit_plant_sprite() -> void:
	# Scale the texture to PLANT_TARGET_HEIGHT and stand it bottom-center on the pot.
	# offset puts the sprite's origin at its bottom-center (the shader sways around it).
	var base_y = _plant_base_y()
	plant_sprite.position = Vector2(size.x / 2.0, base_y)
	if plant_sprite.texture == null:
		return
	var s := plant_sprite.texture.get_size()
	if s.y <= 0.0:
		return
	var target_h = clamp(base_y - 4.0, 16.0, PLANT_TARGET_HEIGHT)   # never taller than the slot
	plant_sprite.scale = Vector2.ONE * (target_h / s.y)
	plant_sprite.offset = Vector2(-s.x / 2.0, -s.y)

func _redraw() -> void:
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()

# ---------------------------------------------------------------- pot / plant

func can_plant(data: PlantData, grid_tag: String = "") -> bool:
	if grid_tag != "" and grid_tag == data.required_pot_id:
		return true
	return pot_id != "" and pot_id == data.required_pot_id

func place_pot(new_pot: PotData, skin_id: String = "") -> bool:
	if plant_data != null or pot_id != "":
		return false   # slot already has a pot (or a plant)
	pot_id = new_pot.pot_id
	var skin = Inventory.get_pot_skin(pot_id, skin_id)
	pot_skin_id = skin.id if skin != null else ""
	_refresh_pot_visual()
	_refresh_action_popups()
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
		var id = need.need_id
		if id == WATER_ID:
			need_counts[id] = 0   # water is a continuous bar, not a fixed number of events
			thresholds[id] = _generate_thresholds(0, 0.0)   # empty typed array
		else:
			need_counts[id] = _roll_need_count(need)
			thresholds[id] = _generate_thresholds(need_counts[id], need.randomization_pct)
		next_threshold_index[id] = 0
		due_since[id] = 0.0
		wilted_needs[id] = false
	_update_growth_stage()
	_refresh_action_popups()
	return true

# How many times this need appears for this planting: a random number inside
# PlantData.need_count_ranges[need_id] (Vector2i(min, max)), or the NeedData's
# needed_count if the plant doesn't define a range.
func _roll_need_count(need: NeedData) -> int:
	var range_v = plant_data.need_count_ranges.get(need.need_id)
	if range_v is Vector2i:
		return randi_range(mini(range_v.x, range_v.y), maxi(range_v.x, range_v.y))
	return need.needed_count

func _needed_count(need_id: String) -> int:
	return int(need_counts.get(need_id, 0))

func _has_need(need_id: String) -> bool:
	return plant_data != null and _find_need(need_id) != null

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
	need_counts.clear()
	water_level = WATER_FULL
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
	_apply_wilt_visual_instant(false)

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
	if need_id == WATER_ID:
		water_level = WATER_FULL   # watering refills the bar; water has no threshold index
	else:
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
	_update_pot_anim(delta)
	_update_press()
	_update_harvest_fx(delta)
	if plant_data == null or growth_progress >= required_growth:
		return

	_update_event_cooldown()
	var now = Time.get_unix_time_from_system()
	var effective_rate = 1.0
	var any_wilted = false
	var progress_pct = growth_progress / required_growth

	for need in plant_data.needs:
		if need.need_id == WATER_ID:
			# Water: the bar drains continuously; at WATER_DUE_LEVEL% it becomes due
			water_level = max(0.0, water_level - plant_data.water_decay_per_sec * delta)
			if water_level <= WATER_DUE_LEVEL and due_since[WATER_ID] == 0.0:
				_make_need_due(need, now)
		else:
			var idx = next_threshold_index[need.need_id]
			if idx >= _needed_count(need.need_id):
				continue
			var threshold = thresholds[need.need_id][idx]
			if progress_pct >= threshold and due_since[need.need_id] == 0.0:
				_make_need_due(need, now)

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
	_redraw()   # water bar

	if _event_blocks_maturity():
		# Hold just below maturity until the special event is won or forfeited
		growth_progress = min(growth_progress, required_growth * 0.999)
		if event_state == EventState.NONE and _all_regular_needs_done():
			_start_special_event()

	_update_growth_stage()

	if growth_progress >= required_growth:
		_finish_water_need()
		_roll_special_form()
		_refresh_action_popups()   # show the (✓) harvest popup
		matured.emit()

# Once the plant can be harvested, watering is no longer needed: clear any
# due/wilted water state and hide its popup and bar.
func _finish_water_need() -> void:
	if not due_since.has(WATER_ID):
		return
	var was_wilted = wilted_needs.get(WATER_ID, false)
	due_since[WATER_ID] = 0.0
	wilted_needs[WATER_ID] = false
	water_level = WATER_FULL
	_hide_need_popup_if_matching(WATER_ID)
	_refresh_wilted_visual_flag()
	if was_wilted and not is_wilted_visual:
		unwilted.emit()
	_update_growth_stage()
	_redraw()

func _make_need_due(need: NeedData, now: float) -> void:
	due_since[need.need_id] = now
	_show_need_popup(need)
	need_became_due.emit(need.need_id)

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

	# Special form (only once mature and not wilted)
	var show_special = is_special_form and growth_stage == stage_count - 1 and not is_wilted_visual
	if show_special and plant_data.special_form_mature_textures.size() > 0:
		plant_sprite.texture = plant_data.special_form_mature_textures[0]
		plant_sprite.modulate = Color(1, 1, 1)
	elif show_special:
		plant_sprite.modulate = Color(0.6, 0.8, 1.6)   # placeholder blue glow until real art exists
	else:
		plant_sprite.modulate = Color(1, 1, 1)

	# Size/position AFTER the texture is chosen (it may have just changed)
	_fit_plant_sprite()
	if is_wilted_visual != _wilt_visual_applied:
		_set_wilt_visual(is_wilted_visual)

func is_mature() -> bool:
	return plant_data != null and growth_progress >= required_growth

# Harvests the mature plant and returns what goes into the bag:
#   {"plant_id": String, "variant": "normal" | "unhealthy" | "lucky" | "special"}
# The price is decided later when it is sold in the Shop (see Shop.get_sell_price).
func harvest() -> Dictionary:
	var variant = "normal"
	if is_special_form:
		variant = "special"
	elif is_permanently_unhealthy:
		variant = "unhealthy"
	elif plant_data.lucky_variant_mature_textures.size() > 0 and randf() < plant_data.lucky_variant_chance:
		variant = "lucky"
	var item = {"plant_id": plant_data.id, "variant": variant}
	plant_data = null   # the variant roll above must stay BEFORE this line
	_reset_plant_state()
	plant_sprite.texture = null
	_refresh_action_popups()   # back to an empty pot → (+)
	_redraw()
	return item

# (+) when the pot is empty, (✓) when the plant is ready to harvest.
func _refresh_action_popups() -> void:
	if pot_id != "" and plant_data == null:
		_spawn_popup(PLANT_POPUP_ID, PLANT_ICON)
	else:
		_hide_need_popup_if_matching(PLANT_POPUP_ID)
	# ready-to-harvest is shown by the small sparkle badge (see _draw_harvest_fx)
	_hide_need_popup_if_matching(HARVEST_POPUP_ID)
	_redraw()

# ---------------------------------------------------------------- harvest sparkle + hand cursor

var _fx_t: float = 0.0
var _harvest_anim_t: float = -1.0   # < 0 = not playing
var _hovered: bool = false

# Top of the plant in slot coordinates
func _plant_top() -> Vector2:
	var base_y = _plant_base_y()
	var h = PLANT_TARGET_HEIGHT * 0.6
	if plant_sprite != null and plant_sprite.texture != null:
		h = plant_sprite.texture.get_size().y * plant_sprite.scale.y
	return Vector2(size.x / 2.0, base_y - h)

# Small clickable badge near the top-right of the plant
func _badge_rect() -> Rect2:
	var top = _plant_top()
	var c = Vector2(min(top.x + 22.0, size.x - 12.0), max(top.y + 10.0, 12.0))
	return Rect2(c - Vector2(10, 10), Vector2(20, 20))

func _update_harvest_fx(delta: float) -> void:
	_fx_t += delta
	if _harvest_anim_t >= 0.0:
		_harvest_anim_t += delta
		var k = clamp(_harvest_anim_t / HARVEST_ANIM_SEC, 0.0, 1.0)
		# the plant pops up out of the pot and fades (cursor shows a closed hand)
		plant_sprite.position.y = _plant_base_y() - 30.0 * k
		plant_sprite.modulate.a = 1.0 - k
		if _harvest_anim_t >= HARVEST_ANIM_SEC:
			_harvest_anim_t = -1.0
			plant_sprite.modulate.a = 1.0
			_fit_plant_sprite()
			harvest_requested.emit(self)
			HarvestCursor.set_state(self, "open" if _hovered and is_mature() else "")
		_redraw()
		return
	# Hand cursor while hovering a plant that is ready
	HarvestCursor.set_state(self, "open" if _hovered and is_mature() and visible else "")
	if is_mature() and visible:
		_redraw()   # keep the badge twinkling

func _start_harvest_anim() -> void:
	_harvest_anim_t = 0.0
	HarvestCursor.set_state(self, "closed")

func _exit_tree() -> void:
	HarvestCursor.set_state(self, "")

func _draw_harvest_fx() -> void:
	if not is_mature():
		return
	if _harvest_anim_t >= 0.0:
		return   # the cursor is the hand now; just let the plant pop out
	# "Ripe sparkle": a tiny golden 4-point star that bobs, breathes and twinkles,
	# with a little seed orbiting it. Small on purpose — it shouldn't hide the plant.
	var r = _badge_rect()
	var c = r.get_center() + Vector2(0, sin(_fx_t * 2.6) * 2.0)
	var pulse = 0.85 + 0.15 * sin(_fx_t * 4.0)
	var twinkle = clamp(sin(_fx_t * 1.7) * 3.0 - 2.0, 0.0, 1.0)   # a bright flash every ~3.7 s
	_overlay.draw_circle(c, 9.0 * pulse, Color(1.0, 0.85, 0.3, 0.18 + 0.2 * twinkle))
	var arm = 7.0 * pulse + 3.0 * twinkle
	var gold = Color(1.0, 0.86, 0.35)
	_overlay.draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -arm), c + Vector2(2, -2), c + Vector2(arm, 0), c + Vector2(2, 2),
		c + Vector2(0, arm), c + Vector2(-2, 2), c + Vector2(-arm, 0), c + Vector2(-2, -2),
	]), gold)
	_overlay.draw_circle(c, 1.8, Color(1, 1, 0.9))
	var seed_pos = c + Vector2.from_angle(_fx_t * 2.2) * 9.0
	_overlay.draw_circle(seed_pos, 1.6, Color(0.6, 1.0, 0.55, 0.9))

# ---------------------------------------------------------------- shovel / pot moves

# Digs out the plant (Shovel tool). Returns the removed PlantData (or null).
# The pot stays.
func uproot() -> PlantData:
	if plant_data == null:
		return null
	var removed = plant_data
	plant_data = null
	_reset_plant_state()
	plant_sprite.texture = null
	_refresh_action_popups()
	_redraw()
	return removed

# Changes the look of THIS pot only
func set_pot_skin(skin_id: String) -> void:
	var skin = Inventory.get_pot_skin(pot_id, skin_id)
	pot_skin_id = skin.id if skin != null else ""
	_pot_anim_t = 0.0
	_refresh_pot_visual()

# Takes the (empty) pot off the slot. Returns its pot_id, or "" if not allowed.
func remove_pot() -> String:
	if pot_id == "" or plant_data != null:
		return ""
	var removed = pot_id
	pot_id = ""
	pot_skin_id = ""
	_refresh_pot_visual()
	_refresh_action_popups()
	return removed

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
	# The music box is global (MusicManager): one box serves every plant on every shelf.
	if MusicManager.is_playing():
		music_play_progress += delta
	else:
		music_play_progress = 0.0
	if "music" in active_popups:
		active_popups["music"].set_progress(music_play_progress / max(0.001, need.required_continuous_play_sec))
	if music_play_progress >= need.required_continuous_play_sec:
		satisfy_need("music")
		return true
	return false

func get_music_progress() -> float:
	return music_play_progress

func get_music_required() -> float:
	var need = _find_need("music") if plant_data != null else null
	return need.required_continuous_play_sec if need != null else 0.0

func get_location_text() -> String:
	var shelf = _find_grid_window()
	var shelf_no = shelf.shelf_index if shelf != null else 0
	return "Shelf %d · Slot %d" % [shelf_no, get_index() + 1]

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
		PLANT_POPUP_ID:
			plant_requested.emit(self)
		HARVEST_POPUP_ID:
			harvest_requested.emit(self)
		"music":
			# Clicking only opens/reopens the shared music box viewer. The need
			# is satisfied later by _tick_music_need once the plant has heard
			# music continuously for long enough.
			MusicManager.open_ui()
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
		if need.need_id == WATER_ID:
			continue   # the water bar is continuous, it never "finishes"
		if next_threshold_index.get(need.need_id, 0) < _needed_count(need.need_id):
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
		return {"pot_id": pot_id, "pot_skin_id": pot_skin_id, "plant_id": "", "growth_progress": 0.0, "hidden": user_hidden}
	return {
		"hidden": user_hidden,
		"pot_id": pot_id,
		"pot_skin_id": pot_skin_id,
		"plant_id": plant_data.id,
		"growth_progress": growth_progress,
		"required_growth": required_growth,
		"wilt_incident_count": wilt_incident_count,
		"is_permanently_unhealthy": is_permanently_unhealthy,
		"thresholds": thresholds,
		"next_threshold_index": next_threshold_index,
		"due_since": due_since,
		"wilted_needs": wilted_needs,
		"need_counts": need_counts,
		"water_level": water_level,
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
	pot_skin_id = str(data.get("pot_skin_id", ""))
	set_user_hidden(bool(data.get("hidden", false)))
	_refresh_pot_visual()

	var plant_id = str(data.get("plant_id", ""))
	if plant_id == "":
		_refresh_action_popups()
		return
	plant_data = plant_lookup.get(plant_id)
	if plant_data == null:
		_refresh_action_popups()
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
	var saved_counts: Dictionary = data.get("need_counts", {})
	water_level = float(data.get("water_level", WATER_FULL))
	for need in plant_data.needs:
		var id = need.need_id
		if id == WATER_ID:
			need_counts[id] = 0
		elif saved_counts.has(id):
			need_counts[id] = int(saved_counts[id])
		else:
			need_counts[id] = _roll_need_count(need)   # save from before random counts existed
		var arr: Array[float] = []
		for v in saved_thresholds.get(id, []):
			arr.append(float(v))
		if arr.size() != need_counts[id]:
			arr = _generate_thresholds(need_counts[id], need.randomization_pct)
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

	if is_mature():
		_finish_water_need()

	# need_became_due is not re-emitted on load, so re-show popups for any need
	# that was already due when the game was saved.
	for need in plant_data.needs:
		if is_need_due(need.need_id):
			_show_need_popup(need)
	_refresh_action_popups()
