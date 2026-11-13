extends Resource
class_name PlantData

@export var id: String = ""
@export var display_name: String = ""
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
