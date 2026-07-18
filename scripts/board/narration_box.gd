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
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
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

	# Le texte complet est posé d'un coup (retour à la ligne calculé une
	# seule fois, il ne bougera plus). On le laisse temporairement
	# entièrement visible le temps d'une frame pour que la bulle se
	# dimensionne et se positionne sur sa taille FINALE.
	label.text = bbcode_text
	label.visible_ratio = 1.0
	visible = true
	call_deferred("_reveal_after_layout")


func _reveal_after_layout() -> void:
	# La bulle est maintenant à sa taille et sa position définitives.
	_reposition()

	var total_chars := label.get_total_character_count()
	label.visible_characters = 0
	if total_chars <= 0:
		return

	_reveal_tween = create_tween()
	_reveal_tween.tween_property(label, "visible_characters", total_chars, total_chars * CHAR_REVEAL_DELAY)


func _reposition() -> void:
	size = get_combined_minimum_size()
	var vp := get_viewport_rect().size
	position = Vector2((vp.x - size.x) / 2.0, vp.y - size.y - 40)
