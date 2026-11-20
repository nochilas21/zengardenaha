extends Window
class_name SkinPicker

# Small window that lists the skins you own for ONE thing (a shelf, a pot,
# the menu light, the music box) and lets you pick one.
#   SkinPicker.open(parent, "pot", current_skin_id, on_pick, near_screen_pos, "cloud")
#     on_pick(skin: SkinData) is called when a skin is chosen.
#     pot_id (last arg) limits pot skins to that pot type.
# Only one picker is open at a time.

static var _current: SkinPicker = null

var _category: String
var _pot_id: String
var _current_id: String
var _on_pick: Callable
var _near: Vector2i

static func open(parent: Node, category: String, current_id: String, on_pick: Callable, near: Vector2i, pot_id: String = "") -> SkinPicker:
	if _current != null and is_instance_valid(_current):
		_current.queue_free()
	var picker = SkinPicker.new()
	picker._category = category
	picker._current_id = current_id
	picker._on_pick = on_pick
	picker._near = near
	picker._pot_id = pot_id
	parent.add_child(picker)
	_current = picker
	return picker

func _init() -> void:
	size = Vector2i(300, 320)
	unresizable = true
	always_on_top = true
	close_requested.connect(queue_free)
	focus_exited.connect(queue_free)   # click elsewhere = close

func _ready() -> void:
	title = "Choose a look"
	var rect = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	position = Vector2i(clampi(_near.x + 20, rect.position.x, rect.end.x - size.x), clampi(_near.y - size.y / 2, rect.position.y, rect.end.y - size.y))

	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var any = false
	for skin in Inventory.get_all_skins(_category):
		if not Inventory.owns_skin(_category, skin.id):
			continue
		if _category == "pot" and _pot_id != "" and skin.pot_id != _pot_id:
			continue   # only skins made for this kind of pot
		any = true
		list.add_child(_make_row(skin))
	if not any:
		var label = Label.new()
		label.text = "You don't own other looks for this yet."
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(label)

func _make_row(skin: SkinData) -> Control:
	var button = Button.new()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 48)
	button.text = "  " + (skin.display_name if skin.display_name != "" else skin.id)
	if skin.id == _current_id:
		button.text += "   (current)"
		button.disabled = true
	button.icon = _preview_of(skin)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 40)
	button.pressed.connect(_pick.bind(skin))
	return button

func _preview_of(skin: SkinData) -> Texture2D:
	if skin.preview != null:
		return skin.preview
	if skin is ShelfSkinData:
		return skin.base_middle
	if skin is PotSkinData and skin.hframes * skin.vframes <= 1:
		return skin.texture
	if skin is IconSkinData:
		return skin.icon
	return null

func _pick(skin: SkinData) -> void:
	if _on_pick.is_valid():
		_on_pick.call(skin)
	queue_free()
