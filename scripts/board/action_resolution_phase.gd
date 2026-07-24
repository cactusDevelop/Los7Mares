extends Node

## Déclenchée juste après qu'un joueur pose une pièce sur une case action
## (pion_placement_phase.gd). Chaque case action donne accès à 2 des 4
## actions du jeu ; le joueur choisit l'ordre, puis fait ou décline chaque
## action (déclin = 1 ressource nourriture OU 1 jeton fortune au choix).
## Seule l'action "déplacement" est pour l'instant implémentée ; les autres
## ne peuvent que être déclinées en attendant leurs règles détaillées.
##
## Tous les choix (ordre des actions, faire/décliner, ressources,
## déplacement...) se font via la narration_box : le paragraphe explique la
## situation et les boutons apparaissent juste en dessous, dans la même
## boîte (plus de popup séparée au centre de l'écran). Le contour de la
## narration_box prend la couleur du joueur dont c'est le tour (posé
## automatiquement par narration_box.say_with_player).

signal finished

const ACTIONS_BY_SPOT: Array = [
	["deplacement", "reparation"],  # Spot1
	["deplacement", "port"],        # Spot2
	["port", "reparation"],         # Spot3
	["ile", "reparation"],          # Spot4
	["ile", "deplacement"],         # Spot5
]
## Libellé de l'action selon la force de l'emplacement (règle 4) :
## fort = action principale, faible = action réduite (règle 12).
const ACTION_LABELS_STRONG := {
	"deplacement": "Naviguer en mer",
	"reparation": "Rénover son bateau",
	"port": "Accéder à un port",
	"ile": "Débarquer sur une île",
}
const ACTION_LABELS_WEAK := {
	"deplacement": "Caboter en mer",
	"reparation": "Rabibocher son bateau",
	"port": "Travailler au port",
	"ile": "Collecter sur une île",
}
const IMPLEMENTED_ACTIONS: Array[String] = ["deplacement", "reparation"]

## Émis dès que la destination du déplacement est connue, que ce soit via un
## clic sur une mer (_on_sea_tile_clicked) ou via un bouton de la narration
## box ("draw"/"stop") : permet d'attendre les deux sources à la fois dans
## _run_deplacement (cf await _choice_made ci-dessous).
signal _choice_made(value: String)

var _board: Board
var _player: Dictionary
var _is_strong: bool = true


func start(board: Board, player: Dictionary, spot_index: int, is_strong: bool = true) -> void:
	_board = board
	_player = player
	_is_strong = is_strong
	var actions: Array = ACTIONS_BY_SPOT[spot_index]

	var first: String = await _choose_order(actions[0], actions[1])
	var second: String = actions[1] if first == actions[0] else actions[0]

	await _resolve_action(first)
	await _resolve_action(second)

	_board.narration_box.hide_box()
	finished.emit()


func _label_for(action: String) -> String:
	return ACTION_LABELS_STRONG[action] if _is_strong else ACTION_LABELS_WEAK[action]


func _choose_order(a: String, b: String) -> String:
	_board.narration_box.say_with_player(tr("Tour de %s : choisis quelle action faire en premier."), _player)
	_board.narration_box.set_options([
		{"id": a, "label": _label_for(a)},
		{"id": b, "label": _label_for(b)},
	])
	var chosen: String = await _board.narration_box.option_selected
	return chosen


func _resolve_action(action: String) -> void:
	var is_implemented: bool = action in IMPLEMENTED_ACTIONS and _can_do_action(action)
	var action_text: String = _label_for(action) if is_implemented else _label_for(action) + tr(" (bientôt disponible)")
	_board.narration_box.say_with_player(
		tr("Tour de %s : action ") + action_text + ".", _player
	)

	var options: Array = []
	if is_implemented:
		options.append({"id": "do", "label": tr("Faire l'action")})
	options.append({"id": "decline", "label": tr("Décliner")})
	_board.narration_box.set_options(options)
	var choice: String = await _board.narration_box.option_selected

	if choice == "do" and action == "deplacement":
		await _run_deplacement()
	elif choice == "do" and action == "reparation":
		await _run_renovation()
	else:
		await _run_decline()


## Vérifie si l'action est réellement jouable dans l'état actuel du joueur
## (au-delà du simple fait qu'elle soit codée). Pour l'instant seule
## "reparation" a une précondition (règle 9/12) ; "deplacement" est toujours
## possible (même à 0 planche il ne bouge simplement pas, cf boucle).
func _can_do_action(action: String) -> bool:
	if action == "reparation":
		return _can_do_renovation()
	return true


## Rénover son bateau (fort) nécessite ressources suffisantes pour au moins
## une amélioration, OU une coque endommagée à réparer (règle 9).
## Rabibocher (faible) nécessite uniquement une coque endommagée (règle 12).
func _can_do_renovation() -> bool:
	if not _is_strong:
		return _player["hull_planks"] < GameFlow.HULL_PLANKS_START
	if _player["hull_planks"] < GameFlow.HULL_PLANKS_START:
		return true
	return _can_upgrade(_player["arms_level"], "steel") or _can_upgrade(_player["sail_level"], "wool")


func _can_upgrade(level: int, other_key: String) -> bool:
	if level >= GameFlow.SHIP_LEVEL_MAX:
		return false
	var cost: Dictionary = GameFlow.UPGRADE_COST_BY_LEVEL[level + 1]
	return _player["resources"]["wood"] >= cost["wood"] and _player["resources"][other_key] >= cost["other"]


func _run_decline() -> void:
	_board.narration_box.say_with_player(tr("Tour de %s : reçois une ressource à la place :"), _player)
	_board.narration_box.set_options([
		{"id": "food", "label": tr("Nourriture")},
		{"id": "fortune", "label": tr("Jeton fortune")},
	])
	var choice: String = await _board.narration_box.option_selected

	if choice == "food":
		_player["resources"]["food"] += 1
	else:
		_player["special_resources"]["fortune"] += 1
	GameFlow.players_changed.emit()
	_board._autosave("pions")


## Rénover son bateau (fort) : Améliorer OU Réparer, ou les deux en dépensant
## 1 rhum (règle 9). Rabibocher (faible) : uniquement +1 planche gratuite,
## sans amélioration ni planche supplémentaire (règle 12).
func _run_renovation() -> void:
	if not _is_strong:
		await _run_rabibochage()
		_board._autosave("pions")
		return

	var can_ameliorer: bool = _can_upgrade(_player["sail_level"], "wool") \
		or _can_upgrade(_player["arms_level"], "steel")
	var has_rum: bool = _player["resources"]["rum"] >= 1

	var options: Array = [{"id": "reparer", "label": tr("Réparer la coque")}]
	if can_ameliorer:
		options.append({"id": "ameliorer", "label": tr("Améliorer (voile ou armes)")})
	if can_ameliorer and has_rum:
		options.append({"id": "both", "label": tr("Les deux (dépenser 1 rhum)")})

	_board.narration_box.say_with_player(tr("Tour de %s : Rénover son bateau, que veux-tu faire ?"), _player)
	_board.narration_box.set_options(options)
	var choice: String = await _board.narration_box.option_selected

	if choice == "both":
		_player["resources"]["rum"] -= 1
		await _do_ameliorer()
		await _do_reparer()
	elif choice == "ameliorer":
		await _do_ameliorer()
	else:
		await _do_reparer()

	GameFlow.players_changed.emit()
	_board._autosave("pions")


func _run_rabibochage() -> void:
	_player["hull_planks"] = min(_player["hull_planks"] + 1, GameFlow.HULL_PLANKS_START)
	_board.narration_box.say_with_player(tr("Tour de %s : rabibocle son bateau (+1 planche gratuite)."), _player)
	_board.narration_box.set_options([{"id": "ok", "label": tr("Continuer")}])
	await _board.narration_box.option_selected
	GameFlow.players_changed.emit()


## Améliorer : choisit voile ou armes, paie le coût de l'emplacement vide le
## plus à gauche de la piste choisie (bois + toile pour voile, bois + acier
## pour armes) et monte le niveau d'1 cran (règle 9). Une seule amélioration
## à la fois, même quand appelé via "Les deux".
func _do_ameliorer() -> void:
	var options: Array = []
	if _can_upgrade(_player["sail_level"], "wool"):
		var cost: Dictionary = GameFlow.UPGRADE_COST_BY_LEVEL[_player["sail_level"] + 1]
		options.append({"id": "voile", "label": tr("Voile niveau %d (coût : %d bois, %d toile)") % [_player["sail_level"] + 1, cost["wood"], cost["other"]]})
	if _can_upgrade(_player["arms_level"], "steel"):
		var cost2: Dictionary = GameFlow.UPGRADE_COST_BY_LEVEL[_player["arms_level"] + 1]
		options.append({"id": "armes", "label": tr("Armes niveau %d (coût : %d bois, %d acier)") % [_player["arms_level"] + 1, cost2["wood"], cost2["other"]]})
	if options.is_empty():
		return

	_board.narration_box.say_with_player(tr("Tour de %s : quelle amélioration ?"), _player)
	_board.narration_box.set_options(options)
	var choice: String = await _board.narration_box.option_selected

	if choice == "voile":
		var cost: Dictionary = GameFlow.UPGRADE_COST_BY_LEVEL[_player["sail_level"] + 1]
		_player["resources"]["wood"] -= cost["wood"]
		_player["resources"]["wool"] -= cost["other"]
		_player["sail_level"] += 1
	else:
		var cost2: Dictionary = GameFlow.UPGRADE_COST_BY_LEVEL[_player["arms_level"] + 1]
		_player["resources"]["wood"] -= cost2["wood"]
		_player["resources"]["steel"] -= cost2["other"]
		_player["arms_level"] += 1

	GameFlow.players_changed.emit()


## Réparer : +1 planche gratuite, puis +1 planche par ressource dépensée
## (bois, ou toile/acier en remplacement - règle 9), jusqu'à la coque
## complète (7 planches).
func _do_reparer() -> void:
	_player["hull_planks"] = min(_player["hull_planks"] + 1, GameFlow.HULL_PLANKS_START)
	GameFlow.players_changed.emit()

	while _player["hull_planks"] < GameFlow.HULL_PLANKS_START:
		var options: Array = []
		if _player["resources"]["wood"] >= 1:
			options.append({"id": "wood", "label": tr("Dépenser 1 bois (+1 planche)")})
		if _player["resources"]["wool"] >= 1:
			options.append({"id": "wool", "label": tr("Dépenser 1 toile (+1 planche)")})
		if _player["resources"]["steel"] >= 1:
			options.append({"id": "steel", "label": tr("Dépenser 1 acier (+1 planche)")})
		if options.is_empty():
			break
		options.append({"id": "stop", "label": tr("Arrêter la réparation")})

		_board.narration_box.say_with_player(
			tr("Tour de %s : réparer davantage la coque (%d/%d planches) ?"),
			_player, [_player["hull_planks"], GameFlow.HULL_PLANKS_START]
		)
		_board.narration_box.set_options(options)
		var choice: String = await _board.narration_box.option_selected
		if choice == "stop":
			break

		_player["resources"][choice] -= 1
		_player["hull_planks"] = min(_player["hull_planks"] + 1, GameFlow.HULL_PLANKS_START)
		GameFlow.players_changed.emit()


## Déplace le bateau du joueur en dépensant jusqu'à sail_level points de
## déplacement. Chaque point permet : hideout -> une des 2 mers adjacentes,
## OU mer -> une des 2 mers adjacentes, OU mer -> sa propre cachette (si
## elle en fait partie des 2 mers adjacentes), OU rester sur la même mer
## pour piocher une nouvelle carte. S'il termine le tour dans sa cachette
## (qu'il y soit explicitement retourné ou qu'il y soit resté sans bouger),
## le joueur reçoit une planche de coque (si moins de 7) et une ressource
## au choix.
func _run_deplacement() -> void:
	# Fort -> Naviguer en mer (points = niveau de voile).
	# Faible -> Caboter en mer (1 seul point, quel que soit le niveau de voile).
	var points: int = _player.get("sail_level", 1) if _is_strong else 1

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
			tr("Tour de %s : clique sur une mer voisine pour t'y déplacer (points restants : %d)."),
			_player, [points]
		)
		_board.narration_box.set_options(options)

		# Active le clic sur les mers accessibles (+ la cachette du joueur si
		# elle est adjacente) pendant que les boutons non-spatiaux (piocher /
		# arrêter) restent affichés : les deux sources de choix émettent
		# toutes les deux _choice_made.
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
			hideout_spot.set_hover_label("")
			hideout_spot.set_hover_enabled(true)
			hideout_spot.spot_clicked.connect(_on_hideout_spot_clicked)

		_board.narration_box.option_selected.connect(_on_panel_choice)

		var choice: String = await _choice_made

		_board.narration_box.option_selected.disconnect(_on_panel_choice)
		for tile in tiles:
			tile.set_hover_enabled(false)
			tile.spot_clicked.disconnect(_on_sea_tile_clicked)
		if hideout_spot != null:
			hideout_spot.set_hover_enabled(false)
			hideout_spot.set_hover_label("POSER")
			hideout_spot.spot_clicked.disconnect(_on_hideout_spot_clicked)

		if choice == "stop":
			break
		elif choice == "draw":
			_board.card_draw_phase.redraw_card_for_sea(current_sea)
			points -= 1
		elif choice == "hideout":
			_board.move_boat_to_hideout(_player)
			points -= 1
		elif choice.begins_with("move:"):
			var dest: String = choice.substr(5)
			_board.move_player_boat(_player, dest)
			points -= 1

	if _player.get("boat_sea", "") == "":
		await _grant_hideout_reward()

	_board._autosave("pions")


## Récompense de retour à la cachette (règle 6a) : +1 planche de coque
## (plafonnée à GameFlow.HULL_PLANKS_START), +1 nourriture ET +1 bois -
## les 3 cumulés, ce n'est PAS un choix entre nourriture et bois.
func _grant_hideout_reward() -> void:
	if _player["hull_planks"] < GameFlow.HULL_PLANKS_START:
		_player["hull_planks"] += 1
	_player["resources"]["food"] += 1
	_player["resources"]["wood"] += 1

	_board.narration_box.say_with_player(
		tr("Tour de %s : de retour à la cachette, +1 planche, +1 nourriture, +1 bois."), _player
	)
	GameFlow.players_changed.emit()


func _on_sea_tile_clicked(tile: Node2D) -> void:
	_board.narration_box.set_options([])
	_choice_made.emit("move:" + tile.sea_key)


func _on_hideout_spot_clicked(_spot: Node2D) -> void:
	_board.narration_box.set_options([])
	_choice_made.emit("hideout")


func _on_panel_choice(id: String) -> void:
	_choice_made.emit(id)
