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
## Le SVG source est dessiné en noir et 2x trop grand à l'écran (cf
## custom_cursor.gd, même constantes) : on applique la même réduction ici
## pour que le curseur distant ait la même taille que le curseur local.
const CURSOR_SCALE := 0.5
const CURSOR_HOTSPOT := Vector2(20, 25)

var _sprites: Dictionary = {}      # peer_id (int) -> Sprite2D
var _last_update_sec: Dictionary = {}  # peer_id (int) -> float (Time.get_ticks_msec/1000)
## Image de base (redimensionnée, encore noire) utilisée pour générer une
## variante colorée par joueur à la demande, cf _get_colored_texture.
var _base_image: Image
## Cache "#rrggbb" -> Texture2D déjà recolorée, pour ne recolorer chaque
## couleur (5 au maximum, cf GameFlow.COLOR_VALUES) qu'une seule fois.
var _colored_texture_cache: Dictionary = {}


func _ready() -> void:
	# Sous les popups/GlobalUi, au-dessus du plateau : cf board.tscn/UiTheme
	# pour les autres CanvasLayer déjà utilisés dans le projet.
	layer = 90
	_base_image = _load_base_image()


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
		sprite.centered = false
		sprite.z_index = 4096
		add_child(sprite)
		_sprites[peer_id] = sprite
	sprite.texture = _get_colored_texture(color)
	# La texture est déjà à la bonne taille (CURSOR_SCALE appliqué dans
	# _load_base_image) : on ne fait qu'aligner la pointe (CURSOR_HOTSPOT,
	## déjà mise à l'échelle) sur la position réelle du curseur distant.
	sprite.position = norm_pos * get_viewport().get_visible_rect().size - CURSOR_HOTSPOT * CURSOR_SCALE
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


func _load_base_image() -> Image:
	if not ResourceLoader.exists(CURSOR_TEXTURE_PATH):
		return _build_fallback_image()
	var tex: Texture2D = load(CURSOR_TEXTURE_PATH)
	var img: Image = tex.get_image() if tex else null
	if img == null:
		return _build_fallback_image()
	if img.is_compressed():
		img.decompress()
	var target_size := (Vector2(img.get_size()) * CURSOR_SCALE).round()
	img.resize(int(target_size.x), int(target_size.y), Image.INTERPOLATE_LANCZOS)
	return img


## Le SVG source est dessiné en noir opaque : un simple `modulate` (produit
## multiplicatif) sur un Sprite2D ne peut jamais l'éclaircir vers la
## couleur du joueur (noir * n'importe quelle couleur = toujours noir).
## On remplace donc réellement le RGB de chaque pixel non-transparent par
## la couleur du joueur, en gardant l'alpha d'origine (anticrénelage des
## bords du SVG rasterisé préservé). Fait une seule fois par couleur
## (5 couleurs max, cf GameFlow.COLOR_VALUES), puis mis en cache : coût
## négligeable même sur Raspberry Pi.
func _get_colored_texture(color: Color) -> Texture2D:
	var key := color.to_html(false)
	if _colored_texture_cache.has(key):
		return _colored_texture_cache[key]
	var img: Image = _base_image.duplicate()
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var px := img.get_pixel(x, y)
			if px.a > 0.01:
				img.set_pixel(x, y, Color(color.r, color.g, color.b, px.a))
	var tex := ImageTexture.create_from_image(img)
	_colored_texture_cache[key] = tex
	return tex


## Repli si cursor.svg est absent/pas encore importé (ResourceLoader.exists
## == false juste après avoir ajouté le fichier, avant réimport par
## l'éditeur) : petit losange plein, toujours visible, recolorable comme
## le reste (entièrement opaque -> _get_colored_texture le teinte en
## totalité).
func _build_fallback_image() -> Image:
	var img := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(20):
		for x in range(20):
			if absf(x - 4) + absf(y - 4) <= 5:
				img.set_pixel(x, y, Color(1, 1, 1, 1))
	return img
