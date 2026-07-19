extends Control

signal piece_selected(rank: int)

const HOVER_SCALE := 1.1
const SELECTED_SCALE := 1.2
const TWEEN_DURATION := 0.15
const UNSELECTED_TINT := Color(0.55, 0.55, 0.55)

## Effet 3D (épaisseur) des icônes capitaine/second : géré par un shader
## (shaders/piece_thickness.gdshader), le même que celui utilisé pour les
## pièces sur le plateau (captain_piece.gd/second_piece.gd). Un seul draw
## call par icône, donc aucun souci d'ordre d'affichage.
const PIECE_THICKNESS_PX := 12.0
const PIECE_THICKNESS_LAYERS := 8
const PIECE_EDGE_DARKEN := 0.5

## Annonce de tour : filtre noir + texte/jeton en perspective.
const ANNOUNCE_FADE_IN_DURATION := 0.12
const ANNOUNCE_FILTER_ALPHA := 0.88
const ANNOUNCE_ZOOM_IN_DURATION := 0.35
const ANNOUNCE_HOLD_DURATION := 0.65
const ANNOUNCE_ZOOM_OUT_DURATION := 0.3
const ANNOUNCE_START_SCALE := 0.05
const ANNOUNCE_EXIT_SCALE := 2.4
const ANNOUNCE_CONTENT_SEPARATION := 30
const ANNOUNCE_FORTUNE_SIZE := Vector2(140, 140)
## Halo tournant derrière le jeton (shaders/star_burst.gdshader) : plus
## grand que le jeton pour que les rayons dépassent visiblement de ses bords.
const ANNOUNCE_SHINE_SIZE := Vector2(320, 320)

var background: ColorRect
var icons_box: VBoxContainer
var captain_button: TextureButton
var second_button: TextureButton
var splatter: TextureRect

## Overlay plein écran indépendant du rect du panneau (posé dans son propre
## CanvasLayer pour être garanti au-dessus de tout le reste de l'UI).
var turn_overlay: CanvasLayer
var black_filter: ColorRect
var announce_content: VBoxContainer
var tour_label: Label
var fortune_wrap: Control
var fortune_shine: ColorRect
var fortune_sprite: TextureRect

var _button_group := ButtonGroup.new()
var _current_color: Color = Color.WHITE
var _tweens: Dictionary = {}


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	background = ColorRect.new()
	background.color = Color(0.102, 0.102, 0.117, 1.0)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(background)
	
	splatter = TextureRect.new()
	splatter.texture = preload("res://assets/art/ui/splatter-black-paint.png")
	splatter.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	splatter.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	splatter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(splatter)

	icons_box = VBoxContainer.new()
	icons_box.alignment = BoxContainer.ALIGNMENT_CENTER
	icons_box.add_theme_constant_override("separation", 60)
	add_child(icons_box)

	captain_button = _build_piece_option("Capitaine", preload("res://assets/art/pieces/capitaine.png"))
	second_button = _build_piece_option("Second", preload("res://assets/art/pieces/second.png"))

	captain_button.pressed.connect(func(): piece_selected.emit(GameFlow.PieceRank.CAPTAIN))
	second_button.pressed.connect(func(): piece_selected.emit(GameFlow.PieceRank.SECOND))

	get_viewport().size_changed.connect(_layout)
	_layout()

	_build_turn_overlay()


func _build_piece_option(label_text: String, texture: Texture2D) -> TextureButton:
	var option := VBoxContainer.new()
	option.alignment = BoxContainer.ALIGNMENT_CENTER
	option.add_theme_constant_override("separation", 8)
	icons_box.add_child(option)

	var btn := TextureButton.new()
	btn.texture_normal = texture
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.toggle_mode = true
	btn.button_group = _button_group
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	# Taille calée EXACTEMENT sur le ratio de la texture : aucune marge
	# verticale ajoutée, donc les pieds tombent pile en bas du bouton.
	var aspect := texture.get_width() / float(texture.get_height())
	btn.custom_minimum_size = Vector2(UiTheme.SELECTION_ICON_HEIGHT * aspect, UiTheme.SELECTION_ICON_HEIGHT)
	btn.pivot_offset = btn.custom_minimum_size / 2.0

	var mat := ShaderMaterial.new()
	mat.set_shader_parameter("depth_direction", UiTheme.DEPTH_DIRECTION)
	mat.set_shader_parameter("thickness_px", PIECE_THICKNESS_PX)
	mat.set_shader_parameter("layers", PIECE_THICKNESS_LAYERS)
	mat.set_shader_parameter("edge_darken", PIECE_EDGE_DARKEN)
	mat.set_shader_parameter("display_scale", btn.custom_minimum_size.y / texture.get_height())
	btn.material = mat

	btn.mouse_entered.connect(_on_button_hover.bind(btn, true))
	btn.mouse_exited.connect(_on_button_hover.bind(btn, false))
	btn.toggled.connect(_on_button_toggled.bind(btn))
	option.add_child(btn)

	var label := Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	option.add_child(label)

	return btn


func _layout() -> void:
	var viewport_size := get_viewport_rect().size
	position = Vector2(viewport_size.x - UiTheme.SELECTION_PANEL_WIDTH, 0)
	size = Vector2(UiTheme.SELECTION_PANEL_WIDTH, viewport_size.y)
	background.position = Vector2.ZERO
	background.size = size
	splatter.position = Vector2.ZERO
	splatter.size = size
	icons_box.position = Vector2.ZERO
	icons_box.size = size


func show_for_placement_phase() -> void:
	_layout()
	visible = true


func hide_panel() -> void:
	visible = false


## only_rank == -1 -> les deux pièces proposées, capitaine sélectionné par défaut.
## only_rank == CAPTAIN/SECOND -> une seule affichée, forcée/sélectionnée.
func setup_for_player(color: Color, only_rank: int = -1) -> void:
	_current_color = color
	captain_button.get_parent().visible = only_rank == -1 or only_rank == GameFlow.PieceRank.CAPTAIN
	second_button.get_parent().visible = only_rank == -1 or only_rank == GameFlow.PieceRank.SECOND

	for btn in [captain_button, second_button]:
		btn.button_pressed = false
		btn.scale = Vector2.ONE

	if only_rank != -1:
		var forced_btn: TextureButton = captain_button if only_rank == GameFlow.PieceRank.CAPTAIN else second_button
		forced_btn.button_pressed = true
		piece_selected.emit(only_rank)
	else:
		captain_button.button_pressed = true
		piece_selected.emit(GameFlow.PieceRank.CAPTAIN)

	_refresh_colors()


func _on_button_hover(btn: TextureButton, hovering: bool) -> void:
	var target_scale := (SELECTED_SCALE if btn.button_pressed else 1.0) * (HOVER_SCALE if hovering else 1.0)
	_tween_scale(btn, target_scale)


func _on_button_toggled(is_pressed: bool, btn: TextureButton) -> void:
	_tween_scale(btn, SELECTED_SCALE if is_pressed else 1.0)
	_refresh_colors()


## Sélectionnée = couleur pleine. Non sélectionnée = couleur grisée.
## Plus de filtre noir supplémentaire au survol (le gris suffit déjà).
func _refresh_colors() -> void:
	for btn in [captain_button, second_button]:
		btn.modulate = _current_color if btn.button_pressed else _current_color * UNSELECTED_TINT


func _tween_scale(btn: TextureButton, target_scale: float) -> void:
	if _tweens.has(btn) and _tweens[btn]:
		_tweens[btn].kill()
	var tween := create_tween()
	tween.tween_property(btn, "scale", Vector2.ONE * target_scale, TWEEN_DURATION)
	_tweens[btn] = tween


## Construit l'overlay d'annonce de tour dans son propre CanvasLayer (layer
## élevé) : il reste donc plein écran et toujours au-dessus du reste de
## l'UI, indépendamment du rect (réduit à la colonne de droite) de ce panel.
func _build_turn_overlay() -> void:
	turn_overlay = CanvasLayer.new()
	turn_overlay.layer = 10
	add_child(turn_overlay)

	black_filter = ColorRect.new()
	black_filter.color = Color(0, 0, 0, 0)
	black_filter.mouse_filter = Control.MOUSE_FILTER_STOP
	black_filter.set_anchors_preset(Control.PRESET_FULL_RECT)
	turn_overlay.add_child(black_filter)

	announce_content = VBoxContainer.new()
	announce_content.alignment = BoxContainer.ALIGNMENT_CENTER
	announce_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	announce_content.add_theme_constant_override("separation", ANNOUNCE_CONTENT_SEPARATION)
	turn_overlay.add_child(announce_content)

	tour_label = Label.new()
	tour_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tour_label.add_theme_font_size_override("font_size", 72)
	tour_label.add_theme_color_override("font_color", Color.WHITE)
	tour_label.add_theme_color_override("font_outline_color", Color.BLACK)
	tour_label.add_theme_constant_override("outline_size", 8)
	announce_content.add_child(tour_label)

	# Conteneur libre (pas de layout auto) qui superpose le halo tournant
	# (dessous) et le jeton (dessus), au lieu d'un simple sprite empilé
	# dans le VBoxContainer.
	fortune_wrap = Control.new()
	fortune_wrap.custom_minimum_size = ANNOUNCE_SHINE_SIZE
	fortune_wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	fortune_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	announce_content.add_child(fortune_wrap)

	# Halo procédural (shader) : rayons irréguliers tournant en continu via
	# TIME côté GPU, pas de logique _process/queue_redraw côté script.
	fortune_shine = ColorRect.new()
	fortune_shine.position = Vector2.ZERO
	fortune_shine.size = ANNOUNCE_SHINE_SIZE
	fortune_shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shine_mat := ShaderMaterial.new()
	shine_mat.shader = preload("res://shaders/star_burst.gdshader")
	fortune_shine.material = shine_mat
	fortune_wrap.add_child(fortune_shine)

	fortune_sprite = TextureRect.new()
	fortune_sprite.texture = preload("res://assets/art/tokens/fortune.png")
	fortune_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fortune_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	fortune_sprite.position = (ANNOUNCE_SHINE_SIZE - ANNOUNCE_FORTUNE_SIZE) / 2.0
	fortune_sprite.size = ANNOUNCE_FORTUNE_SIZE
	fortune_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fortune_wrap.add_child(fortune_sprite)

	turn_overlay.visible = false


## Recentre l'overlay sur le viewport courant et replace le pivot du groupe
## texte+jeton en son centre, pour que le zoom se fasse depuis ce point.
func _layout_turn_overlay() -> void:
	var vp := get_viewport_rect().size
	announce_content.size = announce_content.get_combined_minimum_size()
	announce_content.position = (vp - announce_content.size) / 2.0
	announce_content.pivot_offset = announce_content.size / 2.0


## Fondu noir rapide, puis "Tour X" + jeton fortune qui apparaissent en
## zoom-in (pop) et disparaissent en continuant sur le MEME zoom-in
## (accélération vers le spectateur) après une courte pause. Le texte et le
## jeton sont dans un seul groupe (announce_content) mis à l'échelle
## ensemble : la distance entre eux reste donc proportionnelle au zoom,
## contrairement à un simple scale indépendant de chaque élément.
func play_turn_announcement(round_number: int) -> void:
	tour_label.text = tr("Tour %d") % round_number
	_layout_turn_overlay()

	black_filter.color.a = 0.0
	announce_content.scale = Vector2.ONE * ANNOUNCE_START_SCALE
	announce_content.modulate.a = 0.0
	turn_overlay.visible = true

	var fade_in := create_tween()
	fade_in.tween_property(black_filter, "color:a", ANNOUNCE_FILTER_ALPHA, ANNOUNCE_FADE_IN_DURATION)
	await fade_in.finished

	var zoom_in := create_tween()
	zoom_in.set_parallel(true)
	zoom_in.tween_property(announce_content, "scale", Vector2.ONE, ANNOUNCE_ZOOM_IN_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	zoom_in.tween_property(announce_content, "modulate:a", 1.0, ANNOUNCE_ZOOM_IN_DURATION * 0.6)
	await zoom_in.finished

	await get_tree().create_timer(ANNOUNCE_HOLD_DURATION).timeout

	var zoom_out := create_tween()
	zoom_out.set_parallel(true)
	zoom_out.tween_property(announce_content, "scale", Vector2.ONE * ANNOUNCE_EXIT_SCALE, ANNOUNCE_ZOOM_OUT_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	zoom_out.tween_property(announce_content, "modulate:a", 0.0, ANNOUNCE_ZOOM_OUT_DURATION)
	zoom_out.tween_property(black_filter, "color:a", 0.0, ANNOUNCE_ZOOM_OUT_DURATION).set_delay(ANNOUNCE_ZOOM_OUT_DURATION * 0.3)
	await zoom_out.finished

	turn_overlay.visible = false
