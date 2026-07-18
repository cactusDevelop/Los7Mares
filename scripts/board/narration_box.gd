extends PanelContainer

@onready var label: RichTextLabel = $Padding/NarrationLabel

## Délai entre chaque lettre affichée (en secondes)
const CHAR_REVEAL_DELAY := 0.015

var _reveal_tween: Tween


func _ready() -> void:
	visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 1)
	style.corner_radius_top_left = 20
	style.corner_radius_top_right = 20
	style.corner_radius_bottom_left = 20
	style.corner_radius_bottom_right = 20
	add_theme_stylebox_override("panel", style)

	label.add_theme_color_override("default_color", Color.BLACK)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	# Calcule le retour à la ligne sur le texte COMPLET (déjà mis en forme),
	# indépendamment du nombre de lettres actuellement révélées. Sans ça,
	# Godot ne tient compte que des lettres visibles pour le wrap, ce qui
	# fait sauter les mots de fin de ligne pendant l'animation.
	label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	label.custom_minimum_size = Vector2(420, 0)


## Affiche un texte de narration simple (sans nom de joueur à colorer).
func say(text: String) -> void:
	_start_reveal(text)


## Affiche un texte de narration où "%s" est remplacé par le nom du joueur,
## affiché dans sa couleur (ex: format = "Tour de %s : joue.").
func say_with_player(format: String, player: Dictionary) -> void:
	var player_color: Color = GameFlow.COLOR_VALUES[player["color"]]
	var colored_name := "[color=#%s]%s[/color]" % [player_color.to_html(false), player["name"]]
	_start_reveal(format % colored_name)


func hide_box() -> void:
	visible = false
	if _reveal_tween:
		_reveal_tween.kill()


func _start_reveal(bbcode_text: String) -> void:
	if _reveal_tween:
		_reveal_tween.kill()

	# Le texte complet est posé d'un coup : le retour à la ligne (autowrap)
	# est donc calculé une seule fois et ne bougera plus jamais pendant
	# l'animation (un mot ne peut plus être renvoyé à la ligne suivante
	# au fur et à mesure qu'il apparaît). Le texte reste toutefois
	# invisible (alpha 0) le temps de mesurer la taille finale de la bulle.
	label.text = bbcode_text
	label.visible_ratio = 1.0
	label.modulate.a = 0.0
	visible = true
	call_deferred("_reveal_after_layout")


func _reveal_after_layout() -> void:
	# La bulle est maintenant à sa taille et sa position définitives.
	_reposition()

	var total_chars := label.get_total_character_count()
	label.modulate.a = 1.0
	label.visible_characters = 0
	if total_chars <= 0:
		return

	# Chaque lettre passe individuellement de invisible à visible.
	_reveal_tween = create_tween()
	_reveal_tween.tween_property(label, "visible_characters", total_chars, total_chars * CHAR_REVEAL_DELAY)


func _reposition() -> void:
	size = get_combined_minimum_size()
	var vp := get_viewport_rect().size
	position = Vector2((vp.x - size.x) / 2.0, vp.y - size.y - 40)
