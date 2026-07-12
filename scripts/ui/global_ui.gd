extends CanvasLayer

## Overlay global (icône paramètres) : instancié une seule fois en autoload,
## donc il survit à change_scene_to_file() et reste visible sur TOUTES les
## scènes (title screen, board, etc.), toujours ancré en bas à droite.

@onready var settings_button: TextureButton = $SettingsButton
@onready var settings_popup: PopupPanel = $SettingsPopup

var _settings_hover_tween: Tween
var _settings_open := false  # true tant que la popup paramètres est affichée


func _ready() -> void:
	layer = 100  # au-dessus de tout le reste (toutes scènes confondues)

	var settings_size := Vector2(50, 50)
	settings_button.size = settings_size
	settings_button.pivot_offset = settings_size / 2.0
	settings_button.texture_normal = preload("res://assets/art/ui/gear.svg")
	settings_button.ignore_texture_size = true
	settings_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	settings_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	settings_button.pressed.connect(_on_settings_pressed)
	settings_button.mouse_entered.connect(_on_settings_hover)
	settings_button.mouse_exited.connect(_on_settings_unhover)
	settings_popup.popup_hide.connect(_on_settings_popup_hide)

	_reposition()
	get_viewport().size_changed.connect(_reposition)


## Coin bas-droit, 20px de marge. Recalculé à chaque redimensionnement
## de la fenêtre pour rester toujours visible, quelle que soit la scène.
func _reposition() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	settings_button.position = viewport_size - settings_button.size - Vector2(20, 20)


func _on_settings_pressed() -> void:
	_settings_open = true
	_apply_transform(true)
	settings_popup.popup_centered_auto()


## Appelé quand la popup se ferme, que ce soit via clic extérieur, ESC,
## ou fermeture programmatique.
func _on_settings_popup_hide() -> void:
	_settings_open = false
	var mouse_over_button := settings_button.get_global_rect().has_point(get_viewport().get_mouse_position())
	if not mouse_over_button:
		_apply_transform(false)


func _on_settings_hover() -> void:
	_apply_transform(true)


func _on_settings_unhover() -> void:
	if _settings_open:
		return  # Reste tourné/agrandi tant que la popup est ouverte.
	_apply_transform(false)


func _apply_transform(active: bool) -> void:
	if _settings_hover_tween:
		_settings_hover_tween.kill()
	_settings_hover_tween = create_tween().set_parallel(true)
	var target_rotation := 20.0 if active else 0.0
	var target_scale := Vector2(1.15, 1.15) if active else Vector2.ONE
	_settings_hover_tween.tween_property(settings_button, "rotation_degrees", target_rotation, 0.15) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_settings_hover_tween.tween_property(settings_button, "scale", target_scale, 0.15) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
