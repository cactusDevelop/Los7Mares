extends Control

## Affiche le détail de la carte du dessus d'une pile, déjà révélée (recto)
## sur sa pile, dans un panneau centré à l'écran (image à gauche, texte à
## droite), sur un fond assombri. Cliquer en dehors du panneau, ou sur le
## bouton RETOUR, referme le panneau.

signal card_resolved(card: SeaCard)

const TYPE_LABELS := {
	SeaCard.CardType.TRESOR: "Trésor",
	SeaCard.CardType.RENCONTRE: "Rencontre",
	SeaCard.CardType.TEMPETE: "Tempête",
	SeaCard.CardType.COMMERCE: "Commerce",
}

@onready var blocker: ColorRect = $Blocker
@onready var padding: PanelContainer = $Padding
@onready var card_image: TextureRect = $Padding/Margin/Content/CardImage
@onready var title_label: Label = $Padding/Margin/Content/DetailsColumn/TitleLabel
@onready var type_label: Label = $Padding/Margin/Content/DetailsColumn/TypeLabel
@onready var description_label: Label = $Padding/Margin/Content/DetailsColumn/DescriptionLabel
@onready var back_button: Button = $Padding/Margin/Content/DetailsColumn/BackButton

var _current_card: SeaCard


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	blocker.gui_input.connect(_on_blocker_gui_input)
	back_button.pressed.connect(_close)

	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.POPUP_BG_COLOR
	style.corner_radius_top_left = UiTheme.POPUP_CORNER_RADIUS
	style.corner_radius_top_right = UiTheme.POPUP_CORNER_RADIUS
	style.corner_radius_bottom_left = UiTheme.POPUP_CORNER_RADIUS
	style.corner_radius_bottom_right = UiTheme.POPUP_CORNER_RADIUS
	padding.add_theme_stylebox_override("panel", style)


func show_card(card: SeaCard, front_texture: Texture2D) -> void:
	_current_card = card
	card_image.texture = front_texture
	title_label.text = tr(card.title)
	type_label.text = tr(TYPE_LABELS.get(card.type, ""))
	description_label.text = tr(card.description)

	visible = true
	await get_tree().process_frame
	_center_panel()

	padding.scale = Vector2(0.85, 0.85)
	padding.modulate.a = 0.0
	padding.pivot_offset = padding.size / 2.0

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(padding, "scale", Vector2.ONE, UiTheme.CARD_POPUP_DURATION)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(padding, "modulate:a", 1.0, UiTheme.CARD_POPUP_DURATION)
	await tween.finished


func _center_panel() -> void:
	var viewport_size := get_viewport_rect().size
	var panel_size: Vector2 = padding.get_combined_minimum_size()
	padding.position = ((viewport_size - panel_size) / 2.0).round()
	padding.size = panel_size


func _on_blocker_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close()


func _close() -> void:
	visible = false
	var resolved_card := _current_card
	_current_card = null
	card_resolved.emit(resolved_card)
