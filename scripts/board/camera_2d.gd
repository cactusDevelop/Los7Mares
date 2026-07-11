extends Camera2D

@export var pan_speed: float = 1.0
@export var zoom_speed: float = 0.1
@export var min_zoom: float = 0.3
@export var max_zoom: float = 3.0

var _dragging: bool = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMagnifyGesture:
		# Ignore le pincement (pinch in/out) trackpad/tactile : pas de zoom caméra.
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.ctrl_pressed:
			_apply_zoom(1.0 - zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.ctrl_pressed:
			_apply_zoom(1.0 + zoom_speed)

	elif event is InputEventMouseMotion and _dragging:
		position -= event.relative * zoom.x * pan_speed


func _apply_zoom(factor: float) -> void:
	var new_zoom = zoom * factor
	new_zoom.x = clamp(new_zoom.x, min_zoom, max_zoom)
	new_zoom.y = clamp(new_zoom.y, min_zoom, max_zoom)
	zoom = new_zoom
