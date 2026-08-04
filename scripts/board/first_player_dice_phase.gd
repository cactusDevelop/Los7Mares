extends Node

## Phase de mise en place (DEV_RULES_REFERENCE.txt, règle 5, étape 7) : chaque joueur
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

## Mis à true par le bouton debug "Passer" (réutilisé ici, cf
## board._on_debug_skip_button_pressed) : abandonne tous les lancers de dés
## restants et garde l'ordre par défaut des joueurs (players[0] devient le
## 1er joueur), sans jeton fortune de compensation puisqu'aucun jet n'a
## réellement départagé qui que ce soit.
var _skip_requested: bool = false


func start(board: Board) -> void:
	_board = board
	_viewport_container = board.get_node("UI/SubViewportContainer")
	_dice_roll = board.get_node("UI/SubViewportContainer/SubViewport/DiceRoll3D")
	_rolls.clear()
	_skip_requested = false

	var ids: Array[int] = []
	for p in GameFlow.players:
		ids.append(p["id"])

	# board.gd connecte déjà _on_debug_skip_button_pressed en permanence
	# (utilisé pendant la pose de pions) : on le débranche temporairement
	# pour brancher notre propre gestionnaire, sans quoi les deux
	# réagiraient au même clic pendant cette phase.
	_board.debug_skip_button.visible = GameFlow.is_debug_mode
	if _board.debug_skip_button.pressed.is_connected(_board._on_debug_skip_button_pressed):
		_board.debug_skip_button.pressed.disconnect(_board._on_debug_skip_button_pressed)
	_board.debug_skip_button.pressed.connect(_on_skip_pressed)

	_board.narration_box.say(tr("Tirage au sort du 1er joueur : chaque joueur clique pour lancer 1 dé de combat et 1 dé d'exploration."))
	await _board.narration_box.wait_for_click()

	var winner_id: int
	var loser_id: int = -1
	if _skip_requested:
		winner_id = ids[0]
	else:
		winner_id = await _resolve_winner_among(ids)
		# _skip_requested a pu devenir vrai PENDANT l'await ci-dessus (clic sur
		# "Passer" en cours de lancer) : dans ce cas _rolls est incomplet (les
		# joueurs pas encore arrivés à leur tour n'y figurent pas du tout), donc
		# _worst_player planterait (accès à une entrée absente du dictionnaire).
		if not _skip_requested:
			# Le "dernier joueur" de la règle 5.7 se lit sur le tout premier
			# jet de chacun (les relances ne servent qu'à départager les
			# ex-aequo en tête) : on le calcule donc sur la liste complète des
			# joueurs, pas sur un sous-groupe de relance.
			loser_id = _worst_player(ids)
	GameFlow.set_first_player(winner_id)
	GameFlow.set_current_player(winner_id)

	# Règle 5.7 : "le dernier joueur reçoit 1 fortune" - un jeton de
	# compensation général, PAS un des 7 jetons dorés du plateau action (ceux-là
	# comptent les manches restantes et ne doivent être pris qu'en fin de
	# manche, règle 4/7 : _take_fortune_token_for est réservé à _start_round).
	if not _skip_requested and loser_id != -1 and loser_id != winner_id:
		for p in GameFlow.players:
			if p["id"] == loser_id:
				p["special_resources"]["fortune"] += 1
				break
		GameFlow.players_changed.emit()

	_board.debug_skip_button.pressed.disconnect(_on_skip_pressed)
	_board.debug_skip_button.visible = false
	_board.debug_skip_button.pressed.connect(_board._on_debug_skip_button_pressed)

	var winner_name := _player_name(winner_id)
	_board.narration_box.say(tr("%s commence la partie !") % winner_name)
	await _board.narration_box.wait_for_click()

	_viewport_container.visible = false
	finished.emit()


## Débloque immédiatement l'attente en cours (clic sur "Lancer les dés" du
## joueur courant, cf _roll_for_player) : émettre option_selected avec un id
## quelconque suffit, _roll_for_player vérifie _skip_requested avant de
## regarder quel bouton a été cliqué.
func _on_skip_pressed() -> void:
	_skip_requested = true
	_board.narration_box.set_options([])
	_board.narration_box.option_selected.emit("skip")
	_board.narration_box.request_advance()


## Fait rouler les dés pour chaque joueur de player_ids, puis renvoie l'id
## du gagnant ; en cas d'égalité totale, relance uniquement entre les
## joueurs à égalité jusqu'à départage.
func _resolve_winner_among(player_ids: Array[int]) -> int:
	for pid in player_ids:
		await _roll_for_player(pid)
		if _skip_requested:
			return player_ids[0]

	var best_ids := _players_ranked_best(player_ids)
	if best_ids.size() > 1:
		_board.narration_box.say(tr("Égalité (%s) ! On relance entre les joueurs à égalité.") % _describe_roll(_rolls[best_ids[0]]))
		await _board.narration_box.wait_for_click()
		var winner_id: int = await _resolve_winner_among(best_ids)
		return winner_id

	return best_ids[0]


## Libellé lisible d'un jet (combat + exploration), utilisé pour rendre
## l'annonce d'égalité vérifiable : les 3 faces "canon" du dé noir (par ex.)
## sont bien strictement équivalentes entre elles selon la règle, donc 2
## joueurs peuvent tomber sur des faces physiquement différentes tout en
## ayant un jet réellement à égalité - ceci permet de le confirmer d'un
## coup d'œil plutôt que de devoir deviner.
func _describe_roll(roll: Dictionary) -> String:
	var black_labels := {"vide": tr("combat vide"), "abordage": tr("abordage"), "canon": tr("canon")}
	var white_labels := {"vide": tr("exploration vide"), "un": tr("1 étoile"), "double": tr("2 étoiles")}
	return "%s, %s" % [black_labels[roll["black"]], white_labels[roll["white"]]]


## Attend un clic du joueur concerné sur "Lancer les dés" (1 clic = son
## propre lancer, règle 5.7 : chaque joueur lance ses 2 dés à tour de rôle
## dans l'implémentation, le résultat restant équivalent à un lancer
## simultané puisque rien ne dépend de l'ordre entre joueurs). Si le bouton
## debug "Passer" est cliqué entre-temps, renvoie immédiatement sans lancer
## (résultat "vide" placeholder, ignoré car _skip_requested court-circuite
## le classement dans start()).
func _roll_for_player(player_id: int) -> void:
	if _skip_requested:
		_rolls[player_id] = {"black": "vide", "white": "vide"}
		return

	_viewport_container.visible = true
	GameFlow.set_current_player(player_id)
	_board.narration_box.say_with_player(tr("Tour de %s : clique sur \"Lancer les dés\"."), _find_player(player_id))
	_board.narration_box.set_options([{"id": "roll", "label": tr("Lancer les dés")}])
	await _board.narration_box.option_selected
	_board.narration_box.set_options([])

	if _skip_requested:
		_rolls[player_id] = {"black": "vide", "white": "vide"}
		return

	_board.narration_box.say(tr("%s lance ses dés...") % _player_name(player_id))
	var results: Array[String] = await _throw_and_await()
	_rolls[player_id] = {"black": results[0], "white": results[1]}
	# Mémorisé directement sur le joueur (pas seulement dans _rolls, qui est
	# local à cette phase) pour rester affichable toute la partie dans la
	# popup DiceResultsPopup (cf board.gd).
	var player := _find_player(player_id)
	if not player.is_empty():
		player["dice_roll"] = _rolls[player_id].duplicate()
		GameFlow.players_changed.emit()

	await _board.get_tree().create_timer(ROLL_PAUSE).timeout


func _throw_and_await() -> Array[String]:
	var scenes: Array[PackedScene] = [BLACK_DIE_SCENE, WHITE_DIE_SCENE]
	# Réseau : seul l'hôte fait réellement tourner la simulation physique,
	# le résultat est ensuite le même pour tout le monde (cf Board.roll_dice_synced).
	return await _board.roll_dice_synced(_dice_roll, scenes)


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


func _find_player(player_id: int) -> Dictionary:
	for p in GameFlow.players:
		if p["id"] == player_id:
			return p
	return {}
