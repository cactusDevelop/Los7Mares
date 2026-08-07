extends Node
## Autoload "CustomCursor" : applique le curseur personnalisé du jeu au
## démarrage (assets/art/ui/cursor.svg).
##
## Le SVG est supporté nativement par l'import Texture2D de Godot 4 (il est
## rasterisé à l'import, cf .import généré à côté du fichier) : pas besoin
## de conversion, contrairement à l'ancien .cur.

const CURSOR_PATH := "res://assets/art/ui/cursor.svg"
## Point exact du visuel qui correspond à la position réelle du clic
## (en pixels, depuis le coin haut-gauche de l'image). A ajuster dans
## l'inspecteur... il n'y a pas d'inspecteur ici (autoload sans scène) :
## modifier la valeur directement si la pointe du curseur ne correspond
## pas visuellement au point de clic une fois le PNG en place.
const CURSOR_HOTSPOT := Vector2(4, 2)


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
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW, CURSOR_HOTSPOT)
