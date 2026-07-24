extends PanelContainer

@onready var action_label: Label = $Padding/Content/ActionLabel
@onready var label: RichTextLabel = $Padding/Content/NarrationLabel
@onready var buttons_box: VBoxContainer = $Padding/Content/ButtonsBox

## Émis quand un bouton de choix (cf set_options) est cliqué.
signal option_selected(id: String)

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
	var player_color: Color = GameFlow.COLOR_VALUES[player["color"]]
	var colored_name := "[color=#%s]%s[/color]" % [player_color.to_html(false), player["name"]]
	var args: Array = [colored_name] + extra_args
	_start_reveal(format % args)
	set_outline_color(player_color)


## Couleur du contour de la boîte (couleur du joueur dont c'est le tour).
func set_outline_color(color: Color) -> void:
	_panel_style.border_color = color


## Remet le contour à l'état neutre (aucun joueur concerné, ex: écran de fin).
func clear_outline() -> void:
	_panel_style.border_color = Color(0, 0, 0, 0)


## Affiche une liste de boutons de choix sous le texte de narration.
## options: Array[{"id": String, "label": String}]. Liste vide = pas de bouton.
func set_options(options: Array) -> void:
	_current_option_ids = options.map(func(o): return o["id"])
	for child in buttons_box.get_children():
		buttons_box.remove_child(child)
		child.queue_free()
	for option in options:
		var btn := Button.new()
		btn.text = option["label"]
		btn.custom_minimum_size = Vector2(LABEL_WIDTH, BUTTON_HEIGHT)
		btn.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
		btn.pressed.connect(_on_button_pressed.bind(option["id"]))
		buttons_box.add_child(btn)
	call_deferred("_layout")


func _on_button_pressed(id: String) -> void:
	option_selected.emit(id)


## Vrai si des boutons de choix sont actuellement affichés (donc qu'un await
## option_selected est en attente quelque part, ex. action_resolution_phase).
func has_options() -> bool:
	return not _current_option_ids.is_empty()


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

	# Chaque lettre passe individuellement de invisible à visible.
	_reveal_tween = create_tween()
	_reveal_tween.tween_property(label, "visible_characters", total_chars, total_chars * CHAR_REVEAL_DELAY)


## Recalcule la hauteur de la boîte pour s'adapter à son contenu (texte +
## boutons), tout en gardant sa largeur et sa position (coin haut-gauche)
## fixes.
func _layout() -> void:
	custom_minimum_size = Vector2(BOX_WIDTH, 0)
	size = Vector2(BOX_WIDTH, get_combined_minimum_size().y)
