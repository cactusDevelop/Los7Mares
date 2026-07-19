extends PanelContainer

@onready var action_label: Label = $Padding/Content/ActionLabel
@onready var label: RichTextLabel = $Padding/Content/NarrationLabel

## Délai entre chaque lettre affichée (en secondes)
const CHAR_REVEAL_DELAY := 0.015
const LABEL_WIDTH := 170.0
## Filtre noir semi-transparent (au lieu d'un fond blanc opaque), même
## principe que le fondu noir de l'annonce "Tour X" (piece_selection_panel).
const PANEL_FILTER_ALPHA := 0.75

var _reveal_tween: Tween


func _ready() -> void:
	# Onglet fixe de la sidebar gauche : toujours visible, ne se repositionne
	# plus jamais (contrairement à l'ancienne bulle flottante en bas d'écran).
	visible = true

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, PANEL_FILTER_ALPHA)
	style.set_corner_radius_all(UiTheme.POPUP_CORNER_RADIUS)
	add_theme_stylebox_override("panel", style)

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


## Affiche un texte de narration simple (sans nom de joueur à colorer).
func say(text: String) -> void:
	_start_reveal(text)


## Affiche un texte de narration où "%s" est remplacé par le nom du joueur,
## affiché dans sa couleur (ex: format = "Tour de %s : joue.").
func say_with_player(format: String, player: Dictionary) -> void:
	var player_color: Color = GameFlow.COLOR_VALUES[player["color"]]
	var colored_name := "[color=#%s]%s[/color]" % [player_color.to_html(false), player["name"]]
	_start_reveal(format % colored_name)


## Vide l'onglet "Action" (le panneau reste affiché, seul le texte disparaît).
func hide_box() -> void:
	if _reveal_tween:
		_reveal_tween.kill()
	label.text = ""


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
	if total_chars <= 0:
		return

	# Chaque lettre passe individuellement de invisible à visible.
	_reveal_tween = create_tween()
	_reveal_tween.tween_property(label, "visible_characters", total_chars, total_chars * CHAR_REVEAL_DELAY)
