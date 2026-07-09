extends Control

signal piece_selected(rank: int)

const ICON_SIZE := Vector2(100, 150)
const HOVER_SCALE := 1.1
const SELECTED_SCALE := 1.2
const TWEEN_DURATION := 0.15
const PANEL_WIDTH := 240.0
const UNSELECTED_TINT := Color(0.55, 0.55, 0.55)

@onready var background: ColorRect = $Background
@onready var icons_box: VBoxContainer = $IconsBox
@onready var captain_option: VBoxContainer = $IconsBox/CaptainOption
@onready var captain_button: TextureButton = $IconsBox/CaptainOption/CaptainButton
@onready var second_option: VBoxContainer = $IconsBox/SecondOption
@onready var second_button: TextureButton = $IconsBox/SecondOption/SecondButton

var _button_group := ButtonGroup.new()
var _current_color: Color = Color.WHITE
var _tweens: Dictionary = {}
var _hovering: Dictionary = {}


func _ready() -> void:
	visible = false
	for btn in [captain_button, second_button]:
		btn.custom_minimum_size = ICON_SIZE
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.toggle_mode = true
		btn.button_group = _button_group
		btn.pivot_offset = ICON_SIZE / 2.0
		_hovering[btn] = false
		btn.mouse_entered.connect(_on_button_hover.bind(btn, true))
		btn.mouse_exited.connect(_on_button_hover.bind(btn, false))
		btn.toggled.connect(_on_button_toggled.bind(btn))

	captain_button.pressed.connect(func(): piece_selected.emit(GameFlow.PieceRank.CAPTAIN))
	second_button.pressed.connect(func(): piece_selected.emit(GameFlow.PieceRank.SECOND))

	icons_box.add_theme_constant_override("separation", 60)
	_layout()


func _layout() -> void:
	var viewport_size := get_viewport_rect().size
	background.position = Vector2(viewport_size.x - PANEL_WIDTH, 0)
	background.size = Vector2(PANEL_WIDTH, viewport_size.y)
	background.color = Color(0, 0, 0, 1)

	position = background.position
	size = background.size
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
	captain_option.visible = only_rank == -1 or only_rank == GameFlow.PieceRank.CAPTAIN
	second_option.visible = only_rank == -1 or only_rank == GameFlow.PieceRank.SECOND

	for btn in [captain_button, second_button]:
		btn.button_pressed = false
		btn.scale = Vector2.ONE
		_hovering[btn] = false

	if only_rank != -1:
		var forced_btn: TextureButton = captain_button if only_rank == GameFlow.PieceRank.CAPTAIN else second_button
		forced_btn.button_pressed = true
		piece_selected.emit(only_rank)

	_refresh_colors()


func _on_button_hover(btn: TextureButton, hovering: bool) -> void:
	_hovering[btn] = hovering
	var target_scale := (SELECTED_SCALE if btn.button_pressed else 1.0) * (HOVER_SCALE if hovering else 1.0)
	_tween_scale(btn, target_scale)
	_refresh_colors()


func _on_button_toggled(is_pressed: bool, btn: TextureButton) -> void:
	_tween_scale(btn, SELECTED_SCALE if is_pressed else 1.0)
	_refresh_colors()


func _refresh_colors() -> void:
	for btn in [captain_button, second_button]:
		var base: Color = _current_color if btn.button_pressed else _current_color * UNSELECTED_TINT
		if _hovering.get(btn, false):
			base *= GameFlow.HOVER_TINT
		btn.modulate = base


func _tween_scale(btn: TextureButton, target_scale: float) -> void:
	if _tweens.has(btn) and _tweens[btn]:
		_tweens[btn].kill()
	var tween := create_tween()
	tween.tween_property(btn, "scale", Vector2.ONE * target_scale, TWEEN_DURATION)
	_tweens[btn] = tween
