extends Node
class_name GameFlowManager

signal players_changed
## Émis quand le joueur "actif" (celui dont le plateau doit apparaître en bas,
## en grand, dans la disposition des plateaux joueurs) change. En mode local,
## ça suit le joueur dont c'est le tour (cf pion_placement_phase / hideout_phase
## qui appellent set_current_player). En mode héberger/rejoindre, ce n'est pas
## utilisé : voir board.gd, le joueur du PC reste toujours en bas.
signal current_player_changed(player_id: int)

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
const GEM_TEXTURE_PATH := "res://assets/art/pieces/gemme-%s.png"
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
const LOBBY_SCENE_PATH := "res://scenes/ui/lobby.tscn"

var pending_setup_mode: String = ""
var pending_setup_target_count: int = 1
var is_debug_mode: bool = false

## Mode de la partie en cours, fixé une fois pour toutes au lancement du
## plateau (cf board.gd _ready, à partir de pending_setup_mode) : "local"
## (partie locale, le joueur actif change à chaque tour), "host" ou "join"
## (partie en réseau : pas de vrai réseau implémenté pour l'instant, donc un
## seul joueur existe réellement - le joueur du PC reste toujours affiché
## en bas).
var game_mode: String = "local"

## Id du joueur "actif" en mode local (voir current_player_changed). -1 tant
## qu'aucun tour n'a encore commencé.
var current_player_id: int = -1

var players: Array[Dictionary] = []

var _next_player_id: int = 0

var is_continuing: bool = false
var _pending_board_data: Dictionary = {}
var round_number: int = 0

## Graine RNG partagée pour le mélange des tuiles mer (board._ready), fixée
## par l'hôte au lancement de la partie (cf network_manager._start_game) pour
## que host et clients obtiennent le même ordre sans avoir à le transmettre.
## Ignorée en mode local/debug (chaque partie a un ordre aléatoire normal).
var board_seed: int = 0

## Id du joueur ayant remporté le combat final (règle 8, "Égalité au score
## final -> Combat final"), ou -1 si la partie ne s'est pas terminée sur
## une égalité (pas de combat final nécessaire).
var final_battle_winner_id: int = -1


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
		# Gemmes (règle 3/10) : sea_key -> true dès que la 1ère carte de cette
		# mer est collectée. Jetons bonus : sea_key -> {"active": bool}, créé
		# à la 2e carte de la mer, "active" repasse à true à chaque carte
		# suivante de cette mer ("rafraîchi") et à false après utilisation
		# (cf DEV_RULES_REFERENCE.txt section 10 "JETONS BONUS").
		"gems": {},
		"bonus_tokens": {},
		"hull_planks": HULL_PLANKS_START,
		"is_first_player": false,
		"sail_level": 1,
		"arms_level": 1,
		"boat_sea": "",
		# Jet du tirage au sort du 1er joueur (dé combat + dé exploration),
		# rempli par first_player_dice_phase.gd et affiché ensuite toute la
		# partie dans la popup DiceResultsPopup (voir board.gd). Vide tant
		# que le joueur n'a pas encore lancé ses dés.
		"dice_roll": {},
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


## Nombre de cartes déjà collectées par le joueur dans une mer donnée, toutes
## pistes confondues (utilisé par register_sea_progress juste après l'ajout
## de la carte qui vient d'être obtenue, donc le compte l'inclut déjà).
func sea_card_count(player: Dictionary, sea_key: String) -> int:
	var count := 0
	for track in CARD_TRACK_KEYS:
		for c in player.get("card_tracks", {}).get(track, []):
			if c.get("sea_key", "") == sea_key:
				count += 1
	return count


## Récompense de mer (règle 10.2), à appeler juste après add_card_to_track :
## - 1ère carte de la mer -> gemme.
## - 2e carte de la mer -> jeton bonus (créé, face "effet" visible).
## - 3e carte ou plus -> rafraîchit le jeton bonus déjà possédé (sinon rien,
##   ex: jeton déjà épuisé côté plateau - pas encore modélisé en détail).
## Renvoie "gem" / "token_new" / "token_refresh" / "none" pour que l'appelant
## puisse afficher le bon message.
func register_sea_progress(player: Dictionary, sea_key: String) -> String:
	if not player.has("gems"):
		player["gems"] = {}
	if not player.has("bonus_tokens"):
		player["bonus_tokens"] = {}

	var count: int = sea_card_count(player, sea_key)
	var result := "none"
	if count == 1:
		player["gems"][sea_key] = true
		result = "gem"
	elif count == 2:
		player["bonus_tokens"][sea_key] = {"active": true}
		result = "token_new"
	elif count >= 3 and player["bonus_tokens"].has(sea_key):
		player["bonus_tokens"][sea_key]["active"] = true
		result = "token_refresh"

	if result != "none":
		players_changed.emit()
	return result


## Index d'un joueur dans GameFlow.players (règle 3 : chaque sea_gem_pile
## colore/positionne ses gemmes dans ce même ordre, cf sea_gem_pile.setup) ;
## -1 si introuvable. Comparaison par "id" plutôt que par égalité de
## Dictionary pour rester correct même si l'appelant détient une copie.
func get_player_index(player: Dictionary) -> int:
	for i in range(players.size()):
		if players[i]["id"] == player.get("id", -1):
			return i
	return -1


## Retire un joueur de la partie : utilisé UNIQUEMENT pour une déconnexion
## pendant le lobby, avant le lancement de la partie (cf
## network_manager._handle_peer_left), pour ne pas laisser de "joueur
## fantôme" dans la liste d'attente ni bloquer le lancement de l'hôte.
## NE DOIT PAS être appelé une fois la partie commencée : les autres systèmes
## (plateaux, tour par tour, plateau action...) supposent que players ne
## rétrécit jamais en cours de partie (cf player_disconnected_ingame côté
## réseau, qui garde le joueur et prévient juste les autres à la place).
func remove_player_by_id(player_id: int) -> void:
	for i in range(players.size()):
		if players[i]["id"] == player_id:
			players.remove_at(i)
			players_changed.emit()
			return


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


## Renvoie le Dictionary du joueur d'id donné, ou {} si introuvable. Utilisé
## par network_manager.gd (_change_color) pour retrouver le joueur associé à
## un peer réseau avant de modifier sa couleur.
func get_player_by_id(player_id: int) -> Dictionary:
	for p in players:
		if p["id"] == player_id:
			return p
	return {}


## Change la couleur d'un joueur déjà inscrit (choix interactif depuis le
## menu d'attente host/join, cf lobby.gd _on_lobby_color_pressed), sans
## toucher au reste de ses données. Appelant responsable de vérifier au
## préalable que la couleur cible n'est pas déjà prise (cf
## network_manager._change_color).
func set_player_color(player_id: int, color: String) -> void:
	var player := get_player_by_id(player_id)
	if player.is_empty():
		return
	player["color"] = color
	players_changed.emit()


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
		for sea_key in SeaDecks.SEA_KEYS:
			players[0]["gems"][sea_key] = true
		_debug_seed_card_tracks(players[0])
	if players.size() >= 2:
		players[1]["has_own_parrot"] = false
		players[1]["parrot_captured_by"] = players[0]["id"]


## Mode DEBUG uniquement : donne au premier joueur des cartes dans les 3
## pistes (Exploration/Combat/Commerce, règle 3), en piochant dans le
## catalogue les cartes qui déclarent cette piste parmi leurs
## possible_tracks (répétées si le catalogue n'en contient pas assez, faute
## de contenu final). Quantités différentes par piste (utile pour tester
## l'affichage de piles de tailles variées) : 5 en exploration, 3 en combat,
## 1 en commerce.
const DEBUG_CARD_COUNTS := {"exploration": 5, "combat": 3, "commerce": 1}

func _debug_seed_card_tracks(player: Dictionary) -> void:
	var catalog_cards: Array[GameCard] = CardCatalog.build_cards()
	for track in CARD_TRACK_KEYS:
		var matching := catalog_cards.filter(
			func(c: GameCard) -> bool: return c.possible_tracks.has(track)
		)
		var count: int = DEBUG_CARD_COUNTS.get(track, 3)
		for i in range(count):
			if matching.is_empty():
				add_card_to_track(player, track, GameCard.new())
			else:
				add_card_to_track(player, track, matching[i % matching.size()])


func go_to_title() -> void:
	save_players()
	call_deferred("_deferred_change_scene", TITLE_SCENE_PATH)


func go_to_board() -> void:
	call_deferred("_deferred_change_scene", BOARD_SCENE_PATH)


func go_to_lobby() -> void:
	call_deferred("_deferred_change_scene", LOBBY_SCENE_PATH)


## Remplace players par l'état reçu de l'hôte (mode réseau, cf
## network_manager._sync_lobby_state). Contrairement à add_player, ne touche
## pas à _next_player_id : seul l'hôte ajoute des joueurs, les clients ne
## font qu'afficher l'état reçu.
func set_players_from_network(data: Array) -> void:
	# copie profonde impérative : en call_local (l'hôte se synchronisant
	# lui-même), "data" est la MÊME référence mémoire que "players" (pas de
	# sérialisation réseau réelle en local) — players.clear() sans copie
	# viderait aussi "data" avant la boucle de réinjection ci-dessous.
	# Bug confirmé par test réel (2 process headless host+client) : sans ce
	# fix, la liste de l'hôte redevenait vide après CHAQUE synchro.
	var copy: Array = data.duplicate(true)
	players.clear()
	for p in copy:
		players.append(p)
	players_changed.emit()


## Diffère change_scene_to_file (cf go_to_title/go_to_board) : évite de
## libérer la scène courante (et ses éventuelles Window/ConfirmationDialog
## encore en train de se fermer, elles-mêmes des Viewport) pendant qu'un
## évènement d'input est encore en cours de propagation ce qui provoquait
## "_push_unhandled_input_internal: Condition !is_inside_tree() is true".
func _deferred_change_scene(path: String) -> void:
	get_tree().change_scene_to_file(path)


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


## Points de gloire par niveau de voile/armes (règle 8, niveau 1 = 0 pt).
const SAIL_ARMS_POINTS: Dictionary = {1: 0, 2: 1, 3: 3, 4: 5, 5: 7}

## Calcule le détail du score final d'un joueur (règle 8 "Points de
## gloire"). Catégories couvertes : trésors, fortunes, voile, armes,
## planches, ressources, perroquets, pistes de cartes, gemmes, jetons bonus.
func compute_final_score_breakdown(player: Dictionary) -> Dictionary:
	var breakdown := {}
	breakdown["treasures"] = player["special_resources"].get("treasure", 0) * 2
	breakdown["fortunes"] = int(player["special_resources"].get("fortune", 0) / 2)
	breakdown["sail"] = SAIL_ARMS_POINTS.get(player.get("sail_level", SHIP_LEVEL_MIN), 0)
	breakdown["arms"] = SAIL_ARMS_POINTS.get(player.get("arms_level", SHIP_LEVEL_MIN), 0)

	var planks: int = player.get("hull_planks", 0)
	breakdown["planks"] = 3 if planks == HULL_PLANKS_START else (1 if planks >= 5 else 0)

	var total_resources := 0
	for r in RESOURCE_TYPES:
		total_resources += player["resources"].get(r, 0)
	breakdown["resources"] = int(total_resources / 3.0)

	var parrot_points := 0
	if player.get("has_own_parrot", true):
		parrot_points += 2
	for p in players:
		if p.get("parrot_captured_by", -1) == player["id"]:
			parrot_points += 1
	breakdown["parrots"] = parrot_points

	var track_points := 0
	for track in CARD_TRACK_KEYS:
		track_points += _card_track_points(player, track)
	breakdown["card_tracks"] = track_points

	# Gemmes (règle 8.1) : 2 pts/gemme, +2 bonus si les 7 mers sont collectées.
	var gem_count: int = player.get("gems", {}).size()
	breakdown["gems"] = gem_count * 2 + (2 if gem_count >= SeaDecks.SEA_KEYS.size() else 0)
	# Jetons bonus (règle 8.8) : 1 pt chacun, utilisé ou non.
	breakdown["bonus_tokens"] = player.get("bonus_tokens", {}).size()

	return breakdown


## Points de classement d'un joueur sur une piste donnée (règle 8, point
## 10) : rang = nombre de joueurs STRICTEMENT mieux classés (pas la
## position dans l'ordre de jeu), donc les égalités partagent le même rang
## et décalent les places suivantes sans jamais sauter de palier.
func _card_track_points(player: Dictionary, track_key: String) -> int:
	var my_count: int = track_card_count(player, track_key)
	var rank := 0
	for p in players:
		if track_card_count(p, track_key) > my_count:
			rank += 1
	return _rank_points(rank, players.size())


func _rank_points(rank: int, player_count: int) -> int:
	match rank:
		0: return player_count
		1: return max(player_count - 2, 0)
		2: return max(player_count - 4, 0)
		_: return 0


func compute_final_score_total(player: Dictionary) -> int:
	var total := 0
	for value in compute_final_score_breakdown(player).values():
		total += value
	return total


## Calcule et affecte le score final de tous les joueurs (règle 8),
## appelé une seule fois à la fin de la partie (board._end_game).
func apply_final_scores() -> void:
	for p in players:
		p["points"] = compute_final_score_total(p)
	players_changed.emit()


func get_players_sorted_by_points() -> Array[Dictionary]:
	var sorted := players.duplicate()
	sorted.sort_custom(func(a, b): return a["points"] > b["points"])
	return sorted


## Change le joueur "actif" affiché en bas/en grand dans la disposition des
## plateaux (board.gd). N'a d'effet visible qu'en mode local : voir
## current_player_changed.
func set_current_player(player_id: int) -> void:
	if current_player_id == player_id:
		return
	current_player_id = player_id
	current_player_changed.emit(player_id)


const DICE_BLACK_LABELS: Dictionary = {"vide": "Combat vide", "abordage": "Abordage", "canon": "Canon"}
const DICE_WHITE_LABELS: Dictionary = {"vide": "Exploration vide", "un": "1 étoile", "double": "2 étoiles"}

## Libellé lisible d'un jet de dés {"black": ..., "white": ...} (tirage au
## sort du 1er joueur), utilisé par DiceResultsPopup. Renvoie une chaîne vide
## si le joueur n'a pas encore lancé ses dés (roll vide ou absent).
func describe_dice_roll(roll: Dictionary) -> String:
	if roll.is_empty():
		return ""
	return "%s — %s" % [
		DICE_BLACK_LABELS.get(roll.get("black", ""), "?"),
		DICE_WHITE_LABELS.get(roll.get("white", ""), "?"),
	]


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
	final_battle_winner_id = -1


func continue_game() -> void:
	var data := SaveManager.read()
	if data.is_empty():
		return
	# Filet de sécurité pour d'anciennes sauvegardes (avant le correctif
	# ci-dessus dans autosave()) qui contiendraient encore une partie en
	# ligne : impossible à reprendre sans MultiplayerPeer actif, donc on
	# supprime la sauvegarde plutôt que de planter au premier RPC.
	var saved_mode: String = data.get("game_mode", "local")
	if saved_mode == "host" or saved_mode == "join":
		SaveManager.delete()
		return
	reset_players()
	for p in data.get("players", []):
		players.append(p)
	_next_player_id = data.get("next_player_id", players.size())
	is_debug_mode = data.get("is_debug_mode", false)
	game_mode = data.get("game_mode", "local")
	pending_setup_mode = ""
	is_continuing = true
	_pending_board_data = data.get("board", {})
	players_changed.emit()
	go_to_board()


func take_pending_board_data() -> Dictionary:
	var d := _pending_board_data
	_pending_board_data = {}
	return d


## Ne sauvegarde JAMAIS une partie en ligne (game_mode "host"/"join") : la
## reprendre plus tard depuis "Continuer" au title screen n'a aucun
## MultiplayerPeer actif (pas d'hôte/pair reconnecté), ce qui fait planter
## le jeu au premier appel RPC (ex: hideout_phase._request_claim_spot_rpc).
## Seules les parties locales/solo/debug sont sauvegardées.
func autosave(board_data: Dictionary) -> void:
	if game_mode == "host" or game_mode == "join":
		return
	SaveManager.write({
		"players": players, "next_player_id": _next_player_id,
		"is_debug_mode": is_debug_mode, "game_mode": game_mode, "board": board_data,
	})
