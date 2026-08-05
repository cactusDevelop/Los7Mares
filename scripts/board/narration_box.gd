extends PanelContainer

@onready var action_label: Label = $Padding/Content/ActionLabel
@onready var label: RichTextLabel = $Padding/Content/NarrationLabel
@onready var buttons_box: VBoxContainer = $Padding/Content/ButtonsBox

## Émis quand un bouton de choix (cf set_options) est cliqué.
signal option_selected(id: String)

## Émis quand la boîte elle-même est cliquée pendant qu'un message "de
## lecture" (sans bouton) attend d'être passé, cf wait_for_click().
signal advance_requested

## Vrai entre le début et la fin d'un wait_for_click() : un clic sur cette
## boîte OU sur le plateau (cf board._unhandled_input) fait alors avancer.
var _awaiting_advance: bool = false

## Délai entre chaque lettre affichée (en secondes)
const CHAR_REVEAL_DELAY := 0.015
const BOX_WIDTH := 260.0
const LABEL_WIDTH := 220.0
const BUTTON_HEIGHT := 44.0
const BUTTON_FONT_SIZE := 16
## Filtre noir semi-transparent (au lieu d'un fond blanc opaque), même
## principe que le fondu noir de l'annonce "Tour X" (pion_selection_panel).
const PANEL_FILTER_ALPHA := 0.75
## Épaisseur du contour indiquant la couleur du joueur dont c'est le tour.
const OUTLINE_WIDTH := 4

var _reveal_tween: Tween
var _panel_style: StyleBoxFlat
var _current_option_ids: Array = []

## Id (GameFlow.players) du joueur à qui s'adresse le choix affiché
## actuellement, posé par say_with_player. En réseau, seul l'écran de CE
## joueur affiche réellement les boutons de set_options() et peut cliquer
## "Continuer" (wait_for_click/wait_for_continue) : tout le monde voit le
## même texte, mais un seul joueur agit à la fois, cf énoncé "chaque joueur
## a le contrôle sur les actions qui le concernent". N'est jamais remis à
## -1 par say()/hide_box() (même logique que le contour couleur, qui reste
## lui aussi jusqu'au prochain say_with_player), pour rester correct sur les
## messages "de lecture" intercalés (ex: "action impossible") qui ne
## changent pas de joueur concerné.
var _active_player_id: int = -1


func _ready() -> void:
	# Onglet fixe de la sidebar gauche : toujours visible, ne se repositionne
	# plus jamais (contrairement à l'ancienne bulle flottante en bas d'écran).
	# Sa hauteur s'ajuste en revanche dynamiquement à son contenu (texte +
	# boutons éventuels), cf _layout().
	visible = true

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, PANEL_FILTER_ALPHA)
	style.set_corner_radius_all(UiTheme.POPUP_CORNER_RADIUS)
	style.border_width_left = OUTLINE_WIDTH
	style.border_width_top = OUTLINE_WIDTH
	style.border_width_right = OUTLINE_WIDTH
	style.border_width_bottom = OUTLINE_WIDTH
	style.border_color = Color(0, 0, 0, 0)  # invisible tant qu'aucun joueur n'est concerné
	add_theme_stylebox_override("panel", style)
	_panel_style = style

	action_label.add_theme_color_override("font_color", Color.WHITE)
	action_label.add_theme_font_size_override("font_size", 20)

	label.add_theme_color_override("default_color", Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	# Calcule le retour à la ligne sur le texte COMPLET (déjà mis en forme),
	# indépendamment du nombre de lettres actuellement révélées. Sans ça,
	# Godot ne tient compte que des lettres visibles pour le wrap, ce qui
	# fait sauter les mots de fin de ligne pendant l'animation.
	label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)

	buttons_box.add_theme_constant_override("separation", 8)

	gui_input.connect(_on_box_gui_input)

	call_deferred("_layout")


## Affiche un texte de narration simple (sans nom de joueur à colorer).
## N'efface PAS le contour couleur ni les boutons en cours (permet d'afficher
## un message ponctuel, ex. "action impossible", sans perdre le contexte du
## joueur actif ni les boutons affichés).
func say(text: String) -> void:
	_start_reveal(text)


## Affiche un texte de narration où "%s" est remplacé par le nom du joueur,
## affiché dans sa couleur (ex: format = "Tour de %s : joue."), et donne au
## contour de la boîte la couleur de ce joueur : cette boîte sert d'unique
## indicateur "à qui le tour" (cases action, pose du bateau, etc.), à la
## place des contours individuels dispersés sur le plateau.
## extra_args : arguments supplémentaires insérés après le nom du joueur
## (ex: format = "Tour de %s : il reste %d points.", extra_args = [points]).
func say_with_player(format: String, player: Dictionary, extra_args: Array = []) -> void:
	_active_player_id = player.get("id", -1)
	var player_color: Color = GameFlow.COLOR_VALUES[player["color"]]
	var colored_name := "[color=#%s]%s[/color]" % [player_color.to_html(false), player["name"]]
	var args: Array = [colored_name] + extra_args
	_start_reveal(format % args)
	set_outline_color(player_color)


## Comme say_with_player, mais affiche un texte DIFFÉRENT selon que ce client
## est celui du joueur concerné ou non (cf énoncé : le joueur actif doit voir
## une phrase à la 2e personne, ex. "Lance les dés", tandis que les autres
## voient une phrase à la 3e personne nommant le joueur, ex. "Thomas lance
## les dés"). mine_format s'adresse au joueur actif (pas de nom à insérer,
## % avec extra_args uniquement si besoin) ; others_format reçoit le nom
## coloré du joueur en 1er argument, puis extra_args (comme say_with_player).
## En hotseat/solo (_is_local_player_active() toujours vrai), tout le monde
## partage le même écran : mine_format est donc systématiquement affiché.
func say_for_actor(mine_format: String, others_format: String, player: Dictionary, extra_args: Array = []) -> void:
	_active_player_id = player.get("id", -1)
	var player_color: Color = GameFlow.COLOR_VALUES[player["color"]]
	set_outline_color(player_color)
	if _is_local_player_active():
		if extra_args.is_empty():
			_start_reveal(mine_format)
		else:
			_start_reveal(mine_format % extra_args)
	else:
		var colored_name := "[color=#%s]%s[/color]" % [player_color.to_html(false), player["name"]]
		var args: Array = [colored_name] + extra_args
		_start_reveal(others_format % args)


## Couleur du contour de la boîte (couleur du joueur dont c'est le tour).
func set_outline_color(color: Color) -> void:
	_panel_style.border_color = color


## Remet le contour à l'état neutre (aucun joueur concerné, ex: écran de fin).
func clear_outline() -> void:
	_panel_style.border_color = Color(0, 0, 0, 0)


## Affiche une liste de boutons de choix sous le texte de narration.
## options: Array[{"id": String, "label": String}]. Liste vide = pas de bouton.
func set_options(options: Array) -> void:
	# _current_option_ids reste rempli pour TOUT le monde (utilisé par
	# has_options()/skip(), et par l'hôte pour valider les choix reçus des
	# clients, cf _request_option_rpc) : seul l'AFFICHAGE des boutons est
	# restreint au joueur concerné juste en dessous.
	_current_option_ids = options.map(func(o): return o["id"])
	for child in buttons_box.get_children():
		buttons_box.remove_child(child)
		child.queue_free()
	if _is_local_player_active():
		for option in options:
			var btn := Button.new()
			btn.text = option["label"]
			btn.custom_minimum_size = Vector2(LABEL_WIDTH, BUTTON_HEIGHT)
			btn.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
			btn.pressed.connect(_on_button_pressed.bind(option["id"]))
			buttons_box.add_child(btn)
	call_deferred("_layout")


## Vrai si CET écran doit afficher/activer les boutons/le clic d'avancement
## en cours : toujours vrai en partie locale/hotseat (une seule machine),
## sinon seulement pour le joueur dont c'est réellement le tour de décider
## (cf _active_player_id, posé par say_with_player). Si _active_player_id
## vaut -1 (aucun say_with_player() n'a encore été appelé, ex: message
## générique juste après la distribution des tuiles mer, avant le tout
## premier say_with_player de la partie), le message ne concerne aucun
## joueur en particulier : n'importe quel joueur peut alors cliquer pour
## avancer, sans quoi PERSONNE (y compris l'hôte) ne le pourrait jamais.
func _is_local_player_active() -> bool:
	if GameFlow.game_mode != "host" and GameFlow.game_mode != "join":
		return true
	var my_player_id: int = Network.peer_player_map.get(multiplayer.get_unique_id(), -1)
	return my_player_id != -1 and (_active_player_id == -1 or my_player_id == _active_player_id)


func _on_button_pressed(id: String) -> void:
	# En partie locale/hotseat, aucun réseau : émission directe, comme avant.
	if GameFlow.game_mode != "host" and GameFlow.game_mode != "join":
		option_selected.emit(id)
		return
	if GameFlow.game_mode == "host":
		# call_local : l'hôte se redonne le résultat à lui-même par le même
		# chemin que les clients, pour que option_selected s'émette de façon
		# identique partout (même principe que hideout_phase._claim_spot_rpc).
		_broadcast_option_selected.rpc(id)
	else:
		_request_option_rpc.rpc_id(1, id)


## Côté client (any_peer) : demande à l'hôte de valider ce choix.
@rpc("any_peer", "call_remote", "reliable")
func _request_option_rpc(id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var sender_player_id: int = Network.peer_player_map.get(sender_id, -1)
	if sender_player_id != _active_player_id:
		return  # pas son tour de décider (ou latence/désynchro) : on ignore
	if not _current_option_ids.has(id):
		return  # option inconnue/périmée
	_broadcast_option_selected.rpc(id)


## Hôte uniquement : rediffuse le choix validé à tout le monde, qui débloque
## alors chacun leur await option_selected local de façon identique.
@rpc("authority", "call_local", "reliable")
func _broadcast_option_selected(id: String) -> void:
	option_selected.emit(id)


## Vrai si des boutons de choix sont actuellement affichés (donc qu'un await
## option_selected est en attente quelque part, ex. action_resolution_phase).
func has_options() -> bool:
	return not _current_option_ids.is_empty()


## Attend un clic n'importe où sur le plateau (cf board._unhandled_input,
## qui appelle request_advance()) OU directement sur cette boîte, pour les
## messages "de lecture" qui n'attendent pas un choix précis (set_options)
## mais ne doivent pas non plus défiler tout seuls après un délai fixe -
## sans quoi rien ne garantit que le joueur ait eu le temps de les lire.
## Si les animations sont désactivées (Settings.animations_enabled), ce
## message n'apporte plus rien (il ne fait qu'attendre que le texte soit lu) :
## on passe directement à la suite sans attendre de clic.
func wait_for_click() -> void:
	if not Settings.animations_enabled:
		return
	_awaiting_advance = true
	await advance_requested
	_awaiting_advance = false


## Équivalent de wait_for_click() pour les messages affichés avec un unique
## bouton "Continuer"/"ok" (aucun choix réel, juste un accusé de lecture) :
## posé une fois pour tous ces appels au lieu de dupliquer set_options([...])
## + await option_selected partout. Sauté automatiquement, comme
## wait_for_click(), quand les animations sont désactivées.
func wait_for_continue() -> void:
	if not Settings.animations_enabled:
		set_options([])
		return
	set_options([{"id": "ok", "label": tr("Continuer")}])
	await option_selected


## Appelé par board._unhandled_input (clic sur le plateau) ou directement
## par _on_box_gui_input (clic sur cette boîte) : ne fait rien si aucun
## wait_for_click() n'est en attente.
func request_advance() -> void:
	if not _awaiting_advance:
		return
	if not _is_local_player_active():
		return  # ce clic ne concerne pas le joueur de cet écran, on l'ignore
	if GameFlow.game_mode != "host" and GameFlow.game_mode != "join":
		advance_requested.emit()
	elif GameFlow.game_mode == "host":
		_broadcast_advance.rpc()
	else:
		_request_advance_rpc.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_advance_rpc() -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var sender_player_id: int = Network.peer_player_map.get(sender_id, -1)
	if sender_player_id == -1 or (_active_player_id != -1 and sender_player_id != _active_player_id):
		return
	if not _awaiting_advance:
		return
	_broadcast_advance.rpc()


@rpc("authority", "call_local", "reliable")
func _broadcast_advance() -> void:
	if _awaiting_advance:
		advance_requested.emit()


func _on_box_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		request_advance()


## Simule le clic du choix le plus "rapide" parmi les options affichées
## (utilisé par le bouton debug "Passer") : préfère decline/stop pour ne pas
## effectuer d'action, sinon prend la première option disponible.
func skip() -> void:
	if _current_option_ids.is_empty():
		return
	var id: String = _current_option_ids[0]
	if _current_option_ids.has("decline"):
		id = "decline"
	elif _current_option_ids.has("stop"):
		id = "stop"
	option_selected.emit(id)


## Vide l'onglet "Action" (le panneau reste affiché, seul le texte disparaît)
## et retire les boutons en cours.
func hide_box() -> void:
	set_options([])
	_start_reveal("...")


func _start_reveal(bbcode_text: String) -> void:
	if _reveal_tween:
		_reveal_tween.kill()

	# Le texte complet est posé d'un coup : le retour à la ligne (autowrap)
	# est donc calculé une seule fois et ne bougera plus jamais pendant
	# l'animation (un mot ne peut plus être renvoyé à la ligne suivante
	# au fur et à mesure qu'il apparaît). Le texte reste toutefois
	# invisible (alpha 0) le temps de mesurer la taille finale.
	label.text = bbcode_text
	label.visible_ratio = 1.0
	label.modulate.a = 0.0
	call_deferred("_reveal_after_layout")


func _reveal_after_layout() -> void:
	var total_chars := label.get_total_character_count()
	label.modulate.a = 1.0
	label.visible_characters = 0
	_layout()
	if total_chars <= 0:
		return

	if not Settings.animations_enabled:
		label.visible_characters = total_chars
		return

	# Chaque lettre passe individuellement de invisible à visible.
	_reveal_tween = create_tween()
	_reveal_tween.tween_property(label, "visible_characters", total_chars, total_chars * CHAR_REVEAL_DELAY)


## Recalcule la hauteur de la boîte pour s'adapter à son contenu (texte +
## boutons), tout en gardant sa largeur et sa position (coin haut-gauche)
## fixes.
func _layout() -> void:
	custom_minimum_size = Vector2(BOX_WIDTH, 0)
	size = Vector2(BOX_WIDTH, get_combined_minimum_size().y)
