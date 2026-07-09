extends Control

@onready var background: TextureRect = $Background
@onready var settings_button: Button = $SettingsButton
@onready var settings_popup: PopupPanel = $SettingsPopup

@onready var center_buttons: VBoxContainer = $CenterButtons
@onready var host_button: Button = $CenterButtons/HostButton
@onready var join_button: Button = $CenterButtons/JoinButton
@onready var local_button: Button = $CenterButtons/LocalButton
@onready var debug_button: Button = $CenterButtons/DebugButton

@onready var player_count_popup: PopupPanel = $PlayerCountPopup
@onready var player_count_spinbox: SpinBox = $PlayerCountPopup/VBoxContainer/PlayerCountSpinBox
@onready var player_count_confirm_button: Button = $PlayerCountPopup/VBoxContainer/ConfirmButton

var _pending_popup_action: String = ""  # "local" ou "debug"


func _ready() -> void:
	_layout_ui()
	get_viewport().size_changed.connect(_layout_ui)

	settings_button.pressed.connect(_on_settings_pressed)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	local_button.pressed.connect(_on_local_pressed)
	debug_button.pressed.connect(_on_debug_pressed)
	player_count_confirm_button.pressed.connect(_on_player_count_confirmed)


func _layout_ui() -> void:
	var viewport_size := get_viewport_rect().size

	background.position = Vector2.ZERO
	background.size = viewport_size
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

	var settings_size := Vector2(50, 50)
	settings_button.size = settings_size
	settings_button.position = viewport_size - settings_size - Vector2(20, 20)
	settings_button.text = ""
	settings_button.icon = preload("res://assets/art/ui/gear.svg")
	settings_button.expand_icon = true
	settings_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	
	for btn in [host_button, join_button, local_button, debug_button]:
		btn.custom_minimum_size = Vector2(320, 60)
	center_buttons.size = center_buttons.get_combined_minimum_size()
	center_buttons.position = (viewport_size - center_buttons.size) / 2.0


func _on_settings_pressed() -> void:
	settings_popup.popup_centered()


func _on_host_pressed() -> void:
	GameFlow.reset_players()
	GameFlow.is_debug_mode = false
	GameFlow.pending_setup_mode = "host"
	GameFlow.pending_setup_target_count = 1
	GameFlow.go_to_board()


func _on_join_pressed() -> void:
	GameFlow.reset_players()
	GameFlow.is_debug_mode = false
	GameFlow.pending_setup_mode = "join"
	GameFlow.pending_setup_target_count = 1
	GameFlow.go_to_board()


func _on_local_pressed() -> void:
	_pending_popup_action = "local"
	player_count_popup.popup_centered()


func _on_debug_pressed() -> void:
	_pending_popup_action = "debug"
	player_count_popup.popup_centered()


func _on_player_count_confirmed() -> void:
	player_count_popup.hide()
	var count := int(player_count_spinbox.value)

	if _pending_popup_action == "debug":
		GameFlow.is_debug_mode = true
		GameFlow.pending_setup_mode = ""
		GameFlow.generate_debug_players(count)
	else:
		GameFlow.is_debug_mode = false
		GameFlow.reset_players()
		GameFlow.pending_setup_mode = "local"
		GameFlow.pending_setup_target_count = count

	GameFlow.go_to_board()
