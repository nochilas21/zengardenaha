extends Resource
class_name NeedData

@export var need_id: String = ""
@export var needed_count: int = 2
@export var randomization_pct: float = 0.15
@export var grace_sec: float = 600.0
@export var slow_multiplier: float = 0.15
@export var wilt_penalty_sec: float = 120.0
@export var icon: Texture2D

# Only used when need_id == "music"
@export var required_continuous_play_sec: float = 10.0

# Only used when need_id == "insects"
@export var bug_count: int = 3
@export var bug_speed: float = 150.0   # pixels per second on the desktop
@export var use_overlay: bool = false  # true = troll plant: all bugs in one overlay window, ignores the global cap
