extends Node

## Déclenchée juste après qu'un joueur pose une pièce sur une case action
## (pion_placement_phase.gd). Chaque case action donne accès à 2 des 4
## actions du jeu ; le joueur choisit l'ordre, puis fait ou décline chaque
## action (déclin = 1 ressource nourriture OU 1 jeton fortune au choix).
## Les 4 actions (déplacement, réparation, île, port) sont implémentées avec
## leurs variantes principale/réduite (règles 9/11/12). "Gérer une
## rencontre" (règle 9) est résolue depuis _run_deplacement dès qu'une carte
## rencontre est révélée : Menace météo / Géant des mers / Créature des mers
## / Bateau marchand / Flotte marchande ont leurs mécaniques dédiées
## (cf _handle_rencontre et suivants). Bateau pirate / Capitaine pirate
## (phases canons/abordage) ne sont PAS ENCORE gérés : il manque la donnée
## de répartition boulets/abordages/faces inconnues par carte, absente de
## card_catalog.json - cf TODO sur _handle_rencontre.
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
const IMPLEMENTED_ACTIONS: Array[String] = ["deplacement", "reparation", "ile", "port"]

## Phrases de narration (règles mode avancé, texte entre parenthèses
## "Narration : ..."), rejouées telles quelles en préfixe des messages
## fonctionnels existants de narration_box, séparées par un saut de ligne.
const N_CHOOSE_ORDER := "Vous commandez votre équipage. À vos ordres, Capitaine !"
const N_ACT := "Place à l'action ! Votre équipage suit vos ordres."
const N_NAVIGUER := "Tout le monde sur le pont, larguez les amarres et levez l'ancre !"
const N_HIDEOUT_RETURN := "Enfin à la maison ! Réparons cette coque et collectons des ressources !"
const N_ILE := "Terre en vue, Capitaine ! Par les étoiles, c'est une île !"
const N_EXPLORATION := "Vous explorez les recoins sauvages de l'île."
const N_COMMERCE_ILE := "Vous commercez avec la tribu amicale."
const N_COMBAT_ILE := "Vous combattez la tribu hostile."
const N_PORT := "Port en vue, Capitaine ! Voyons ce qu'il a en réserve !"
const N_PORT_ORDINAIRE := "Vous échangez des ressources avec les marchands."
const N_PORT_PERILLEUX := "Vous manœuvrez votre bateau, essayant d'atteindre le port indemne."
const N_PORT_PERILLEUX_FAIL := "Capitaine ! Nous avons percuté quelque chose !"
const N_PORT_MALFAME := "Vous luttez contre des brigands, tentant de protéger vos marchandises."
const N_SUCCESS := "On a réussi la compagnie ! À nous le butin !"
const N_FAILURE := "La prochaine fois sera la bonne !"
const N_GEM := "Une gemme ! Un joli trophée, en effet !"
const N_TOKEN_NEW := "Capitaine ! Les locaux nous offrent un cadeau."
const N_TOKEN_REFRESH := "Capitaine, nos amis sont de retour !"
const N_OVERLOAD := "Votre bateau est trop chargé. Vous devez l'alléger."
const N_CAPSIZE := "Votre bateau est en mauvais état !"
const N_CAPSIZE_LOSE := "Capitaine ! Nous prenons l'eau rapidement... Nous devons alléger notre charge !"

const N_RENCONTRE_AMICALE := "Une voile à l'horizon... Elle ne semble pas hostile, Capitaine."
const N_RENCONTRE_DANGEREUSE := "Alerte, Capitaine ! Quelque chose approche, et ça n'annonce rien de bon !"
const N_RENCONTRE_EVITEE := "Vous manœuvrez habilement pour laisser cette rencontre derrière vous."
const N_RENCONTRE_PIRATE := "Un drapeau noir ! Préparez-vous à l'abordage, Capitaine !"
const N_RENCONTRE_METEO := "Le ciel s'assombrit, la mer se soulève : la tempête est sur nous !"
const N_RENCONTRE_GEANT := "Une ombre colossale surgit des profondeurs !"
const N_RENCONTRE_CREATURE := "Des tentacules jaillissent des flots autour du bateau !"
const N_RENCONTRE_MARCHAND := "Un navire marchand isolé croise votre route."
const N_RENCONTRE_FLOTTE := "Une flotte marchande bat pavillon amical à l'horizon."

## Sous-type de rencontre déduit du titre de la carte (règle 9 "Gérer une
## rencontre") : détermine la mécanique de résolution à appliquer. "pirate"
## regroupe Bateau pirate ET Capitaine pirate (même mécanique de phases
## canons/abordage, cf GAME_RULES.txt) — PAS ENCORE IMPLÉMENTÉ : il manque
## la répartition boulets/abordages/faces inconnues par variante de carte,
## absente de card_catalog.json (cf note en tête de _handle_rencontre).
const RENCONTRE_KIND: Dictionary = {
	"Bateau pirate": "pirate",
	"Capitaine pirate": "pirate",
	"Menace météo": "meteo",
	"Géant des mers": "geant",
	"Créature des mers": "creature",
	"Bateau marchand": "marchand",
	"Flotte marchande": "flotte",
}
## Amicale/Dangereuse (règle 9) : détermine le coût d'Éviter (gratuit vs
## 1 fortune + la carte).
const RENCONTRE_DANGEROUS: Dictionary = {
	"pirate": true, "meteo": true, "geant": true, "creature": true,
	"marchand": false, "flotte": false,
}

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
## Suivi pour la compensation de tour "stérile" (règle 6, étape 4b) : remis
## à faux à chaque tour (start()), passe à vrai dès qu'une carte est
## récupérée (_finalize_success) ou qu'une amélioration voile/armes est
## payée (_do_ameliorer). Une simple réparation de coque NE compte PAS
## comme "bateau amélioré" (ce sont deux choix distincts de la règle 9).
var _card_retrieved_this_turn: bool = false
var _ship_upgraded_this_turn: bool = false
## Règle 13 : 1 action optionnelle max par tour (Commercer/Attaquer un
## joueur), remise à faux à chaque tour (start()). Un refus de commerce ne
## consomme PAS ce jeton (règle : "on peut retenter"), seule une
## négociation aboutie ou une attaque effectivement lancée le fait.
var _optional_action_used_this_turn: bool = false


func start(board: Board, player: Dictionary, spot_index: int, is_strong: bool = true) -> void:
	_board = board
	_player = player
	_is_strong = is_strong
	_turn_ended = false
	_card_retrieved_this_turn = false
	_ship_upgraded_this_turn = false
	_optional_action_used_this_turn = false
	var actions: Array = ACTIONS_BY_SPOT[spot_index]

	await _offer_optional_action()

	var first: String
	var second: String
	while true:
		first = await _choose_order(actions[0], actions[1])
		second = actions[1] if first == actions[0] else actions[0]
		var outcome: String = await _resolve_action(first, true)
		if outcome != "back":
			break

	await _offer_optional_action()

	if not _turn_ended:
		await _resolve_action(second, false)

	await _offer_optional_action()

	await _grant_barren_turn_compensation()

	_board.narration_box.hide_box()
	finished.emit()


## Compensation de tour "stérile" (règle 6, étape 4b) : si aucune carte n'a
## été récupérée ni aucune amélioration voile/armes payée pendant ce tour,
## +1 fortune. Indépendante de la compensation d'échec d'activité
## (_grant_activity_failure, règle 10), qui elle est déjà gérée ailleurs :
## les deux peuvent se cumuler sur un même tour raté ET stérile.
func _grant_barren_turn_compensation() -> void:
	if _card_retrieved_this_turn or _ship_upgraded_this_turn:
		return
	_player["special_resources"]["fortune"] += 1
	GameFlow.players_changed.emit()
	_board.narration_box.say_with_player(
		tr("Pas de chance cette fois-ci, mais le vent va bientôt tourner !") +
		tr("\n\nTour de %s : aucune carte récupérée ni bateau amélioré ce tour, reçoit 1 fortune en compensation."),
		_player
	)
	await _board.narration_box.wait_for_continue()


# =========================================================================
# ACTIONS OPTIONNELLES (règle 13, 1 max par tour, avant/après une action
# principale/réduite, non remplaçable par une action par défaut)
# =========================================================================

## Propose Commercer/Attaquer un joueur si le jeton du tour n'est pas déjà
## consommé et qu'au moins un autre joueur partage la mer du joueur actif.
## Appelée à 3 reprises dans start() (avant la 1ère action, entre les deux,
## après la 2e) pour couvrir "avant/après" n'importe laquelle des 2 actions
## du tour. Reboucle sur elle-même après un refus de commerce (règle :
## "action annulée, on peut retenter"), qui ne consomme donc pas le jeton.
func _offer_optional_action() -> void:
	if _optional_action_used_this_turn or _turn_ended:
		return
	var sea_key: String = _player.get("boat_sea", "")
	if sea_key == "":
		return

	while true:
		var candidates: Array = []
		for p in GameFlow.players:
			if p["id"] != _player["id"] and p.get("boat_sea", "") == sea_key:
				candidates.append(p)
		if candidates.is_empty():
			return

		_board.narration_box.say_with_player(
			tr("Tour de %s : un autre bateau se trouve sur cette mer. Action optionnelle ?"), _player
		)
		_board.narration_box.set_options([
			{"id": "commerce", "label": tr("Commercer avec un joueur")},
			{"id": "attaquer", "label": tr("Attaquer un joueur")},
			{"id": "skip", "label": tr("Ne rien faire")},
		])
		var choice: String = await _board.narration_box.option_selected
		if choice == "skip":
			return

		var target: Dictionary = await _choose_target_player(candidates)
		if target.is_empty():
			return

		if choice == "commerce":
			var accepted: bool = await _run_commerce_avec_joueur(target)
			if accepted:
				_optional_action_used_this_turn = true
				return
			# Refusé : ne consomme pas le jeton, on reboucle (retenter un
			# autre joueur, ou changer pour Attaquer, ou abandonner).
		else:
			await _run_attaquer_joueur(target)
			_optional_action_used_this_turn = true
			return


func _choose_target_player(candidates: Array) -> Dictionary:
	if candidates.size() == 1:
		return candidates[0]
	var options: Array = []
	for p in candidates:
		options.append({"id": str(p["id"]), "label": str(p.get("name", ""))})
	options.append({"id": "cancel", "label": tr("Annuler")})
	_board.narration_box.say_with_player(tr("Tour de %s : choisis un joueur sur cette mer."), _player)
	_board.narration_box.set_options(options)
	var choice: String = await _board.narration_box.option_selected
	if choice == "cancel":
		return {}
	for p in candidates:
		if str(p["id"]) == choice:
			return p
	return {}


## Commercer avec un joueur (règle 13) : le joueur ciblé accepte ou refuse
## (décision prise en personne, hotseat) ; s'il accepte, échange libre sans
## limite de quantité. Renvoie true si l'échange a eu lieu (accepté).
func _run_commerce_avec_joueur(target: Dictionary) -> bool:
	_board.narration_box.say_with_player(
		tr("Tour de %s : propose de commercer avec ") + str(target.get("name", "")) + tr(". Accepte-t-il ?"),
		_player
	)
	_board.narration_box.set_options([
		{"id": "accept", "label": tr("Accepter l'échange")},
		{"id": "refuse", "label": tr("Refuser l'échange")},
	])
	var answer: String = await _board.narration_box.option_selected
	if answer == "refuse":
		_board.narration_box.say(tr("L'échange est refusé."))
		await _board.narration_box.wait_for_click()
		return false

	await _run_free_trade(_player, target)
	return true


## Échange libre (règle 13) : ressources/fortunes/trésors/perroquets, sans
## limite de quantité, dans les 2 sens. Les 2 joueurs négocient en personne
## (jeu en local/hotseat) ; l'appli ne fait qu'appliquer les transferts
## déclarés un par un jusqu'à ce qu'un des deux mette fin à l'échange.
func _run_free_trade(a: Dictionary, b: Dictionary) -> void:
	while true:
		_board.narration_box.say(
			tr("Échange libre entre ") + str(a.get("name", "")) + tr(" et ") + str(b.get("name", "")) + tr(" : que transférer ?")
		)
		_board.narration_box.set_options([
			{"id": "a_to_b", "label": str(a.get("name", "")) + tr(" donne à ") + str(b.get("name", ""))},
			{"id": "b_to_a", "label": str(b.get("name", "")) + tr(" donne à ") + str(a.get("name", ""))},
			{"id": "done", "label": tr("Terminer l'échange")},
		])
		var choice: String = await _board.narration_box.option_selected
		if choice == "done":
			break
		if choice == "a_to_b":
			await _transfer_one_item(a, b)
		else:
			await _transfer_one_item(b, a)
	GameFlow.players_changed.emit()


## Transfère 1 unité d'un item choisi par "giver" vers "receiver" :
## ressource, fortune, trésor, ou perroquet actuellement en sa possession
## (le sien propre s'il n'est pas déjà capturé, ou un perroquet d'un tiers
## qu'il détient en cage). Rappelée en boucle par _run_free_trade.
func _transfer_one_item(giver: Dictionary, receiver: Dictionary) -> void:
	var options: Array = []
	for r in GameFlow.RESOURCE_TYPES:
		if giver["resources"].get(r, 0) > 0:
			options.append({"id": "res:" + r, "label": GameFlow.RESOURCE_LABELS[r]})
	if giver["special_resources"].get("fortune", 0) > 0:
		options.append({"id": "fortune", "label": tr("Fortune")})
	if giver["special_resources"].get("treasure", 0) > 0:
		options.append({"id": "treasure", "label": tr("Trésor")})
	for p in GameFlow.players:
		var held_by_giver: bool = p.get("parrot_captured_by", -1) == giver.get("id", -1)
		var is_own_free: bool = p["id"] == giver["id"] and p.get("parrot_captured_by", -1) == -1
		if held_by_giver or is_own_free:
			options.append({"id": "parrot:" + str(p["id"]), "label": tr("Perroquet de ") + str(p.get("name", ""))})

	if options.is_empty():
		_board.narration_box.say(str(giver.get("name", "")) + tr(" n'a rien à donner."))
		await _board.narration_box.wait_for_click()
		return

	_board.narration_box.say_with_player(tr("Tour de %s : que donne ") + str(giver.get("name", "")) + tr(" ?"), giver)
	_board.narration_box.set_options(options)
	var choice: String = await _board.narration_box.option_selected

	if choice.begins_with("res:"):
		var res: String = choice.substr(4)
		giver["resources"][res] -= 1
		receiver["resources"][res] = receiver["resources"].get(res, 0) + 1
	elif choice == "fortune":
		giver["special_resources"]["fortune"] -= 1
		receiver["special_resources"]["fortune"] = receiver["special_resources"].get("fortune", 0) + 1
	elif choice == "treasure":
		giver["special_resources"]["treasure"] -= 1
		receiver["special_resources"]["treasure"] = receiver["special_resources"].get("treasure", 0) + 1
	elif choice.begins_with("parrot:"):
		var victim_id: int = int(choice.substr(7))
		GameFlow.capture_parrot(receiver["id"], victim_id)

	GameFlow.players_changed.emit()


## Attaquer un joueur (règle 13) : tentative d'évasion optionnelle de la
## cible (dés d'exploration = son niveau de voile, sans bonus possible),
## puis si elle échoue ou n'est pas tentée, combat à 2 phases similaire à
## celui d'un bateau pirate (cf _run_rencontre_pirate) mais symétrique.
func _run_attaquer_joueur(target: Dictionary) -> void:
	_board.narration_box.say_with_player(
		tr("Tour de %s : attaque ") + str(target.get("name", "")) + tr(" !"), _player
	)
	_board.narration_box.set_options([
		{"id": "flee", "label": str(target.get("name", "")) + tr(" tente de fuir")},
		{"id": "fight", "label": str(target.get("name", "")) + tr(" fait face")},
	])
	var reaction: String = await _board.narration_box.option_selected

	if reaction == "flee":
		var sail: int = max(target.get("sail_level", 1), 1)
		_board.narration_box.say_with_player(
			tr("Tour de %s : ") + str(target.get("name", "")) + tr(" tente de fuir (%d dé(s) d'exploration, sans bonus)."),
			target, [sail]
		)
		await _board.narration_box.wait_for_click()
		var results: Array[String] = await _throw_dice(sail, true)
		var stars := 0
		for r in results:
			stars += 2 if r == "double" else (1 if r == "un" else 0)
		if stars > max(_player.get("sail_level", 1), 1):
			_board.narration_box.say_with_player(tr("Tour de %s : évasion réussie, l'attaque n'a pas lieu."), target)
			await _board.narration_box.wait_for_continue()
			return
		_board.narration_box.say(tr("Évasion manquée : le combat commence."))
		await _board.narration_box.wait_for_click()

	# Phase jet de dés.
	var attacker_count: int = min(max(_player.get("arms_level", 1), 1), MAX_DICE_PER_ROLL)
	attacker_count = await _offer_rhum_extra_die_for(_player, attacker_count)
	var attacker_results: Array[String] = await _offer_fortune_dice_fixing_for(_player, attacker_count, false)
	var attacker_canons: int = attacker_results.count("canon")
	var attacker_abordages: int = attacker_results.count("abordage")

	var defender_count: int = min(max(target.get("arms_level", 1), 1), MAX_DICE_PER_ROLL)
	defender_count = await _offer_rhum_extra_die_for(target, defender_count)
	var defender_results: Array[String] = await _offer_fortune_dice_fixing_for(target, defender_count, false)
	var defender_canons: int = defender_results.count("canon")
	var defender_abordages: int = defender_results.count("abordage")

	_board.narration_box.say(
		tr("Tour de %s : ") % str(_player.get("name", "")) +
		tr("%d boulet(s)/%d abordage(s) contre %d boulet(s)/%d abordage(s) de ") % [attacker_canons, attacker_abordages, defender_canons, defender_abordages] +
		str(target.get("name", "")) + "."
	)
	await _board.narration_box.wait_for_continue()

	# Phase des canons.
	_player["hull_planks"] = max(_player["hull_planks"] - defender_canons, 0)
	target["hull_planks"] = max(target["hull_planks"] - attacker_canons, 0)
	GameFlow.players_changed.emit()
	var attacker_sunk: bool = _player["hull_planks"] <= 0
	var defender_sunk: bool = target["hull_planks"] <= 0

	if attacker_sunk and defender_sunk:
		await _capsize_for(_player)
		await _capsize_for(target)
		_player["special_resources"]["fortune"] += 1
		target["special_resources"]["fortune"] = target["special_resources"].get("fortune", 0) + 1
		_turn_ended = true
		GameFlow.players_changed.emit()
		_board.narration_box.say(tr("Les deux bateaux chavirent ! Chacun reçoit 1 fortune."))
		await _board.narration_box.wait_for_click()
		return

	if attacker_sunk or defender_sunk:
		var plank_loser: Dictionary = _player if attacker_sunk else target
		var plank_winner: Dictionary = target if attacker_sunk else _player
		await _capsize_for(plank_loser, plank_winner)
		plank_loser["special_resources"]["fortune"] = plank_loser["special_resources"].get("fortune", 0) + 1
		GameFlow.capture_parrot(plank_winner["id"], plank_loser["id"])
		if attacker_sunk:
			_turn_ended = true
		GameFlow.players_changed.emit()
		_board.narration_box.say_with_player(
			tr("Tour de %s : bateau coulé ! Reçoit 1 fortune ; l'adversaire vole son perroquet et les ressources perdues."),
			plank_loser
		)
		await _board.narration_box.wait_for_click()
		return

	# Phase d'abordage.
	if attacker_abordages == defender_abordages:
		_player["special_resources"]["fortune"] += 1
		target["special_resources"]["fortune"] = target["special_resources"].get("fortune", 0) + 1
		GameFlow.players_changed.emit()
		_board.narration_box.say(tr("Égalité à l'abordage ! Chacun reçoit 1 fortune."))
		await _board.narration_box.wait_for_click()
		return

	var winner: Dictionary = _player if attacker_abordages > defender_abordages else target
	var loser: Dictionary = target if attacker_abordages > defender_abordages else _player
	var excess: int = abs(attacker_abordages - defender_abordages)
	loser["special_resources"]["fortune"] = loser["special_resources"].get("fortune", 0) + 1
	GameFlow.capture_parrot(winner["id"], loser["id"])
	GameFlow.players_changed.emit()
	_board.narration_box.say_with_player(
		tr("Tour de %s : victoire à l'abordage ! Vole le perroquet adverse et 1 fortune de compensation pour le perdant."),
		winner
	)
	await _board.narration_box.wait_for_continue()
	await _offer_pvp_theft(winner, loser, excess)


## Répartition du butin d'abordage (règle 13) : le gagnant choisit comment
## dépenser ses faces d'abordage excédentaires : 1 face = 1 ressource
## volée, 2 faces = 1 trésor volé, chaque face n'étant utilisée qu'une fois.
func _offer_pvp_theft(winner: Dictionary, loser: Dictionary, excess_faces: int) -> void:
	while excess_faces > 0:
		var options: Array = []
		var has_resource: bool = false
		for r in GameFlow.RESOURCE_TYPES:
			if loser["resources"].get(r, 0) > 0:
				has_resource = true
				break
		if has_resource:
			options.append({"id": "resource", "label": tr("Voler 1 ressource (1 face)")})
		if excess_faces >= 2 and loser["special_resources"].get("treasure", 0) > 0:
			options.append({"id": "treasure", "label": tr("Voler 1 trésor (2 faces)")})
		options.append({"id": "stop", "label": tr("Ne rien voler de plus")})

		_board.narration_box.say_with_player(
			tr("Tour de %s : %d face(s) d'abordage en excès à dépenser."), winner, [excess_faces]
		)
		_board.narration_box.set_options(options)
		var choice: String = await _board.narration_box.option_selected

		if choice == "stop":
			break
		if choice == "treasure":
			loser["special_resources"]["treasure"] -= 1
			winner["special_resources"]["treasure"] = winner["special_resources"].get("treasure", 0) + 1
			excess_faces -= 2
		else:
			var res_options: Array = []
			for r in GameFlow.RESOURCE_TYPES:
				if loser["resources"].get(r, 0) > 0:
					res_options.append({"id": r, "label": GameFlow.RESOURCE_LABELS[r]})
			_board.narration_box.say_with_player(tr("Tour de %s : quelle ressource voler ?"), winner)
			_board.narration_box.set_options(res_options)
			var res: String = await _board.narration_box.option_selected
			loser["resources"][res] -= 1
			winner["resources"][res] = winner["resources"].get(res, 0) + 1
			excess_faces -= 1
		GameFlow.players_changed.emit()


func _label_for(action: String) -> String:
	return ACTION_LABELS_STRONG[action] if _is_strong else ACTION_LABELS_WEAK[action]


func _choose_order(a: String, b: String) -> String:
	_board.narration_box.say_with_player(tr(N_CHOOSE_ORDER + "\n\nTour de %s : choisis quelle action faire en premier."), _player)
	_board.narration_box.set_options([
		{"id": a, "label": _label_for(a)},
		{"id": b, "label": _label_for(b)},
	])
	var chosen: String = await _board.narration_box.option_selected
	return chosen


## allow_back : si vrai, un bouton "Retour" permet de revenir au choix de
## l'ordre des 2 actions (uniquement pertinent pour la 1ère action du tour,
## tant qu'elle n'est pas confirmée - règle 6.3 "impossible de revenir à la
## précédente [action] une fois commencée", donc seulement AVANT ce point).
## Retourne "back" si le joueur est remonté jusqu'au choix d'ordre, sinon "".
## Si le joueur choisit "Faire l'action" puis se ravise avant tout coût payé
## ou dé lancé (cf _run_xxx qui renvoient "cancel"), on réaffiche ce même
## menu Faire/Décliner/Retour plutôt que d'imposer un choix.
func _resolve_action(action: String, allow_back: bool) -> String:
	while true:
		var is_implemented: bool = action in IMPLEMENTED_ACTIONS and _can_do_action(action)
		var action_text: String = _label_for(action) if is_implemented else _label_for(action) + _unavailable_reason(action)
		var prefix: String = tr(N_ACT) + "\n\n" if allow_back else ""
		_board.narration_box.say_with_player(
			prefix + tr("Tour de %s : action ") + action_text + ".", _player
		)

		var options: Array = []
		if is_implemented:
			options.append({"id": "do", "label": tr("Faire l'action")})
		options.append({"id": "decline", "label": tr("Décliner")})
		if allow_back:
			options.append({"id": "back", "label": tr("↩ Retour (changer l'ordre)")})
		_board.narration_box.set_options(options)
		var choice: String = await _board.narration_box.option_selected

		if choice == "back":
			return "back"

		var result: String = ""
		if choice == "do" and action == "deplacement":
			result = await _run_deplacement()
		elif choice == "do" and action == "reparation":
			result = await _run_renovation()
		elif choice == "do" and action == "ile":
			result = await _run_ile()
		elif choice == "do" and action == "port":
			result = await _run_port()
		else:
			await _run_decline()
			return ""

		if result != "cancel":
			return ""
		# result == "cancel" : le joueur s'est ravisé avant toute confirmation
		# (aucun coût payé, aucun dé lancé) -> on réaffiche Faire/Décliner.
	return ""  # jamais atteint (la boucle ne sort que via un return ci-dessus), imposé par l'analyseur statique de Godot


## Motif affiché entre parenthèses quand une action n'est pas jouable dans
## l'état actuel du joueur (règle 9/12) : les 4 actions sont bien codées,
## seule leur précondition n'est pas remplie ici — pas de texte laissant
## croire qu'elles ne le sont pas ("bientôt disponible").
func _unavailable_reason(action: String) -> String:
	match action:
		"ile":
			return tr(" (aucune carte île sur cette mer)")
		"port":
			var sea_key: String = _player.get("boat_sea", "")
			var card: GameCard = _board.card_draw_phase.get_current_revealed_card(sea_key)
			if card == null or card.card_type != GameCard.CardType.PORT:
				return tr(" (aucune carte port sur cette mer)")
			return tr(" (ressources insuffisantes, même avec substitution)")
		"reparation":
			if not _is_strong:
				return tr(" (coque déjà intacte)")
			return tr(" (coque intacte et aucune amélioration abordable)")
		_:
			return ""


## Vérifie si l'action est réellement jouable dans l'état actuel du joueur
## (au-delà du simple fait qu'elle soit codée). Pour l'instant seule
## "reparation" a une précondition (règle 9/12) ; "deplacement" est toujours
## possible (même à 0 planche il ne bouge simplement pas, cf boucle).
func _can_do_action(action: String) -> bool:
	if action == "reparation":
		return _can_do_renovation()
	if action == "ile":
		return _can_do_ile()
	if action == "port":
		return _can_do_port()
	return true


## Débarquer sur une île (fort) / Collecter sur une île (faible) nécessite
## une mer avec une carte île actuellement révélée (règle 9/12).
func _can_do_ile() -> bool:
	var sea_key: String = _player.get("boat_sea", "")
	if sea_key == "":
		return false
	var card: GameCard = _board.card_draw_phase.get_current_revealed_card(sea_key)
	return card != null and card.card_type == GameCard.CardType.ILE


## Accéder à un port (fort) nécessite une mer avec une carte port + les
## ressources suffisantes (avec substitution) pour un port ordinaire ; les
## variantes à dés (périlleux/malfamé) n'ont pas de précondition de
## ressources. Travailler au port (faible, règle 12) ne nécessite que la
## carte port.
func _can_do_port() -> bool:
	var sea_key: String = _player.get("boat_sea", "")
	if sea_key == "":
		return false
	var card: GameCard = _board.card_draw_phase.get_current_revealed_card(sea_key)
	if card == null or card.card_type != GameCard.CardType.PORT:
		return false
	if not _is_strong:
		return true
	var activity: Dictionary = card.activities.get("commerce", {})
	if activity.get("dice_rule", "") == "":
		return _can_afford_port_cost(activity.get("cost", []))
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
func _run_renovation() -> String:
	if not _is_strong:
		var r: String = await _run_rabibochage()
		if r != "cancel":
			_board._autosave("pions")
		return r

	var can_ameliorer: bool = _can_upgrade(_player["sail_level"], "wool") \
		or _can_upgrade(_player["arms_level"], "steel")
	var has_rum: bool = _player["resources"]["rum"] >= 1

	var options: Array = [{"id": "reparer", "label": tr("Réparer la coque")}]
	if can_ameliorer:
		options.append({"id": "ameliorer", "label": tr("Améliorer (voile ou armes)")})
	if can_ameliorer and has_rum:
		options.append({"id": "both", "label": tr("Les deux (dépenser 1 rhum)")})
	options.append({"id": "back", "label": tr("↩ Retour")})

	_board.narration_box.say_with_player(tr("Tour de %s : Rénover son bateau, que veux-tu faire ?"), _player)
	_board.narration_box.set_options(options)
	var choice: String = await _board.narration_box.option_selected
	if choice == "back":
		return "cancel"

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
	return ""


func _run_rabibochage() -> String:
	_board.narration_box.say_with_player(tr("Tour de %s : rabibocher son bateau (+1 planche gratuite). Confirmer ?"), _player)
	_board.narration_box.set_options([
		{"id": "confirm", "label": tr("Confirmer")},
		{"id": "back", "label": tr("↩ Retour")},
	])
	var choice: String = await _board.narration_box.option_selected
	if choice == "back":
		return "cancel"

	_player["hull_planks"] = min(_player["hull_planks"] + 1, GameFlow.HULL_PLANKS_START)
	_board.narration_box.say_with_player(tr("Tour de %s : rabibocle son bateau (+1 planche gratuite)."), _player)
	await _board.narration_box.wait_for_continue()
	GameFlow.players_changed.emit()
	return ""


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

	_ship_upgraded_this_turn = true
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
func _run_deplacement() -> String:
	if _is_strong:
		_board.narration_box.say(tr(N_NAVIGUER))
		await _board.narration_box.wait_for_click()

	# Cas spécial (règle 9) : une rencontre est déjà présente sur la mer du
	# joueur en tout début d'action -> la résoudre avant toute autre chose.
	var pending_rencontre: GameCard = _current_rencontre_card()
	if pending_rencontre != null:
		var resolved: bool = await _handle_rencontre(pending_rencontre)
		if resolved or _turn_ended:
			_board._autosave("pions")
			return ""

	# Fort -> Naviguer en mer (points = niveau de voile).
	# Faible -> Caboter en mer (1 seul point, quel que soit le niveau de voile).
	var points: int = _player.get("sail_level", 1) if _is_strong else 1
	var can_cancel := true

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
		if can_cancel:
			options.append({"id": "back", "label": tr("↩ Retour")})

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

		if choice == "back":
			return "cancel"
		elif choice == "stop":
			break
		elif choice == "draw":
			_board.card_draw_phase.redraw_card_for_sea(current_sea)
			points -= 1
			can_cancel = false
		elif choice == "hideout":
			_board.move_boat_to_hideout(_player)
			points -= 1
			can_cancel = false
		elif choice.begins_with("move:"):
			var dest: String = choice.substr(5)
			_board.move_player_boat(_player, dest)
			points -= 1
			can_cancel = false

		if choice == "draw" or choice.begins_with("move:"):
			var revealed: GameCard = _current_rencontre_card()
			if revealed != null:
				var success: bool = await _handle_rencontre(revealed)
				if success or _turn_ended:
					break

	if _player.get("boat_sea", "") == "":
		_grant_hideout_reward()

	_board._autosave("pions")
	return ""


## Récompense de retour à la cachette (règle 6a) : +1 planche de coque
## (plafonnée à GameFlow.HULL_PLANKS_START), +1 nourriture ET +1 bois -
## les 3 cumulés, ce n'est PAS un choix entre nourriture et bois.
func _grant_hideout_reward() -> void:
	if _player["hull_planks"] < GameFlow.HULL_PLANKS_START:
		_player["hull_planks"] += 1
	_player["resources"]["food"] += 1
	_player["resources"]["wood"] += 1

	_board.narration_box.say_with_player(
		tr(N_HIDEOUT_RETURN + "\n\nTour de %s : de retour à la cachette, +1 planche, +1 nourriture, +1 bois."), _player
	)
	GameFlow.players_changed.emit()


# =========================================================================
# GÉRER UNE RENCONTRE (règle 9)
# =========================================================================

## Renvoie la carte rencontre actuellement révélée sur la mer du joueur, ou
## null (aucune carte / une carte île ou port, qui elle ne force rien).
func _current_rencontre_card() -> GameCard:
	var sea_key: String = _player.get("boat_sea", "")
	if sea_key == "":
		return null
	var card: GameCard = _board.card_draw_phase.get_current_revealed_card(sea_key)
	if card != null and card.card_type == GameCard.CardType.RENCONTRE:
		return card
	return null


## Point d'entrée appelé par _run_deplacement dès qu'une rencontre est
## révélée (ou déjà présente en tout début d'action) : détermine
## Amicale/Dangereuse, propose Éviter (gratuit si amicale, 1 fortune si
## dangereuse) ou Gérer, puis dispatch vers la mécanique du sous-type.
## Renvoie true si la rencontre a été résolue en SUCCÈS (auquel cas la règle
## 9 dit que l'action Naviguer se termine immédiatement) ; false si évitée
## ou échouée (la navigation continue s'il reste des points, sauf chavirage
## qui est déjà géré via _turn_ended par _lose_planks/_capsize).
func _handle_rencontre(card: GameCard) -> bool:
	var kind: String = RENCONTRE_KIND.get(card.title, "")
	if kind == "":
		return false

	var dangerous: bool = RENCONTRE_DANGEROUS.get(kind, true)
	_board.narration_box.say_with_player(
		(tr(N_RENCONTRE_DANGEREUSE) if dangerous else tr(N_RENCONTRE_AMICALE)) +
		tr("\n\nTour de %s : rencontre — ") + tr(card.title) +
		(tr(" (dangereuse).") if dangerous else tr(" (amicale).")),
		_player
	)
	await _board.narration_box.wait_for_click()

	var can_avoid: bool = not dangerous or _player["special_resources"].get("fortune", 0) >= 1
	var options: Array = [{"id": "gerer", "label": tr("Gérer la rencontre")}]
	if can_avoid:
		options.append({
			"id": "eviter",
			"label": tr("Éviter (défausser 1 fortune + la carte)") if dangerous else tr("Éviter (défausser la carte)"),
		})
	_board.narration_box.set_options(options)
	var choice: String = await _board.narration_box.option_selected

	if choice == "eviter":
		if dangerous:
			_player["special_resources"]["fortune"] -= 1
			GameFlow.players_changed.emit()
		_board.narration_box.say_with_player(tr(N_RENCONTRE_EVITEE + "\n\nTour de %s : rencontre évitée, carte défaussée."), _player)
		await _board.narration_box.wait_for_continue()
		_board.card_draw_phase.discard_revealed_card_for_sea(card.sea_key)
		return false

	match kind:
		"pirate":
			_board.narration_box.say(tr(N_RENCONTRE_PIRATE))
			await _board.narration_box.wait_for_click()
			return await _run_rencontre_pirate(card)
		"meteo":
			_board.narration_box.say(tr(N_RENCONTRE_METEO))
			await _board.narration_box.wait_for_click()
			return await _resolve_rencontre_activity(card, "exploration")
		"geant":
			_board.narration_box.say(tr(N_RENCONTRE_GEANT))
			await _board.narration_box.wait_for_click()
			return await _resolve_rencontre_activity(card, "combat")
		"creature":
			_board.narration_box.say(tr(N_RENCONTRE_CREATURE))
			await _board.narration_box.wait_for_click()
			return await _run_rencontre_creature(card)
		"flotte":
			_board.narration_box.say(tr(N_RENCONTRE_FLOTTE))
			await _board.narration_box.wait_for_click()
			return await _resolve_rencontre_activity(card, "commerce")
		"marchand":
			_board.narration_box.say(tr(N_RENCONTRE_MARCHAND))
			await _board.narration_box.wait_for_click()
			return await _run_rencontre_marchand(card)
		_:
			return false


## Résolution générique d'une seule piste d'activité de rencontre (règle 10,
## réutilise le même moteur coût/dés/récompense que île/port), puis défausse
## systématiquement la carte (contrairement à île/port qui restent en
## place) : c'est la seule différence de traitement pour ces sous-types.
func _resolve_rencontre_activity(card: GameCard, activity_key: String) -> bool:
	var activity: Dictionary = card.activities.get(activity_key, {})
	var dice_rule: String = activity.get("dice_rule", "")
	var success: bool
	if dice_rule == "":
		if _can_afford_cost(activity.get("cost", [])):
			_apply_cost(activity.get("cost", []))
			success = true
		else:
			success = false
	else:
		success = await _roll_for_activity(activity, dice_rule)

	if success:
		await _grant_activity_success(card, activity_key, activity)
	else:
		await _grant_activity_failure(card)

	_board.card_draw_phase.discard_revealed_card_for_sea(card.sea_key)
	return success


## Bateau marchand (amicale, règle 9) : choix entre Commerce ou Attaquer
## (dés de combat), chacun résolu via le moteur générique ci-dessus.
func _run_rencontre_marchand(card: GameCard) -> bool:
	_board.narration_box.say_with_player(tr("Tour de %s : ") + tr(card.title) + tr(" — commercer ou l'attaquer ?"), _player)
	_board.narration_box.set_options([
		{"id": "commerce", "label": tr("Commercer (payer des ressources)")},
		{"id": "combat", "label": tr("Attaquer (dés de combat)")},
	])
	var choice: String = await _board.narration_box.option_selected
	return await _resolve_rencontre_activity(card, choice)


## Créature des mers (dangereuse, règle 9) : lancer SIMULTANÉMENT des dés
## d'exploration (niveau de voile, +1 nourriture -> +1 dé max) ET des dés de
## combat (niveau d'armes) ; succès uniquement si les 2 seuils sont atteints
## en même temps. Ne peut pas passer par _resolve_rencontre_activity (une
## seule piste à la fois) : orchestration dédiée, mais réutilise les mêmes
## briques de lancer de dés (rhum/fortune inclus).
func _run_rencontre_creature(card: GameCard) -> bool:
	var exploration: Dictionary = card.activities.get("exploration", {})
	var combat: Dictionary = card.activities.get("combat", {})

	var base: int = max(_player.get("sail_level", 1), 1)
	var stars: int = await _roll_exploration_stars(base, 1)
	var explo_ok: bool = stars >= _needed_stars(exploration)

	var count: int = min(max(_player.get("arms_level", 1), 1), MAX_DICE_PER_ROLL)
	count = await _offer_rhum_extra_die(count)
	var results: Array[String] = await _offer_fortune_dice_fixing(count, false)
	var combat_ok: bool = _meets_combat_requirement(results, combat.get("cost", []))

	var success: bool = explo_ok and combat_ok
	if success:
		var activity_key: String = "combat"
		if card.possible_tracks.size() > 1:
			_board.narration_box.say_with_player(tr("Tour de %s : dans quelle piste ranger cette carte ?"), _player)
			var track_options: Array = []
			for t in card.possible_tracks:
				track_options.append({"id": t, "label": GameFlow.CARD_TRACK_LABELS.get(t, t)})
			_board.narration_box.set_options(track_options)
			activity_key = await _board.narration_box.option_selected
		await _grant_activity_success(card, activity_key, combat)
	else:
		await _grant_activity_failure(card)

	_board.card_draw_phase.discard_revealed_card_for_sea(card.sea_key)
	return success


## Bateau pirate / Capitaine pirate (dangereuse, règle 9) : combat en 2
## phases contre un pirate dont les stats (planches / faces connues /
## nombre de dés "inconnus") viennent de card.activities.combat
## (pirate_planks / known_faces / unknown_dice, cf card_catalog.json).
## 1. Jet de dés : faces connues du pirate + un AUTRE joueur (celui à
##    gauche) lance unknown_dice dés de combat pour les faces inconnues,
##    ajoutés au jet du pirate ; le joueur actif lance ses propres dés de
##    combat (niveau d'armes, avec rhum/fortune comme d'habitude).
## 2. Phase canons : les 2 camps perdent des planches = boulets adverses.
##    Pirate à 0 planche (boulets joueur >= planches pirate) et joueur
##    encore à flot -> victoire. Joueur chaviré -> échec. Sinon -> abordage.
## 3. Phase abordage : joueur strictement plus d'abordages -> victoire.
##    Sinon défaite : le pirate vole 1 ressource par abordage en excès.
func _run_rencontre_pirate(card: GameCard) -> bool:
	var combat: Dictionary = card.activities.get("combat", {})
	var pirate_planks: int = combat.get("pirate_planks", 0)
	var known_faces: Array = combat.get("known_faces", [])
	var unknown_dice: int = combat.get("unknown_dice", 0)

	var pirate_canons: int = known_faces.count("canon")
	var pirate_abordages: int = known_faces.count("abordage")

	if unknown_dice > 0:
		var other_results: Array[String] = await _roll_dice_for_other_player(unknown_dice)
		for r in other_results:
			if r == "canon":
				pirate_canons += 1
			elif r == "abordage":
				pirate_abordages += 1

	var count: int = min(max(_player.get("arms_level", 1), 1), MAX_DICE_PER_ROLL)
	count = await _offer_rhum_extra_die(count)
	var player_results: Array[String] = await _offer_fortune_dice_fixing(count, false)
	var player_canons: int = player_results.count("canon")
	var player_abordages: int = player_results.count("abordage")

	_board.narration_box.say_with_player(
		tr("Tour de %s : le pirate a %d boulet(s) et %d abordage(s) (pour %d planche(s)) ; vous avez %d boulet(s) et %d abordage(s)."),
		_player, [pirate_canons, pirate_abordages, pirate_planks, player_canons, player_abordages]
	)
	await _board.narration_box.wait_for_continue()

	# Phase des canons.
	if pirate_canons > 0:
		await _lose_planks(pirate_canons)
	var pirate_sunk: bool = player_canons >= pirate_planks

	if _turn_ended:
		await _grant_activity_failure(card)
		_board.card_draw_phase.discard_revealed_card_for_sea(card.sea_key)
		return false

	if pirate_sunk:
		_board.narration_box.say_with_player(tr("Tour de %s : le bateau pirate est coulé !"), _player)
		await _board.narration_box.wait_for_continue()
		await _grant_activity_success(card, "combat", combat)
		_board.card_draw_phase.discard_revealed_card_for_sea(card.sea_key)
		return true

	# Phase d'abordage.
	if player_abordages > pirate_abordages:
		_board.narration_box.say_with_player(tr("Tour de %s : victoire à l'abordage !"), _player)
		await _board.narration_box.wait_for_continue()
		await _grant_activity_success(card, "combat", combat)
		_board.card_draw_phase.discard_revealed_card_for_sea(card.sea_key)
		return true

	var excess: int = max(pirate_abordages - player_abordages, 0)
	if excess > 0:
		_board.narration_box.say_with_player(
			tr("Tour de %s : repoussé à l'abordage, le pirate vole %d ressource(s)."), _player, [excess]
		)
		await _board.narration_box.wait_for_continue()
		await _lose_resources(excess)
	await _grant_activity_failure(card)
	_board.card_draw_phase.discard_revealed_card_for_sea(card.sea_key)
	return false


## Fait lancer count dés de combat par un AUTRE joueur que le joueur actif
## (règle 9, "faces inconnues" du pirate) : en principe celui à gauche, ici
## le joueur suivant dans GameFlow.players (ordre de jeu), avec repli sur le
## joueur actif lui-même en partie solo (1 seul joueur).
func _roll_dice_for_other_player(count: int) -> Array[String]:
	var idx: int = GameFlow.get_player_index(_player)
	var other: Dictionary = _player
	if idx != -1 and GameFlow.players.size() > 1:
		other = GameFlow.players[(idx + 1) % GameFlow.players.size()]

	_board.narration_box.say_with_player(
		tr("Tour de %s : ") + str(other.get("name", "")) + tr(" lance %d dé(s) pour les faces inconnues du pirate."),
		_player, [count]
	)
	await _board.narration_box.wait_for_click()
	return await _throw_dice(count, false)


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
func _run_ile() -> String:
	if not _is_strong:
		var r: String = await _run_ile_collect()
		if r != "cancel":
			_board._autosave("pions")
		return r

	var sea_key: String = _player.get("boat_sea", "")
	var card: GameCard = _board.card_draw_phase.get_current_revealed_card(sea_key)
	if card == null or card.card_type != GameCard.CardType.ILE:
		await _run_decline()
		return ""

	_board.narration_box.say(tr(N_ILE))
	await _board.narration_box.wait_for_click()

	var choices: Array = card.activities.keys()
	var activity_key: String = ""
	if choices.size() <= 1:
		activity_key = choices[0] if not choices.is_empty() else "exploration"
		_board.narration_box.say_with_player(
			tr(_activity_narration(activity_key) + "\n\nTour de %s : ") + tr(card.title) + tr(" — ") + _activity_label(activity_key) + tr(". Confirmer ?"), _player
		)
		_board.narration_box.set_options([
			{"id": "confirm", "label": tr("Confirmer")},
			{"id": "back", "label": tr("↩ Retour")},
		])
		var confirm: String = await _board.narration_box.option_selected
		if confirm == "back":
			return "cancel"
	else:
		_board.narration_box.say_with_player(
			tr("Tour de %s : ") + tr(card.title) + tr(" — comment débarquer ?"), _player
		)
		var options: Array = []
		for c in choices:
			options.append({"id": c, "label": _activity_label(c)})
		options.append({"id": "back", "label": tr("↩ Retour")})
		_board.narration_box.set_options(options)
		activity_key = await _board.narration_box.option_selected
		if activity_key == "back":
			return "cancel"

	await _resolve_activity(card, activity_key)
	_board._autosave("pions")
	return ""


## Faible (règle 12) : 1 ressource au choix parmi bois/nourriture indiquées
## sur l'activité exploration de la carte, sans dé, sans trésor, la carte
## reste en place.
func _run_ile_collect() -> String:
	var sea_key: String = _player.get("boat_sea", "")
	var card: GameCard = _board.card_draw_phase.get_current_revealed_card(sea_key)
	if card == null or card.card_type != GameCard.CardType.ILE:
		await _run_decline()
		return ""

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
	options.append({"id": "back", "label": tr("↩ Retour")})
	_board.narration_box.set_options(options)
	var choice: String = await _board.narration_box.option_selected
	if choice == "back":
		return "cancel"
	_add_icon_amount(choice, 1)
	GameFlow.players_changed.emit()
	return ""


func _activity_narration(key: String) -> String:
	match key:
		"exploration": return N_EXPLORATION
		"combat": return N_COMBAT_ILE
		"commerce": return N_COMMERCE_ILE
		_: return ""


func _activity_label(key: String) -> String:
	match key:
		"exploration": return tr("Explorer (dés d'exploration)")
		"combat": return tr("Combattre (dés de combat)")
		"commerce": return tr("Commercer (payer des ressources)")
		_: return key


# =========================================================================
# ACCEDER A UN PORT (règle 9) / TRAVAILLER AU PORT (règle 12)
# =========================================================================

## Fort : détermine la variante depuis dice_rule de l'activité "commerce"
## (null -> ordinaire, "voile_food_max1" -> périlleux, "armes" -> malfamé)
## et la résout (règle 9).
func _run_port() -> String:
	if not _is_strong:
		var r: String = await _run_port_work()
		if r != "cancel":
			_board._autosave("pions")
		return r

	var sea_key: String = _player.get("boat_sea", "")
	var card: GameCard = _board.card_draw_phase.get_current_revealed_card(sea_key)
	if card == null or card.card_type != GameCard.CardType.PORT:
		await _run_decline()
		return ""

	_board.narration_box.say(tr(N_PORT))
	await _board.narration_box.wait_for_click()

	var activity: Dictionary = card.activities.get("commerce", {})
	var result: String = ""
	match activity.get("dice_rule", ""):
		"voile_food_max1":
			result = await _run_port_perilleux(card, activity)
		"armes":
			result = await _run_port_malfame(card, activity)
		_:
			result = await _run_port_ordinaire(card, activity)

	if result != "cancel":
		_board._autosave("pions")
	return result


## Port ordinaire : payer les ressources demandées, avec substitution
## possible (1 rhum pour n'importe quelle ressource, ou 2 ressources d'un
## autre type pour 1) puis recevoir la récompense (règle 9).
func _run_port_ordinaire(card: GameCard, activity: Dictionary) -> String:
	var cost: Array = activity.get("cost", [])
	if not _can_afford_port_cost(cost):
		_board.narration_box.say_with_player(
			tr("Tour de %s : ressources insuffisantes pour accéder au port (même avec substitution)."), _player
		)
		await _board.narration_box.wait_for_continue()
		await _run_decline()
		return ""

	_board.narration_box.say_with_player(tr(N_PORT_ORDINAIRE + "\n\nTour de %s : accéder au port, confirmer le paiement ?"), _player)
	_board.narration_box.set_options([
		{"id": "confirm", "label": tr("Payer et continuer")},
		{"id": "back", "label": tr("↩ Retour")},
	])
	var confirm: String = await _board.narration_box.option_selected
	if confirm == "back":
		return "cancel"

	await _pay_port_cost_interactive(cost)
	for reward in activity.get("reward", []):
		await _grant_reward_entry(reward)
	await _check_overload()
	await _finalize_success(card, "commerce")
	return ""


## Port périlleux : dés d'exploration = niveau de voile (+1 nourriture pour
## +1 dé, max 1) pour atteindre le nombre d'étoiles requis. Échec -> perdre
## autant de planches que d'étoiles manquantes (règle 9), sans fortune de
## compensation ni carte défaussée (pas la même mécanique qu'échouer une
## activité classique).
func _run_port_perilleux(card: GameCard, activity: Dictionary) -> String:
	_board.narration_box.say_with_player(tr(N_PORT_PERILLEUX + "\n\nTour de %s : port périlleux, lancer les dés d'exploration ?"), _player)
	_board.narration_box.set_options([
		{"id": "confirm", "label": tr("Lancer les dés")},
		{"id": "back", "label": tr("↩ Retour")},
	])
	var confirm: String = await _board.narration_box.option_selected
	if confirm == "back":
		return "cancel"

	var base: int = max(_player.get("sail_level", 1), 1)
	var stars: int = await _roll_exploration_stars(base, 1)
	var needed: int = _needed_stars(activity)

	if stars >= needed:
		for reward in activity.get("reward", []):
			await _grant_reward_entry(reward)
		await _check_overload()
		await _finalize_success(card, "commerce")
		return ""

	var missing: int = needed - stars
	_board.narration_box.say_with_player(
		tr(N_PORT_PERILLEUX_FAIL + "\n\nTour de %s : étoiles insuffisantes (%d/%d) au port périlleux, perd %d planche(s)."),
		_player, [stars, needed, missing]
	)
	await _board.narration_box.wait_for_continue()
	await _lose_planks(missing)
	return ""


## Port malfamé : dés de combat = niveau d'armes pour atteindre le nombre
## de succès requis (canon OU abordage). Réussite -> Commerce normal.
## Échec -> Commerce quand même, mais récompense réduite du nombre de
## succès manquants (règle 9).
func _run_port_malfame(card: GameCard, activity: Dictionary) -> String:
	_board.narration_box.say_with_player(tr(N_PORT_MALFAME + "\n\nTour de %s : port malfamé, lancer les dés de combat ?"), _player)
	_board.narration_box.set_options([
		{"id": "confirm", "label": tr("Lancer les dés")},
		{"id": "back", "label": tr("↩ Retour")},
	])
	var confirm: String = await _board.narration_box.option_selected
	if confirm == "back":
		return "cancel"

	var count: int = min(max(_player.get("arms_level", 1), 1), MAX_DICE_PER_ROLL)
	count = await _offer_rhum_extra_die(count)
	var results: Array[String] = await _offer_fortune_dice_fixing(count, false)

	var successes := 0
	for r in results:
		if r == "canon" or r == "abordage":
			successes += 1
	var needed := 0
	for c in activity.get("cost", []):
		if c.get("icon", "") in ["canon", "abordage", "reussite"]:
			needed += c.get("amount", 0)
	var missing: int = max(needed - successes, 0)

	_board.narration_box.say_with_player(
		tr("Tour de %s : %d succès obtenus sur %d requis au port malfamé."),
		_player, [successes, needed]
	)
	await _board.narration_box.wait_for_continue()

	var reward: Array = activity.get("reward", [])
	if missing > 0:
		reward = _reduced_reward(reward, missing)
	for entry in reward:
		await _grant_reward_entry(entry)
	await _check_overload()
	await _finalize_success(card, "commerce")
	return ""


## Réduit une liste de récompenses de "missing" unités au total (règle 9,
## port malfamé) en rognant d'abord les entrées les plus abondantes.
func _reduced_reward(reward: Array, missing: int) -> Array:
	var result: Array = []
	var to_cut: int = missing
	for entry in reward:
		var e: Dictionary = entry.duplicate(true)
		var cut: int = min(to_cut, int(e.get("amount", 0)))
		e["amount"] = int(e.get("amount", 0)) - cut
		to_cut -= cut
		if e["amount"] > 0:
			result.append(e)
	return result


## Vérifie si le coût peut être couvert en tenant compte de la substitution
## (règle 9) : ressource exacte possédée + 1 rhum par unité manquante, ou 2
## ressources (hors rhum, hors la ressource demandée) par unité manquante.
func _can_afford_port_cost(cost: Array) -> bool:
	for entry in cost:
		var icon: String = entry.get("icon", "")
		var amount: int = entry.get("amount", 0)
		var missing: int = amount - _get_icon_amount(icon)
		if missing <= 0:
			continue
		var rhum: int = _player["resources"].get("rum", 0)
		missing -= min(missing, rhum)
		if missing <= 0:
			continue
		var other_total := 0
		for key in GameFlow.RESOURCE_TYPES:
			if key == "rum" or ICON_TO_RESOURCE.get(icon, "") == key:
				continue
			other_total += _player["resources"].get(key, 0)
		if int(other_total / 2.0) < missing:
			return false
	return true


## Paie le coût demandé, en piochant d'abord dans la ressource exacte, puis
## en demandant au joueur comment couvrir le manque (1 rhum ou 2 d'une autre
## ressource par unité manquante - règle 9).
func _pay_port_cost_interactive(cost: Array) -> void:
	for entry in cost:
		var icon: String = entry.get("icon", "")
		var amount: int = entry.get("amount", 0)
		var direct: int = min(_get_icon_amount(icon), amount)
		_add_icon_amount(icon, -direct)
		var remaining: int = amount - direct

		while remaining > 0:
			var options: Array = []
			if _player["resources"].get("rum", 0) >= 1:
				options.append({"id": "rhum", "label": tr("Payer avec 1 rhum")})
			for key in GameFlow.RESOURCE_TYPES:
				if key == "rum" or ICON_TO_RESOURCE.get(icon, "") == key:
					continue
				if _player["resources"].get(key, 0) >= 2:
					options.append({"id": "sub:" + key, "label": tr("Payer avec 2 ") + GameFlow.RESOURCE_LABELS.get(key, key)})

			_board.narration_box.say_with_player(
				tr("Tour de %s : il manque ") + _icon_label(icon) + tr(" (%d restant(s)), comment payer ?"),
				_player, [remaining]
			)
			_board.narration_box.set_options(options)
			var choice: String = await _board.narration_box.option_selected

			if choice == "rhum":
				_player["resources"]["rum"] -= 1
			elif choice.begins_with("sub:"):
				_player["resources"][choice.substr(4)] -= 2
			remaining -= 1
			GameFlow.players_changed.emit()


## Faible (règle 12) : 1 ressource au choix parmi celles à droite de la
## flèche d'échange, sans dé, sans trésor, la carte reste en place.
func _run_port_work() -> String:
	var sea_key: String = _player.get("boat_sea", "")
	var card: GameCard = _board.card_draw_phase.get_current_revealed_card(sea_key)
	if card == null or card.card_type != GameCard.CardType.PORT:
		await _run_decline()
		return ""

	var activity: Dictionary = card.activities.get("commerce", {})
	var choices: Array = []
	for reward in activity.get("reward", []):
		var candidates: Array = reward["icons"] if reward.has("icons") else [reward.get("icon", "")]
		for ic in candidates:
			if not choices.has(ic):
				choices.append(ic)
	if choices.is_empty():
		choices = ["bois", "bouffe"]

	_board.narration_box.say_with_player(tr("Tour de %s : travaille au port, quelle ressource ?"), _player)
	var options: Array = []
	for c in choices:
		options.append({"id": c, "label": _icon_label(c)})
	options.append({"id": "back", "label": tr("↩ Retour")})
	_board.narration_box.set_options(options)
	var choice: String = await _board.narration_box.option_selected
	if choice == "back":
		return "cancel"
	_add_icon_amount(choice, 1)
	GameFlow.players_changed.emit()
	return ""


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
			await _board.narration_box.wait_for_continue()
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


## Lance des dés d'exploration en proposant, à chaque dé restant, de dépenser
## de la nourriture pour un dé supplémentaire (jusqu'à max_food_extra),
## puis retourne le nombre total d'étoiles obtenues. Partagé par île
## (ile_libre / voile_food_max1) et port périlleux (règle 9/10).
func _roll_exploration_stars(base_count: int, max_food_extra: int) -> int:
	var count: int = min(base_count, MAX_DICE_PER_ROLL)
	count = await _offer_rhum_extra_die(count)
	var food_spent := 0
	while food_spent < max_food_extra and count < MAX_DICE_PER_ROLL and _player["resources"]["food"] >= 1:
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

	var results: Array[String] = await _offer_fortune_dice_fixing(count, true)
	var stars := 0
	for r in results:
		stars += {"vide": 0, "un": 1, "double": 2}.get(r, 0)
	return stars


func _needed_stars(activity: Dictionary) -> int:
	for c in activity.get("cost", []):
		if c.get("icon", "") == "etoile":
			return c.get("amount", 0)
	return 0


func _meets_combat_requirement(results: Array[String], cost: Array) -> bool:
	var canons := 0
	var abordages := 0
	for r in results:
		if r == "canon":
			canons += 1
		elif r == "abordage":
			abordages += 1
	for c in cost:
		var icon: String = c.get("icon", "")
		var amt: int = c.get("amount", 0)
		if icon == "canon" and canons < amt:
			return false
		elif icon == "abordage" and abordages < amt:
			return false
		elif icon == "reussite" and (canons + abordages) < amt:
			return false
	return true


## Lance les dés adaptés à dice_rule et compare au(x) coût(s) requis :
## - "ile_libre" (île) : dés d'exploration, 1er gratuit, +1 par nourriture
##   dépensée (pas de max autre que MAX_DICE_PER_ROLL).
## - "voile_food_max1" (port périlleux / rencontres météo-créature) : dés
##   d'exploration = niveau de voile, +1 dé si 1 nourriture dépensée (max +1).
## - "armes" (combat) : dés de combat = niveau d'armes, pas de dé bonus.
func _roll_for_activity(activity: Dictionary, dice_rule: String) -> bool:
	match dice_rule:
		"ile_libre":
			var stars: int = await _roll_exploration_stars(1, MAX_DICE_PER_ROLL)
			return stars >= _needed_stars(activity)
		"voile_food_max1":
			var base: int = max(_player.get("sail_level", 1), 1)
			var stars: int = await _roll_exploration_stars(base, 1)
			return stars >= _needed_stars(activity)
		"armes":
			var count: int = min(max(_player.get("arms_level", 1), 1), MAX_DICE_PER_ROLL)
			count = await _offer_rhum_extra_die(count)
			var results: Array[String] = await _offer_fortune_dice_fixing(count, false)
			return _meets_combat_requirement(results, activity.get("cost", []))
		_:
			return true


## RHUM - "Motiver son équipage" (règle 10, mécanique transversale) : avant
## un jet de dés (exploration OU combat, jamais le commerce qui ne lance pas
## de dés), dépenser 1 rhum max PAR JET pour +1 dé additionnel. Distinct de
## la dépense de nourriture (spécifique à l'exploration, cf
## _roll_exploration_stars) : on ne propose donc qu'une seule fois, avant
## tout autre choix de dé, et jamais au-delà de MAX_DICE_PER_ROLL.
func _offer_rhum_extra_die(count: int) -> int:
	return await _offer_rhum_extra_die_for(_player, count)


func _offer_rhum_extra_die_for(actor: Dictionary, count: int) -> int:
	if count >= MAX_DICE_PER_ROLL or actor["resources"].get("rum", 0) < 1:
		return count
	_board.narration_box.say_with_player(
		tr("Tour de %s : dépenser 1 rhum pour motiver l'équipage (+1 dé) avant de lancer ?"), actor
	)
	_board.narration_box.set_options([
		{"id": "rhum", "label": tr("Dépenser 1 rhum (+1 dé)")},
		{"id": "skip", "label": tr("Ne pas dépenser de rhum")},
	])
	var choice: String = await _board.narration_box.option_selected
	if choice != "rhum":
		return count
	actor["resources"]["rum"] -= 1
	GameFlow.players_changed.emit()
	return count + 1


## FORTUNE - "Fixer ses dés" (règle 10, mécanique transversale) : avant de
## lancer, dépenser des fortunes pour fixer des faces au lieu de les
## lancer : 1 fortune = 1 étoile (exploration) ou 1 canon (combat) ;
## 2 fortunes = 1 double-étoile (exploration) ou 1 abordage (combat). On ne
## fixe que des dés déjà comptés dans "count" (pas d'achat de dé
## supplémentaire), et jamais après le lancer : les dés non fixés restants
## sont ensuite lancés normalement via _throw_dice.
func _offer_fortune_dice_fixing(count: int, is_white: bool) -> Array[String]:
	return await _offer_fortune_dice_fixing_for(_player, count, is_white)


func _offer_fortune_dice_fixing_for(actor: Dictionary, count: int, is_white: bool) -> Array[String]:
	var cheap_face: String = "un" if is_white else "canon"
	var costly_face: String = "double" if is_white else "abordage"
	var cheap_label: String = tr("1 étoile") if is_white else tr("Canon")
	var costly_label: String = tr("2 étoiles") if is_white else tr("Abordage")

	var fixed: Array[String] = []
	while fixed.size() < count:
		var fortune: int = actor["special_resources"].get("fortune", 0)
		var options: Array = []
		if fortune >= 1:
			options.append({"id": "cheap", "label": tr("Fixer un dé à %s (1 fortune)") % cheap_label})
		if fortune >= 2:
			options.append({"id": "costly", "label": tr("Fixer un dé à %s (2 fortunes)") % costly_label})
		if options.is_empty():
			break
		options.append({"id": "stop", "label": tr("Ne plus fixer, lancer les dés restants")})

		_board.narration_box.say_with_player(
			tr("Tour de %s : dépenser de la fortune pour fixer une face avant le lancer (%d/%d dé(s) fixé(s)) ?"),
			actor, [fixed.size(), count]
		)
		_board.narration_box.set_options(options)
		var choice: String = await _board.narration_box.option_selected
		if choice == "stop":
			break
		if choice == "cheap":
			actor["special_resources"]["fortune"] -= 1
			fixed.append(cheap_face)
		else:
			actor["special_resources"]["fortune"] -= 2
			fixed.append(costly_face)
		GameFlow.players_changed.emit()

	var remaining: int = count - fixed.size()
	var rolled: Array[String] = await _throw_dice(remaining, is_white) if remaining > 0 else []
	var results: Array[String] = []
	results.append_array(fixed)
	results.append_array(rolled)
	return results


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
	await _finalize_success(card, activity_key)


## Partie commune à toute activité réussie une fois les récompenses déjà
## distribuées (île, port, rencontre) : rangement en piste + gemme/jeton
## bonus (règle 10). Séparé de _grant_activity_success pour être réutilisé
## par le port, dont les récompenses/coûts ont leurs propres subtilités
## (substitution de ressources, malus de succès manquants...).
func _finalize_success(card: GameCard, activity_key: String) -> void:
	_card_retrieved_this_turn = true
	GameFlow.add_card_to_track(_player, activity_key, card)
	var progress: String = GameFlow.register_sea_progress(_player, card.sea_key)

	_board.narration_box.say_with_player(
		tr(N_SUCCESS + "\n\nTour de %s : activité réussie ! Carte rangée en piste ") + GameFlow.CARD_TRACK_LABELS.get(activity_key, activity_key) + ".",
		_player
	)
	await _board.narration_box.wait_for_continue()

	if progress == "gem":
		var gem_pile: Node2D = _board.get_gem_pile(card.sea_key)
		if gem_pile != null:
			var player_index: int = GameFlow.get_player_index(_player)
			if player_index != -1:
				gem_pile.take_gem(player_index)

	if progress != "none":
		_board.narration_box.say_with_player(_progress_message(progress), _player)
		await _board.narration_box.wait_for_continue()


func _progress_message(progress: String) -> String:
	match progress:
		"gem": return tr(N_GEM + "\n\nTour de %s : 1ère carte de cette mer — récupère la gemme correspondante !")
		"token_new": return tr(N_TOKEN_NEW + "\n\nTour de %s : 2e carte de cette mer — récupère le jeton bonus (s'il en reste) !")
		"token_refresh": return tr(N_TOKEN_REFRESH + "\n\nTour de %s : jeton bonus de cette mer rafraîchi (face effet).")
		_: return ""


## Échouer une activité (règle 10) : 1 fortune de compensation, puis l'effet
## négatif de la carte s'il y en a un (planche grise, non encore détaillée
## icône par icône - cf GAME_RULES.txt section 14 - donc parsée depuis le
## texte negative_effect du catalogue).
func _grant_activity_failure(card: GameCard) -> void:
	_player["special_resources"]["fortune"] += 1
	GameFlow.players_changed.emit()

	_board.narration_box.say_with_player(
		tr(N_FAILURE + "\n\nTour de %s : activité échouée. Reçoit 1 fortune en compensation."), _player
	)
	await _board.narration_box.wait_for_continue()

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
			tr(N_OVERLOAD + "\n\nTour de %s : bateau surchargé (%d/9), défausse une ressource."), _player, [_total_resources()]
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
	await _lose_planks_for(_player, n)


func _lose_planks_for(actor: Dictionary, n: int) -> void:
	actor["hull_planks"] = max(actor["hull_planks"] - n, 0)
	GameFlow.players_changed.emit()
	if actor["hull_planks"] <= 0:
		await _capsize_for(actor)
		if actor.get("id") == _player.get("id"):
			_turn_ended = true


## "Bateau chavire" (règle 10) : perd la moitié de ses ressources (arrondi
## à l'inférieur) et ne peut plus rien faire ce tour-ci.
func _capsize() -> void:
	await _capsize_for(_player)
	_turn_ended = true


## Variante générique (combat entre joueurs, règle 13) : n'importe quel
## joueur peut chavirer, pas seulement le joueur actif (_player). Ne force
## _turn_ended que si c'est bien _player qui chavire (sinon ça n'a pas de
## sens : l'autre joueur n'est pas en train de jouer son tour). Si
## loot_recipient est fourni, les ressources perdues lui reviennent au lieu
## d'être simplement défaussées (règle 13, "le gagnant vole les ressources
## défaussées par le perdant").
func _capsize_for(actor: Dictionary, loot_recipient: Dictionary = {}) -> void:
	_board.narration_box.say_with_player(tr(N_CAPSIZE + "\n\nTour de %s : le bateau chavire !"), actor)
	await _board.narration_box.wait_for_continue()

	_board.narration_box.say(tr(N_CAPSIZE_LOSE))
	await _board.narration_box.wait_for_click()

	var total := 0
	for r in GameFlow.RESOURCE_TYPES:
		total += actor["resources"].get(r, 0)
	var to_lose: int = int(total / 2.0)
	await _lose_resources_for(actor, to_lose, loot_recipient)
	GameFlow.players_changed.emit()


## "Perdre X ressources" (règle 10) : le joueur choisit lesquelles défausser
## (simplification de la règle physique "les plus éloignées du joueur").
func _lose_resources(n: int) -> void:
	await _lose_resources_for(_player, n)


func _lose_resources_for(actor: Dictionary, n: int, loot_recipient: Dictionary = {}) -> void:
	for i in range(n):
		var options: Array = []
		for r in GameFlow.RESOURCE_TYPES:
			if actor["resources"].get(r, 0) > 0:
				options.append({"id": r, "label": GameFlow.RESOURCE_LABELS[r]})
		if options.is_empty():
			break
		_board.narration_box.say_with_player(
			tr("Tour de %s : choisis une ressource à perdre (%d restante(s) à perdre)."), actor, [n - i]
		)
		_board.narration_box.set_options(options)
		var choice: String = await _board.narration_box.option_selected
		actor["resources"][choice] -= 1
		if not loot_recipient.is_empty():
			loot_recipient["resources"][choice] = loot_recipient["resources"].get(choice, 0) + 1
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
		await _board.narration_box.wait_for_continue()
		return

	# Forme non encore reconnue : affichée telle quelle, sans effet mécanique.
	_board.narration_box.say_with_player(tr("Tour de %s : effet — ") + text, _player)
	await _board.narration_box.wait_for_continue()
