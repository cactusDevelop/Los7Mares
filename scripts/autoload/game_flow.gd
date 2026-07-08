extends Node

signal players_changed

const COLORS: Array[String] = ["rouge", "jaune", "bleu", "vert", "violet"]
const COLOR_VALUES: Dictionary = {
	"rouge": Color(0.85, 0.15, 0.15),
	"jaune": Color(0.95, 0.8, 0.1),
	"bleu": Color(0.15, 0.45, 0.9),
	"vert": Color(0.2, 0.7, 0.3),
	"violet": Color(0.55, 0.25, 0.75),
}
const RANDOM_NAMES: Array[String] = ["Thomas", "Adrien", "Martino", "Raphael", "Alex"]

const TITLE_SCENE_PATH := "res://scenes/ui/title_screen.tscn"
const BOARD_SCENE_PATH := "res://scenes/board/board.tscn"

## "" = rien à faire (mode debug, joueurs déjà générés).
## "host" ou "join" = le joueur local doit passer par le popup nom/couleur
## en arrivant sur le board (stub en attendant le vrai réseau).
var pending_setup_mode: String = ""
var is_debug_mode: bool = false

var players: Array[Dictionary] = []

var _next_player_id: int = 0


func reset_players() -> void:
	players.clear()
	_next_player_id = 0
	players_changed.emit()


func add_player(player_name: String, color: String) -> Dictionary:
	var player := {
		"id": _next_player_id,
		"name": player_name,
		"color": color,
	}
	_next_player_id += 1
	players.append(player)
	players_changed.emit()
	return player


func is_color_taken(color: String) -> bool:
	for p in players:
		if p["color"] == color:
			return true
	return false


func generate_debug_players(count: int) -> void:
	reset_players()
	var shuffled_names := RANDOM_NAMES.duplicate()
	shuffled_names.shuffle()
	var shuffled_colors := COLORS.duplicate()
	shuffled_colors.shuffle()
	for i in range(count):
		add_player(shuffled_names[i], shuffled_colors[i])


func go_to_title() -> void:
	get_tree().change_scene_to_file(TITLE_SCENE_PATH)


func go_to_board() -> void:
	get_tree().change_scene_to_file(BOARD_SCENE_PATH)
