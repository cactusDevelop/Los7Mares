extends Node

## Déclenchée juste après qu'un joueur pose une pièce sur une case action
## (piece_placement_phase.gd). Chaque case action donne accès à 2 des 4
## actions du jeu ; le joueur choisit l'ordre, puis fait ou décline chaque
## action (déclin = 1 ressource nourriture OU 1 jeton fortune au choix).
## Seule l'action "déplacement" est pour l'instant implémentée ; les autres
## ne peuvent que être déclinées en attendant leurs règles détaillées.

signal finished

const ACTIONS_BY_SPOT: Array = [
	["deplacement", "reparation"],  # Spot1
	["deplacement", "port"],        # Spot2
	["port", "reparation"],         # Spot3
	["ile", "reparation"],          # Spot4
	["ile", "deplacement"],         # Spot5
]
const ACTION_LABELS := {
	"deplacement": "Déplacement",
	"reparation": "Réparation",
	"port": "Port",
	"ile": "Île",
}
const IMPLEMENTED_ACTIONS: Array[String] = ["deplacement"]

## Émis dès que la destination du déplacement est connue, que ce soit via un
## clic sur une mer (_on_sea_tile_clicked) ou via un bouton du panneau
## ("draw"/"stop") : permet d'attendre les deux sources à la fois dans
## _run_deplacement (cf await _choice_made ci-dessous).
signal _choice_made(value: String)

var _board: Board
var _player: Dictionary


func start(board: Board, player: Dictionary, spot_index: int) -> void:
	_board = board
	_player = player
	var actions: Array = ACTIONS_BY_SPOT[spot_index]

	var first: String = await _choose_order(actions[0], actions[1])
	var second: String = actions[1] if first == actions[0] else actions[0]

	await _resolve_action(first)
	await _resolve_action(second)

	_board.action_resolution_panel.hide_panel()
	_board.narration_box.hide_box()
	finished.emit()


func _choose_order(a: String, b: String) -> String:
	_board.narration_box.say_with_player(tr("Tour de %s : choisis quelle action faire en premier."), _player)
	_board.action_resolution_panel.set_title(tr("Quelle action faire en premier ?"))
	_board.action_resolution_panel.set_options([
		{"id": a, "label": ACTION_LABELS[a]},
		{"id": b, "label": ACTION_LABELS[b]},
	])
	_board.action_resolution_panel.show_panel()
	var chosen: String = await _board.action_resolution_panel.option_selected
	return chosen


func _resolve_action(action: String) -> void:
	var is_implemented: bool = action in IMPLEMENTED_ACTIONS
	_board.narration_box.say_with_player(
		tr("Tour de %s : action ") + ACTION_LABELS[action] + ".", _player
	)

	_board.action_resolution_panel.set_title(
		ACTION_LABELS[action] if is_implemented else ACTION_LABELS[action] + tr(" (bientôt disponible)")
	)
	var options: Array = []
	if is_implemented:
		options.append({"id": "do", "label": tr("Faire l'action")})
	options.append({"id": "decline", "label": tr("Décliner")})
	_board.action_resolution_panel.set_options(options)
	_board.action_resolution_panel.show_panel()
	var choice: String = await _board.action_resolution_panel.option_selected

	if choice == "do" and action == "deplacement":
		await _run_deplacement()
	else:
		await _run_decline()


func _run_decline() -> void:
	_board.action_resolution_panel.set_title(tr("Reçois une ressource à la place :"))
	_board.action_resolution_panel.set_options([
		{"id": "food", "label": tr("Nourriture")},
		{"id": "fortune", "label": tr("Jeton fortune")},
	])
	_board.action_resolution_panel.show_panel()
	var choice: String = await _board.action_resolution_panel.option_selected

	if choice == "food":
		_player["resources"]["food"] += 1
	else:
		_player["special_resources"]["fortune"] += 1
	GameFlow.players_changed.emit()
	_board._autosave("pieces")


## Déplace le bateau du joueur en dépensant jusqu'à sail_level points de
## déplacement. Chaque point permet : hideout -> une des 2 mers adjacentes,
## OU mer -> une des 2 mers adjacentes, OU mer -> sa propre cachette (si
## elle en fait partie des 2 mers adjacentes), OU rester sur la même mer
## pour piocher une nouvelle carte. S'il termine le déplacement dans sa
## cachette (donc après y être explicitement retourné), le joueur reçoit une
## planche de coque (si moins de 7) et une ressource au choix.
func _run_deplacement() -> void:
	var points: int = _player.get("sail_level", 1)
	var returned_to_hideout: bool = false

	while points > 0:
		var current_sea: String = _player.get("boat_sea", "")
		var hideout_index: int = _board.hideout_index_for_color(_player["color"])
		var reachable: Array[String] = []
		var can_return_home: bool = false

		if current_sea == "":
			if hideout_index == -1:
				break
			reachable = _board.adjacent_seas_for_hideout(hideout_index)
		else:
			reachable = _board.adjacent_seas_for_sea(current_sea)
			can_return_home = hideout_index != -1 and _board.adjacent_seas_for_hideout(hideout_index).has(current_sea)

		var options: Array = []
		if current_sea != "":
			options.append({"id": "draw", "label": tr("Rester ici et piocher une nouvelle carte")})
		options.append({"id": "stop", "label": tr("Terminer le déplacement")})

		_board.narration_box.say_with_player(
			tr("Tour de %s : clique sur une mer voisine pour t'y déplacer."), _player
		)
		_board.action_resolution_panel.set_title(tr("Déplacement — points restants : %d") % points)
		_board.action_resolution_panel.set_options(options)
		_board.action_resolution_panel.show_panel()

		# Active le clic sur les mers accessibles (+ la cachette du joueur si
		# elle est adjacente) pendant que le panneau reste ouvert pour les
		# options non-spatiales (piocher / arrêter) : les deux sources de
		# choix émettent toutes les deux _choice_made.
		var tiles: Array = []
		for sea_key in reachable:
			var tile: Node2D = _board.get_sea_tile_by_key(sea_key)
			if tile == null:
				continue
			tiles.append(tile)
			tile.set_hover_enabled(true)
			tile.spot_clicked.connect(_on_sea_tile_clicked)

		var hideout_spot: Node2D = null
		if can_return_home:
			hideout_spot = _board.hideout_spots_container.get_children()[hideout_index]
			hideout_spot.set_hover_enabled(true)
			hideout_spot.spot_clicked.connect(_on_hideout_spot_clicked)

		_board.action_resolution_panel.option_selected.connect(_on_panel_choice)

		var choice: String = await _choice_made

		_board.action_resolution_panel.option_selected.disconnect(_on_panel_choice)
		for tile in tiles:
			tile.set_hover_enabled(false)
			tile.spot_clicked.disconnect(_on_sea_tile_clicked)
		if hideout_spot != null:
			hideout_spot.set_hover_enabled(false)
			hideout_spot.spot_clicked.disconnect(_on_hideout_spot_clicked)

		if choice == "stop":
			break
		elif choice == "draw":
			_board.card_draw_phase.redraw_card_for_sea(current_sea)
			points -= 1
		elif choice == "hideout":
			_board.move_boat_to_hideout(_player)
			returned_to_hideout = true
			points -= 1
		elif choice.begins_with("move:"):
			var dest: String = choice.substr(5)
			_board.move_player_boat(_player, dest)
			returned_to_hideout = false
			points -= 1

	if returned_to_hideout and _player.get("boat_sea", "") == "":
		await _grant_hideout_reward()

	_board._autosave("pieces")


## Récompense de retour à la cachette : une planche de coque (plafonnée à
## GameFlow.HULL_PLANKS_START) et une ressource au choix entre nourriture et bois.
func _grant_hideout_reward() -> void:
	if _player["hull_planks"] < GameFlow.HULL_PLANKS_START:
		_player["hull_planks"] += 1

	_board.narration_box.say_with_player(tr("Tour de %s : de retour à la cachette, choisis une ressource."), _player)
	_board.action_resolution_panel.set_title(tr("De retour à la cachette — choisis une ressource"))
	_board.action_resolution_panel.set_options([
		{"id": "food", "label": tr("Nourriture")},
		{"id": "wood", "label": tr("Bois")},
	])
	_board.action_resolution_panel.show_panel()
	var resource: String = await _board.action_resolution_panel.option_selected
	_board.action_resolution_panel.hide_panel()

	_player["resources"][resource] += 1
	GameFlow.players_changed.emit()


func _on_sea_tile_clicked(tile: Node2D) -> void:
	_board.action_resolution_panel.hide_panel()
	_choice_made.emit("move:" + tile.sea_key)


func _on_hideout_spot_clicked(_spot: Node2D) -> void:
	_board.action_resolution_panel.hide_panel()
	_choice_made.emit("hideout")


func _on_panel_choice(id: String) -> void:
	_choice_made.emit(id)
