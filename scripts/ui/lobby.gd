extends Control

@onready var status_label: Label = $StatusLabel
@onready var code_label: Label = $CodeLabel
@onready var players_list_box: VBoxContainer = $PlayersPanel/PlayersPanelMargin/PlayersPanelContent/PlayersListBox
@onready var start_button: Button = $StartButton
@onready var quit_button: Button = $QuitButton
@onready var player_setup_popup: Control = $PlayerSetupPopup

## Devient vrai après que Network.request_join() a été envoyé pour CETTE
## instance (empêche de rouvrir la popup tant qu'on attend une réponse).
var _has_registered: bool = false
## Devient vrai dès que la popup a été ouverte une première fois (empêche de
## la rouvrir/réinitialiser à chaque signal de statut réseau reçu).
var _setup_opened: bool = false
## Vrai si le serveur est un "Serveur dédié" (lancement Raspberry Pi en
## ligne de commande) : il ne joue pas, on n'ouvre jamais la popup
## nom/couleur pour lui.
var _dedicated_server_chosen: bool = false
## Cf request_lobby_preview/_on_lobby_preview_received : en mode "join",
## popup nom/couleur retardée jusqu'à réception de la liste des joueurs déjà
## inscrits (pour griser leurs couleurs), pas seulement jusqu'à connexion.
var _preview_requested: bool = false
var _preview_received: bool = false


func _ready() -> void:
	status_label.text = ""
	start_button.visible = multiplayer.is_server()
	start_button.disabled = true
	start_button.pressed.connect(_on_start_pressed)

	quit_button.pressed.connect(_on_quit_pressed)

	code_label.visible = multiplayer.is_server()
	if multiplayer.is_server():
		code_label.text = tr("Code de la partie : %s") % Network.room_code

	player_setup_popup.player_confirmed.connect(_on_local_player_confirmed)

	GameFlow.players_changed.connect(_refresh_list)
	Network.join_rejected.connect(_on_join_rejected)
	Network.player_list_changed.connect(_on_network_status_changed)
	Network.lobby_synced.connect(_refresh_list)
	Network.lobby_preview_received.connect(_on_lobby_preview_received)

	_refresh_list()
	if Network.is_dedicated_server_launch():
		_setup_opened = true
		_dedicated_server_chosen = true
		Network.set_host_name("Serveur (Raspberry Pi)")
		return
	_try_open_local_setup()


func _try_open_local_setup() -> void:
	if _has_registered or _setup_opened or _dedicated_server_chosen:
		return
	if GameFlow.game_mode == "join":
		var mp_peer: MultiplayerPeer = multiplayer.multiplayer_peer
		if mp_peer == null or mp_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			status_label.text = tr("Connexion à l'hôte...")
			return
		# On attend la liste des joueurs déjà inscrits (avec leur couleur)
		# avant d'ouvrir la popup, sans quoi GameFlow.players serait encore
		# vide côté client à cet instant (elle n'est normalement remplie
		# qu'APRÈS l'inscription, cf _sync_lobby_state) et aucune couleur ne
		# serait grisée, contrairement aux autres modes (règle demandée :
		# mêmes couleurs grisées qu'en partie locale/debug).
		if not _preview_requested:
			_preview_requested = true
			status_label.text = tr("Connexion à l'hôte...")
			Network.request_lobby_preview()
			return
		if not _preview_received:
			return
		status_label.text = ""
		_setup_opened = true
		player_setup_popup.open_for_new_player()
		return
	# GameFlow.game_mode == "host" : l'hôte joue automatiquement (le choix
	# manuel "Rejoindre en tant que joueur" a été supprimé). Le mode
	# "serveur dédié" (Raspberry Pi qui ne joue pas) reste géré uniquement
	# via Network.is_dedicated_server_launch() (lancement en ligne de
	# commande), voir plus haut dans _ready().
	status_label.text = ""
	_setup_opened = true
	player_setup_popup.open_for_new_player()


func _on_network_status_changed() -> void:
	_try_open_local_setup()


func _on_lobby_preview_received() -> void:
	_preview_received = true
	if _setup_opened and player_setup_popup.visible:
		# Rafraîchissement après rejet (cf _on_join_rejected) : la popup est
		# déjà ouverte, on met juste à jour le grisé sans toucher au nom déjà
		# tapé ni à la sélection de couleur en cours (sauf si celle-ci vient
		# justement d'être prise entre-temps, cf refresh_colors()).
		player_setup_popup.refresh_colors()
		return
	_try_open_local_setup()


func _on_local_player_confirmed(player_name: String, color: String) -> void:
	player_setup_popup.visible = false
	_has_registered = true
	Network.request_join(player_name, color)


func _on_join_rejected(reason: String) -> void:
	_has_registered = false
	player_setup_popup.visible = true
	player_setup_popup.show_error(reason)
	# L'état grisé affiché peut être périmé (un autre joueur a pu prendre une
	# couleur/un nom entre l'ouverture de la popup et ce rejet) : on redemande
	# un aperçu à jour de l'hôte, cf _on_lobby_preview_received ci-dessous.
	_preview_received = false
	Network.request_lobby_preview()


func _refresh_list() -> void:
	print("[Lobby] _refresh_list, %d joueur(s)" % GameFlow.players.size())
	for child in players_list_box.get_children():
		child.queue_free()

	# id du JOUEUR qui correspond au pair hôte (peer_id 1), s'il joue lui-même.
	var host_player_id: int = Network.peer_player_map.get(1, -1)

	for p in GameFlow.players:
		players_list_box.add_child(_build_player_row("%s — %s" % [p["name"], p["color"]], p["id"] == host_player_id))

	# Hôte en "Serveur dédié" (pas dans GameFlow.players, mais a un nom
	# d'affichage) : ligne séparée avec la couronne, sans couleur.
	if host_player_id == -1 and not Network.host_name.is_empty():
		players_list_box.add_child(_build_player_row(Network.host_name, true))

	if multiplayer.is_server():
		start_button.disabled = GameFlow.players.is_empty()


## Construit une ligne "[couronne si is_host] Nom — Couleur".
func _build_player_row(display_text: String, is_host: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	if is_host:
		var icon := TextureRect.new()
		icon.texture = load("res://assets/art/ui/crown.svg")
		# Ne doit jamais dépasser la taille du texte du pseudo de plus de 6px.
		var text_size: float = ThemeDB.fallback_font_size
		icon.custom_minimum_size = Vector2(text_size + 6.0, text_size + 6.0)
		# EXPAND_IGNORE_SIZE : sans ça, la taille minimale du TextureRect est
		# celle du texture importé (crown.svg fait 1280x815px), qui écrase
		# purement et simplement custom_minimum_size -> icône bien plus
		# grande que le texte du pseudo. Avec ce mode, custom_minimum_size
		# fait foi et stretch_mode se charge de mettre le SVG à l'échelle.
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
	var lbl := Label.new()
	lbl.text = display_text
	row.add_child(lbl)
	return row


func _on_start_pressed() -> void:
	Network.request_start_game()


func _on_quit_pressed() -> void:
	Network.close_connection()
	GameFlow.reset_players()
	GameFlow.game_mode = "local"
	GameFlow.go_to_title()
