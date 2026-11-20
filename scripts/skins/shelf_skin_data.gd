extends SkinData
class_name ShelfSkinData

# A shelf is built from square tiles that all share one canvas size (e.g.
# 1024x1024): LEFT end + MIDDLE x (slots - 2) + RIGHT end. One tile = one pot
# slot, so a 3-pot shelf is left+middle+right, and it grows up to 5 pots by
# adding middle tiles. Each tile has 3 layers (only base is required):
#   back  — art behind the shelf ("BG sau kệ")
#   base  — the shelf itself
#   front — art drawn in front of the pots (e.g. a lace trim on the front edge)

@export_group("Tiles")
@export var base_left: Texture2D
@export var base_middle: Texture2D
@export var base_right: Texture2D
@export var back_left: Texture2D
@export var back_middle: Texture2D
@export var back_right: Texture2D
@export var front_left: Texture2D
@export var front_middle: Texture2D
@export var front_right: Texture2D

@export_group("Layout (canvas pixels)")
@export var canvas_size: float = 1024.0       # tile art is canvas_size x canvas_size
@export var surface_y: float = 600.0          # where pot bottoms stand ("chỗ đặt chậu")
@export var crop_bottom_y: float = 770.0      # art below this is cut off (end of the legs)
@export var slot_x_left: float = 560.0        # pot center x inside the left tile
@export var slot_x_middle: float = 512.0
@export var slot_x_right: float = 464.0
@export var pot_scale: float = 1.2            # pot canvas -> shelf canvas scale (1.2 ≈ pot fills ~45% of a tile)

@export_group("Display (screen pixels)")
@export var tile_display_width: float = 192.0 # how wide one tile is on screen
@export var top_padding: float = 64.0         # extra room above the art for plants + need popups
@export var slot_width: float = 130.0         # clickable width of one slot
@export var fallback_color: Color = Color(0.68, 0.4, 0.05)   # used if a base texture is missing

func get_tile(layer: String, index: int, count: int) -> Texture2D:
	var part = "middle"
	if index == 0:
		part = "left"
	elif index == count - 1:
		part = "right"
	return get("%s_%s" % [layer, part])

func get_slot_x(index: int, count: int) -> float:
	if index == 0:
		return slot_x_left
	if index == count - 1:
		return slot_x_right
	return slot_x_middle

func display_scale() -> float:
	return tile_display_width / canvas_size
