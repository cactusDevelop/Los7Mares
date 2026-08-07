extends CanvasLayer
class_name RemoteCursors
## Overlay affichant la position du curseur souris des AUTRES joueurs
## connectés (partie en ligne héberger/rejoindre uniquement), tinté avec
## leur couleur (cf GameFlow.COLOR_VALUES). Instancié et piloté par
## board.gd (voir _process/_report_cursor_pos/_relay_cursor_pos là-bas).
##
## Coût volontairement minimal pour rester jouable sur un Raspberry Pi
## (host dédié ARM32 ET/OU client faible type Pi 2) :
## - 1 seul float2 envoyé par joueur, ~20 fois/seconde, en unreliable_ordered
##   (paquets perdus/anciens simplement ignorés, pas de retransmission) ;
## - au plus (MAX_PLAYERS - 1) sprites 2D statiques à l'écran, sans
##   physique ni particule ; coût de rendu négligeable par rapport au reste
##   du plateau (cf compatibilité gl_compatibility déjà utilisée par le
##   projet pour cette même raison, voir project.godot).

const CURSOR_TEXTURE_PATH := "res://assets/art/ui/cursor.svg"
## Au-delà de ce délai sans nouvelle position reçue pour un joueur (déco,
## fenêtre changée, etc.), on masque son curseur plutôt que de le laisser
## figé à l'écran.
const CURSOR_TIMEOUT := 2.0

var _sprites: Dictionary = {}      # peer_id (int) -> Sprite2D
var _last_update_sec: Dictionary = {}  # peer_id (int) -> float (Time.get_ticks_msec/1000)
var _shared_texture: Texture2D


func _ready() -> void:
	# Sous les popups/GlobalUi, au-dessus du plateau : cf board.tscn/UiTheme
	# pour les autres CanvasLayer déjà utilisés dans le projet.
	layer = 90
	_shared_texture = load(CURSOR_TEXTURE_PATH) if ResourceLoader.exists(CURSOR_TEXTURE_PATH) else _build_fallback_texture()


func _process(_delta: float) -> void:
	if _last_update_sec.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	for peer_id in _last_update_sec.keys().duplicate():
		if now - _last_update_sec[peer_id] > CURSOR_TIMEOUT:
			_remove_cursor(peer_id)


## norm_pos : position souris normalisée (0..1 de la taille du viewport de
## l'émetteur), indépendante de la résolution/fenêtre de chacun.
func update_cursor(peer_id: int, norm_pos: Vector2, color: Color) -> void:
	var sprite: Sprite2D = _sprites.get(peer_id)
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.texture = _shared_texture
		sprite.centered = false
		sprite.z_index = 4096
		add_child(sprite)
		_sprites[peer_id] = sprite
	sprite.modulate = color
	sprite.position = norm_pos * get_viewport().get_visible_rect().size
	_last_update_sec[peer_id] = Time.get_ticks_msec() / 1000.0


func _remove_cursor(peer_id: int) -> void:
	if _sprites.has(peer_id):
		_sprites[peer_id].queue_free()
		_sprites.erase(peer_id)
	_last_update_sec.erase(peer_id)


## Appelé par board.gd au retour au menu / à la fermeture de connexion.
func clear_all() -> void:
	for peer_id in _sprites.keys():
		_sprites[peer_id].queue_free()
	_sprites.clear()
	_last_update_sec.clear()


## Repli si cursor.svg est absent/pas encore importé (ResourceLoader.exists
## == false juste après avoir ajouté le fichier, avant réimport par
## l'éditeur) : petit losange plein, toujours visible.
func _build_fallback_texture() -> Texture2D:
	var img := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(20):
		for x in range(20):
			if absf(x - 4) + absf(y - 4) <= 5:
				img.set_pixel(x, y, Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)
