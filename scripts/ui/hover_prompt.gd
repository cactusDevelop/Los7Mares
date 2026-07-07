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

@onready var outline: Node2D = $Outline
@onready var hint_label: Label = $HintLabel


func _ready() -> void:
	outline.box_size = box_size
	outline.line_width = outline_width
	hint_label.text = label_text
	hide_prompt()


func show_prompt() -> void:
	visible = true


func hide_prompt() -> void:
	visible = false
