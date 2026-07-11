extends Control

@onready var background: TextureRect = $Background
@onready var settings_button: TextureButton = $SettingsButton
@onready var settings_popup: PopupPanel = $SettingsPopup

@onready var center_buttons: VBoxContainer = $CenterButtons
@onready var host_button: Button = $CenterButtons/HostButton
@onready var join_button: Button = $CenterButtons/JoinButton
@onready var local_button: Button = $CenterButtons/LocalButton
@onready var debug_button: Button = $CenterButtons/DebugButton

@onready var player_count_popup: PopupPanel = $PlayerCountPopup
@onready var player_count_spinbox: SpinBox = $PlayerCountPopup/Padding/VBoxContainer/PlayerCountSpinBox
@onready var player_count_confirm_button: Button = $PlayerCountPopup/Padding/VBoxContainer/ConfirmButton


func _ready() -> void:
	_style_popup_background(player_count_popup)

	_layout_ui()
	get_viewport().size_changed.connect(_layout_ui)

	MusicManager.play_menu_music()

	settings_button.pressed.connect(_on_settings_pressed)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	local_button.pressed.connect(_on_local_pressed)
	debug_button.pressed.connect(_on_debug_pressed)
	player_count_confirm_button.pressed.connect(_on_player_count_confirmed)


func _layout_ui() -> void:
	var viewport_size := get_viewport_rect().size

	# Image de fond : couvre toute la largeur, ancrée en HAUT (pas de crop centré).
	clip_contents = true
	var tex := background.texture
	if tex:
		var tex_size := tex.get_size()
		var scale_factor := viewport_size.x / tex_size.x
		background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		background.stretch_mode = TextureRect.STRETCH_SCALE
		background.position = Vector2.ZERO
		background.size = Vector2(viewport_size.x, tex_size.y * scale_factor)

	var settings_size := Vector2(50, 50)
	settings_button.size = settings_size
	settings_button.position = viewport_size - settings_size - Vector2(20, 20)
	settings_button.texture_normal = preload("res://assets/art/ui/gear.svg")
	settings_button.ignore_texture_size = true
	settings_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED

	for btn in [host_button, join_button, local_button, debug_button]:
		btn.custom_minimum_size = GameFlow.TITLE_BUTTON_SIZE
		btn.add_theme_font_size_override("font_size", GameFlow.TITLE_BUTTON_FONT_SIZE)
	center_buttons.size = center_buttons.get_combined_minimum_size()
	center_buttons.position = (viewport_size - center_buttons.size) / 2.0 \
		+ Vector2(0, GameFlow.TITLE_BUTTONS_Y_OFFSET)


func _style_popup_background(popup: PopupPanel) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = GameFlow.POPUP_BG_COLOR
	style.corner_radius_top_left = GameFlow.POPUP_CORNER_RADIUS
	style.corner_radius_top_right = GameFlow.POPUP_CORNER_RADIUS
	style.corner_radius_bottom_left = GameFlow.POPUP_CORNER_RADIUS
	style.corner_radius_bottom_right = GameFlow.POPUP_CORNER_RADIUS
	popup.add_theme_stylebox_override("panel", style)


func _on_settings_pressed() -> void:
	settings_popup.popup_centered_auto()


func _on_host_pressed() -> void:
	GameFlow.reset_players()
	GameFlow.is_debug_mode = false
	GameFlow.pending_setup_mode = "host"
	GameFlow.pending_setup_target_count = 1
	MusicManager.fade_to_random_game_music()
	GameFlow.go_to_board()


func _on_join_pressed() -> void:
	GameFlow.reset_players()
	GameFlow.is_debug_mode = false
	GameFlow.pending_setup_mode = "join"
	GameFlow.pending_setup_target_count = 1
	MusicManager.fade_to_random_game_music()
	GameFlow.go_to_board()


func _on_local_pressed() -> void:
	_popup_player_count_centered()


## Le bouton Debug ne demande plus rien : 5 joueurs générés directement.
func _on_debug_pressed() -> void:
	GameFlow.is_debug_mode = true
	GameFlow.pending_setup_mode = ""
	GameFlow.generate_debug_players(5)
	MusicManager.fade_to_random_game_music()
	GameFlow.go_to_board()


func _popup_player_count_centered() -> void:
	var padding: MarginContainer = $PlayerCountPopup/Padding
	var min_size: Vector2 = padding.get_combined_minimum_size()
	min_size.x = max(min_size.x, 320)
	player_count_popup.size = min_size
	player_count_popup.popup_centered()


func _on_player_count_confirmed() -> void:
	player_count_popup.hide()
	var count := int(player_count_spinbox.value)
	GameFlow.is_debug_mode = false
	GameFlow.reset_players()
	GameFlow.pending_setup_mode = "local"
	GameFlow.pending_setup_target_count = count
	MusicManager.fade_to_random_game_music()
	GameFlow.go_to_board()
