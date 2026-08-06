extends Control

## Mêmes couleurs que player_setup_popup.gd (dupliquées ici car ce script
## n'a pas de class_name à référencer depuis lobby.gd) : style des pastilles
## de couleur interactives du panneau ColorPickerPanel (choix de couleur du
## joueur local, à côté de la liste d'attente).
const SWATCH_TAKEN_COLOR := Color(0.45, 0.45, 0.45)
const SWATCH_SELECTED_BORDER := Color(1.0, 1.0, 1.0)

@onready var status_label: Label = $StatusLabel
@onready var code_label: Label = $CodeLabel
@onready var players_list_box: VBoxContainer = $PlayersPanel/PlayersPanelMargin/PlayersPanelContent/PlayersListBox
@onready var start_button: Button = $StartButton
@onready var quit_button: Button = $QuitButton
@onready var player_setup_popup: Control = $PlayerSetupPopup
@onready var background: TextureRect = $Background
@onready var color_picker_panel: PanelContainer = $ColorPickerPanel
@onready var color_swatches_box: HBoxContainer = $ColorPickerPanel/ColorPickerMargin/ColorPickerContent/ColorSwatchesBox

## Dossier contenant les images de fond du lobby : une est choisie au hasard
## à chaque ouverture (cf _apply_random_background). Fichiers attendus :
## .png/.jpg/.jpeg/.webp ; tout autre fichier (ou le dossier absent/vide)
## est simplement ignoré, sans erreur bloquante.
const BACKGROUND_DIR := "res://assets/art/ui/bgi"
const BACKGROUND_EXTENSIONS := ["png", "jpg", "jpeg", "webp"]

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

	_apply_random_background()

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
	Network.color_change_rejected.connect(_on_color_change_rejected)

	_refresh_list()
	if Network.is_dedicated_server_launch():
		_setup_opened = true
		_dedicated_server_chosen = true
		Network.set_host_name("Serveur (Raspberry Pi)")
		return
	_try_open_local_setup()


## Choisit une image au hasard dans BACKGROUND_DIR et la met en fond plein
## écran (recadrée, pas déformée : STRETCH_KEEP_ASPECT_COVERED). Silencieux
## si le dossier est absent/vide (pas d'image = pas de fond, écran uni).
func _apply_random_background() -> void:
	var path := _pick_random_background_path()
	if path.is_empty():
		return
	var tex: Texture2D = load(path)
	if tex == null:
		return
	background.texture = tex


func _pick_random_background_path() -> String:
	var dir := DirAccess.open(BACKGROUND_DIR)
	if dir == null:
		return ""
	var candidates: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and BACKGROUND_EXTENSIONS.has(file_name.get_extension().to_lower()):
			candidates.append(BACKGROUND_DIR + "/" + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	if candidates.is_empty():
		return ""
	return candidates[randi() % candidates.size()]


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
	# id du JOUEUR qui correspond à CETTE instance (le "moi" local, hôte ou
	# client) : sert à afficher SES pastilles de couleur dans le panneau
	# dédié ColorPickerPanel ci-dessous (cf _refresh_color_picker).
	var local_player_id: int = Network.peer_player_map.get(multiplayer.get_unique_id(), -1)

	for p in GameFlow.players:
		players_list_box.add_child(_build_player_row(p, p["id"] == host_player_id))

	# Hôte en "Serveur dédié" (pas dans GameFlow.players, mais a un nom
	# d'affichage) : ligne séparée avec la couronne, sans couleur.
	if host_player_id == -1 and not Network.host_name.is_empty():
		players_list_box.add_child(_build_name_only_row(Network.host_name, true))

	if multiplayer.is_server():
		start_button.disabled = GameFlow.players.is_empty()

	_refresh_color_picker(local_player_id)

	# Un joueur a pu changer/perdre sa couleur pendant que la popup nom/
	# couleur d'un NOUVEAU joueur est ouverte (cf
	# player_setup_popup.open_for_new_player) : on la rafraîchit pour que son
	# grisé reste synchronisé avec la liste ci-dessus, sans rien réinitialiser
	# d'autre (nom déjà tapé, etc.).
	if player_setup_popup.visible:
		player_setup_popup.refresh_colors()


## Remplit le panneau dédié ColorPickerPanel (à côté de la liste des
## joueurs) avec les pastilles de couleur du joueur LOCAL uniquement : ce
## panneau reste cette instance de client/hôte tant qu'elle n'est pas
## inscrite (local_player_id == -1, ex: popup nom/couleur pas encore
## confirmée, ou hôte "Serveur dédié" qui ne joue pas).
func _refresh_color_picker(local_player_id: int) -> void:
	for child in color_swatches_box.get_children():
		child.queue_free()
	var local_player: Dictionary = GameFlow.get_player_by_id(local_player_id)
	color_picker_panel.visible = not local_player.is_empty()
	if local_player.is_empty():
		return
	for color_name in GameFlow.COLORS:
		color_swatches_box.add_child(_build_color_swatch_button(local_player, color_name))


## Construit la ligne "[couronne si is_host] Nom — Couleur" d'un joueur déjà
## inscrit.
func _build_player_row(p: Dictionary, is_host: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	if is_host:
		row.add_child(_build_crown_icon())
	var lbl := Label.new()
	lbl.text = "%s — %s" % [p["name"], p["color"]]
	row.add_child(lbl)
	return row


## Ligne "[couronne si is_host] Nom" sans couleur, pour l'hôte en "Serveur
## dédié" (cf _refresh_list) qui n'est pas un joueur de GameFlow.players.
func _build_name_only_row(display_text: String, is_host: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	if is_host:
		row.add_child(_build_crown_icon())
	var lbl := Label.new()
	lbl.text = display_text
	row.add_child(lbl)
	return row


func _build_crown_icon() -> TextureRect:
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
	return icon


## Une pastille cliquable du panneau ColorPickerPanel : grisée/désactivée si
## prise par un AUTRE joueur (GameFlow.is_color_taken), bordure blanche sur
## la couleur actuelle du joueur local. Cf _on_lobby_color_pressed pour
## l'envoi réseau du changement.
func _build_color_swatch_button(p: Dictionary, color_name: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(28, 28)
	btn.text = ""
	btn.focus_mode = Control.FOCUS_NONE
	var is_current: bool = color_name == p["color"]
	var taken_by_other: bool = GameFlow.is_color_taken(color_name) and not is_current
	btn.disabled = taken_by_other
	var base_color: Color = SWATCH_TAKEN_COLOR if taken_by_other else GameFlow.COLOR_VALUES[color_name]
	var style := StyleBoxFlat.new()
	style.bg_color = base_color
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	if is_current:
		style.border_width_left = 3
		style.border_width_top = 3
		style.border_width_right = 3
		style.border_width_bottom = 3
		style.border_color = SWATCH_SELECTED_BORDER
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_stylebox_override("disabled", style)
	btn.pressed.connect(_on_lobby_color_pressed.bind(color_name))
	return btn


## Envoie la demande de changement de couleur à l'hôte (directement si l'on
## EST l'hôte, sinon par RPC, cf Network.request_change_color). Aucune mise
## à jour locale immédiate : on attend la rediffusion _sync_lobby_state pour
## que la liste et la popup nom/couleur restent la SEULE source de vérité,
## cohérente entre tous les joueurs (cf _refresh_list).
func _on_lobby_color_pressed(color_name: String) -> void:
	Network.request_change_color(color_name)


func _on_color_change_rejected(reason: String) -> void:
	status_label.text = reason


func _on_start_pressed() -> void:
	Network.request_start_game()


func _on_quit_pressed() -> void:
	Network.close_connection()
	GameFlow.reset_players()
	GameFlow.game_mode = "local"
	GameFlow.go_to_title()
