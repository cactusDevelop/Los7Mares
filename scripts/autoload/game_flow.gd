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
const RESOURCE_TYPES: Array[String] = ["wood", "steel", "food", "wool", "rum"]
const SPECIAL_RESOURCE_TYPES: Array[String] = ["fortune", "treasure"]
const RESOURCE_LABELS: Dictionary = {
	"wood": "Bois", "steel": "Acier", "food": "Nourriture",
	"wool": "Laine", "rum": "Rhum", "fortune": "Fortune", "treasure": "Trésor",
}
const PLAYER_BOARD_TEXTURE := "res://assets/art/board/plateau-joueur-jaune.png" # provisoire pour tous
const RANDOM_NAMES: Array[String] = ["Thomas", "Adrien", "Martino", "Raphael", "Alex"]

const PIECE_SCALE := 0.6
const SELECTION_PANEL_WIDTH := 240.0
const SELECTION_ICON_HEIGHT := 110.0
const HOVER_TINT := Color(0.82, 0.82, 0.82)
const CAMERA_SELECTION_SHIFT := 400.0   # décalage horizontal caméra (unités monde)
const CAMERA_SELECTION_ZOOM := Vector2(0.22, 0.22)
const CASE_PIECE_RADIUS := 100.0         # rayon de répartition des pièces sur une case (polygone)
const CASE_PIECE_VERTICAL_OFFSET := 40.0  # décale tout le polygone vers le bas pour compenser l'ancrage des sprites
const CARD_POPUP_DURATION := 0.35       # durée de l'apparition (fondu + zoom) d'une carte de mer piochée
const CARD_PILE_RADIUS_OFFSET := 620.0  # distance supplémentaire (au-delà du rayon des mers) pour placer la pioche de chaque mer
const PARROT_TEXTURE_PATH := "res://assets/art/pieces/perro-%s.png"
const PARROT_TEXTURE_PATH_PRISON := "res://assets/art/pieces/perro-%s-prison.png"

# --- Constantes UI communes (tailles, couleurs, styles) ---
# Regroupées ici pour n'avoir qu'un seul endroit à modifier si le design change.
const TITLE_BUTTON_SIZE := Vector2(420, 84)
const TITLE_BUTTON_FONT_SIZE := 24
const TITLE_BUTTONS_Y_OFFSET := 100.0     # décalage vertical (vers le bas) des boutons du menu titre
const POPUP_BG_COLOR := Color(0.12, 0.12, 0.16, 1.0)
const POPUP_CORNER_RADIUS := 12.0

# --- Localisation ---
const SETTINGS_FILE_PATH := "user://settings.cfg"
const DEFAULT_LOCALE := "fr"
const AVAILABLE_LOCALES: Array[String] = ["fr", "en", "es"]
const DEFAULT_VOLUME := 1.0

enum PieceRank { SECOND = 0, CAPTAIN = 1 }

const TITLE_SCENE_PATH := "res://scenes/ui/title_screen.tscn"
const BOARD_SCENE_PATH := "res://scenes/board/board.tscn"

## "" = rien à faire (mode debug, joueurs déjà générés).
## "host" ou "join" = le joueur local doit passer par le popup nom/couleur
## en arrivant sur le board (stub en attendant le vrai réseau).
var pending_setup_mode: String = ""
var pending_setup_target_count: int = 1
var is_debug_mode: bool = false

var players: Array[Dictionary] = []

var _next_player_id: int = 0


func _ready() -> void:
	_load_locale()
	_load_volume()


func _load_locale() -> void:
	var config := ConfigFile.new()
	var err := config.load(SETTINGS_FILE_PATH)
	var locale: String = DEFAULT_LOCALE
	if err == OK:
		locale = config.get_value("settings", "locale", DEFAULT_LOCALE)
	TranslationServer.set_locale(locale)


## Change la langue courante et la sauvegarde pour les prochains lancements.
func set_locale(locale: String) -> void:
	TranslationServer.set_locale(locale)
	var config := ConfigFile.new()
	config.load(SETTINGS_FILE_PATH)
	config.set_value("settings", "locale", locale)
	config.save(SETTINGS_FILE_PATH)


func _load_volume() -> void:
	var config := ConfigFile.new()
	var err := config.load(SETTINGS_FILE_PATH)
	var volume: float = DEFAULT_VOLUME
	if err == OK:
		volume = config.get_value("settings", "volume", DEFAULT_VOLUME)
	_apply_volume(volume)


## Change le volume du bus Master (ratio linéaire 0.0–1.0) et le sauvegarde
## pour les prochains lancements.
func set_volume(volume: float) -> void:
	_apply_volume(volume)
	var config := ConfigFile.new()
	config.load(SETTINGS_FILE_PATH)
	config.set_value("settings", "volume", volume)
	config.save(SETTINGS_FILE_PATH)


func get_volume() -> float:
	var bus_index := AudioServer.get_bus_index("Master")
	return db_to_linear(AudioServer.get_bus_volume_db(bus_index))


func _apply_volume(volume: float) -> void:
	var bus_index := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(volume))


func reset_players() -> void:
	players.clear()
	_next_player_id = 0
	players_changed.emit()


func add_player(player_name: String, color: String) -> Dictionary:
	var resources := {}
	for r in RESOURCE_TYPES:
		resources[r] = 0
	var special := {}
	for r in SPECIAL_RESOURCE_TYPES:
		special[r] = 0
	var player := {
		"id": _next_player_id,
		"name": player_name,
		"color": color,
		"points": 0,
		"resources": resources,
		"special_resources": special,
		"has_own_parrot": true,
		"parrot_captured_by": -1,  # id du voleur, -1 = personne
	}
	_next_player_id += 1
	players.append(player)
	players_changed.emit()
	return player


func is_name_taken(player_name: String) -> bool:
	var normalized := player_name.strip_edges().to_lower()
	for p in players:
		if p["name"].to_lower() == normalized:
			return true
	return false


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

## pieces: Array de Dictionaries {color: String, rank: PieceRank, order: int}
## "order" = ordre chronologique de pose (le plus petit = posé en premier).
## Retourne la couleur que doit prendre la case selon la règle :
## priorité au rang le plus élevé (capitaine > second), puis à la pièce
## posée en premier parmi celles du rang le plus élevé.
func compute_case_color(pieces: Array) -> Color:
	if pieces.is_empty():
		return Color(0, 0, 0, 0)
	var max_rank: int = -1
	for p in pieces:
		max_rank = max(max_rank, p["rank"])
	var top_pieces := pieces.filter(func(p): return p["rank"] == max_rank)
	top_pieces.sort_custom(func(a, b): return a["order"] < b["order"])
	return COLOR_VALUES[top_pieces[0]["color"]]


## Retourne les positions relatives (centrées sur la case) pour "count" pièces.
func layout_positions_for_case(count: int) -> Array[Vector2]:
	var spacing := CASE_PIECE_RADIUS
	var vertical_offset := Vector2(0, CASE_PIECE_VERTICAL_OFFSET)
	match count:
		0: return []
		1: return [vertical_offset]
		2: return [Vector2(-spacing, 0) + vertical_offset, Vector2(spacing, 0) + vertical_offset]
		_:
			var positions: Array[Vector2] = []
			for i in range(count):
				var angle := -PI / 2.0 + i * (TAU / count)
				positions.append(Vector2(cos(angle), sin(angle)) * spacing + vertical_offset)
			return positions


func add_points(player_id: int, amount: int) -> void:
	for p in players:
		if p["id"] == player_id:
			p["points"] += amount
			break
	players_changed.emit()


func capture_parrot(capturer_id: int, victim_id: int) -> void:
	for p in players:
		if p["id"] == victim_id:
			p["parrot_captured_by"] = capturer_id
			break
	players_changed.emit()


func get_players_sorted_by_points() -> Array[Dictionary]:
	var sorted := players.duplicate()
	sorted.sort_custom(func(a, b): return a["points"] > b["points"])
	return sorted
