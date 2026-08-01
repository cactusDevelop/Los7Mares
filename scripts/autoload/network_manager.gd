extends Node

signal player_list_changed
signal connection_failed_signal
signal server_disconnected_signal
signal lobby_synced
signal join_rejected(reason: String)

const DEFAULT_PORT := 7373
const MAX_PLAYERS := 5

var peer: ENetMultiplayerPeer
var is_online: bool = false

## peer_id (int, réseau) -> infos brutes reçues avant assignation dans GameFlow.players
var connected_peers: Dictionary = {}

## peer_id (int, réseau) -> player_id (int, GameFlow.players), rempli par
## _sync_lobby_state (autorité seulement) une fois le lobby validé. Permet à
## chaque instance de savoir "quel joueur suis-je" (cf board._get_display_current_player_id).
var peer_player_map: Dictionary = {}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host_game(port: int = DEFAULT_PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_online = true
	connected_peers[1] = {"name": "Hôte"}  # id 1 = toujours le serveur en Godot
	player_list_changed.emit()
	return OK

func join_game(ip: String, port: int = DEFAULT_PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_online = true
	return OK

func close_connection() -> void:
	if peer:
		peer.close()
	multiplayer.multiplayer_peer = null
	is_online = false
	connected_peers.clear()

func _on_peer_connected(id: int) -> void:
	connected_peers[id] = {"name": "Joueur %d" % id}
	player_list_changed.emit()

func _on_peer_disconnected(id: int) -> void:
	connected_peers.erase(id)
	player_list_changed.emit()

func _on_connected_to_server() -> void:
	player_list_changed.emit()

func _on_connection_failed() -> void:
	is_online = false
	connection_failed_signal.emit()

func _on_server_disconnected() -> void:
	is_online = false
	server_disconnected_signal.emit()


## Appelé localement par lobby.gd une fois que le joueur de CETTE instance a
## choisi son nom/couleur. Côté hôte, enregistre directement ; côté client,
## passe par un RPC vers l'hôte (toujours peer id 1 en ENet).
func request_join(player_name: String, color: String) -> void:
	if multiplayer.is_server():
		_register_player(1, player_name, color)
	else:
		_register_player_rpc.rpc_id(1, player_name, color)


@rpc("any_peer", "call_remote", "reliable")
func _register_player_rpc(player_name: String, color: String) -> void:
	if not multiplayer.is_server():
		return
	_register_player(multiplayer.get_remote_sender_id(), player_name, color)


## Autorité uniquement (hôte). Valide, ajoute le joueur dans GameFlow.players
## et rediffuse l'état complet à tout le monde (y compris soi-même, via
## call_local sur _sync_lobby_state).
func _register_player(peer_id: int, player_name: String, color: String) -> void:
	if GameFlow.is_name_taken(player_name):
		_reject_join.rpc_id(peer_id, "Ce nom est déjà pris.")
		return
	if GameFlow.is_color_taken(color):
		_reject_join.rpc_id(peer_id, "Cette couleur est déjà prise.")
		return
	var player: Dictionary = GameFlow.add_player(player_name, color)
	peer_player_map[peer_id] = player["id"]
	_sync_lobby_state.rpc(GameFlow.players, peer_player_map)


@rpc("authority", "call_remote", "reliable")
func _reject_join(reason: String) -> void:
	join_rejected.emit(reason)


@rpc("authority", "call_local", "reliable")
func _sync_lobby_state(players_data: Array, peer_map: Dictionary) -> void:
	GameFlow.set_players_from_network(players_data)
	peer_player_map = peer_map
	lobby_synced.emit()


## Appelé uniquement depuis lobby.gd quand l'hôte clique "Lancer la partie".
func request_start_game() -> void:
	if multiplayer.is_server():
		_start_game.rpc()


@rpc("authority", "call_local", "reliable")
func _start_game() -> void:
	GameFlow.go_to_board()
