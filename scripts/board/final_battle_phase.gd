extends Node

## Combat final en cas d'égalité au score (GAME_RULES.txt, règle 8,
## "Égalité au score final -> Combat final") :
## - Chaque joueur à égalité ajuste son bateau à 7 planches et 5 canons
##   (niveau d'armes 5), gratuitement et uniquement pour ce combat (aucun
##   effet permanent sur sa fiche joueur).
## - Interdiction d'utiliser rhum, fortune ou tout autre effet : on ne
##   propose donc ici que le lancer de dés, sans aucune option de dépense.
## - Vainqueur = celui qui gagne la Phase des canons OU la Phase
##   d'abordage. Si aucun vainqueur, on répète le combat (coque conservée,
##   donc on relance avec 7 planches fraîches à chaque répétition) jusqu'à
##   en obtenir un.
##
## [Extension - la règle d'origine ne décrit qu'un duel à 2 joueurs] : en
## cas d'égalité à plus de 2 joueurs, chaque joueur encaisse la somme des
## canons de TOUS les autres joueurs à égalité (mêlée générale). La phase
## d'abordage, si elle a lieu, ne compare alors que les survivants de la
## phase des canons.

signal finished(winner_id: int)

const BLACK_DIE_SCENE := preload("res://scenes/effects/dice_3d.tscn")
const FINAL_BATTLE_PLANKS := 7
const FINAL_BATTLE_DICE := 5
const DICE_PAUSE := 0.6

var _board: Board
var _tied_ids: Array[int] = []


## Lance le combat final entre les joueurs de tied_ids (à égalité au score)
## et renvoie l'id du vainqueur une fois qu'il y en a un.
func start(board: Board, tied_ids: Array[int]) -> int:
	_board = board
	_tied_ids = tied_ids

	var names: Array[String] = []
	for pid in _tied_ids:
		names.append(_find_player(pid)["name"])
	_board.narration_box.say(tr("Égalité au score final entre %s ! Combat final : chaque bateau est ajusté à 7 planches et 5 canons, sans rhum ni fortune.") % ", ".join(names))
	await _board.narration_box.wait_for_click()

	var winner_id := -1
	while winner_id == -1:
		winner_id = await _run_one_round()

	var winner := _find_player(winner_id)
	_board.narration_box.say_with_player(tr("%s remporte le combat final !"), winner)
	await _board.narration_box.wait_for_click()

	finished.emit(winner_id)
	return winner_id


## Un "round" = 1 combat complet (phase des canons puis, si besoin, phase
## d'abordage) avec des bateaux frais à 7 planches. Renvoie l'id du
## vainqueur, ou -1 si le round ne départage personne (à relancer).
func _run_one_round() -> int:
	var rolls: Dictionary = {}  # player_id -> {"canons": int, "abordages": int}
	for pid in _tied_ids:
		rolls[pid] = await _roll_for_player(pid)

	# Phase des canons : chaque joueur encaisse les canons de tous les
	# autres joueurs encore en lice (règle 9 "Gérer une rencontre",
	# généralisée ici à N joueurs, cf note d'extension en tête de fichier).
	var planks: Dictionary = {}
	for pid in _tied_ids:
		var damage := 0
		for other_id in _tied_ids:
			if other_id != pid:
				damage += rolls[other_id]["canons"]
		planks[pid] = max(FINAL_BATTLE_PLANKS - damage, 0)

	var survivors: Array[int] = []
	for pid in _tied_ids:
		if planks[pid] > 0:
			survivors.append(pid)

	_board.narration_box.say(tr("Phase des canons : %s") % _describe_canon_phase(planks))
	await _board.narration_box.wait_for_click()

	if survivors.size() == 1:
		return survivors[0]
	if survivors.is_empty():
		_board.narration_box.say(tr("Tous les bateaux chavirent ! Aucun vainqueur, on relance le combat."))
		await _board.narration_box.wait_for_click()
		return -1

	# Phase d'abordage : seuls les survivants de la phase des canons
	# comptent (règle : "sinon -> phase d'abordage").
	var best_abordages := -1
	for pid in survivors:
		best_abordages = max(best_abordages, rolls[pid]["abordages"])
	var abordage_winners: Array[int] = []
	for pid in survivors:
		if rolls[pid]["abordages"] == best_abordages:
			abordage_winners.append(pid)

	_board.narration_box.say(tr("Phase d'abordage : %s") % _describe_abordage_phase(survivors, rolls))
	await _board.narration_box.wait_for_click()

	if abordage_winners.size() == 1:
		return abordage_winners[0]

	_board.narration_box.say(tr("Égalité aux abordages ! Aucun vainqueur, on relance le combat."))
	await _board.narration_box.wait_for_click()
	return -1


func _describe_canon_phase(planks: Dictionary) -> String:
	var parts: Array[String] = []
	for pid in _tied_ids:
		parts.append("%s : %d planche(s)" % [_find_player(pid)["name"], planks[pid]])
	return ", ".join(parts)


func _describe_abordage_phase(survivors: Array[int], rolls: Dictionary) -> String:
	var parts: Array[String] = []
	for pid in survivors:
		parts.append("%s : %d abordage(s)" % [_find_player(pid)["name"], rolls[pid]["abordages"]])
	return ", ".join(parts)


## Lance les 5 dés de combat (armes niveau 5) d'un joueur et renvoie le
## nombre de canons et d'abordages obtenus.
func _roll_for_player(player_id: int) -> Dictionary:
	var player := _find_player(player_id)
	var viewport_container: Control = _board.get_node("UI/SubViewportContainer")
	var dice_roll: Node3D = _board.get_node("UI/SubViewportContainer/SubViewport/DiceRoll3D")

	viewport_container.visible = true
	_board.narration_box.say_with_player(tr("Tour de %s : lance ses 5 dés de combat..."), player)
	_board.narration_box.set_options([])

	var scenes: Array[PackedScene] = []
	for i in range(FINAL_BATTLE_DICE):
		scenes.append(BLACK_DIE_SCENE)
	dice_roll.roll_mixed(scenes)
	var results: Array[String] = await dice_roll.roll_finished
	await _board.get_tree().create_timer(DICE_PAUSE).timeout
	viewport_container.visible = false

	var canons := 0
	var abordages := 0
	for r in results:
		if r == "canon":
			canons += 1
		elif r == "abordage":
			abordages += 1
	return {"canons": canons, "abordages": abordages}


func _find_player(player_id: int) -> Dictionary:
	for p in GameFlow.players:
		if p["id"] == player_id:
			return p
	return {}
