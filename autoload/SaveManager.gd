extends Node

const SAVE_PATH = "user://savegame.json"

var loaded_state: Dictionary = {}

func save_game(state: Dictionary) -> void:
    var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    file.store_string(JSON.stringify(state, "  "))
    file.close()

func load_game() -> Dictionary:
    if not FileAccess.file_exists(SAVE_PATH):
        loaded_state = {}
        return {}
    var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
    var text = file.get_as_text()
    file.close()
    var parsed = JSON.parse_string(text)
    loaded_state = parsed if parsed is Dictionary else {}
    return loaded_state

func has_save() -> bool:
    return FileAccess.file_exists(SAVE_PATH)
