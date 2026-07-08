extends Control

@onready var background: TextureRect = $Background
@onready var settings_button: Button = $SettingsButton
@onready var settings_popup: PopupPanel = $SettingsPopup

@onready var center_buttons: VBoxContainer = $CenterButtons
@onready var host_button: Button = $CenterButtons/HostButton
@onready var join_button: Button = $CenterButtons/JoinButton
@onready var debug_button: Button = $CenterButtons/DebugButton

@onready var debug_popup: PopupPanel = $DebugPopup
@onready var debug_player_count: SpinBox = $DebugPopup/VBoxContainer/PlayerCountSpinBox
@onready var debug_confirm_button: Button = $DebugPopup/VBoxContainer/ConfirmButton


func _ready() -> void:
	_layout_ui()
	get_viewport().size_changed.connect(_layout_ui)

	settings_button.pressed.connect(_on_settings_pressed)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	debug_button.pressed.connect(_on_debug_pressed)
	debug_confirm_button.pressed.connect(_on_debug_confirm_pressed)


func _layout_ui() -> void:
	var viewport_size := get_viewport_rect().size

	# Image de fond : couvre tout l'écran, en gardant les proportions.
	background.position = Vector2.ZERO
	background.size = viewport_size
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

	# Bouton paramètres, en bas à droite.
	var settings_size := Vector2(180, 50)
	settings_button.size = settings_size
	settings_button.position = viewport_size - settings_size - Vector2(20, 20)

	# Boutons centraux (host/join/debug), centrés à l'écran.
	for btn in [host_button, join_button, debug_button]:
		btn.custom_minimum_size = Vector2(320, 60)
	center_buttons.size = center_buttons.get_combined_minimum_size()
	center_buttons.position = (viewport_size - center_buttons.size) / 2.0


func _on_settings_pressed() -> void:
	settings_popup.popup_centered()


func _on_host_pressed() -> void:
	GameFlow.reset_players()
	GameFlow.is_debug_mode = false
	GameFlow.pending_setup_mode = "host"
	GameFlow.go_to_board()


func _on_join_pressed() -> void:
	GameFlow.reset_players()
	GameFlow.is_debug_mode = false
	GameFlow.pending_setup_mode = "join"
	GameFlow.go_to_board()


func _on_debug_pressed() -> void:
	debug_popup.popup_centered()


func _on_debug_confirm_pressed() -> void:
	debug_popup.hide()
	var count := int(debug_player_count.value)
	GameFlow.is_debug_mode = true
	GameFlow.pending_setup_mode = ""
	GameFlow.generate_debug_players(count)
	GameFlow.go_to_board()
