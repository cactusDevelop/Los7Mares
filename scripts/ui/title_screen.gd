extends Control

@onready var background: TextureRect = $Background

@onready var center_buttons: VBoxContainer = $CenterButtons
@onready var host_button: Button = $CenterButtons/HostButton
@onready var join_button: Button = $CenterButtons/JoinButton
@onready var local_button: Button = $CenterButtons/LocalButton
@onready var debug_button: Button = $CenterButtons/DebugButton

@onready var player_count_popup: PopupPanel = $PlayerCountPopup
@onready var player_count_spinbox: SpinBox = $PlayerCountPopup/Padding/VBoxContainer/PlayerCountSpinBox
@onready var player_count_confirm_button: Button = $PlayerCountPopup/Padding/VBoxContainer/ConfirmButton
@onready var continue_button: Button = $CenterButtons/ContinueButton

@onready var join_ip_popup: PopupPanel = $JoinIpPopup
@onready var join_ip_line_edit: LineEdit = $JoinIpPopup/Padding/VBoxContainer/JoinIpLineEdit
@onready var join_ip_confirm_button: Button = $JoinIpPopup/Padding/VBoxContainer/ConfirmButton
@onready var join_error_label: Label = $JoinIpPopup/Padding/VBoxContainer/JoinErrorLabel

@onready var update_panel: PanelContainer = $UpdatePanel
@onready var update_label: Label = $UpdatePanel/Margin/HBoxContainer/UpdateLabel
@onready var update_download_button: Button = $UpdatePanel/Margin/HBoxContainer/UpdateDownloadButton
@onready var update_dismiss_button: Button = $UpdatePanel/Margin/HBoxContainer/UpdateDismissButton


func _on_continue_pressed() -> void:
	MusicManager.fade_to_random_game_music()
	GameFlow.continue_game()


func _ready() -> void:
	_style_popup_background(player_count_popup)
	_style_popup_background(join_ip_popup)

	continue_button.visible = SaveManager.has_save()

	_layout_ui()
	get_viewport().size_changed.connect(_layout_ui)

	MusicManager.play_menu_music()

	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	local_button.pressed.connect(_on_local_pressed)
	debug_button.pressed.connect(_on_debug_pressed)
	player_count_confirm_button.pressed.connect(_on_player_count_confirmed)
	continue_button.pressed.connect(_on_continue_pressed)
	join_ip_confirm_button.pressed.connect(_on_join_ip_confirmed)
	Network.code_join_found.connect(_on_code_join_found)
	Network.code_join_failed.connect(_on_code_join_failed)

	if Network.is_dedicated_server_launch():
		call_deferred("_on_host_pressed")
		return

	update_download_button.pressed.connect(_on_update_download_pressed)
	update_dismiss_button.pressed.connect(_on_update_dismiss_pressed)
	UpdateChecker.update_available.connect(_on_update_available)
	UpdateChecker.check_for_update()

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--join="):
			join_ip_line_edit.text = arg.substr("--join=".length())
			call_deferred("_on_join_ip_confirmed")
			break


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

	for btn in [continue_button, host_button, join_button, local_button, debug_button]:
		btn.custom_minimum_size = UiTheme.TITLE_BUTTON_SIZE
		btn.add_theme_font_size_override("font_size", UiTheme.TITLE_BUTTON_FONT_SIZE)
	center_buttons.size = center_buttons.get_combined_minimum_size()
	center_buttons.position = Vector2(
		(viewport_size.x - center_buttons.size.x) / 2.0,
		viewport_size.y - center_buttons.size.y - UiTheme.TITLE_BUTTONS_Y_OFFSET
	)


func _style_popup_background(popup: PopupPanel) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.POPUP_BG_COLOR
	style.corner_radius_top_left = UiTheme.POPUP_CORNER_RADIUS
	style.corner_radius_top_right = UiTheme.POPUP_CORNER_RADIUS
	style.corner_radius_bottom_left = UiTheme.POPUP_CORNER_RADIUS
	style.corner_radius_bottom_right = UiTheme.POPUP_CORNER_RADIUS
	popup.add_theme_stylebox_override("panel", style)


func _on_host_pressed() -> void:
	var err: Error = Network.host_game()
	if err != OK:
		push_error("Impossible d'héberger la partie : %s" % err)
		return
	SaveManager.delete()
	GameFlow.reset_players()
	GameFlow.is_debug_mode = false
	GameFlow.game_mode = "host"
	MusicManager.fade_to_random_game_music()
	GameFlow.go_to_lobby()


func _on_join_pressed() -> void:
	_popup_join_ip_centered()


func _on_join_ip_confirmed() -> void:
	var input := join_ip_line_edit.text.strip_edges()
	if input.is_empty():
		return
	join_error_label.visible = false
	join_ip_confirm_button.disabled = true
	if input.is_valid_ip_address():
		var err: Error = Network.join_game(input, Network.DEFAULT_PORT)
		if err != OK:
			_on_code_join_failed()
			return
		_on_code_join_found()
		return
	Network.find_game_by_code(input)


func _on_code_join_found() -> void:
	join_ip_confirm_button.disabled = false
	join_ip_popup.hide()
	SaveManager.delete()
	GameFlow.reset_players()
	GameFlow.is_debug_mode = false
	GameFlow.game_mode = "join"
	MusicManager.fade_to_random_game_music()
	GameFlow.go_to_lobby()


func _on_code_join_failed() -> void:
	join_ip_confirm_button.disabled = false
	join_error_label.visible = true


func _on_local_pressed() -> void:
	_popup_player_count_centered()


func _popup_join_ip_centered() -> void:
	join_error_label.visible = false
	join_ip_confirm_button.disabled = false
	join_ip_line_edit.text = ""
	var padding: MarginContainer = $JoinIpPopup/Padding
	var min_size: Vector2 = padding.get_combined_minimum_size()
	min_size.x = max(min_size.x, 320)
	join_ip_popup.size = min_size
	join_ip_popup.popup_centered()


## Le bouton Debug ne demande plus rien : 5 joueurs générés directement.
func _on_debug_pressed() -> void:
	SaveManager.delete()
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


func _on_update_available(latest_version: String) -> void:
	update_label.text = "Une nouvelle version (%s) est disponible !" % latest_version
	update_panel.visible = true


func _on_update_download_pressed() -> void:
	OS.shell_open(UpdateChecker.RELEASES_PAGE_URL)


func _on_update_dismiss_pressed() -> void:
	update_panel.visible = false


func _on_player_count_confirmed() -> void:
	SaveManager.delete()
	player_count_popup.hide()
	var count := int(player_count_spinbox.value)
	GameFlow.is_debug_mode = false
	GameFlow.reset_players()
	GameFlow.pending_setup_mode = "local"
	GameFlow.pending_setup_target_count = count
	MusicManager.fade_to_random_game_music()
	GameFlow.go_to_board()
