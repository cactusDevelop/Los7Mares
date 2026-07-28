extends Node2D

## Ensemble des gemmes disponibles pour une mer donnée, une par joueur en
## partie (2 à 5, cf title_screen PlayerCountSpinBox), réparties autour du
## même point que le cercle des bateaux de cette mer (cf
## Board.get_sea_marker_position / BOAT_MARKER_RADIUS), avec un rayon de
## répartition plus grand (cf Board.gem_layout_radius).
## _layout_offsets forme un polygone régulier avec toujours un côté à plat
## "en bas" (pas de sommet en bas), puis fait pivoter tout le polygone de
## p_rotation_degrees pour l'orienter selon la position de la mer sur le
## plateau (même angle que celui utilisé pour les jetons mer) : ainsi les
## gemmes ne chevauchent jamais la pile de jetons, quelle que soit la mer.
## Chaque gemme est teintée (shader white_recolor, cf ci-dessous) de la
## couleur du joueur auquel elle correspond, dans l'ordre de GameFlow.players.
## Posées en même temps que la pile de jetons mer (DealingPhase._drop_gem_piles).
##
## Contrairement aux bateaux (qui se redistribuent en cercle à chaque
## arrivée/départ), les gemmes ne bougent JAMAIS : quand un joueur en prend
## une, take_gem() la cache simplement sur place et laisse un "trou" plutôt
## que de resserrer les autres.

## Nombre max de gemmes pré-créées dans la scène (= nombre max de joueurs).
const MAX_GEMS := 7

const RECOLOR_SHADER := preload("res://shaders/white_recolor.gdshader")

@onready var _gems: Array[Sprite2D] = [$Gem0, $Gem1, $Gem2, $Gem3, $Gem4, $Gem5, $Gem6]

## Couches d'épaisseur 3D par gemme (ombres + face avant), construites une
## fois par setup() (cf _ensure_thickness_layers). Un index par gemme, dans
## le même ordre que _gems ; chaque entrée est un Array[Sprite2D] (ombres
## d'abord, face avant en dernier), CHACUNE avec son propre ShaderMaterial
## white_recolor : contrairement aux pions (PionThickness.add_to_sprite, qui
## se contente de copier texture/centered/offset car la couleur du pion
## vient d'un simple modulate hérité par les enfants), la couleur d'une
## gemme vient d'un ShaderMaterial (replace_color) qui, lui, n'est PAS hérité
## par les enfants : chaque couche doit donc avoir son propre matériau,
## remis à jour par _apply_player_color à chaque setup()/refresh().
var _gem_layers: Array = []

var sea_key: String = ""

## Rayon/rotation mémorisés lors de setup(), pour pouvoir recalculer la
## disposition plus tard via refresh() (cf board.gd, appelé à chaque ajout
## de joueur : au moment de la construction initiale du plateau, la liste
## des joueurs n'est pas encore forcément complète en mode "local" normal,
## contrairement au mode debug où elle est pré-remplie avant même de
## charger la scène plateau).
var _radius: float = 0.0
var _rotation_degrees: float = 0.0

## Index des gemmes déjà prises (take_gem), à respecter par setup()/refresh()
## pour ne pas les faire réapparaître au prochain recalcul de disposition
## (cf GameFlow.players_changed -> board._refresh_gem_piles -> refresh()).
var _taken: Dictionary = {}


## Positions d'un polygone régulier à count sommets, rayon spacing, avec un
## côté à plat toujours "en bas" (angle +90°) plutôt qu'un sommet : pour un
## nombre de côtés pair, on décale le premier sommet d'un demi-pas par
## rapport au sommet-en-haut par défaut (sinon un sommet pointerait aussi
## en bas, symétrique de celui du haut) ; pour un nombre impair, le
## sommet-en-haut classique laisse déjà un côté à plat en bas. L'ensemble
## est ensuite pivoté de rotation_degrees pour suivre l'orientation de la
## mer sur le plateau (même logique que la rotation des jetons/bateaux).
func _layout_offsets(count: int, spacing: float, rotation_degrees: float) -> Array[Vector2]:
	var offsets: Array[Vector2] = []
	if count <= 0:
		return offsets
	elif count == 1:
		offsets.append(Vector2.ZERO)
	elif count == 2:
		offsets.append(Vector2(-spacing, 0))
		offsets.append(Vector2(spacing, 0))
	else:
		var start_angle := -PI / 2.0
		if count % 2 == 0:
			start_angle += PI / count
		for i in range(count):
			var angle := start_angle + i * (TAU / count)
			offsets.append(Vector2(cos(angle), sin(angle)) * spacing)

	var rot_rad := deg_to_rad(rotation_degrees)
	for i in range(offsets.size()):
		offsets[i] = offsets[i].rotated(rot_rad)
	return offsets


## Applique la couleur du joueur à TOUTES les couches d'épaisseur 3D de la
## gemme d'indice `index` (ombres + face avant, cf _ensure_thickness_layers),
## chacune ayant son propre ShaderMaterial (partager une seule instance
## entre plusieurs couches/gemmes partagerait aussi leur replace_color).
func _apply_player_color(index: int, player_color: String) -> void:
	var color: Color = GameFlow.COLOR_VALUES.get(player_color, Color.WHITE)
	for layer in _gem_layers[index]:
		var mat: ShaderMaterial = layer.material as ShaderMaterial
		mat.set_shader_parameter("replace_color", color)


## Construit (une seule fois par gemme) les couches d'épaisseur 3D : mêmes
## constantes que les pions capitaine/second (PionThickness, cf
## scripts/common/pion_thickness.gd), mais implémenté ici à la main plutôt
## que via PionThickness.add_to_sprite, qui ne copie pas le "material" du
## sprite d'origine (seulement texture/centered/offset) : sans ça, les
## couches resteraient blanches au lieu de prendre la couleur du joueur.
## `gem` (le sprite d'origine) devient invisible (self_modulate.a = 0), ses
## enfants (ombres puis face avant, dans cet ordre d'ajout) restent seuls
## visibles et suivent automatiquement sa position/rotation/échelle.
func _ensure_thickness_layers(index: int, gem: Sprite2D) -> void:
	if not _gem_layers[index].is_empty():
		return
	if PionThickness.LAYERS <= 0 or PionThickness.THICKNESS_PX <= 0.0:
		return
	gem.self_modulate.a = 0.0

	var scale_x: float = gem.scale.x if absf(gem.scale.x) > 0.0001 else 1.0
	var scale_y: float = gem.scale.y if absf(gem.scale.y) > 0.0001 else 1.0
	var step_screen: Vector2 = UiTheme.DEPTH_DIRECTION * (PionThickness.THICKNESS_PX / float(PionThickness.LAYERS))
	var step_local := Vector2(step_screen.x / scale_x, step_screen.y / scale_y)
	var darken := Color(1, 1, 1).darkened(PionThickness.EDGE_DARKEN)

	var layers: Array = []
	for layer in range(PionThickness.LAYERS, 0, -1):
		var shadow := Sprite2D.new()
		shadow.texture = gem.texture
		shadow.centered = gem.centered
		shadow.offset = gem.offset
		shadow.position = step_local * layer
		shadow.modulate = darken
		var shadow_mat := ShaderMaterial.new()
		shadow_mat.shader = RECOLOR_SHADER
		shadow.material = shadow_mat
		gem.add_child(shadow)
		layers.append(shadow)

	var front := Sprite2D.new()
	front.texture = gem.texture
	front.centered = gem.centered
	front.offset = gem.offset
	var front_mat := ShaderMaterial.new()
	front_mat.shader = RECOLOR_SHADER
	front.material = front_mat
	gem.add_child(front)
	layers.append(front)

	_gem_layers[index] = layers


## À appeler une fois à la création de la pile. p_radius est le rayon de
## répartition (plus grand que BOAT_MARKER_SPREAD des bateaux).
## p_rotation_degrees oriente à la fois chaque sprite et l'ensemble du
## polygone vers le centre du plateau, comme les jetons et les bateaux. Le
## nombre de gemmes affichées correspond au nombre de joueurs actuellement
## en partie ; les emplacements en trop restent cachés (utile si MAX_GEMS >
## nombre de joueurs).
func setup(p_sea_key: String, p_texture: Texture2D, p_gem_scale: float, p_radius: float, p_rotation_degrees: float = 0.0) -> void:
	sea_key = p_sea_key
	_radius = p_radius
	_rotation_degrees = p_rotation_degrees
	var count: int = clampi(GameFlow.players.size(), 0, _gems.size())
	var offsets: Array[Vector2] = _layout_offsets(count, p_radius, p_rotation_degrees)
	for i in range(_gems.size()):
		var gem := _gems[i]
		if i >= count:
			gem.visible = false
			continue
		gem.texture = p_texture
		gem.scale = Vector2.ONE * p_gem_scale
		gem.rotation_degrees = p_rotation_degrees
		gem.position = offsets[i]
		_apply_player_color(gem, GameFlow.players[i].get("color", ""))
		gem.visible = not _taken.has(i)


## Recalcule le nombre de gemmes visibles, leur disposition et leur couleur
## à partir de GameFlow.players actuel, sans re-préciser texture/échelle
## (déjà posées par setup()). À appeler quand la liste des joueurs change
## après la construction initiale du plateau (cf board.gd,
## GameFlow.players_changed).
func refresh() -> void:
	var count: int = clampi(GameFlow.players.size(), 0, _gems.size())
	var offsets: Array[Vector2] = _layout_offsets(count, _radius, _rotation_degrees)
	for i in range(_gems.size()):
		var gem := _gems[i]
		if i >= count:
			gem.visible = false
			continue
		gem.position = offsets[i]
		_apply_player_color(gem, GameFlow.players[i].get("color", ""))
		gem.visible = not _taken.has(i)


## Retire (cache) la gemme d'index donné sans toucher aux autres, laissant un
## trou dans la disposition. Retourne false si l'index est invalide ou déjà pris.
func take_gem(index: int) -> bool:
	if index < 0 or index >= _gems.size():
		return false
	var gem: Sprite2D = _gems[index]
	if not gem.visible:
		return false
	gem.visible = false
	_taken[index] = true
	return true


## Prend la première gemme encore disponible (ordre fixe). Retourne son index,
## ou -1 si la pile est épuisée.
func take_next_gem() -> int:
	for i in range(_gems.size()):
		if _gems[i].visible:
			take_gem(i)
			return i
	return -1


## Indices des gemmes déjà prises (pour la sauvegarde/restauration).
func get_taken_indices() -> Array:
	var taken: Array = []
	for i in range(_gems.size()):
		if not _gems[i].visible:
			taken.append(i)
	return taken


## Réapplique un ensemble d'indices pris (restauration depuis une sauvegarde),
## sans passer par take_gem un par un.
func restore_taken_indices(taken: Array) -> void:
	for i in taken:
		if i >= 0 and i < _gems.size():
			_gems[i].visible = false
			_taken[i] = true
