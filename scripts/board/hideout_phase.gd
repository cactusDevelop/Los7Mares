extends Node

signal finished

var _board: Board
var _hideout_turn_order: Array = []
var _hideout_turn_index: int = 0


func _ready() -> void:
	# HideoutPhase est un enfant direct de Board dans board.tscn : ceci
	# garantit que _board est valide même côté client réseau, qui ne reçoit
	# start() que côté hôte et exécute la suite uniquement via les RPC
	# broadcast ci-dessous (_begin_phase, _claim_spot_rpc).
	_board = get_parent() as Board


## Ordre "du dernier au 1er joueur" (règle 5.8), calculé à partir du vrai
## 1er joueur désigné par le lancer de dés de mise en place
## (first_player_dice_phase), pas d'un index fixe dans GameFlow.players.
## Déterministe (aucun hasard) : peut donc être recalculé à l'identique sur
## chaque écran sans rien transmettre, tant que GameFlow.players/first_player
## sont synchronisés (déjà le cas via la diffusion d'état générique).
func _compute_hideout_order() -> Array:
	var n: int = GameFlow.players.size()
	var first_id: int = GameFlow.get_first_player_id()
	var first_index: int = 0
	for i in range(n):
		if GameFlow.players[i]["id"] == first_id:
			first_index = i
			break
	var order: Array = []
	for i in range(n - 1, -1, -1):
		order.append((first_index + i) % n)
	return order


## Appelé uniquement côté hôte (cf board.gd, first_player_dice_phase.finished
## est gardé par _is_remote_client). En réseau, ne fait qu'annoncer le début
## de la phase à tout le monde ; toute la suite (_begin_phase) est rejouée
## à l'identique sur chaque écran via ce même appel RPC (call_local).
func start(board: Board) -> void:
	_board = board
	if GameFlow.game_mode == "host":
		_begin_phase.rpc()
	else:
		_begin_phase()


@rpc("authority", "call_local", "reliable")
func _begin_phase() -> void:
	_hideout_turn_order = _compute_hideout_order()
	_hideout_turn_index = 0

	for spot in _board.hideout_spots_container.get_children():
		spot.fade_in_empty()
		if not spot.spot_clicked.is_connected(_on_hideout_spot_clicked):
			spot.spot_clicked.connect(_on_hideout_spot_clicked)

	_begin_hideout_turn()


func _begin_hideout_turn() -> void:
	if _hideout_turn_index >= _hideout_turn_order.size():
		_end_hideout_phase()
		return

	var player_index: int = _hideout_turn_order[_hideout_turn_index]
	var player: Dictionary = GameFlow.players[player_index]
	GameFlow.set_current_player(player["id"])
	var color: Color = GameFlow.COLOR_VALUES[player["color"]]
	_board.narration_box.say_for_actor(
		tr("Choisis l'emplacement de ta cachette."), tr("%s choisit l'emplacement de sa cachette."), player
	)

	# En réseau, seul l'écran du joueur dont c'est le tour doit pouvoir
	# survoler/cliquer les emplacements ; les autres (y compris l'hôte s'il
	# ne joue pas, cf lobby "Serveur dédié") sont de simples spectateurs.
	var can_act := true
	if GameFlow.game_mode == "host" or GameFlow.game_mode == "join":
		can_act = Network.peer_player_map.get(multiplayer.get_unique_id(), -1) == player["id"]

	for spot in _board.hideout_spots_container.get_children():
		spot.set_hover_enabled(can_act and not spot.is_taken)
		spot.set_outline_color(color)


func _on_hideout_spot_clicked(spot: Node2D) -> void:
	var spot_index: int = _board.hideout_spots_container.get_children().find(spot)
	if spot_index == -1:
		return
	if GameFlow.game_mode == "host":
		_try_claim_spot(spot_index)
	elif GameFlow.game_mode == "join":
		# Le clic n'est possible que sur l'écran du joueur actif
		# (set_hover_enabled ci-dessus), mais on revalide côté hôte dans
		# _request_claim_spot_rpc avant d'appliquer quoi que ce soit.
		_request_claim_spot_rpc.rpc_id(1, spot_index)
	else:
		_claim_spot_rpc(spot_index)


@rpc("any_peer", "call_remote", "reliable")
func _request_claim_spot_rpc(spot_index: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var expected_player_id: int = GameFlow.players[_hideout_turn_order[_hideout_turn_index]]["id"]
	if Network.peer_player_map.get(sender_id, -1) != expected_player_id:
		return  # pas son tour (ou latence/désynchro) : on ignore silencieusement
	_try_claim_spot(spot_index)


## Hôte uniquement : valide que l'emplacement est encore libre, puis
## diffuse le vrai claim (_claim_spot_rpc) à tout le monde. Séparé de
## _claim_spot_rpc pour que la validation ne s'exécute qu'une fois (pas une
## fois par pair via call_local).
func _try_claim_spot(spot_index: int) -> void:
	var spots := _board.hideout_spots_container.get_children()
	if spot_index < 0 or spot_index >= spots.size() or spots[spot_index].is_taken:
		return
	_claim_spot_rpc.rpc(spot_index)


@rpc("authority", "call_local", "reliable")
func _claim_spot_rpc(spot_index: int) -> void:
	var player_index: int = _hideout_turn_order[_hideout_turn_index]
	var player: Dictionary = GameFlow.players[player_index]
	var spot = _board.hideout_spots_container.get_children()[spot_index]
	spot.claim(player["color"])
	_board.narration_box.hide_box()
	_hideout_turn_index += 1
	if not _board._is_remote_client():
		_board._autosave("hideout")
	_begin_hideout_turn()


func _end_hideout_phase() -> void:
	for spot in _board.hideout_spots_container.get_children():
		spot.set_hover_enabled(false)
		if spot.spot_clicked.is_connected(_on_hideout_spot_clicked):
			spot.spot_clicked.disconnect(_on_hideout_spot_clicked)
	finished.emit()


func resume(board: Board) -> void:
	_board = board
	var claimed := 0
	for spot in _board.hideout_spots_container.get_children():
		if spot.is_taken:
			claimed += 1
	_hideout_turn_order = _compute_hideout_order()
	_hideout_turn_index = claimed
	for spot in _board.hideout_spots_container.get_children():
		if spot.is_taken:
			spot.visible = true
		else:
			spot.fade_in_empty()
		if not spot.spot_clicked.is_connected(_on_hideout_spot_clicked):
			spot.spot_clicked.connect(_on_hideout_spot_clicked)
	_begin_hideout_turn()
