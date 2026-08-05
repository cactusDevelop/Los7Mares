extends Node

signal finished

const CAPTAIN_SCENE := preload("res://scenes/board/pions/captain_pion.tscn")
const OFFICER_SCENE := preload("res://scenes/board/pions/officer_pion.tscn")
const DEBUG_TOTAL_ROUNDS := 7

var _board: Board
var _current_round: int = 0
var _current_player_index: int = 0
var _turn_order: Array[int] = []  # turn_order[step] = index dans GameFlow.players
var _selected_rank: int = -1
var _placed_rank_by_player: Dictionary = {}
var _debug_round_index := 0
var _resolving_action := false
var _round_transitioning := false
## Vrai une fois _end_pion_placement_phase() atteint (les 2 cycles de tours
## de la manche sont posés) : empêche force_skip() de recommencer à poser
## des pions si le bouton debug "Passer" est encore actif après coup (ex :
## partie terminée entre-temps, cf board._on_debug_skip_button_pressed).
## Sans ce garde-fou, _begin_player_pion_turn() remet _current_player_index
## à 0 juste avant d'appeler _end_pion_placement_phase(), ce qui fait croire
## à force_skip() qu'une nouvelle manche recommence.
var _finished := false


## Ordre de tour clockwise en partant du vrai 1er joueur (marqueur doré),
## au lieu de l'index 0 fixe dans GameFlow.players.
func _compute_turn_order() -> Array[int]:
	var n: int = GameFlow.players.size()
	var first_id: int = GameFlow.get_first_player_id()
	var first_index: int = 0
	for i in range(n):
		if GameFlow.players[i]["id"] == first_id:
			first_index = i
			break
	var order: Array[int] = []
	for i in range(n):
		order.append((first_index + i) % n)
	return order


## Raccourci vers le joueur courant (règle 6) : GameFlow.players[_turn_order[_current_player_index]].
func _current_player() -> Dictionary:
	return GameFlow.players[_turn_order[_current_player_index]]


func start(board: Board) -> void:
	_board = board
	_board.debug_skip_button.visible = GameFlow.is_debug_mode
	_current_round = 0
	_current_player_index = 0
	_turn_order = _compute_turn_order()
	_placed_rank_by_player.clear()
	_resolving_action = false
	_finished = false

	for spot in _board.action_spots_container.get_children():
		spot.clear_pions()
		if not spot.spot_clicked.is_connected(_on_action_spot_clicked):
			spot.spot_clicked.connect(_on_action_spot_clicked)
		spot.set_hover_enabled(true)
	if not _board.pion_selection_panel.pion_selected.is_connected(_on_pion_selected):
		_board.pion_selection_panel.pion_selected.connect(_on_pion_selected)
	if not _board.pion_selection_panel.pion_drag_ended.is_connected(_on_pion_drag_ended):
		_board.pion_selection_panel.pion_drag_ended.connect(_on_pion_drag_ended)
	if not _board.pion_selection_panel.pion_drag_started.is_connected(_on_pion_drag_started):
		_board.pion_selection_panel.pion_drag_started.connect(_on_pion_drag_started)
	if not _board.pion_selection_panel.pion_drag_stopped.is_connected(_on_pion_drag_stopped):
		_board.pion_selection_panel.pion_drag_stopped.connect(_on_pion_drag_stopped)

	_begin_player_pion_turn()


## Vrai si CET écran doit pouvoir sélectionner/poser un pion pour le tour en
## cours : toujours vrai en partie locale/hotseat, sinon seulement pour
## l'écran du joueur dont c'est réellement le tour.
func _can_local_player_act() -> bool:
	if GameFlow.game_mode != "host" and GameFlow.game_mode != "join":
		return true
	var my_player_id: int = Network.peer_player_map.get(multiplayer.get_unique_id(), -1)
	return my_player_id == _current_player()["id"]


## Affiche le panneau de sélection de pièce + recadre la caméra sur la zone
## de sélection uniquement quand un tour va effectivement suivre (si la
## phase se termine à la place, on reste sur la vue par défaut : cf le
## "return" avant ces lignes).
func _begin_player_pion_turn() -> void:
	if _current_player_index >= GameFlow.players.size():
		_current_player_index = 0
		_current_round += 1
		if _current_round > 1:
			_end_pion_placement_phase()
			return

	var player: Dictionary = _current_player()
	GameFlow.set_current_player(player["id"])
	var color: Color = GameFlow.COLOR_VALUES[player["color"]]
	_selected_rank = -1
	var can_act := _can_local_player_act()

	# Le panneau de sélection de pièce + le recadrage caméra ne concernent
	# QUE l'écran du joueur actif : les autres gardent la vue normale du
	# plateau (ils ne font qu'observer ce tour), cf énoncé "chaque joueur a
	# le contrôle sur les actions qui le concernent".
	if can_act:
		_board.pion_selection_panel.show_for_placement_phase()
	else:
		_board.pion_selection_panel.hide_panel()
	_shift_camera_for_selection(can_act)

	for spot in _board.action_spots_container.get_children():
		spot.set_hover_enabled(can_act)

	if player.get("hull_planks", GameFlow.HULL_PLANKS_START) <= 0:
		await _repair_capsized_boat(player)

	if _current_round == 0:
		_board.narration_box.say_for_actor(
			tr("Choisis le pion à jouer (capitaine ou officier)."),
			tr("%s choisit le pion à jouer (capitaine ou officier)."),
			player
		)
		if can_act:
			_board.pion_selection_panel.setup_for_player(color, -1)
	else:
		var placed_rank: int = _placed_rank_by_player[_current_player_index]
		var forced_rank: int = GameFlow.PionRank.OFFICER if placed_rank == GameFlow.PionRank.CAPTAIN else GameFlow.PionRank.CAPTAIN
		_board.narration_box.say_for_actor(
			tr("Place ta dernière pièce."), tr("%s place sa dernière pièce."), player
		)
		if can_act:
			_board.pion_selection_panel.setup_for_player(color, forced_rank)


## Rafistoler son bateau (règle 6, étape 1) : "ssi chaviré" (0 planche), en
## tout DÉBUT de tour, avant même de choisir son action. Redresse le bateau
## et donne +3 planches automatiquement (aucun choix pour le joueur).
func _repair_capsized_boat(player: Dictionary) -> void:
	player["hull_planks"] = 3
	GameFlow.players_changed.emit()
	_board.narration_box.say_for_actor(
		tr("Contre toute attente, votre équipage maintient le bateau à flot !") +
		tr("\n\nLe bateau chaviré est redressé, +3 planches."),
		tr("Contre toute attente, l'équipage de %s maintient le bateau à flot !") +
		tr("\n\nLe bateau chaviré est redressé, +3 planches."),
		player
	)
	await _board.narration_box.wait_for_continue()


func _on_pion_selected(rank: int) -> void:
	_selected_rank = rank


## Teinte toutes les cases d'action avec la couleur du joueur courant dès
## qu'il commence à draguer une pièce, pour bien montrer où elle va
## atterrir au survol (en plus du zoom habituel, cf action_spot.gd
## set_drag_hover_color).
func _on_pion_drag_started(_rank: int) -> void:
	var player: Dictionary = _current_player()
	var color: Color = GameFlow.COLOR_VALUES[player["color"]]
	for spot in _board.action_spots_container.get_children():
		spot.set_drag_hover_color(color)


## Retire la teinte de survol posée par _on_pion_drag_started, que le drag
## se soit terminé par une pose de pièce ou par un simple relâchement.
func _on_pion_drag_stopped() -> void:
	for spot in _board.action_spots_container.get_children():
		spot.set_drag_hover_color(null)


## Pose automatiquement la pièce du joueur courant sur la première case
## action libre (utilisé par le bouton debug "Passer"). Ne fait rien si une
## résolution d'action est déjà en cours (le bouton doit alors agir sur
## narration_box.skip() à la place, cf board.gd).
func force_skip() -> void:
	if _finished or _resolving_action or _round_transitioning or _current_player_index >= GameFlow.players.size():
		return
	if _selected_rank == -1:
		if _current_round == 0:
			_selected_rank = GameFlow.PionRank.CAPTAIN
		else:
			var placed_rank: int = _placed_rank_by_player[_current_player_index]
			_selected_rank = GameFlow.PionRank.OFFICER if placed_rank == GameFlow.PionRank.CAPTAIN else GameFlow.PionRank.CAPTAIN

	var player: Dictionary = _current_player()
	for spot in _board.action_spots_container.get_children():
		if not spot.has_player_pion(player["color"]):
			_on_action_spot_clicked(spot)
			return


## Fin d'un drag démarré dans le panneau et relâché hors de celui-ci
## (pion_selection_panel.gd). On ne pose la pièce que si la souris (pas le
## point-fantôme) touche la collision d'une case au moment du relâchement,
## repéré via action_spot.is_hovering() (même état que l'effet de zoom).
func _on_pion_drag_ended(rank: int) -> void:
	var spot := _find_hovered_spot()
	if spot == null:
		return
	_selected_rank = rank
	_on_action_spot_clicked(spot)


func _find_hovered_spot() -> Node2D:
	for spot in _board.action_spots_container.get_children():
		if spot.is_hovering():
			return spot
	return null


func _on_action_spot_clicked(spot: Node2D) -> void:
	if _selected_rank == -1 or _resolving_action or not _can_local_player_act():
		return

	var player: Dictionary = _current_player()

	if spot.has_player_pion(player["color"]):
		# Simple retour visuel local (pas de mutation d'état) : pas besoin
		# de passer par le réseau, seul l'écran du joueur actif peut de
		# toute façon arriver jusqu'ici (cf _can_local_player_act ci-dessus).
		_board.narration_box.say(tr("Tu ne peux pas poser tes deux pions sur la même case."))
		return

	var spot_index: int = spot.get_index()
	if GameFlow.game_mode == "host":
		_try_place_pion(spot_index, _selected_rank)
	elif GameFlow.game_mode == "join":
		_request_place_pion_rpc.rpc_id(1, spot_index, _selected_rank)
	else:
		_apply_pion_placement(spot_index, _selected_rank)


## Côté client (any_peer) : demande à l'hôte de valider la pose de pion.
@rpc("any_peer", "call_remote", "reliable")
func _request_place_pion_rpc(spot_index: int, rank: int) -> void:
	if not multiplayer.is_server():
		return
	# Cf hideout_phase._request_claim_spot_rpc : l'hôte peut recevoir cette
	# requête avant (ou après) avoir lui-même atteint localement cette phase
	# / ce tour (les écrans avancent chacun à leur rythme via des clics
	# locaux non synchronisés), auquel cas _turn_order serait vide ou
	# _current_player_index hors bornes. On ignore plutôt que de planter.
	if _turn_order.is_empty() or _current_player_index >= _turn_order.size():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if Network.peer_player_map.get(sender_id, -1) != _current_player()["id"]:
		return  # pas son tour (ou latence/désynchro) : on ignore silencieusement
	_try_place_pion(spot_index, rank)


## Hôte uniquement : revalide (case encore libre pour ce joueur) puis
## rediffuse la pose réelle à tout le monde.
func _try_place_pion(spot_index: int, rank: int) -> void:
	var spots := _board.action_spots_container.get_children()
	if spot_index < 0 or spot_index >= spots.size():
		return
	var spot: Node2D = spots[spot_index]
	var player: Dictionary = _current_player()
	if spot.has_player_pion(player["color"]):
		return
	_apply_pion_placement.rpc(spot_index, rank)


## Rejoué à l'identique sur chaque écran (call_local) : c'est le vrai corps
## de la pose de pion + résolution d'action qui suit (règle 6), inchangé par
## rapport à avant, seul le déclenchement est désormais réseau.
@rpc("authority", "call_local", "reliable")
func _apply_pion_placement(spot_index: int, rank: int) -> void:
	var spots := _board.action_spots_container.get_children()
	if spot_index < 0 or spot_index >= spots.size():
		return
	var spot: Node2D = spots[spot_index]
	var player: Dictionary = _current_player()

	# Snapshot AVANT la pose : la force (fort/faible) dépend de ce qui est
	# déjà présent sur la case au moment où ce pion y atterrit (règle 4).
	var existing_pions: Array = spot.get_pions_snapshot()
	var is_strong: bool = GameFlow.compute_placement_strength(existing_pions, rank)

	var pion_scene: PackedScene = CAPTAIN_SCENE if rank == GameFlow.PionRank.CAPTAIN else OFFICER_SCENE
	var pion: Node2D = pion_scene.instantiate()
	pion.modulate = GameFlow.COLOR_VALUES[player["color"]]
	pion.scale = Vector2.ONE * UiTheme.PION_SCALE
	spot.add_pion(pion, player["color"], rank)

	# Narration (règles mode avancé, règle 6) : emplacement fort = sang-froid,
	# emplacement faible = équipage démotivé.
	var placement_mine: String = tr("Vous gardez votre sang-froid et motivez votre équipage !") if is_strong \
		else tr("Vous n'arrivez pas à motiver votre équipage...")
	var placement_others: String = tr("%s garde son sang-froid et motive son équipage !") if is_strong \
		else tr("%s n'arrive pas à motiver son équipage...")
	_board.narration_box.say_for_actor(placement_mine, placement_others, player)
	await _board.narration_box.wait_for_click()
	_board.narration_box.hide_box()

	if _current_round == 0:
		_placed_rank_by_player[_current_player_index] = rank
	_selected_rank = -1
	if not _board._is_remote_client():
		_board._autosave("pions")

	# On quitte la vue "sélection de pièce" (zoom + panneau) dès que la pièce
	# est posée : la résolution d'action (ex. cliquer sur une mer pour le
	# déplacement) a besoin de la vue par défaut sur tout le plateau. On y
	# revient dans _begin_player_pion_turn() pour le joueur suivant.
	_board.pion_selection_panel.hide_panel()
	_shift_camera_for_selection(false)

	_resolving_action = true
	await _board.action_resolution_phase.start(_board, player, spot_index, is_strong)
	_resolving_action = false

	_current_player_index += 1
	_begin_player_pion_turn()


## Vrai une fois les DEBUG_TOTAL_ROUNDS manches de test écoulées (utilisé par
## board.gd pour arrêter la boucle du bouton debug "Passer").
func is_debug_finished() -> bool:
	return _debug_round_index >= DEBUG_TOTAL_ROUNDS


func _end_pion_placement_phase() -> void:
	for spot in _board.action_spots_container.get_children():
		spot.set_hover_enabled(false)
	_board.pion_selection_panel.hide_panel()
	_shift_camera_for_selection(false)

	if _board.debug_skip_to_pions:
		_round_transitioning = true
		_debug_round_index += 1
		if _debug_round_index < DEBUG_TOTAL_ROUNDS:
			_board.narration_box.say(tr("Manche %d/%d terminée.") % [_debug_round_index, DEBUG_TOTAL_ROUNDS])
			await get_tree().create_timer(1.0).timeout
			_board.narration_box.hide_box()
			_board._start_round()
			start(_board)
		else:
			_board.narration_box.say(tr("Mode test : 7 tours de pose de pièces terminés."))
		_round_transitioning = false
		return

	_board.debug_skip_button.visible = false
	_board.narration_box.hide_box()
	_finished = true
	finished.emit()


func _shift_camera_for_selection(active: bool) -> void:
	var target_pos := _board._camera_base_position + Vector2(UiTheme.CAMERA_SELECTION_SHIFT, 0) if active else _board._camera_base_position
	var target_zoom: Vector2 = UiTheme.CAMERA_SELECTION_ZOOM if active else _board._camera_base_zoom
	_board.tween_camera(target_pos, target_zoom, 0.5)


func resume(board: Board) -> void:
	_board = board
	_board.debug_skip_button.visible = GameFlow.is_debug_mode
	_placed_rank_by_player.clear()
	_turn_order = _compute_turn_order()
	var n: int = GameFlow.players.size()
	var total_pions := 0
	for step in range(n):
		var player_index: int = _turn_order[step]
		var color: String = GameFlow.players[player_index]["color"]
		var count := 0
		var known_rank := -1
		for spot in _board.action_spots_container.get_children():
			for p in spot.get_pions_snapshot():
				if p["color"] == color:
					count += 1
					known_rank = p["rank"]
		total_pions += count
		if count == 1:
			_placed_rank_by_player[step] = known_rank

	_current_round = 0 if total_pions < n else 1
	_current_player_index = total_pions if _current_round == 0 else total_pions - n

	for spot in _board.action_spots_container.get_children():
		if not spot.spot_clicked.is_connected(_on_action_spot_clicked):
			spot.spot_clicked.connect(_on_action_spot_clicked)
		spot.set_hover_enabled(true)
	if not _board.pion_selection_panel.pion_selected.is_connected(_on_pion_selected):
		_board.pion_selection_panel.pion_selected.connect(_on_pion_selected)
	if not _board.pion_selection_panel.pion_drag_ended.is_connected(_on_pion_drag_ended):
		_board.pion_selection_panel.pion_drag_ended.connect(_on_pion_drag_ended)
	if not _board.pion_selection_panel.pion_drag_started.is_connected(_on_pion_drag_started):
		_board.pion_selection_panel.pion_drag_started.connect(_on_pion_drag_started)
	if not _board.pion_selection_panel.pion_drag_stopped.is_connected(_on_pion_drag_stopped):
		_board.pion_selection_panel.pion_drag_stopped.connect(_on_pion_drag_stopped)
	_begin_player_pion_turn()
