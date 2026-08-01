extends Node

signal player_list_changed
signal connection_failed_signal
signal server_disconnected_signal
signal lobby_synced
signal join_rejected(reason: String)
signal code_join_found
signal code_join_failed

const DEFAULT_PORT := 7373
const MAX_PLAYERS := 5
## Port UDP séparé du port ENet, utilisé uniquement pour la découverte par
## code sur le réseau local (broadcast). N'a pas besoin d'être ouvert/forwardé
## sur un routeur puisque tout se passe en LAN.
const DISCOVERY_PORT := 7374
## Sans I ni O (confusion visuelle avec 1/0), pour rester lisible si un jour
## affiché sur un petit écran/HDMI branché au Raspberry Pi.
const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ"
const DISCOVERY_TIMEOUT := 4.0

var peer: ENetMultiplayerPeer
var is_online: bool = false

## Code à 4 lettres généré par l'hôte, affiché dans le Lobby, à donner aux
## autres joueurs pour qu'ils rejoignent sans connaître l'IP.
var room_code: String = ""

## peer_id (int, réseau) -> infos brutes reçues avant assignation dans GameFlow.players
var connected_peers: Dictionary = {}

## peer_id (int, réseau) -> player_id (int, GameFlow.players), rempli par
## _sync_lobby_state (autorité seulement) une fois le lobby validé. Permet à
## chaque instance de savoir "quel joueur suis-je" (cf board._get_display_current_player_id).
var peer_player_map: Dictionary = {}

## Douille de réponse aux demandes de découverte, active tant qu'on héberge.
var _discovery_server_peer: PacketPeerUDP
var _discovery_enet_port: int = DEFAULT_PORT

## Douille de recherche côté client, active seulement pendant find_game_by_code.
var _discovery_client_peer: PacketPeerUDP
var _discovery_seeking_code: String = ""
var _discovery_search_elapsed: float = 0.0

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
	room_code = _generate_room_code()
	_start_discovery_responder(port)
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
	_stop_discovery_responder()
	_stop_discovery_client()

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


func _generate_room_code() -> String:
	var code := ""
	for i in range(4):
		code += CODE_ALPHABET[randi() % CODE_ALPHABET.length()]
	return code


func _start_discovery_responder(enet_port: int) -> void:
	_discovery_enet_port = enet_port
	_discovery_server_peer = PacketPeerUDP.new()
	var err := _discovery_server_peer.bind(DISCOVERY_PORT)
	if err != OK:
		push_warning("Découverte par code indisponible (port UDP %d occupé : %s). Le port ENet %d reste utilisable directement." % [DISCOVERY_PORT, err, enet_port])
		_discovery_server_peer = null
		return
	set_process(true)


func _stop_discovery_responder() -> void:
	if _discovery_server_peer:
		_discovery_server_peer.close()
		_discovery_server_peer = null


## Lance une recherche broadcast LAN pour le code donné. Émet code_join_found
## (et rejoint automatiquement la partie) ou code_join_failed après timeout.
func find_game_by_code(code: String) -> void:
	_stop_discovery_client()
	_discovery_seeking_code = code.strip_edges().to_upper()
	_discovery_search_elapsed = 0.0
	_discovery_client_peer = PacketPeerUDP.new()
	_discovery_client_peer.set_broadcast_enabled(true)
	_discovery_client_peer.bind(0)
	_discovery_client_peer.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_discovery_client_peer.put_packet(("L7M_FIND:" + _discovery_seeking_code).to_utf8_buffer())
	set_process(true)


func _stop_discovery_client() -> void:
	if _discovery_client_peer:
		_discovery_client_peer.close()
		_discovery_client_peer = null
	_discovery_seeking_code = ""


func _process(delta: float) -> void:
	if _discovery_server_peer:
		while _discovery_server_peer.get_available_packet_count() > 0:
			var data: PackedByteArray = _discovery_server_peer.get_packet()
			var sender_ip := _discovery_server_peer.get_packet_ip()
			var sender_port := _discovery_server_peer.get_packet_port()
			_handle_discovery_request(data.get_string_from_utf8(), sender_ip, sender_port)

	if _discovery_client_peer:
		while _discovery_client_peer and _discovery_client_peer.get_available_packet_count() > 0:
			var data: PackedByteArray = _discovery_client_peer.get_packet()
			var sender_ip := _discovery_client_peer.get_packet_ip()
			_handle_discovery_response(data.get_string_from_utf8(), sender_ip)
		if _discovery_client_peer:
			_discovery_search_elapsed += delta
			if _discovery_search_elapsed > DISCOVERY_TIMEOUT:
				_stop_discovery_client()
				code_join_failed.emit()


func _handle_discovery_request(text: String, sender_ip: String, sender_port: int) -> void:
	if not text.begins_with("L7M_FIND:"):
		return
	var requested_code := text.substr("L7M_FIND:".length())
	if requested_code != room_code:
		return
	var reply := "L7M_HERE:%s:%d" % [room_code, _discovery_enet_port]
	_discovery_server_peer.set_dest_address(sender_ip, sender_port)
	_discovery_server_peer.put_packet(reply.to_utf8_buffer())


func _handle_discovery_response(text: String, sender_ip: String) -> void:
	if not text.begins_with("L7M_HERE:"):
		return
	var parts := text.split(":")
	if parts.size() != 3 or parts[1] != _discovery_seeking_code:
		return
	var found_port := int(parts[2])
	_stop_discovery_client()
	var err := join_game(sender_ip, found_port)
	if err != OK:
		connection_failed_signal.emit()
		return
	code_join_found.emit()


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
