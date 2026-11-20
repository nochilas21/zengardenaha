extends Node

# Autoload "Inventory": what the player owns but hasn't placed yet, plus skins.
#   pots          — unplaced pots by type (pot_id -> count). Bought in the shop,
#                   dragged from the Inventory window onto a shelf slot.
#   seeds         — plant_id -> count. Bought in the shop, used by the (+) popup.
#   harvested     — "plant_id|variant" -> count. Harvested plants (✓ popup);
#                   sold in the Shop's Sell section. variant = normal / unhealthy
#                   / lucky / special.
#   owned_skins   — category -> Array of skin ids the player owns
#   equipped      — "shelf" / "music_box" / "menu" -> skin id,
#                   "pot:<pot_id>" -> skin id for that pot type
# Fertilizer is still counted in EconomyManager (it is shown here too).
# Skins are found by scanning res://resources/skins/<category>/*.tres.

signal changed()
signal skin_equipped(category: String, skin_id: String)   # "use this look everywhere" (Inventory → Equip)

const SKIN_ROOT: String = "res://resources/skins/"
const CATEGORIES: Array[String] = ["shelf", "pot", "music_box", "menu"]
# Placeholder new-game items. The cloud pot + Memoria seed are here FOR TESTING
# the Memoria cloud pot skin — remove them when the real economy is set.
const STARTING_POTS: Dictionary = {"dirt": 3, "cloud": 1}
const STARTING_SEEDS: Dictionary = {"sunflower": 2, "memoria_moonflower": 1}

var pots: Dictionary = {}
var seeds: Dictionary = {}
var harvested: Dictionary = {}
var owned_skins: Dictionary = {}
var equipped: Dictionary = {}

var _skins: Dictionary = {}   # category -> {id: SkinData}

func _ready() -> void:
	_load_skin_library()
	reset_to_new_game()

# ---------------------------------------------------------------- skins

func _load_skin_library() -> void:
	_skins.clear()
	for category in CATEGORIES:
		_skins[category] = {}
		var dir = DirAccess.open(SKIN_ROOT + category)
		if dir == null:
			continue
		for raw_name in dir.get_files():
			var file_name = raw_name.trim_suffix(".remap")   # exported builds list *.tres.remap
			if not file_name.ends_with(".tres"):
				continue
			var res = load(SKIN_ROOT + category + "/" + file_name)
			if res is SkinData and res.id != "":
				_skins[category][res.id] = res

func get_all_skins(category: String) -> Array:
	return _skins.get(category, {}).values()

func get_skin(category: String, skin_id: String) -> SkinData:
	return _skins.get(category, {}).get(skin_id)

func get_equipped_skin(category: String) -> SkinData:
	var skin = get_skin(category, equipped.get(category, ""))
	if skin != null:
		return skin
	var all = get_all_skins(category)   # fall back to any skin of that category
	return all[0] if all.size() > 0 else null

func get_pot_skin(pot_id: String, skin_id: String = "") -> PotSkinData:
	# A specific skin if given and valid, else the equipped skin for that pot type,
	# else any skin made for that pot type, else null (plot draws a placeholder).
	var skin = get_skin("pot", skin_id)
	if skin is PotSkinData and skin.pot_id == pot_id:
		return skin
	skin = get_skin("pot", equipped.get("pot:" + pot_id, ""))
	if skin is PotSkinData:
		return skin
	for s in get_all_skins("pot"):
		if s is PotSkinData and s.pot_id == pot_id:
			return s
	return null

func owns_skin(category: String, skin_id: String) -> bool:
	return skin_id in owned_skins.get(category, [])

func add_skin(category: String, skin_id: String) -> void:
	if not owned_skins.has(category):
		owned_skins[category] = []
	if not owns_skin(category, skin_id):
		owned_skins[category].append(skin_id)
		changed.emit()

func equip_skin(category: String, skin_id: String) -> bool:
	var skin = get_skin(category, skin_id)
	if skin == null or not owns_skin(category, skin_id):
		return false
	if category == "pot":
		equipped["pot:" + skin.pot_id] = skin_id
	else:
		equipped[category] = skin_id
	changed.emit()
	skin_equipped.emit(category, skin_id)
	return true

func is_equipped(category: String, skin_id: String) -> bool:
	var skin = get_skin(category, skin_id)
	if skin == null:
		return false
	if category == "pot":
		return equipped.get("pot:" + skin.pot_id, "") == skin_id
	return equipped.get(category, "") == skin_id

# ---------------------------------------------------------------- pots

func add_pot(pot_id: String, amount: int = 1) -> void:
	pots[pot_id] = get_pot_count(pot_id) + amount
	changed.emit()

func take_pot(pot_id: String) -> bool:
	if get_pot_count(pot_id) <= 0:
		return false
	pots[pot_id] = get_pot_count(pot_id) - 1
	changed.emit()
	return true

func get_pot_count(pot_id: String) -> int:
	return int(pots.get(pot_id, 0))

# ---------------------------------------------------------------- seeds

func add_seed(plant_id: String, amount: int = 1) -> void:
	seeds[plant_id] = get_seed_count(plant_id) + amount
	changed.emit()

func take_seed(plant_id: String) -> bool:
	if get_seed_count(plant_id) <= 0:
		return false
	seeds[plant_id] = get_seed_count(plant_id) - 1
	changed.emit()
	return true

func get_seed_count(plant_id: String) -> int:
	return int(seeds.get(plant_id, 0))

# ---------------------------------------------------------------- harvested plants

static func harvest_key(plant_id: String, variant: String) -> String:
	return "%s|%s" % [plant_id, variant]

static func split_harvest_key(key: String) -> Array:
	var parts = key.split("|")
	return [parts[0], parts[1] if parts.size() > 1 else "normal"]

func add_harvest(plant_id: String, variant: String = "normal") -> void:
	var key = harvest_key(plant_id, variant)
	harvested[key] = int(harvested.get(key, 0)) + 1
	changed.emit()

func take_harvest(key: String) -> bool:
	if int(harvested.get(key, 0)) <= 0:
		return false
	harvested[key] = int(harvested[key]) - 1
	changed.emit()
	return true

# ---------------------------------------------------------------- new game / save

func reset_to_new_game() -> void:
	pots = STARTING_POTS.duplicate()
	seeds = STARTING_SEEDS.duplicate()
	harvested.clear()
	owned_skins.clear()
	equipped.clear()
	# Every skin with unlock_cost 0 is owned from the start; equip the first of each
	for category in CATEGORIES:
		for skin in get_all_skins(category):
			if skin.unlock_cost <= 0:
				add_skin(category, skin.id)
				if category == "pot":
					if not equipped.has("pot:" + skin.pot_id):
						equipped["pot:" + skin.pot_id] = skin.id
				elif not equipped.has(category):
					equipped[category] = skin.id
	changed.emit()

func to_dict() -> Dictionary:
	return {"pots": pots, "seeds": seeds, "harvested": harvested, "owned_skins": owned_skins, "equipped": equipped}

func from_dict(data: Dictionary) -> void:
	reset_to_new_game()   # keeps free default skins even for old saves
	if data.has("pots"):
		pots.clear()
		for k in data["pots"]:
			pots[str(k)] = int(data["pots"][k])
	if data.has("seeds"):
		seeds.clear()
		for k in data["seeds"]:
			seeds[str(k)] = int(data["seeds"][k])
	for k in data.get("harvested", {}):
		harvested[str(k)] = int(data["harvested"][k])
	for category in data.get("owned_skins", {}):
		for skin_id in data["owned_skins"][category]:
			if get_skin(category, str(skin_id)) != null:
				add_skin(category, str(skin_id))
	for key in data.get("equipped", {}):
		var value = str(data["equipped"][key])
		var category = "pot" if str(key).begins_with("pot:") else str(key)
		if get_skin(category, value) != null:
			equipped[str(key)] = value
	changed.emit()
