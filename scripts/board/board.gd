extends Node2D

const DEAL_DELAY = 0.35
const DEAL_DURATION = 0.7
const FLIP_DELAY_AFTER_DEAL = 0.6
const FLIP_WAVE_DELAY = 0.12

@export var radius: float = 1340.0
@export var deck_stack_offset: Vector2 = Vector2(0, -2)

@onready var seas_container: Node2D = $Seas
@onready var deck_area: Area2D = $Seas/DeckArea
@onready var deck_marker: Marker2D = $Seas/DeckMarker
@onready var center_piece: Node2D = $CenterPiece

var _sea_tiles: Array = []
var _dealt_count: int = 0
var _total_seas: int = 0
var _has_started: bool = false


func _ready() -> void:
	# On récupère les mers uniquement (on exclut DeckArea et DeckMarker,
	# qui sont aussi enfants de Seas mais ne sont pas des tuiles)
	_sea_tiles = []
	for child in seas_container.get_children():
		if child != deck_area and child != deck_marker:
			_sea_tiles.append(child)

	_total_seas = _sea_tiles.size()

	# Centre du cercle ancré sur CenterPiece, converti dans l'espace local de Seas
	var board_center_local: Vector2 = seas_container.to_local(center_piece.global_position)

	for i in range(_sea_tiles.size()):
		var tile = _sea_tiles[i]
		var angle_degrees = 90.0 + i * (360.0 / _sea_tiles.size())
		var angle_rad = deg_to_rad(angle_degrees)
		var target_pos = board_center_local + radius * Vector2(cos(angle_rad), sin(angle_rad))
		var target_rot = angle_degrees + 90.0

		tile.set_meta("target_position", target_pos)
		tile.set_meta("target_rotation", target_rot)

	var deal_order: Array = _sea_tiles.duplicate()
	deal_order.shuffle()

	for i in range(deal_order.size()):
		var tile = deal_order[i]
		tile.position = deck_marker.position + deck_stack_offset * i
		tile.rotation_degrees = 0.0
		tile.back_sprite.visible = true
		tile.front_sprite.visible = false

	set_meta("deal_order", deal_order)
	deck_area.deck_clicked.connect(_on_deck_clicked)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()


func _on_deck_clicked() -> void:
	if _has_started:
		return
	_has_started = true
	deck_area.get_node("HoverPrompt").hide_prompt()
	_deal_seas(get_meta("deal_order"))


func _deal_seas(deal_order: Array) -> void:
	for i in range(deal_order.size()):
		var tile = deal_order[i]
		var target_pos = tile.get_meta("target_position")
		var target_rot = tile.get_meta("target_rotation")

		var tween = create_tween()
		tween.tween_interval(i * DEAL_DELAY)
		tween.tween_property(tile, "position", target_pos, DEAL_DURATION)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(tile, "rotation_degrees", target_rot, DEAL_DURATION)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_callback(_on_one_card_dealt)


func _on_one_card_dealt() -> void:
	_dealt_count += 1
	if _dealt_count == _total_seas:
		await get_tree().create_timer(FLIP_DELAY_AFTER_DEAL).timeout
		_flip_all_as_wave()


# Retourne les cartes en vague, dans l'ordre horaire (ordre de _sea_tiles,
# puisque leur index correspond déjà à l'angle croissant autour de l'heptagone)
func _flip_all_as_wave() -> void:
	for i in range(_sea_tiles.size()):
		var tile = _sea_tiles[i]
		var t = get_tree().create_timer(i * FLIP_WAVE_DELAY)
		t.timeout.connect(tile.flip_to_front)
