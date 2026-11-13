extends Node

signal currency_changed(new_amount: int)
signal fertilizer_changed(new_amount: int)

var currency: int = 0
var fertilizer_count: int = 0

var unlocked_pot_types: Array[String] = ["dirt"]     # dirt starts unlocked for v1 bootstrapping; adjust as designed
var unlocked_plants: Array[String] = []
var unlocked_grids: Array[int] = [1]

func add(amount: int) -> void:
    currency += amount
    currency_changed.emit(currency)

func spend(amount: int) -> bool:
    if currency < amount:
        return false
    currency -= amount
    currency_changed.emit(currency)
    return true

func add_fertilizer(amount: int) -> void:
    fertilizer_count += amount
    fertilizer_changed.emit(fertilizer_count)

func use_fertilizer() -> bool:
    if fertilizer_count <= 0:
        return false
    fertilizer_count -= 1
    fertilizer_changed.emit(fertilizer_count)
    return true

func unlock_pot_type(pot: PotData) -> bool:
    if pot.pot_id in unlocked_pot_types:
        return false
    if not spend(pot.unlock_cost):
        return false
    unlocked_pot_types.append(pot.pot_id)
    return true

func unlock_plant(plant: PlantData) -> bool:
    if plant.id in unlocked_plants:
        return false
    if not spend(plant.unlock_cost):
        return false
    unlocked_plants.append(plant.id)
    return true
