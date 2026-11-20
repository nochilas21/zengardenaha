extends SkinData
class_name PotSkinData

# The look of one pot TYPE (pot_id = "dirt", "water", "cloud"...). Pot art is
# drawn on a canvas_size x canvas_size image, standing at the bottom.

@export var pot_id: String = "dirt"         # which pot type this skin is for
@export var texture: Texture2D
@export var canvas_size: float = 1024.0
@export var center_x: float = 512.0         # pot center x on the canvas
@export var bottom_y: float = 1020.0        # y of the pot's bottom edge (stands on the shelf)
@export var soil_y: float = 715.0           # y where the plant comes out of the soil
@export var fallback_color: Color = Color(0.45, 0.28, 0.15)   # drawn shape when texture is empty

@export_group("Look")
@export var scale: float = 1.0              # extra size multiplier (e.g. big art on a small pot)

@export_group("Animation (sprite sheet)")
# If `texture` is a sprite sheet, set how it is cut. All the *_x / *_y values
# above are then measured inside ONE frame.
@export var hframes: int = 1
@export var vframes: int = 1
@export var frame_count: int = 0            # 0 = hframes * vframes (use less if the last row isn't full)
@export var fps: float = 12.0

func total_frames() -> int:
	var all = max(1, hframes * vframes)
	return all if frame_count <= 0 else mini(frame_count, all)
