extends Node

signal player_list_changed
signal connection_failed_signal
signal server_disconnected_signal

const DEFAULT_PORT := 7373
const MAX_PLAYERS := 5

var peer: ENetMultiplayerPeer
var is_online: bool = false

## peer_id (int, réseau) -> infos brutes reçues avant assignation dans GameFlow.players
var connected_peers: Dictionary = {}

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
