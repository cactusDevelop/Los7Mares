extends Node

const SAVE_PATH := "user://savegame.json"

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func write(data: Dictionary) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))

func read() -> Dictionary:
	if not has_save():
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}

func delete() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)

## Met à jour uniquement la liste des joueurs dans la sauvegarde existante
## (sans toucher au reste de l'état du plateau), pour pouvoir persister des
## changements légers (ex: déplacement d'un objet dans l'inventaire) sans
## dépendre du prochain autosave lié à une phase de jeu. Ne fait rien s'il
## n'y a pas de partie sauvegardée en cours.
func update_players(players: Array) -> void:
	var data := read()
	if data.is_empty():
		return
	data["players"] = players
	write(data)
