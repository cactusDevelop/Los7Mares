extends Control

@onready var status_label: Label = $StatusLabel
@onready var players_list_box: VBoxContainer = $PlayersListBox
@onready var start_button: Button = $StartButton
@onready var player_setup_popup: Control = $PlayerSetupPopup

## Devient vrai après que Network.request_join() a été envoyé pour CETTE
## instance (empêche de rouvrir la popup tant qu'on attend une réponse).
var _has_registered: bool = false
## Devient vrai dès que la popup a été ouverte une première fois (empêche de
## la rouvrir/réinitialiser à chaque signal de statut réseau reçu).
var _setup_opened: bool = false


func _ready() -> void:
	status_label.text = ""
	start_button.visible = multiplayer.is_server()
	start_button.disabled = true
	start_button.pressed.connect(_on_start_pressed)

	player_setup_popup.player_confirmed.connect(_on_local_player_confirmed)

	GameFlow.players_changed.connect(_refresh_list)
	Network.join_rejected.connect(_on_join_rejected)
	Network.player_list_changed.connect(_on_network_status_changed)
	Network.lobby_synced.connect(_refresh_list)

	_refresh_list()
	_try_open_local_setup()


func _try_open_local_setup() -> void:
	if _has_registered or _setup_opened:
		return
	if GameFlow.game_mode == "join":
		var mp_peer: MultiplayerPeer = multiplayer.multiplayer_peer
		if mp_peer == null or mp_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			status_label.text = tr("Connexion à l'hôte...")
			return
	status_label.text = ""
	_setup_opened = true
	player_setup_popup.open_for_new_player()


func _on_network_status_changed() -> void:
	_try_open_local_setup()


func _on_local_player_confirmed(player_name: String, color: String) -> void:
	_has_registered = true
	player_setup_popup.visible = false
	Network.request_join(player_name, color)


func _on_join_rejected(reason: String) -> void:
	_has_registered = false
	player_setup_popup.visible = true
	player_setup_popup.show_error(reason)


func _refresh_list() -> void:
	for child in players_list_box.get_children():
		child.queue_free()
	for p in GameFlow.players:
		var lbl := Label.new()
		lbl.text = "%s — %s" % [p["name"], p["color"]]
		players_list_box.add_child(lbl)
	if multiplayer.is_server():
		start_button.disabled = GameFlow.players.is_empty()


func _on_start_pressed() -> void:
	Network.request_start_game()
