extends Node2D

const DEAL_DELAY = 0.15
const FLIP_DELAY_AFTER_DEAL = 0.5

@onready var seas_container: Node2D = $Seas

var _dealt_count: int = 0
var _total_seas: int = 0


func _ready() -> void:
	var sea_tiles: Array = seas_container.get_children()
	_total_seas = sea_tiles.size()

	for i in range(sea_tiles.size()):
		var tile = sea_tiles[i]
		var angle_degrees = -90 + i * (360.0 / sea_tiles.size())
		tile.rotation_degrees = angle_degrees + 90  # ajuste ce +90 si l'orientation ne colle pas, teste

		var target_pos = tile.position
		tile.set_meta("target_position", target_pos)
		tile.position = Vector2.ZERO

	for i in range(sea_tiles.size()):
		var tile = sea_tiles[i]
		var target_pos = tile.get_meta("target_position")

		var tween = create_tween()
		tween.tween_interval(i * DEAL_DELAY)
		tween.tween_property(tile, "position", target_pos, 0.4)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_callback(_on_one_card_dealt)


func _on_one_card_dealt() -> void:
	_dealt_count += 1
	if _dealt_count == _total_seas:
		await get_tree().create_timer(FLIP_DELAY_AFTER_DEAL).timeout
		for tile in seas_container.get_children():
			tile.flip_to_front()
