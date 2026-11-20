extends Resource
class_name SkinData

# Base for every cosmetic skin. Gameplay never depends on a skin — a skin only
# changes how something looks. Categories:
#   "shelf"     → ShelfSkinData   (the shelf windows)
#   "pot"       → PotSkinData     (one pot TYPE's look, e.g. the dirt pot)
#   "music_box" → IconSkinData    (music box icon in the menu)
#   "menu"      → IconSkinData    (the glowing fairy/firefly menu icon)
# To add a skin: create a new .tres of the right class in
# res://resources/skins/<category>/ — no code changes needed.

@export var id: String = ""
@export var display_name: String = ""
@export_enum("shelf", "pot", "music_box", "menu") var category: String = "shelf"
@export var preview: Texture2D            # small icon for inventory/shop lists (optional)
@export var unlock_cost: int = 0          # for the future skin shop
