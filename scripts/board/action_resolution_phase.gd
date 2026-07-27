extends Node

## Déclenchée juste après qu'un joueur pose une pièce sur une case action
## (pion_placement_phase.gd). Chaque case action donne accès à 2 des 4
## actions du jeu ; le joueur choisit l'ordre, puis fait ou décline chaque
## action (déclin = 1 ressource nourriture OU 1 jeton fortune au choix).
## "déplacement", "reparation" et "ile" sont implémentées ; "port" ne peut
## encore qu'être déclinée en attendant ses règles détaillées.
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
const IMPLEMENTED_ACTIONS: Array[String] = ["deplacement", "reparation", "ile"]

## Dés physiques réutilisés depuis first_player_dice_phase.gd : noir = combat
## (vide/abordage/canon), blanc = exploration (vide/un/double étoile).
const BLACK_DIE_SCENE := preload("res://scenes/effects/dice_3d.tscn")
const WHITE_DIE_SCENE := preload("res://scenes/effects/dice_white_3d.tscn")
const DICE_PAUSE := 0.6
## Nombre max de dés d'un même type lancés ensemble (règle 9 "mécaniques
## transversales").
const MAX_DICE_PER_ROLL := 5

## Correspondance icône du catalogue (card_catalog.json) -> clé de ressource
## de GameFlow.RESOURCE_TYPES. "fortune"/"tresor" sont gérées à part car ce
## sont des special_resources, pas des RESOURCE_TYPES.
const ICON_TO_RESOURCE: Dictionary = {
	"bois": "wood", "acier": "steel", "bouffe": "food", "toile": "wool", "rhum": "rum",
}

## Émis dès que la destination du déplacement est connue, que ce soit via un
## clic sur une mer (_on_sea_tile_clicked) ou via un bouton de la narration
## box ("draw"/"stop") : permet d'attendre les deux sources à la fois dans
## _run_deplacement (cf await _choice_made ci-dessous).
signal _choice_made(value: String)

var _board: Board
var _player: Dictionary
var _is_strong: bool = true
## Vrai si une activité en cours vient de déclencher un effet "ne plus
## pouvoir effectuer d'action ce tour-ci" ou un chavirage (règle 10.2/10.4) :
## la 2e action du tour (si elle n'a pas encore commencé) est alors annulée.
var _turn_ended: bool = false


func start(board: Board, player: Dictionary, spot_index: int, is_strong: bool = true) -> void:
	_board = board
	_player = player
	_is_strong = is_strong
	_turn_ended = false
	var actions: Array = ACTIONS_BY_SPOT[spot_index]

	var first: String = await _choose_order(actions[0], actions[1])
	var second: String = actions[1] if first == actions[0] else actions[0]

	await _resolve_action(first)
	if not _turn_ended:
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
	elif choice == "do" and action == "ile":
		await _run_ile()
	else:
		await _run_decline()


## Vérifie si l'action est réellement jouable dans l'état actuel du joueur
## (au-delà du simple fait qu'elle soit codée). Pour l'instant seule
## "reparation" a une précondition (règle 9/12) ; "deplacement" est toujours
## possible (même à 0 planche il ne bouge simplement pas, cf boucle).
func _can_do_action(action: String) -> bool:
	if action == "reparation":
		return _can_do_renovation()
	if action == "ile":
		return _can_do_ile()
	return true


## Débarquer sur une île (fort) / Collecter sur une île (faible) nécessite
## une mer avec une carte île actuellement révélée (règle 9/12).
func _can_do_ile() -> bool:
	var sea_key: String = _player.get("boat_sea", "")
	if sea_key == "":
		return false
	var card: GameCard = _board.card_draw_phase.get_current_revealed_card(sea_key)
	return card != null and card.card_type == GameCard.CardType.ILE


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
		_grant_hideout_reward()

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


# =========================================================================
# DEBARQUER SUR UNE ILE (règle 9) / COLLECTER SUR UNE ILE (règle 12)
# =========================================================================

## Fort : choisit l'activité (Exploration seule si île sauvage, Exploration
## OU Commerce si île amicale, Exploration OU Combat si île hostile - ces
## choix viennent directement des clés de card.activities, alimentées par
## card_catalog.json) puis la résout (dés / paiement, règle 10).
func _run_ile() -> void:
	if not _is_strong:
		await _run_ile_collect()
		_board._autosave("pions")
		return

	var sea_key: String = _player.get("boat_sea", "")
	var card: GameCard = _board.card_draw_phase.get_current_revealed_card(sea_key)
	if card == null or card.card_type != GameCard.CardType.ILE:
		await _run_decline()
		return

	var choices: Array = card.activities.keys()
	var activity_key: String
	if choices.size() <= 1:
		activity_key = choices[0] if not choices.is_empty() else "exploration"
	else:
		_board.narration_box.say_with_player(
			tr("Tour de %s : ") + tr(card.title) + tr(" — comment débarquer ?"), _player
		)
		var options: Array = []
		for c in choices:
			options.append({"id": c, "label": _activity_label(c)})
		_board.narration_box.set_options(options)
		activity_key = await _board.narration_box.option_selected

	await _resolve_activity(card, activity_key)
	_board._autosave("pions")


## Faible (règle 12) : 1 ressource au choix parmi bois/nourriture indiquées
## sur l'activité exploration de la carte, sans dé, sans trésor, la carte
## reste en place.
func _run_ile_collect() -> void:
	var sea_key: String = _player.get("boat_sea", "")
	var card: GameCard = _board.card_draw_phase.get_current_revealed_card(sea_key)
	if card == null or card.card_type != GameCard.CardType.ILE:
		await _run_decline()
		return

	var exploration: Dictionary = card.activities.get("exploration", {})
	var choices: Array = []
	for reward in exploration.get("reward", []):
		var candidates: Array = reward["icons"] if reward.has("icons") else [reward.get("icon", "")]
		for ic in candidates:
			if ic in ["bois", "bouffe"] and not choices.has(ic):
				choices.append(ic)
	if choices.is_empty():
		choices = ["bois", "bouffe"]

	_board.narration_box.say_with_player(tr("Tour de %s : collecte sur l'île, quelle ressource ?"), _player)
	var options: Array = []
	for c in choices:
		options.append({"id": c, "label": _icon_label(c)})
	_board.narration_box.set_options(options)
	var choice: String = await _board.narration_box.option_selected
	_add_icon_amount(choice, 1)
	GameFlow.players_changed.emit()


func _activity_label(key: String) -> String:
	match key:
		"exploration": return tr("Explorer (dés d'exploration)")
		"combat": return tr("Combattre (dés de combat)")
		"commerce": return tr("Commercer (payer des ressources)")
		_: return key


# =========================================================================
# MECANIQUES TRANSVERSALES (règle 10) : réussir/échouer une activité,
# lancers de dés, récompenses, gemmes/jetons bonus, effets négatifs.
# =========================================================================

## Résout une activité de carte (exploration/combat = jet de dés à comparer
## au coût ; commerce = paiement direct des ressources demandées), puis
## déclenche réussite ou échec (règle 10).
func _resolve_activity(card: GameCard, activity_key: String) -> void:
	var activity: Dictionary = card.activities.get(activity_key, {})
	var dice_rule: String = activity.get("dice_rule", "")
	var success: bool

	if dice_rule == "":
		if not _can_afford_cost(activity.get("cost", [])):
			_board.narration_box.say_with_player(tr("Tour de %s : ressources insuffisantes pour commercer."), _player)
			_board.narration_box.set_options([{"id": "ok", "label": tr("Continuer")}])
			await _board.narration_box.option_selected
			await _run_decline()
			return
		_apply_cost(activity.get("cost", []))
		success = true
	else:
		success = await _roll_for_activity(activity, dice_rule)

	if success:
		await _grant_activity_success(card, activity_key, activity)
	else:
		await _grant_activity_failure(card)


## Lance les dés adaptés à dice_rule et compare au(x) coût(s) requis :
## - "ile_libre" (île) : dés d'exploration, 1er gratuit, +1 par nourriture
##   dépensée (pas de max autre que MAX_DICE_PER_ROLL).
## - "voile_food_max1" (port périlleux / rencontres météo-créature) : dés
##   d'exploration = niveau de voile, +1 dé si 1 nourriture dépensée (max +1).
## - "armes" (combat) : dés de combat = niveau d'armes, pas de dé bonus.
func _roll_for_activity(activity: Dictionary, dice_rule: String) -> bool:
	var is_white: bool = dice_rule != "armes"
	var count: int = 0
	var can_add_food: bool = false
	var max_food_extra: int = 0

	match dice_rule:
		"ile_libre":
			count = 1
			can_add_food = true
			max_food_extra = MAX_DICE_PER_ROLL
		"voile_food_max1":
			count = max(_player.get("sail_level", 1), 1)
			can_add_food = true
			max_food_extra = 1
		"armes":
			count = max(_player.get("arms_level", 1), 1)
		_:
			count = 1
	count = min(count, MAX_DICE_PER_ROLL)

	var food_spent := 0
	while can_add_food and food_spent < max_food_extra and count < MAX_DICE_PER_ROLL and _player["resources"]["food"] >= 1:
		_board.narration_box.say_with_player(
			tr("Tour de %s : lancer %d dé(s) d'exploration, ou dépenser 1 nourriture pour +1 dé ?"),
			_player, [count]
		)
		_board.narration_box.set_options([
			{"id": "roll", "label": tr("Lancer les dés")},
			{"id": "food", "label": tr("Dépenser 1 nourriture (+1 dé)")},
		])
		var choice: String = await _board.narration_box.option_selected
		if choice != "food":
			break
		_player["resources"]["food"] -= 1
		count += 1
		food_spent += 1
		GameFlow.players_changed.emit()

	var results: Array[String] = await _throw_dice(count, is_white)

	if is_white:
		var stars := 0
		for r in results:
			stars += {"vide": 0, "un": 1, "double": 2}.get(r, 0)
		var needed := 0
		for c in activity.get("cost", []):
			if c.get("icon", "") == "etoile":
				needed = c.get("amount", 0)
		return stars >= needed

	var canons := 0
	var abordages := 0
	for r in results:
		if r == "canon":
			canons += 1
		elif r == "abordage":
			abordages += 1
	for c in activity.get("cost", []):
		var icon: String = c.get("icon", "")
		var amt: int = c.get("amount", 0)
		if icon == "canon" and canons < amt:
			return false
		elif icon == "abordage" and abordages < amt:
			return false
		elif icon == "reussite" and (canons + abordages) < amt:
			return false
	return true


## Instancie et lance count dés du même type (via le sous-système 3D déjà
## utilisé pour le tirage au sort du 1er joueur, cf first_player_dice_phase).
func _throw_dice(count: int, is_white: bool) -> Array[String]:
	var viewport_container: Control = _board.get_node("UI/SubViewportContainer")
	var dice_roll: Node3D = _board.get_node("UI/SubViewportContainer/SubViewport/DiceRoll3D")
	var scene: PackedScene = WHITE_DIE_SCENE if is_white else BLACK_DIE_SCENE
	var scenes: Array[PackedScene] = []
	for i in range(count):
		scenes.append(scene)

	viewport_container.visible = true
	_board.narration_box.say_with_player(tr("Tour de %s : lancer des dés..."), _player)
	_board.narration_box.set_options([])
	dice_roll.roll_mixed(scenes)
	var results: Array[String] = await dice_roll.roll_finished
	await _board.get_tree().create_timer(DICE_PAUSE).timeout
	viewport_container.visible = false
	return results


## Réussir une activité (règle 10) : récompenses, rangement en piste, puis
## gemme/jeton bonus selon le nombre de cartes déjà obtenues dans cette mer.
func _grant_activity_success(card: GameCard, activity_key: String, activity: Dictionary) -> void:
	for reward in activity.get("reward", []):
		await _grant_reward_entry(reward)
	await _check_overload()

	GameFlow.add_card_to_track(_player, activity_key, card)
	var progress: String = GameFlow.register_sea_progress(_player, card.sea_key)

	_board.narration_box.say_with_player(
		tr("Tour de %s : activité réussie ! Carte rangée en piste ") + GameFlow.CARD_TRACK_LABELS.get(activity_key, activity_key) + ".",
		_player
	)
	_board.narration_box.set_options([{"id": "ok", "label": tr("Continuer")}])
	await _board.narration_box.option_selected

	if progress != "none":
		_board.narration_box.say_with_player(_progress_message(progress), _player)
		_board.narration_box.set_options([{"id": "ok", "label": tr("Continuer")}])
		await _board.narration_box.option_selected


func _progress_message(progress: String) -> String:
	match progress:
		"gem": return tr("Tour de %s : 1ère carte de cette mer — récupère la gemme correspondante !")
		"token_new": return tr("Tour de %s : 2e carte de cette mer — récupère le jeton bonus (s'il en reste) !")
		"token_refresh": return tr("Tour de %s : jeton bonus de cette mer rafraîchi (face effet).")
		_: return ""


## Échouer une activité (règle 10) : 1 fortune de compensation, puis l'effet
## négatif de la carte s'il y en a un (planche grise, non encore détaillée
## icône par icône - cf GAME_RULES.txt section 14 - donc parsée depuis le
## texte negative_effect du catalogue).
func _grant_activity_failure(card: GameCard) -> void:
	_player["special_resources"]["fortune"] += 1
	GameFlow.players_changed.emit()

	_board.narration_box.say_with_player(
		tr("Tour de %s : activité échouée. Reçoit 1 fortune en compensation."), _player
	)
	_board.narration_box.set_options([{"id": "ok", "label": tr("Continuer")}])
	await _board.narration_box.option_selected

	if card.negative_effect != "":
		await _apply_negative_effect(card.negative_effect)


func _grant_reward_entry(reward: Dictionary) -> void:
	var amount: int = reward.get("amount", 0)
	var icon: String
	if reward.has("icons"):
		var options: Array = []
		for ic in reward["icons"]:
			options.append({"id": ic, "label": _icon_label(ic) + " x%d" % amount})
		_board.narration_box.say_with_player(tr("Tour de %s : choisis la récompense :"), _player)
		_board.narration_box.set_options(options)
		icon = await _board.narration_box.option_selected
	else:
		icon = reward.get("icon", "")
	_add_icon_amount(icon, amount)


func _icon_label(icon: String) -> String:
	match icon:
		"bois": return tr("Bois")
		"bouffe": return tr("Nourriture")
		"acier": return tr("Acier")
		"toile": return tr("Toile")
		"rhum": return tr("Rhum")
		"fortune": return tr("Fortune")
		"tresor": return tr("Trésor")
		_: return icon


func _can_afford_cost(cost: Array) -> bool:
	for entry in cost:
		var amount: int = entry.get("amount", 0)
		if entry.has("icons"):
			var total := 0
			for ic in entry["icons"]:
				total += _get_icon_amount(ic)
			if total < amount:
				return false
		elif _get_icon_amount(entry.get("icon", "")) < amount:
			return false
	return true


func _apply_cost(cost: Array) -> void:
	for entry in cost:
		var amount: int = entry.get("amount", 0)
		if entry.has("icons"):
			var remaining: int = amount
			for ic in entry["icons"]:
				var take: int = min(remaining, _get_icon_amount(ic))
				_add_icon_amount(ic, -take)
				remaining -= take
				if remaining <= 0:
					break
		else:
			_add_icon_amount(entry.get("icon", ""), -amount)
	GameFlow.players_changed.emit()


func _get_icon_amount(icon: String) -> int:
	if icon == "fortune":
		return _player["special_resources"].get("fortune", 0)
	if icon == "tresor":
		return _player["special_resources"].get("treasure", 0)
	var key: String = ICON_TO_RESOURCE.get(icon, "")
	return _player["resources"].get(key, 0) if key != "" else 0


func _add_icon_amount(icon: String, delta: int) -> void:
	if icon == "fortune":
		_player["special_resources"]["fortune"] += delta
		return
	if icon == "tresor":
		_player["special_resources"]["treasure"] += delta
		return
	var key: String = ICON_TO_RESOURCE.get(icon, "")
	if key != "":
		_player["resources"][key] += delta
	GameFlow.players_changed.emit()


## Bateau surchargé (règle 10) : si > 9 ressources (hors fortune/trésor),
## défausser jusqu'à revenir à 9.
func _check_overload() -> void:
	while _total_resources() > 9:
		var options: Array = []
		for r in GameFlow.RESOURCE_TYPES:
			if _player["resources"].get(r, 0) > 0:
				options.append({"id": r, "label": tr("Défausser 1 ") + GameFlow.RESOURCE_LABELS[r]})
		if options.is_empty():
			break
		_board.narration_box.say_with_player(
			tr("Tour de %s : bateau surchargé (%d/9), défausse une ressource."), _player, [_total_resources()]
		)
		_board.narration_box.set_options(options)
		var choice: String = await _board.narration_box.option_selected
		_player["resources"][choice] -= 1
	GameFlow.players_changed.emit()


func _total_resources() -> int:
	var total := 0
	for r in GameFlow.RESOURCE_TYPES:
		total += _player["resources"].get(r, 0)
	return total


## "Perdre X planches" (règle 10) : retire X planches, chavire à 0.
func _lose_planks(n: int) -> void:
	_player["hull_planks"] = max(_player["hull_planks"] - n, 0)
	GameFlow.players_changed.emit()
	if _player["hull_planks"] <= 0:
		await _capsize()


## "Bateau chavire" (règle 10) : perd la moitié de ses ressources (arrondi
## à l'inférieur) et ne peut plus rien faire ce tour-ci.
func _capsize() -> void:
	_board.narration_box.say_with_player(tr("Tour de %s : le bateau chavire !"), _player)
	_board.narration_box.set_options([{"id": "ok", "label": tr("Continuer")}])
	await _board.narration_box.option_selected

	var to_lose: int = int(_total_resources() / 2)
	await _lose_resources(to_lose)
	_turn_ended = true
	GameFlow.players_changed.emit()


## "Perdre X ressources" (règle 10) : le joueur choisit lesquelles défausser
## (simplification de la règle physique "les plus éloignées du joueur").
func _lose_resources(n: int) -> void:
	for i in range(n):
		var options: Array = []
		for r in GameFlow.RESOURCE_TYPES:
			if _player["resources"].get(r, 0) > 0:
				options.append({"id": r, "label": GameFlow.RESOURCE_LABELS[r]})
		if options.is_empty():
			break
		_board.narration_box.say_with_player(
			tr("Tour de %s : choisis une ressource à perdre (%d restante(s) à perdre)."), _player, [n - i]
		)
		_board.narration_box.set_options(options)
		var choice: String = await _board.narration_box.option_selected
		_player["resources"][choice] -= 1
	GameFlow.players_changed.emit()


## Applique l'effet négatif (planche grise) d'une carte échouée. Les icônes
## précises ne sont pas encore formalisées (GAME_RULES.txt section 14
## [A FAIRE]) : on parse donc le texte negative_effect du catalogue, qui ne
## couvre pour l'instant que les 3 formes déjà présentes dans les données.
func _apply_negative_effect(text: String) -> void:
	var re_both := RegEx.new()
	re_both.compile("Perdez (\\d+) planches? et (\\d+) ressources?")
	var m := re_both.search(text)
	if m:
		await _lose_planks(int(m.get_string(1)))
		if not _turn_ended:
			await _lose_resources(int(m.get_string(2)))
		return

	var re_planks := RegEx.new()
	re_planks.compile("Perdez (\\d+) planches?")
	m = re_planks.search(text)
	if m:
		await _lose_planks(int(m.get_string(1)))
		return

	if text.begins_with("Vous ne pouvez plus effectuer d'action"):
		_turn_ended = true
		_board.narration_box.say_with_player(tr("Tour de %s : ne peut plus effectuer d'action ce tour-ci."), _player)
		_board.narration_box.set_options([{"id": "ok", "label": tr("Continuer")}])
		await _board.narration_box.option_selected
		return

	# Forme non encore reconnue : affichée telle quelle, sans effet mécanique.
	_board.narration_box.say_with_player(tr("Tour de %s : effet — ") + text, _player)
	_board.narration_box.set_options([{"id": "ok", "label": tr("Continuer")}])
	await _board.narration_box.option_selected
