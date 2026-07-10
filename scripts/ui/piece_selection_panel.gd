extends Control

signal piece_selected(rank: int)

const HOVER_SCALE := 1.1
const SELECTED_SCALE := 1.2
const TWEEN_DURATION := 0.15
const UNSELECTED_TINT := Color(0.55, 0.55, 0.55)

var background: ColorRect
var icons_box: VBoxContainer
var captain_button: TextureButton
var second_button: TextureButton
var splatter: TextureRect

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

	captain_button = _build_piece_option("Capitaine", preload("res://assets/art/capitaine.png"))
	second_button = _build_piece_option("Second", preload("res://assets/art/second.png"))

	captain_button.pressed.connect(func(): piece_selected.emit(GameFlow.PieceRank.CAPTAIN))
	second_button.pressed.connect(func(): piece_selected.emit(GameFlow.PieceRank.SECOND))

	get_viewport().size_changed.connect(_layout)
	_layout()


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
	btn.custom_minimum_size = Vector2(GameFlow.SELECTION_ICON_HEIGHT * aspect, GameFlow.SELECTION_ICON_HEIGHT)
	btn.pivot_offset = btn.custom_minimum_size / 2.0

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
	position = Vector2(viewport_size.x - GameFlow.SELECTION_PANEL_WIDTH, 0)
	size = Vector2(GameFlow.SELECTION_PANEL_WIDTH, viewport_size.y)
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


## only_rank == -1 -> les deux pièces proposées (aucune sélectionnée au départ).
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
