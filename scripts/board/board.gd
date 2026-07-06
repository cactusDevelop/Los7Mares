extends Node2D

const SEA_COUNT = 7
const RADIUS = 400.0          # distance du centre à chaque mer — à ajuster visuellement
const DEAL_DELAY = 0.15       # délai entre chaque carte distribuée
const FLIP_DELAY_AFTER_DEAL = 0.5

var sea_tile_scene: PackedScene = preload("res://scenes/board/sea_tile.tscn")

var sea_front_textures: Array[Texture2D] = [
	preload("res://assets/art/board/mer-d-abondance.png"),
	preload("res://assets/art/board/mer-d-azur.png"),
	preload("res://assets/art/board/mer-de-feu.png"),
	preload("res://assets/art/board/mer-de-glace.png"),
	preload("res://assets/art/board/mer-de-jade.png"),
	preload("res://assets/art/board/mer-maudite.png"),
	preload("res://assets/art/board/mer-sauvage.png"),
]
var sea_back_texture: Texture2D = preload("res://assets/art/board/dos-de-mer.png")

var sea_tiles: Array = []
var _dealt_count: int = 0


func _ready() -> void:
	_deal_seas()


func _deal_seas() -> void:
	var shuffled_textures = sea_front_textures.duplicate()
	shuffled_textures.shuffle()

	for i in range(SEA_COUNT):
		var tile = sea_tile_scene.instantiate()
		add_child(tile)
		tile.setup(shuffled_textures[i], sea_back_texture)

		# La carte part du centre (comme une pioche) vers sa position finale
		tile.position = Vector2.ZERO
		tile.rotation = _get_sea_rotation(i)

		sea_tiles.append(tile)

		var target_pos = _get_sea_position(i)
		var tween = create_tween()
		tween.tween_interval(i * DEAL_DELAY)
		tween.tween_property(tile, "position", target_pos, 0.4)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_callback(_on_one_card_dealt)


func _get_sea_position(index: int) -> Vector2:
	var angle = deg_to_rad(-90 + index * (360.0 / SEA_COUNT))
	return Vector2(cos(angle), sin(angle)) * RADIUS


func _get_sea_rotation(index: int) -> float:
	# Oriente chaque mer pour qu'elle "pointe" vers l'extérieur de l'heptagone
	# À ajuster selon le rendu visuel réel de tes hexagones
	return deg_to_rad(-90 + index * (360.0 / SEA_COUNT)) + PI / 2.0


func _on_one_card_dealt() -> void:
	_dealt_count += 1
	if _dealt_count == SEA_COUNT:
		await get_tree().create_timer(FLIP_DELAY_AFTER_DEAL).timeout
		for tile in sea_tiles:
			tile.flip_to_front()
