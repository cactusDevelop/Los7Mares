extends Node2D

## Ensemble des gemmes disponibles pour une mer donnée, une par joueur en
## partie (2 à 5, cf title_screen PlayerCountSpinBox), réparties autour du
## même point que le cercle des bateaux de cette mer (cf
## Board.get_sea_marker_position / BOAT_MARKER_RADIUS), avec un rayon de
## répartition plus grand (cf Board.gem_layout_radius).
## GameFlow.layout_positions_for_case forme automatiquement la figure
## correspondant au nombre de joueurs (segment à 2, triangle à 3, carré à 4,
## pentagone à 5 : même fonction que pour les bateaux, cf
## Board._relayout_boats). Chaque gemme est teintée (modulate) de la couleur
## du joueur auquel elle correspond, dans l'ordre de GameFlow.players.
## Posées en même temps que la pile de jetons mer (DealingPhase._drop_gem_piles).
##
## Contrairement aux bateaux (qui se redistribuent en cercle à chaque
## arrivée/départ), les gemmes ne bougent JAMAIS : quand un joueur en prend
## une, take_gem() la cache simplement sur place et laisse un "trou" plutôt
## que de resserrer les autres.

## Nombre max de gemmes pré-créées dans la scène (= nombre max de joueurs).
const MAX_GEMS := 7

@onready var _gems: Array[Sprite2D] = [$Gem0, $Gem1, $Gem2, $Gem3, $Gem4, $Gem5, $Gem6]

var sea_key: String = ""


## À appeler une fois à la création de la pile. p_radius est le rayon de
## répartition (plus grand que BOAT_MARKER_SPREAD des bateaux).
## p_rotation_degrees oriente les sprites vers le centre du plateau, comme
## les jetons et les bateaux. Le nombre de gemmes affichées correspond au
## nombre de joueurs actuellement en partie ; les emplacements en trop
## restent cachés (utile si MAX_GEMS > nombre de joueurs).
func setup(p_sea_key: String, p_texture: Texture2D, p_gem_scale: float, p_radius: float, p_rotation_degrees: float = 0.0) -> void:
	sea_key = p_sea_key
	var count: int = clampi(GameFlow.players.size(), 0, _gems.size())
	var offsets: Array[Vector2] = GameFlow.layout_positions_for_case(count, p_radius, Vector2.ZERO)
	for i in range(_gems.size()):
		var gem := _gems[i]
		if i >= count:
			gem.visible = false
			continue
		gem.texture = p_texture
		gem.scale = Vector2.ONE * p_gem_scale
		gem.rotation_degrees = p_rotation_degrees
		gem.position = offsets[i]
		var player_color: String = GameFlow.players[i].get("color", "")
		gem.modulate = GameFlow.COLOR_VALUES.get(player_color, Color.WHITE)
		gem.visible = true


## Retire (cache) la gemme d'index donné sans toucher aux autres, laissant un
## trou dans la disposition. Retourne false si l'index est invalide ou déjà pris.
func take_gem(index: int) -> bool:
	if index < 0 or index >= _gems.size():
		return false
	var gem: Sprite2D = _gems[index]
	if not gem.visible:
		return false
	gem.visible = false
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
