extends Node2D

@export var box_size: Vector2 = Vector2(200, 280):
	set(value):
		box_size = value
		if outline:
			outline.box_size = value
			outline.queue_redraw()

@export var outline_width: float = 6.0:
	set(value):
		outline_width = value
		if outline:
			outline.line_width = value
			outline.queue_redraw()

@export var label_text: String = "":
	set(value):
		label_text = value
		if hint_label:
			hint_label.text = value
			_center_label()

@export var font_size: int = 32:
	set(value):
		font_size = value
		if hint_label:
			hint_label.add_theme_font_size_override("font_size", value)
			_center_label()

@export var bold: bool = false:
	set(value):
		bold = value
		if hint_label:
			_apply_bold()
			_center_label()

## Décalage additionnel appliqué au label une fois celui-ci centré sur l'origine.
@export var label_offset: Vector2 = Vector2.ZERO:
	set(value):
		label_offset = value
		if hint_label:
			_center_label()

@export var fade_duration: float = 0.15

@onready var outline: Node2D = $Outline
@onready var hint_label: Label = $HintLabel

var _fade_tween: Tween


func _ready() -> void:
	outline.box_size = box_size
	outline.line_width = outline_width
	hint_label.text = label_text
	hint_label.add_theme_font_size_override("font_size", font_size)
	_apply_bold()
	_center_label()
	visible = false
	modulate.a = 1.0


func show_prompt() -> void:
	visible = true
	modulate.a = 0.0
	_fade_to(1.0)


func hide_prompt() -> void:
	_fade_to(0.0, func(): visible = false)


func _fade_to(target_alpha: float, on_finished: Callable = Callable()) -> void:
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", target_alpha, fade_duration)
	if on_finished.is_valid():
		_fade_tween.tween_callback(on_finished)


func _apply_bold() -> void:
	if bold:
		var base_font: Font = hint_label.get_theme_font("font")
		var bold_font := FontVariation.new()
		bold_font.base_font = base_font
		bold_font.variation_embolden = 1.0
		hint_label.add_theme_font_override("font", bold_font)
	else:
		hint_label.remove_theme_font_override("font")


func _center_label() -> void:
	if not hint_label:
		return
	# Recalcule la taille réelle du label (dépend du texte et de la police),
	# puis le repositionne pour que son centre coïncide avec l'origine du noeud.
	hint_label.size = hint_label.get_minimum_size()
	hint_label.position = -hint_label.size / 2.0 + label_offset
