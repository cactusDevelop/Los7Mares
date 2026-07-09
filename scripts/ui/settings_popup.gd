extends PopupPanel

@onready var padding: MarginContainer = $Padding
@onready var volume_slider: HSlider = $Padding/Content/VolumeRow/VolumeSlider


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.16, 1.0)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	add_theme_stylebox_override("panel", style)

	volume_slider.value_changed.connect(_on_volume_changed)


func popup_centered_auto() -> void:
	var min_size: Vector2 = padding.get_combined_minimum_size()
	min_size.x = max(min_size.x, 320)
	size = min_size
	popup_centered()


func _on_volume_changed(value: float) -> void:
	var bus_index := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(value))
