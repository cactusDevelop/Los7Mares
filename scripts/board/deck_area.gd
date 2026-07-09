extends Area2D

signal deck_clicked
signal hover_entered
signal hover_exited

@onready var hover_prompt: Node2D = $HoverPrompt


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	input_event.connect(_on_input_event)


func _on_mouse_entered() -> void:
	hover_prompt.show_prompt()
	hover_entered.emit()


func _on_mouse_exited() -> void:
	hover_prompt.hide_prompt()
	hover_exited.emit()


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		deck_clicked.emit()
