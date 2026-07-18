extends Control

## Affiche en grand, sur fond noir, la carte du dessus d'une pile (à l'instar
## d'un jeton révélé au centre de l'écran). La carte apparaît face verso puis
## se retourne pour révéler son recto. Un clic n'importe où referme la carte.

signal card_resolved(card: SeaCard)

const CARD_DISPLAY_SCALE := 2.2
const FLIP_DELAY := 0.25
const FLIP_DURATION := 0.6

@onready var blocker: ColorRect = $Blocker
@onready var padding: MarginContainer = $Padding
@onready var card_image: TextureRect = $Padding/Content/CardImage

var _current_card: SeaCard


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.color = Color(0, 0, 0, 0.75)
	blocker.gui_input.connect(_on_blocker_gui_input)


func show_card(card: SeaCard, back_texture: Texture2D, front_texture: Texture2D) -> void:
	_current_card = card
	card_image.texture = back_texture

	var display_size: Vector2 = back_texture.get_size() * CARD_DISPLAY_SCALE
	card_image.custom_minimum_size = display_size

	var viewport_size := get_viewport_rect().size
	blocker.position = Vector2.ZERO
	blocker.size = viewport_size
	padding.position = Vector2.ZERO
	padding.size = viewport_size

	await get_tree().process_frame
	card_image.pivot_offset = card_image.size / 2.0

	visible = true
	padding.scale = Vector2(0.7, 0.7)
	padding.modulate.a = 0.0
	padding.pivot_offset = viewport_size / 2.0

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(padding, "scale", Vector2.ONE, UiTheme.CARD_POPUP_DURATION)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(padding, "modulate:a", 1.0, UiTheme.CARD_POPUP_DURATION)
	await tween.finished

	await get_tree().create_timer(Settings.anim_duration(FLIP_DELAY)).timeout
	await _flip_to_front(front_texture)


func _flip_to_front(front_texture: Texture2D) -> void:
	var duration: float = Settings.anim_duration(FLIP_DURATION)
	var tween := create_tween()
	tween.tween_property(card_image, "scale:x", 0.0, duration * 0.45)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(func(): card_image.texture = front_texture)
	tween.tween_property(card_image, "scale:x", 1.0, duration * 0.55)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished


func _on_blocker_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_close()


func _close() -> void:
	visible = false
	SeaDecks.discard_card(_current_card)
	var resolved_card := _current_card
	_current_card = null
	card_resolved.emit(resolved_card)
