extends PanelContainer

@onready var label: Label = $Padding/NarrationLabel


func _ready() -> void:
	visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 1)
	style.corner_radius_top_left = 20
	style.corner_radius_top_right = 20
	style.corner_radius_bottom_left = 20
	style.corner_radius_bottom_right = 20
	add_theme_stylebox_override("panel", style)

	label.add_theme_color_override("font_color", Color.BLACK)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.custom_minimum_size = Vector2(420, 0)


func say(text: String) -> void:
	label.text = text
	visible = true
	call_deferred("_reposition")


func hide_box() -> void:
	visible = false


func _reposition() -> void:
	size = get_combined_minimum_size()
	var vp := get_viewport_rect().size
	position = Vector2((vp.x - size.x) / 2.0, vp.y - size.y - 40)
