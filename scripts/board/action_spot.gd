extends Node2D

signal spot_clicked(spot: Node2D)

const IDLE_AMPLITUDE := 4.0
const IDLE_SPEED := 1.2
const HOVER_SCALE := 1.12
const HOVER_DURATION := 0.15
const PIECE_DROP_HEIGHT := 220.0
const PIECE_DROP_DURATION := 0.35

@onready var case_sprite: Sprite2D = $CaseSprite
@onready var click_area: Area2D = $ClickArea

var _base_position: Vector2
var _idle_time_offset: float = 0.0
var _hover_tween: Tween
var _is_hovering: bool = false
var hover_enabled: bool = false
var _pieces: Array = []  # {color, rank, order, node}


func _ready() -> void:
	_base_position = case_sprite.position
	_idle_time_offset = randf() * TAU
	click_area.mouse_entered.connect(_on_mouse_entered)
	click_area.mouse_exited.connect(_on_mouse_exited)
	click_area.input_event.connect(_on_input_event)


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0 + _idle_time_offset
	case_sprite.position = _base_position + Vector2(0, sin(t * IDLE_SPEED) * IDLE_AMPLITUDE)


func _on_mouse_entered() -> void:
	if not hover_enabled:
		return
	_is_hovering = true
	_tween_scale(HOVER_SCALE)
	_update_case_color()


func _on_mouse_exited() -> void:
	if not hover_enabled:
		return
	_is_hovering = false
	_tween_scale(1.0)
	_update_case_color()


func _tween_scale(target: float) -> void:
	if _hover_tween:
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_property(case_sprite, "scale", Vector2.ONE * target, HOVER_DURATION)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		spot_clicked.emit(self)


func add_piece(piece_node: Node2D, color: String, rank: int) -> void:
	var order := _pieces.size()
	_pieces.append({"color": color, "rank": rank, "order": order, "node": piece_node})
	add_child(piece_node)
	_relayout_pieces()
	_update_case_color()
	_animate_piece_drop(piece_node)


func _animate_piece_drop(piece_node: Node2D) -> void:
	var target_position := piece_node.position
	piece_node.position = target_position - Vector2(0, PIECE_DROP_HEIGHT)
	piece_node.modulate.a = 0.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(piece_node, "position", target_position, PIECE_DROP_DURATION)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(piece_node, "modulate:a", 1.0, PIECE_DROP_DURATION * 0.7)


func _relayout_pieces() -> void:
	var positions := GameFlow.layout_positions_for_case(_pieces.size())
	for i in range(_pieces.size()):
		_pieces[i]["node"].position = positions[i]

	# Les pièces plus en avant du polygone doivent s'afficher devant celles plus
	# en arrière, peu importe l'ordre d'ajout. On classe les indices par y croissant
	# (arrière -> avant) et on attribue un z_index toujours >= 1, pour rester
	# devant le sprite de la case (z_index 0).
	var order := range(_pieces.size())
	order.sort_custom(func(a, b): return positions[a].y < positions[b].y)
	for rank in range(order.size()):
		_pieces[order[rank]]["node"].z_index = rank + 1


func _update_case_color() -> void:
	var color := GameFlow.compute_case_color(_pieces)
	var base := color if color.a > 0.0 else Color.WHITE
	case_sprite.modulate = base * GameFlow.HOVER_TINT if _is_hovering else base


func has_player_piece(color: String) -> bool:
	for p in _pieces:
		if p["color"] == color:
			return true
	return false


func set_hover_enabled(enabled: bool) -> void:
	hover_enabled = enabled
	if not enabled:
		_is_hovering = false
		_tween_scale(1.0)
		_update_case_color()
