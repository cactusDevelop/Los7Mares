extends Node

## Phase de mise en place (GAME_RULES.txt, règle 5, étape 7) : chaque joueur
## lance simultanément 1 dé de combat (noir) + 1 dé d'exploration (blanc).
## Le jet le plus fort désigne le 1er joueur (marqueur doré). Comparaison :
## les dés noirs priment (canon > abordage > rien), puis les dés blancs
## départagent (2 étoiles > 1 étoile > rien). En cas d'égalité totale, on
## relance uniquement entre les joueurs à égalité. Le dernier joueur
## (le plus faible jet) reçoit 1 fortune.
##
## Réutilise le sous-système de dés 3D physiques (dice_roll_3d.gd,
## dice_3d.gd, dice_white_3d.gd) via le noeud DiceRoll3D déjà présent dans
## board.tscn sous UI/SubViewportContainer/SubViewport, normalement masqué
## et affiché seulement pendant cette phase.

signal finished

const BLACK_DIE_SCENE := preload("res://scenes/effects/dice_3d.tscn")
const WHITE_DIE_SCENE := preload("res://scenes/effects/dice_white_3d.tscn")

## Force relative des faces, du plus faible au plus fort.
const BLACK_RANK: Dictionary = {"vide": 0, "abordage": 1, "canon": 2}
const WHITE_RANK: Dictionary = {"vide": 0, "un": 1, "double": 2}

const ROLL_PAUSE := 0.8

var _board: Board
var _viewport_container: Control
var _dice_roll: Node3D
var _rolls: Dictionary = {}  # player_id -> {"black": String, "white": String}


func start(board: Board) -> void:
	_board = board
	_viewport_container = board.get_node("UI/SubViewportContainer")
	_dice_roll = board.get_node("UI/SubViewportContainer/SubViewport/DiceRoll3D")
	_rolls.clear()

	var ids: Array[int] = []
	for p in GameFlow.players:
		ids.append(p["id"])

	_board.narration_box.say(tr("Tirage au sort du 1er joueur : chaque joueur lance 1 dé de combat et 1 dé d'exploration."))
	await _board.get_tree().create_timer(1.0).timeout
	var winner_id: int = await _resolve_winner_among(ids)
	GameFlow.set_first_player(winner_id)

	# Le "dernier joueur" de la règle 5.7 se lit sur le tout premier jet de
	# chacun (les relances ne servent qu'à départager les ex-aequo en tête) :
	# on le calcule donc sur la liste complète des joueurs, pas sur un
	# sous-groupe de relance.
	var loser_id := _worst_player(ids)
	if loser_id != -1 and loser_id != winner_id:
		_board._take_fortune_token_for(loser_id)

	var winner_name := _player_name(winner_id)
	_board.narration_box.say(tr("%s commence la partie !") % winner_name)
	await _board.get_tree().create_timer(1.2).timeout

	_viewport_container.visible = false
	finished.emit()


## Fait rouler les dés pour chaque joueur de player_ids, puis renvoie l'id
## du gagnant ; en cas d'égalité totale, relance uniquement entre les
## joueurs à égalité jusqu'à départage.
func _resolve_winner_among(player_ids: Array[int]) -> int:
	for pid in player_ids:
		await _roll_for_player(pid)

	var best_ids := _players_ranked_best(player_ids)
	if best_ids.size() > 1:
		_board.narration_box.say(tr("Égalité ! On relance entre les joueurs à égalité."))
		await _board.get_tree().create_timer(1.0).timeout
		var winner_id: int = await _resolve_winner_among(best_ids)
		return winner_id

	return best_ids[0]


func _roll_for_player(player_id: int) -> void:
	_viewport_container.visible = true
	_board.narration_box.say(tr("%s lance ses dés...") % _player_name(player_id))

	var results: Array[String] = await _throw_and_await()
	_rolls[player_id] = {"black": results[0], "white": results[1]}

	await _board.get_tree().create_timer(ROLL_PAUSE).timeout


func _throw_and_await() -> Array[String]:
	_dice_roll.roll_mixed([BLACK_DIE_SCENE, WHITE_DIE_SCENE])
	var results: Array[String] = await _dice_roll.roll_finished
	return results


## Renvoie l'id du/des joueur(s) au meilleur jet parmi player_ids (plusieurs
## en cas d'égalité totale).
func _players_ranked_best(player_ids: Array[int]) -> Array[int]:
	var best_black := -1
	var best_white := -1
	for pid in player_ids:
		var roll: Dictionary = _rolls[pid]
		var b: int = BLACK_RANK[roll["black"]]
		var w: int = WHITE_RANK[roll["white"]]
		if b > best_black or (b == best_black and w > best_white):
			best_black = b
			best_white = w
	var best: Array[int] = []
	for pid in player_ids:
		var roll: Dictionary = _rolls[pid]
		if BLACK_RANK[roll["black"]] == best_black and WHITE_RANK[roll["white"]] == best_white:
			best.append(pid)
	return best


## Renvoie l'id du joueur au jet le plus faible (règle : le dernier joueur
## de la comparaison reçoit 1 fortune). S'il y a égalité au plus bas, on en
## choisit un seul (le premier trouvé) : la règle ne prévoit pas de partage
## de cette fortune de compensation.
func _worst_player(player_ids: Array[int]) -> int:
	var worst_id := -1
	var worst_black := 99
	var worst_white := 99
	for pid in player_ids:
		var roll: Dictionary = _rolls[pid]
		var b: int = BLACK_RANK[roll["black"]]
		var w: int = WHITE_RANK[roll["white"]]
		if worst_id == -1 or b < worst_black or (b == worst_black and w < worst_white):
			worst_id = pid
			worst_black = b
			worst_white = w
	return worst_id


func _player_name(player_id: int) -> String:
	for p in GameFlow.players:
		if p["id"] == player_id:
			return p["name"]
	return "?"
