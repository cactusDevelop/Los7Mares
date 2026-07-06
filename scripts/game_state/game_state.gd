class_name GameState
extends RefCounted

const NUMBER_OF_SEAS = 7
const SLOTS_PER_SEA = 5
const RESOURCE_TYPES = ["wood", "steel", "food", "wool", "rum"]
const SPECIAL_RESOURCE_TYPES = ["fortune", "treasure"]

var players: Dictionary = {}
var seas: Array = []
var current_player: int = 0


func setup_new_game(number_of_players: int) -> void:
	print("Initialisation d'une nouvelle partie avec ", number_of_players, " joueurs")
	_setup_players(number_of_players)
	_setup_seas()
	current_player = 0
	print("Partie initialisée : ", players.size(), " joueurs, ", seas.size(), " mers")


func _setup_players(number_of_players: int) -> void:
	players.clear()
	for i in range(number_of_players):
		var resources: Dictionary = {}
		for res_type in RESOURCE_TYPES:
			resources[res_type] = 0
		
		var special_resources: Dictionary = {}
		for res_type in SPECIAL_RESOURCE_TYPES:
			special_resources[res_type] = 0
		
		players[i] = {
			"name": "Joueur " + str(i + 1),
			"resources": resources,
			"special_resources": special_resources,
			"has_own_parrot": true,   # possède son propre perroquet au départ
			"captured_parrots": [],   # liste des id de joueurs dont il a capturé le perroquet
		}


func _setup_seas() -> void:
	seas.clear()
	for sea_id in range(NUMBER_OF_SEAS):
		var slots: Array = []
		for slot_id in range(SLOTS_PER_SEA):
			slots.append({
				"slot_id": slot_id,
				"occupied_by": -1,
				"piece_type": "",
			})
		seas.append({
			"id": sea_id,
			"name": "Mer " + str(sea_id + 1),
			"slots": slots,
			"event_deck": [],   # sera rempli plus tard avec de vraies cartes
			"discard_pile": [],
		})


func place_piece(player_id: int, sea_id: int, slot_id: int, piece_type: String) -> bool:
	if sea_id < 0 or sea_id >= seas.size():
		print("Erreur : mer invalide")
		return false
	
	var sea = seas[sea_id]
	if slot_id < 0 or slot_id >= sea.slots.size():
		print("Erreur : case invalide")
		return false
	
	var slot = sea.slots[slot_id]
	if slot.occupied_by != -1:
		print("Erreur : case déjà occupée")
		return false
	
	slot.occupied_by = player_id
	slot.piece_type = piece_type
	print("Joueur ", player_id, " a placé son ", piece_type, " sur ", sea.name, ", case ", slot_id)
	return true


# --- RESSOURCES ---

func add_resource(player_id: int, resource_type: String, amount: int) -> void:
	if not players.has(player_id):
		print("Erreur : joueur invalide")
		return
	if not RESOURCE_TYPES.has(resource_type):
		print("Erreur : type de ressource invalide")
		return
	players[player_id].resources[resource_type] += amount
	print("Joueur ", player_id, " : +", amount, " ", resource_type, " (total: ", players[player_id].resources[resource_type], ")")


func add_special_resource(player_id: int, resource_type: String, amount: int) -> void:
	if not players.has(player_id):
		print("Erreur : joueur invalide")
		return
	if not SPECIAL_RESOURCE_TYPES.has(resource_type):
		print("Erreur : type de ressource spéciale invalide")
		return
	players[player_id].special_resources[resource_type] += amount
	print("Joueur ", player_id, " : +", amount, " ", resource_type, " spécial (total: ", players[player_id].special_resources[resource_type], ")")


# --- PERROQUETS ---

# Un joueur capture le perroquet d'un autre joueur
func capture_parrot(capturer_id: int, victim_id: int) -> bool:
	if not players.has(capturer_id) or not players.has(victim_id):
		print("Erreur : joueur invalide")
		return false
	
	if not players[victim_id].has_own_parrot and not players[victim_id].captured_parrots.has(victim_id):
		# Le perroquet de la victime a déjà été capturé par quelqu'un d'autre, pas par elle-même
		pass
	
	# On retire le perroquet à la victime (soit le sien, soit un qu'elle avait capturé)
	if players[victim_id].has_own_parrot:
		players[victim_id].has_own_parrot = false
		players[capturer_id].captured_parrots.append(victim_id)
		print("Joueur ", capturer_id, " a capturé le perroquet du Joueur ", victim_id)
		return true
	else:
		print("Erreur : ce joueur n'a plus son propre perroquet à capturer")
		return false


# --- CARTES ÉVÉNEMENTS ---

# Pour l'instant les cartes sont juste des noms (String), on affinera plus tard
func setup_event_deck(sea_id: int, card_names: Array) -> void:
	if sea_id < 0 or sea_id >= seas.size():
		print("Erreur : mer invalide")
		return
	seas[sea_id].event_deck = card_names.duplicate()
	seas[sea_id].event_deck.shuffle()
	print(seas[sea_id].name, " : pioche de ", seas[sea_id].event_deck.size(), " cartes créée")


# Pioche la carte du dessus quand un joueur arrive sur une mer
func draw_event_card(sea_id: int) -> String:
	if sea_id < 0 or sea_id >= seas.size():
		print("Erreur : mer invalide")
		return ""
	
	var sea = seas[sea_id]
	if sea.event_deck.is_empty():
		if sea.discard_pile.is_empty():
			print("Erreur : plus aucune carte disponible pour ", sea.name)
			return ""
		# On remélange la défausse pour reformer une pioche
		sea.event_deck = sea.discard_pile.duplicate()
		sea.discard_pile.clear()
		sea.event_deck.shuffle()
		print(sea.name, " : défausse remélangée en nouvelle pioche")
	
	var card = sea.event_deck.pop_back()
	sea.discard_pile.append(card)
	print(sea.name, " : carte piochée -> ", card)
	return card
