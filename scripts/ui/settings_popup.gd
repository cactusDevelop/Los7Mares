extends PopupPanel

const LOCALE_LABELS := {"fr": "Français", "en": "English", "es": "Español"}

@onready var padding: MarginContainer = $Padding
@onready var volume_slider: HSlider = $Padding/Content/VolumeRow/VolumeSlider
@onready var language_option: OptionButton = $Padding/Content/LanguageRow/LanguageOptionButton
@onready var animations_check: CheckButton = $Padding/Content/AnimationsRow/AnimationsCheckButton


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.POPUP_BG_COLOR
	style.corner_radius_top_left = UiTheme.POPUP_CORNER_RADIUS
	style.corner_radius_top_right = UiTheme.POPUP_CORNER_RADIUS
	style.corner_radius_bottom_left = UiTheme.POPUP_CORNER_RADIUS
	style.corner_radius_bottom_right = UiTheme.POPUP_CORNER_RADIUS
	add_theme_stylebox_override("panel", style)

	volume_slider.value = Settings.get_volume()
	volume_slider.value_changed.connect(_on_volume_changed)

	language_option.clear()
	for locale in Settings.AVAILABLE_LOCALES:
		language_option.add_item(LOCALE_LABELS.get(locale, locale))
	var current_locale := TranslationServer.get_locale().substr(0, 2)
	var current_index: int = Settings.AVAILABLE_LOCALES.find(current_locale)
	language_option.selected = current_index if current_index != -1 else 0
	language_option.item_selected.connect(_on_language_selected)

	animations_check.button_pressed = Settings.animations_enabled
	animations_check.toggled.connect(_on_animations_toggled)


func _on_animations_toggled(enabled: bool) -> void:
	Settings.set_animations_enabled(enabled)


func _on_language_selected(index: int) -> void:
	Settings.set_locale(Settings.AVAILABLE_LOCALES[index])


func popup_centered_auto() -> void:
	var min_size: Vector2 = padding.get_combined_minimum_size()
	min_size.x = max(min_size.x, 320)
	size = min_size
	popup_centered()


func _on_volume_changed(value: float) -> void:
	Settings.set_volume(value)
