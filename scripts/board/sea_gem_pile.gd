extends Node2D

## Ensemble des 7 gemmes disponibles pour une mer donnée, réparties en
## heptagone autour du même point que le cercle des bateaux de cette mer,
## avec un rayon de répartition plus grand. Posées en même temps que la
## pile de jetons mer (DealingPhase._drop_gem_piles).
##
## Contrairement aux bateaux, les gemmes ne bougent jamais : take_gem() en
## cache une sur place et laisse un "trou" dans l'heptagone.

const GEM_COUNT := 7

@onready var _gems: Array[Sprite2D] = [$Gem0, $Gem1, $Gem2, $Gem3, $Gem4, $Gem5, $Gem6]

var sea_key: String = ""


func setup(p_sea_key: String, p_texture: Texture2D, p_gem_scale: float, p_radius: float, p_rotation_degrees: float = 0.0) -> void:
	sea_key = p_sea_key
	var offsets: Array[Vector2] = GameFlow.layout_positions_for_case(GEM_COUNT, p_radius, Vector2.ZERO)
	for i in range(GEM_COUNT):
		var gem := _gems[i]
		gem.texture = p_texture
		gem.scale = Vector2.ONE * p_gem_scale
		gem.rotation_degrees = p_rotation_degrees
		gem.position = offsets[i]
		gem.visible = true


func take_gem(index: int) -> bool:
	if index < 0 or index >= _gems.size():
		return false
	var gem: Sprite2D = _gems[index]
	if not gem.visible:
		return false
	gem.visible = false
	return true


func take_next_gem() -> int:
	for i in range(_gems.size()):
		if _gems[i].visible:
			take_gem(i)
			return i
	return -1


func get_taken_indices() -> Array:
	var taken: Array = []
	for i in range(_gems.size()):
		if not _gems[i].visible:
			taken.append(i)
	return taken


func restore_taken_indices(taken: Array) -> void:
	for i in taken:
		if i >= 0 and i < _gems.size():
			_gems[i].visible = false
