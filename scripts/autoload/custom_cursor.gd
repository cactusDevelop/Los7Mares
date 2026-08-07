extends Node
## Autoload "CustomCursor" : applique le curseur personnalisé du jeu au
## démarrage (assets/art/ui/cursor.svg).
##
## Le SVG est supporté nativement par l'import Texture2D de Godot 4 (il est
## rasterisé à l'import, cf .import généré à côté du fichier) : pas besoin
## de conversion, contrairement à l'ancien .cur.

const CURSOR_PATH := "res://assets/art/ui/cursor.svg"
## Point exact du visuel qui correspond à la position réelle du clic (en
## pixels, mesuré par l'utilisateur sur le SVG à sa taille d'import
## d'origine, AVANT le redimensionnement ci-dessous — CURSOR_SCALE est
## appliqué aux deux pour rester cohérent).
const CURSOR_HOTSPOT := Vector2(20, 25)
## Le SVG importé fait 2x la taille voulue à l'écran : on le redimensionne
## nous-mêmes au chargement (Input.set_custom_mouse_cursor n'a pas de
## paramètre d'échelle, il affiche la texture à sa résolution native).
const CURSOR_SCALE := 0.5


func _ready() -> void:
	_apply_cursor()


func _apply_cursor() -> void:
	if not ResourceLoader.exists(CURSOR_PATH):
		push_warning("CustomCursor: '%s' introuvable ou non importable (voir commentaire en tête de fichier) — curseur système conservé." % CURSOR_PATH)
		return
	var tex: Texture2D = load(CURSOR_PATH)
	if tex == null:
		push_warning("CustomCursor: '%s' n'a pas pu être chargé comme Texture2D — curseur système conservé." % CURSOR_PATH)
		return
	var img: Image = tex.get_image()
	if img == null:
		push_warning("CustomCursor: image source introuvable pour '%s' — curseur système conservé." % CURSOR_PATH)
		return
	if img.is_compressed():
		img.decompress()
	var target_size := (Vector2(img.get_size()) * CURSOR_SCALE).round()
	img.resize(int(target_size.x), int(target_size.y), Image.INTERPOLATE_LANCZOS)
	var scaled_tex := ImageTexture.create_from_image(img)
	Input.set_custom_mouse_cursor(scaled_tex, Input.CURSOR_ARROW, CURSOR_HOTSPOT * CURSOR_SCALE)
