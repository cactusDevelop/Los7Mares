extends Node

signal player_list_changed
signal connection_failed_signal
signal server_disconnected_signal
signal lobby_synced
signal join_rejected(reason: String)
signal code_join_found
signal code_join_failed
## Émis côté client une fois l'aperçu des joueurs déjà inscrits reçu de
## l'hôte (cf request_lobby_preview), AVANT que ce client se soit lui-même
## inscrit : permet à player_setup_popup de griser les couleurs déjà prises
## par les autres, comme en partie locale/debug (GameFlow.players y est déjà
## rempli à ce moment-là, cf lobby.gd).
signal lobby_preview_received
## Émis côté client quand l'hôte refuse un changement de couleur demandé
## depuis le menu d'attente (couleur prise entre-temps par un autre joueur),
## cf request_change_color / lobby.gd.
signal color_change_rejected(reason: String)
## Émis (RPC autorité, call_local) quand un joueur se déconnecte APRÈS le
## lancement de la partie (cf _handle_peer_left) : contrairement au lobby,
## on ne le retire pas de GameFlow.players (son plateau doit rester
## affichable), on prévient juste tout le monde pour afficher une bannière
## d'attente (cf board.gd).
signal player_disconnected_ingame(player_id: int)
## Émis (RPC autorité, call_local) quand un joueur précédemment déconnecté
## en pleine partie vient de se reconnecter (cf _reconnect_player) : cf
## board.gd pour la levée de bannière/pause associée.
signal player_reconnected_ingame(player_id: int)

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

## Nom affiché pour l'hôte dans la liste du Lobby (avec la couronne), même
## quand il choisit "Serveur dédié" et n'est donc PAS dans GameFlow.players.
## Si l'hôte joue, ce champ reste vide : on affiche alors son nom de JOUEUR
## (avec la couronne à côté) via peer_player_map, cf lobby.gd._refresh_list.
var host_name: String = ""

## IP/port/pseudo/couleur de la dernière inscription réussie dans une partie
## en ligne (rempli par request_join, cf plus bas) : permet au bouton
## "CONTINUER (EN LIGNE)" du menu titre de retenter une connexion au même
## hôte avec la même identité après un retour au menu en pleine partie (cf
## rejoin_last_online_game, close_connection qui ne les efface volontairement
## PAS pour que ce bouton reste disponible ensuite).
var last_join_ip: String = ""
var last_join_port: int = -1
var last_player_name: String = ""
var last_player_color: String = ""
## Vrai entre l'appel à rejoin_last_online_game() et l'inscription qui suit
## dans lobby.gd : indique qu'il faut renvoyer last_player_name/color
## directement (pas de popup nom/couleur), cf _try_open_local_setup.
var is_rejoining: bool = false

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
	GameFlow.players_changed.connect(_mark_game_state_dirty)
	GameFlow.current_player_changed.connect(func(_id): _mark_game_state_dirty())

## Vrai si cette instance doit démarrer automatiquement en Serveur dédié,
## sans passer par les boutons du menu :
## - export "Exporter comme serveur dédié" (tag de fonctionnalité
##   "dedicated_server", ajouté automatiquement par Godot à l'export), utilisé
##   pour le binaire ARM32 du Raspberry Pi ;
## - ou argument --dedicated-server (pratique pour tester depuis l'éditeur ou
##   un export classique, sans devoir créer un export dédié).
func is_dedicated_server_launch() -> bool:
	return OS.has_feature("dedicated_server") or OS.get_cmdline_user_args().has("--dedicated-server")


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
	last_join_ip = ip
	last_join_port = port
	return OK

func close_connection() -> void:
	if peer:
		peer.close()
	multiplayer.multiplayer_peer = null
	is_online = false
	_game_started = false
	connected_peers.clear()
	_stop_discovery_responder()
	_stop_discovery_client()

func _on_peer_connected(id: int) -> void:
	connected_peers[id] = {"name": "Joueur %d" % id}
	player_list_changed.emit()

func _on_peer_disconnected(id: int) -> void:
	connected_peers.erase(id)
	player_list_changed.emit()
	# Autorité uniquement : les clients reçoivent aussi ce signal (relayé par
	# le serveur) à titre informatif, mais ne doivent pas modifier
	# GameFlow.players eux-mêmes (source de vérité = l'hôte, cf _register_player).
	if multiplayer.is_server():
		_handle_peer_left(id)


## Autorité uniquement. Un pair vient de se déconnecter (a quitté le lobby,
## ou perdu la connexion en cours de partie) :
## - AVANT le lancement (_game_started == false) : "énorme bug" corrigé ici -
##   le joueur associé restait fantôme dans GameFlow.players (visible dans le
##   lobby, et toujours présent si l'hôte lançait la partie). On le retire
##   entièrement et on rediffuse l'état complet, comme pour une inscription
##   (cf _register_player), pour que la liste du lobby ET le grisé de la
##   popup nom/couleur des autres joueurs se libèrent immédiatement.
## - APRÈS le lancement : on garde son joueur (son plateau, ses ressources...
##   doivent rester affichables) et on prévient tout le monde via
##   player_disconnected_ingame (cf board.gd, bannière "En attente d'un joueur").
func _handle_peer_left(peer_id: int) -> void:
	var player_id: int = peer_player_map.get(peer_id, -1)
	if player_id == -1:
		return
	if not _game_started:
		GameFlow.remove_player_by_id(player_id)
		peer_player_map.erase(peer_id)
		_sync_lobby_state.rpc(GameFlow.players, peer_player_map)
	else:
		# IMPORTANT : on retire aussi l'entrée ici (contrairement à la
		# branche lobby ci-dessus qui retire le JOUEUR ET l'entrée) pour
		# que _find_reconnectable_player le considère comme "orphelin" et
		# accepte sa reconnexion (cf _register_player) ; GameFlow.players,
		# lui, garde bien le joueur (son plateau doit rester affichable).
		peer_player_map.erase(peer_id)
		_notify_player_disconnected_ingame.rpc(player_id)


@rpc("authority", "call_local", "reliable")
func _notify_player_disconnected_ingame(player_id: int) -> void:
	player_disconnected_ingame.emit(player_id)

func _on_connected_to_server() -> void:
	player_list_changed.emit()

func _on_connection_failed() -> void:
	is_online = false
	connection_failed_signal.emit()

func _on_server_disconnected() -> void:
	is_online = false
	server_disconnected_signal.emit()


## Vrai une fois la partie lancée (lobby terminé) : avant ça, la diffusion
## passe uniquement par _sync_lobby_state (cf request_join), pas par ce
## canal générique, pour éviter d'envoyer 2 RPC redondants à chaque ajout de
## joueur dans le lobby.
var _game_started: bool = false
var _state_broadcast_pending: bool = false

## Rebranché à chaque changement de GameFlow.players ou .current_player_id :
## regroupe les appels de la même frame (players_changed peut être émis
## plusieurs fois d'affilée) en un seul paquet réseau via call_deferred.
func _mark_game_state_dirty() -> void:
	if not is_online or not multiplayer.is_server() or not _game_started:
		return
	if _state_broadcast_pending:
		return
	_state_broadcast_pending = true
	call_deferred("_broadcast_game_state")


func _broadcast_game_state() -> void:
	_state_broadcast_pending = false
	_sync_game_state.rpc(GameFlow.players, GameFlow.current_player_id, GameFlow.round_number)


## call_remote (pas call_local) : l'hôte a déjà l'état à jour localement,
## se le renvoyer à lui-même ré-émettrait players_changed et redéclencherait
## _mark_game_state_dirty en boucle.
@rpc("authority", "call_remote", "reliable")
func _sync_game_state(players_data: Array, current_player_id: int, round_number: int) -> void:
	GameFlow.set_players_from_network(players_data)
	GameFlow.current_player_id = current_player_id
	GameFlow.current_player_changed.emit(current_player_id)
	GameFlow.round_number = round_number


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


## Appelé par lobby.gd côté client, juste après connexion, AVANT d'ouvrir la
## popup nom/couleur : demande à l'hôte la liste actuelle des joueurs déjà
## inscrits (mêmes données que _sync_lobby_state, mais sans inscrire qui que
## ce soit) pour que la popup puisse griser les couleurs déjà prises, comme
## en partie locale/debug (cf player_setup_popup.open_for_new_player).
func request_lobby_preview() -> void:
	if not multiplayer.is_server():
		_request_lobby_preview_rpc.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_lobby_preview_rpc() -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	_send_lobby_preview_rpc.rpc_id(sender_id, GameFlow.players)


@rpc("authority", "call_remote", "reliable")
func _send_lobby_preview_rpc(players_data: Array) -> void:
	# GameFlow.set_players_from_network fait exactement ce qu'il faut ici :
	# remplir GameFlow.players avec les joueurs déjà inscrits par les autres
	# (pour is_color_taken/is_name_taken), sans toucher peer_player_map tant
	# que CE client ne s'est pas lui-même inscrit. _sync_lobby_state (appelé
	# juste après request_join) écrasera ensuite cette liste avec l'état
	# complet post-inscription, donc aucun risque de rester sur des données
	# périmées si un autre joueur rejoint entre-temps.
	GameFlow.set_players_from_network(players_data)
	lobby_preview_received.emit()


## Appelé localement par lobby.gd une fois que le joueur de CETTE instance a
## choisi son nom/couleur. Côté hôte, enregistre directement ; côté client,
## passe par un RPC vers l'hôte (toujours peer id 1 en ENet).
func request_join(player_name: String, color: String) -> void:
	last_player_name = player_name
	last_player_color = color
	if multiplayer.is_server():
		_register_player(1, player_name, color)
	else:
		_register_player_rpc.rpc_id(1, player_name, color)


## Rejoue la dernière connexion réussie (même hôte, même pseudo/couleur) :
## utilisé par le bouton "CONTINUER (EN LIGNE)" du menu titre après un
## retour au menu en pleine partie. lobby.gd s'inscrit ensuite normalement
## via request_join() avec last_player_name/last_player_color (cf
## _try_open_local_setup) : si l'hôte reconnaît un joueur du même nom/
## couleur actuellement déconnecté dans une partie en cours, il nous
## reconnecte directement dedans (cf _register_player) ; sinon on retombe
## sur le lobby normal comme une inscription neuve.
func has_resumable_online_session() -> bool:
	return not last_join_ip.is_empty() and last_join_port != -1 and not last_player_name.is_empty()


func rejoin_last_online_game() -> Error:
	if not has_resumable_online_session():
		return ERR_UNCONFIGURED
	var err := join_game(last_join_ip, last_join_port)
	if err != OK:
		return err
	is_rejoining = true
	return OK


@rpc("any_peer", "call_remote", "reliable")
func _register_player_rpc(player_name: String, color: String) -> void:
	if not multiplayer.is_server():
		return
	_register_player(multiplayer.get_remote_sender_id(), player_name, color)


## Autorité uniquement (hôte). Valide, ajoute le joueur dans GameFlow.players
## et rediffuse l'état complet à tout le monde (y compris soi-même, via
## call_local sur _sync_lobby_state).
func _register_player(peer_id: int, player_name: String, color: String) -> void:
	print("[Network] _register_player peer_id=%d name=%s color=%s" % [peer_id, player_name, color])
	if _game_started:
		# La partie est déjà lancée : seul un joueur qui en faisait DÉJÀ
		# partie (même nom + même couleur) ET actuellement déconnecté (pas
		# dans peer_player_map) peut revenir, cf _reconnect_player. Un
		# nouveau venu (ou un nom/couleur qui ne correspond à personne)
		# est refusé avec le même mécanisme que join_rejected (popup nom/
		# couleur du lobby, cf lobby.gd._on_join_rejected).
		var existing := _find_reconnectable_player(player_name, color)
		if existing.is_empty():
			_reject_join.rpc_id(peer_id, "Partie déjà en cours.")
			return
		_reconnect_player(peer_id, existing["id"])
		return
	if GameFlow.is_name_taken(player_name):
		_reject_join.rpc_id(peer_id, "Ce nom est déjà pris.")
		return
	var actual_color := color
	if actual_color.is_empty():
		actual_color = _next_available_color()
		if actual_color.is_empty():
			_reject_join.rpc_id(peer_id, "Plus de couleur disponible.")
			return
	elif GameFlow.is_color_taken(actual_color):
		_reject_join.rpc_id(peer_id, "Cette couleur est déjà prise.")
		return
	var player: Dictionary = GameFlow.add_player(player_name, actual_color)
	peer_player_map[peer_id] = player["id"]
	print("[Network] joueur ajouté id=%s, total joueurs=%d, diffusion à tous les pairs" % [player["id"], GameFlow.players.size()])
	_sync_lobby_state.rpc(GameFlow.players, peer_player_map)


## Un joueur de GameFlow.players (déjà présent depuis avant le lancement de
## la partie) dont le peer courant est absent de peer_player_map : il s'est
## déconnecté en cours de partie (cf _handle_peer_left) et peut donc
## reprendre sa place. Ne matche que sur nom+couleur EXACTS : un joueur qui
## change de pseudo/couleur pour "Continuer (en ligne)" ne récupère pas la
## place d'un autre par erreur.
func _find_reconnectable_player(player_name: String, color: String) -> Dictionary:
	var reconnected_ids: Array = peer_player_map.values()
	for p in GameFlow.players:
		if p["name"] == player_name and p["color"] == color and not reconnected_ids.has(p["id"]):
			return p
	return {}


## Autorité uniquement. Réassocie ce peer au joueur existant (au lieu d'en
## créer un nouveau), lui envoie tout ce qu'il faut pour rejoindre le
## plateau directement (cf GameFlow.apply_reconnect_snapshot, même
## mécanisme que "Continuer" en solo), puis prévient tout le monde pour
## lever la bannière "En attente d'un joueur" et dépauser la partie (cf
## board.gd).
func _reconnect_player(peer_id: int, player_id: int) -> void:
	peer_player_map[peer_id] = player_id
	_send_reconnect_data.rpc_id(
		peer_id, GameFlow.players, GameFlow.current_player_id,
		GameFlow.round_number, GameFlow.board_seed, GameFlow.last_board_snapshot,
	)
	_notify_player_reconnected_ingame.rpc(player_id)


@rpc("authority", "call_remote", "reliable")
func _send_reconnect_data(players_data: Array, current_player_id: int, round_number: int, board_seed: int, board_snapshot: Dictionary) -> void:
	_game_started = true
	GameFlow.apply_reconnect_snapshot(players_data, current_player_id, round_number, board_seed, board_snapshot)


@rpc("authority", "call_local", "reliable")
func _notify_player_reconnected_ingame(player_id: int) -> void:
	player_reconnected_ingame.emit(player_id)


## Couleur assignée automatiquement (client sans choix de couleur, cf
## player_setup_popup require_color=false) : la 1ère non encore prise dans
## l'ordre fixe GameFlow.COLORS, pour un résultat prévisible/reproductible.
func _next_available_color() -> String:
	for color_name in GameFlow.COLORS:
		if not GameFlow.is_color_taken(color_name):
			return color_name
	return ""


## Appelé par lobby.gd quand l'hôte choisit "Serveur dédié" : il fournit un
## nom pour apparaître dans la liste (avec la couronne) sans devenir un
## joueur (pas de couleur, pas d'entrée dans GameFlow.players).
func set_host_name(display_name: String) -> void:
	if multiplayer.is_server():
		_broadcast_host_name.rpc(display_name)


@rpc("authority", "call_local", "reliable")
func _broadcast_host_name(display_name: String) -> void:
	host_name = display_name
	lobby_synced.emit()


@rpc("authority", "call_remote", "reliable")
func _reject_join(reason: String) -> void:
	join_rejected.emit(reason)


@rpc("authority", "call_local", "reliable")
func _sync_lobby_state(players_data: Array, peer_map: Dictionary) -> void:
	print("[Network] _sync_lobby_state reçu, %d joueur(s), moi=%d" % [players_data.size(), multiplayer.get_unique_id()])
	GameFlow.set_players_from_network(players_data)
	peer_player_map = peer_map
	lobby_synced.emit()


## Appelé par lobby.gd quand un joueur DÉJÀ inscrit change de couleur depuis
## le menu d'attente (pas au moment de son inscription initiale, cf
## request_join ci-dessus). Même flux autorité/RPC : l'hôte applique
## directement, les clients passent par un RPC vers l'hôte.
func request_change_color(color: String) -> void:
	if multiplayer.is_server():
		_change_color(1, color)
	else:
		_change_color_rpc.rpc_id(1, color)


@rpc("any_peer", "call_remote", "reliable")
func _change_color_rpc(color: String) -> void:
	if not multiplayer.is_server():
		return
	_change_color(multiplayer.get_remote_sender_id(), color)


## Autorité uniquement (hôte). Rejette si la couleur est déjà prise par un
## AUTRE joueur ; ne fait rien si c'est déjà la couleur actuelle du joueur.
## En cas de succès, rediffuse l'état complet à tout le monde comme
## _register_player, pour que la liste du lobby ET la popup nom/couleur des
## joueurs en train de rejoindre restent synchronisées (cf lobby.gd
## _refresh_list, qui rafraîchit aussi player_setup_popup si elle est ouverte).
func _change_color(peer_id: int, color: String) -> void:
	var player_id: int = peer_player_map.get(peer_id, -1)
	if player_id == -1:
		return
	var player: Dictionary = GameFlow.get_player_by_id(player_id)
	if player.is_empty() or player["color"] == color:
		return
	if GameFlow.is_color_taken(color):
		_reject_color_change.rpc_id(peer_id, "Cette couleur est déjà prise.")
		return
	GameFlow.set_player_color(player_id, color)
	_sync_lobby_state.rpc(GameFlow.players, peer_player_map)


@rpc("authority", "call_remote", "reliable")
func _reject_color_change(reason: String) -> void:
	color_change_rejected.emit(reason)


## Appelé uniquement depuis lobby.gd quand l'hôte clique "Lancer la partie".
func request_start_game() -> void:
	if multiplayer.is_server():
		_start_game.rpc(randi())


@rpc("authority", "call_local", "reliable")
func _start_game(board_seed: int) -> void:
	GameFlow.board_seed = board_seed
	_game_started = true
	GameFlow.go_to_board()
