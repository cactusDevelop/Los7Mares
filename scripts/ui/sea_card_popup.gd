extends Control

signal card_resolved(card: SeaCard)

const TYPE_LABELS := {
	SeaCard.CardType.TRESOR: "Trésor",
	SeaCard.CardType.RENCONTRE: "Rencontre",
	SeaCard.CardType.TEMPETE: "Tempête",
	SeaCard.CardType.COMMERCE: "Commerce",
}

@onready var blocker: ColorRect = $Blocker
@onready var padding: MarginContainer = $Padding
@onready var content: VBoxContainer = $Padding/Content
@onready var title_label: Label = $Padding/Content/TitleLabel
@onready var type_label: Label = $Padding/Content/TypeLabel
@onready var description_label: Label = $Padding/Content/DescriptionLabel
@onready var confirm_button: Button = $Padding/Content/ConfirmButton

var _current_card: SeaCard


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.color = Color(0, 0, 0, 0.55)
	confirm_button.pressed.connect(_on_confirm_pressed)


func show_card(card: SeaCard) -> void:
	_current_card = card
	title_label.text = tr(card.title)
	type_label.text = tr(TYPE_LABELS.get(card.type, ""))
	description_label.text = tr(card.description)

	var viewport_size := get_viewport_rect().size
	blocker.position = Vector2.ZERO
	blocker.size = viewport_size

	var min_size: Vector2 = padding.get_combined_minimum_size()
	min_size.x = max(min_size.x, 420)
	padding.size = min_size
	padding.position = (viewport_size - min_size) / 2.0
	padding.pivot_offset = min_size / 2.0

	visible = true
	padding.scale = Vector2(0.8, 0.8)
	padding.modulate.a = 0.0

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(padding, "scale", Vector2.ONE, UiTheme.CARD_POPUP_DURATION)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(padding, "modulate:a", 1.0, UiTheme.CARD_POPUP_DURATION)


func _on_confirm_pressed() -> void:
	visible = false
	SeaDecks.discard_card(_current_card)
	var resolved_card := _current_card
	_current_card = null
	card_resolved.emit(resolved_card)
