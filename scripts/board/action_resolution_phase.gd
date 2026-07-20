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
## OU mer -> une des 2 mers adjacentes, OU rester sur la même mer pour
## piocher une nouvelle carte.
func _run_deplacement() -> void:
	var points: int = _player.get("sail_level", 1)

	while points > 0:
		var current_sea: String = _player.get("boat_sea", "")
		var options: Array = []

		if current_sea == "":
			var hideout_index: int = _board.hideout_index_for_color(_player["color"])
			if hideout_index == -1:
				break
			for sea_key in _board.adjacent_seas_for_hideout(hideout_index):
				options.append({"id": "move:" + sea_key, "label": tr("Naviguer vers : ") + sea_key.capitalize()})
		else:
			for sea_key in _board.adjacent_seas_for_sea(current_sea):
				options.append({"id": "move:" + sea_key, "label": tr("Naviguer vers : ") + sea_key.capitalize()})
			options.append({"id": "draw", "label": tr("Rester ici et piocher une nouvelle carte")})

		options.append({"id": "stop", "label": tr("Terminer le déplacement")})

		_board.action_resolution_panel.set_title(tr("Déplacement — points restants : %d") % points)
		_board.action_resolution_panel.set_options(options)
		_board.action_resolution_panel.show_panel()
		var choice: String = await _board.action_resolution_panel.option_selected

		if choice == "stop":
			break
		elif choice == "draw":
			_board.card_draw_phase.redraw_card_for_sea(current_sea)
			points -= 1
		elif choice.begins_with("move:"):
			var dest: String = choice.substr(5)
			_board.move_player_boat(_player, dest)
			points -= 1

	_board._autosave("pieces")
