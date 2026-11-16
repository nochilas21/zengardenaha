extends Resource
class_name PlantData

@export var id: String = ""
@export var display_name: String = ""
@export_enum("Common", "Rare", "Epic", "Legendary", "Mythical", "Special") var rarity: String = "Common"
@export var tag: String = ""					 # e.g. "Basic", "Mutant" — free text for now
@export_enum("Flower", "Fruit", "Vegetable") var category: String = "Flower"
@export var stage_textures: Array[Texture2D] = []
@export var wilted_stage_textures: Array[Texture2D] = []
@export var unhealthy_stage_textures: Array[Texture2D] = []  # stage 0 (sprout) unused, only need 1-2
@export var growth_time_sec: float = 300.0
@export var sell_value: int = 10
@export var needs: Array[NeedData] = []
@export var required_pot_id: String = ""
@export var unlock_cost: int = 200
@export var plant_cost: int = 20
@export var lucky_variant_mature_textures: Array[Texture2D] = []  # empty = no lucky variants for this species
@export var lucky_variant_chance: float = 0.0
@export var lucky_variant_sell_bonus: float = 1.5

@export_group("Special event")
@export var special_event_id: String = ""            # "" = none; "memoria_run" = Memoria Moonflower jump-and-run
@export_range(0.0, 1.0, 0.005) var special_form_chance: float = 0.125   # chance after WINNING the event; tweak for testing
@export var special_event_max_losses: int = 3          # lose this many times → event gone, plant matures normally
@export var special_event_cooldown_sec: float = 10.0   # event popup is greyed out this long after a loss
@export var special_form_mature_textures: Array[Texture2D] = []   # empty = placeholder blue glow
