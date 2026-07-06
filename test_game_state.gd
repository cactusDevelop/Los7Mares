extends Node

func _ready() -> void:
	var game_state = GameState.new()
	game_state.setup_new_game(3)
	
	# Placement de pions
	game_state.place_piece(0, 2, 3, "captain")
	
	# Ressources
	game_state.add_resource(0, "wood", 5)
	game_state.add_resource(0, "rum", 2)
	game_state.add_special_resource(0, "treasure", 1)
	
	# Capture de perroquet : joueur 0 capture celui du joueur 1
	game_state.capture_parrot(0, 1)
	
	# Cartes événements sur la mer 0
	game_state.setup_event_deck(0, ["Tempête", "Butin trouvé", "Mutinerie", "Vent favorable"])
	game_state.draw_event_card(0)
	game_state.draw_event_card(0)
	
	print("--- État final joueur 0 ---")
	print(game_state.players[0])
