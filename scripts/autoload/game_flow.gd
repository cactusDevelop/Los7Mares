extends Node
class_name GameFlowManager

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
	"wool": "Toile", "rum": "Rhum", "fortune": "Fortune", "treasure": "Trésor",
}
## Les 3 pistes de cartes du plateau joueur (règle 3) : bleue = Exploration,
## rouge = Combat, brune = Commerce.
const CARD_TRACK_KEYS: Array[String] = ["exploration", "combat", "commerce"]
const CARD_TRACK_LABELS: Dictionary = {
	"exploration": "Exploration", "combat": "Combat", "commerce": "Commerce",
}
const CARD_TRACK_COLORS: Dictionary = {
	"exploration": Color(0.2, 0.45, 0.85),  # bleue
	"combat": Color(0.8, 0.2, 0.2),          # rouge
	"commerce": Color(0.55, 0.35, 0.2),      # brune
}
const PLAYER_BOARD_TEXTURES: Dictionary = {
	"rouge": "res://assets/art/board/plateau-joueur-rouge.png",
	"jaune": "res://assets/art/board/plateau-joueur-jaune.png",
	"bleu": "res://assets/art/board/plateau-joueur-bleu.png",
	"vert": "res://assets/art/board/plateau-joueur-vert.png",
	"violet": "res://assets/art/board/plateau-joueur-violet.png",
}
const RANDOM_NAMES: Array[String] = ["Thomas", "Adrien", "Martino", "Raphael", "Alex"]

const PARROT_TEXTURE_PATH := "res://assets/art/pieces/perro-%s.png"
const PARROT_TEXTURE_PATH_PRISON := "res://assets/art/pieces/perro-%s-prison.png"
const MARKER_TEXTURE_PATH := "res://assets/art/pieces/marqueur.png"
const BOAT_TEXTURE_PATH := "res://assets/art/pieces/bateau.png"
const HULL_PLANKS_START := 7

## Niveau 1 par défaut, jusqu'à 4 améliorations possibles -> niveau max 5
## (règle 3 : plateau joueur, voile ET armes suivent la même progression).
const SHIP_LEVEL_MIN := 1
const SHIP_LEVEL_MAX := 5

## Coût pour atteindre chaque niveau (bois + toile pour la voile, bois +
## acier pour les armes), indexé par niveau visé (2 à 5) - règle 9.
const UPGRADE_COST_BY_LEVEL: Dictionary = {
	2: {"wood": 1, "other": 1},
	3: {"wood": 1, "other": 2},
	4: {"wood": 1, "other": 3},
	5: {"wood": 1, "other": 4},
}

enum PionRank { OFFICER = 0, CAPTAIN = 1 }

const TITLE_SCENE_PATH := "res://scenes/ui/title_screen.tscn"
const BOARD_SCENE_PATH := "res://scenes/board/board.tscn"

var pending_setup_mode: String = ""
var pending_setup_target_count: int = 1
var is_debug_mode: bool = false

var players: Array[Dictionary] = []

var _next_player_id: int = 0

var is_continuing: bool = false
var _pending_board_data: Dictionary = {}
var round_number: int = 0


func _ready() -> void:
	# Par défaut, Godot ferme l'application dès que la fenêtre est fermée
	# (bouton "X", Alt+F4) sans laisser la moindre chance de sauvegarder.
	# On désactive ce comportement automatique pour pouvoir écrire la
	# sauvegarde nous-mêmes juste avant de quitter réellement.
	get_tree().set_auto_accept_quit(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_players()
		get_tree().quit()


## Resauvegarde uniquement la liste des joueurs (donc leur inventaire :
## positions des ressources, jetons, planches...) dans le fichier de
## sauvegarde existant, sans attendre le prochain autosave de phase de jeu.
func save_players() -> void:
	SaveManager.update_players(players)


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
	var card_tracks := {}
	for t in CARD_TRACK_KEYS:
		card_tracks[t] = []  # Array de {"title": String, "sea_key": String} (sérialisable en JSON)
	var player := {
		"id": _next_player_id,
		"name": player_name,
		"color": color,
		"points": 0,
		"resources": resources,
		"special_resources": special,
		"card_tracks": card_tracks,
		"has_own_parrot": true,
		"parrot_captured_by": -1,
		"hull_planks": HULL_PLANKS_START,
		"is_first_player": false,
		"sail_level": 1,
		"arms_level": 1,
		"boat_sea": "",
	}
	_next_player_id += 1
	players.append(player)
	players_changed.emit()
	return player


## Ajoute une carte (résumé sérialisable : titre + mer d'origine, pas la
## Resource GameCard elle-même — JSON.stringify ne sait pas sérialiser les
## Resources, cf save_manager.gd) à une piste du joueur (règle 10).
func add_card_to_track(player: Dictionary, track_key: String, card: GameCard) -> void:
	if not CARD_TRACK_KEYS.has(track_key):
		return
	player["card_tracks"][track_key].append({
		"title": card.title, "sea_key": card.sea_key, "card_type": card.card_type,
	})
	players_changed.emit()


func track_card_count(player: Dictionary, track_key: String) -> int:
	return player.get("card_tracks", {}).get(track_key, []).size()


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

	if players.size() >= 1:
		for res_type in RESOURCE_TYPES:
			players[0]["resources"][res_type] = 1
		players[0]["special_resources"]["fortune"] = 3
		players[0]["special_resources"]["treasure"] = 3
		_debug_seed_card_tracks(players[0])
	if players.size() >= 2:
		players[1]["has_own_parrot"] = false
		players[1]["parrot_captured_by"] = players[0]["id"]


## Mode DEBUG uniquement : donne au premier joueur 3 cartes dans chacune des
## 3 pistes (Exploration/Combat/Commerce), en piochant dans le catalogue les
## cartes qui déclarent cette piste parmi leurs possible_tracks (répétées si
## le catalogue n'en contient pas assez, faute de contenu final).
func _debug_seed_card_tracks(player: Dictionary) -> void:
	var catalog_cards: Array[GameCard] = CardCatalog.build_cards()
	for track in CARD_TRACK_KEYS:
		var matching := catalog_cards.filter(
			func(c: GameCard) -> bool: return c.possible_tracks.has(track)
		)
		for i in range(3):
			if matching.is_empty():
				add_card_to_track(player, track, GameCard.new())
			else:
				add_card_to_track(player, track, matching[i % matching.size()])


func go_to_title() -> void:
	get_tree().change_scene_to_file(TITLE_SCENE_PATH)


func go_to_board() -> void:
	get_tree().change_scene_to_file(BOARD_SCENE_PATH)


## Détermine si la pose d'un pion sur un emplacement d'action rend l'action
## FORTE (principale) ou FAIBLE (réduite), selon la règle 4 du plateau action :
## - Fort : emplacement vide, OU on y pose son capitaine alors qu'il n'y a
##   là que des officiers adverses (aucun capitaine adverse).
## - Faible : on y pose son officier (peu importe ce qui s'y trouve déjà),
##   OU on y pose son capitaine alors qu'un capitaine adverse y est déjà.
## existing_pions doit être l'état de la case AVANT la pose (cf
## action_spot.get_pions_snapshot appelé avant add_pion).
func compute_placement_strength(existing_pions: Array, placed_rank: int) -> bool:
	if existing_pions.is_empty():
		return true
	if placed_rank == PionRank.OFFICER:
		return false
	for p in existing_pions:
		if p["rank"] == PionRank.CAPTAIN:
			return false
	return true


func compute_case_color(pions: Array) -> Color:
	if pions.is_empty():
		return Color(0, 0, 0, 0)
	var max_rank: int = -1
	for p in pions:
		max_rank = max(max_rank, p["rank"])
	var top_pions := pions.filter(func(p): return p["rank"] == max_rank)
	top_pions.sort_custom(func(a, b): return a["order"] < b["order"])
	return COLOR_VALUES[top_pions[0]["color"]]


## Range count éléments en cercle autour d'un centre (utilisé pour les
## pièces sur les action spots ET, avec un spacing différent, pour les
## bateaux regroupés sur une même mer, cf board.gd _relayout_boats).
func layout_positions_for_case(count: int, spacing: float = UiTheme.CASE_PION_RADIUS, vertical_offset: Vector2 = Vector2(0, UiTheme.CASE_PION_VERTICAL_OFFSET)) -> Array[Vector2]:
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


func set_first_player(player_id: int) -> void:
	for p in players:
		p["is_first_player"] = (p["id"] == player_id)
	players_changed.emit()


func advance_first_player() -> void:
	if players.is_empty():
		return
	var current_index := -1
	for i in range(players.size()):
		if players[i].get("is_first_player", false):
			current_index = i
			break
	var next_index := 0 if current_index == -1 else (current_index + 1) % players.size()
	set_first_player(players[next_index]["id"])


func get_first_player_id() -> int:
	for p in players:
		if p.get("is_first_player", false):
			return p["id"]
	return -1


func get_last_player_id() -> int:
	var first_index := -1
	for i in range(players.size()):
		if players[i].get("is_first_player", false):
			first_index = i
			break
	if first_index == -1 or players.is_empty():
		return -1
	var last_index := (first_index - 1 + players.size()) % players.size()
	return players[last_index]["id"]


func start_new_game() -> void:
	SaveManager.delete()
	is_continuing = false
	round_number = 0


func continue_game() -> void:
	var data := SaveManager.read()
	if data.is_empty():
		return
	reset_players()
	for p in data.get("players", []):
		players.append(p)
	_next_player_id = data.get("next_player_id", players.size())
	is_debug_mode = data.get("is_debug_mode", false)
	pending_setup_mode = ""
	is_continuing = true
	_pending_board_data = data.get("board", {})
	players_changed.emit()
	go_to_board()


func take_pending_board_data() -> Dictionary:
	var d := _pending_board_data
	_pending_board_data = {}
	return d


func autosave(board_data: Dictionary) -> void:
	SaveManager.write({
		"players": players, "next_player_id": _next_player_id,
		"is_debug_mode": is_debug_mode, "board": board_data,
	})
