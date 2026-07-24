extends Node2D

signal spot_clicked(spot: Node2D)

const IDLE_SCALE_AMPLITUDE := 0.04  # la case grossit jusqu'à +4%, jamais en dessous de sa taille de base
const IDLE_SPEED := 1.2
const HOVER_SCALE := 1.12
const HOVER_DURATION := 0.15
const PION_DROP_HEIGHT := 220.0
const PION_DROP_DURATION := 0.35

@onready var case_sprite: Sprite2D = $CaseSprite
@onready var click_area: Area2D = $ClickArea

var _idle_time_offset: float = 0.0
var _hover_tween: Tween
var _hover_scale_factor: float = 1.0  # multiplicateur animé séparément par le tween de survol
var _is_hovering: bool = false
var hover_enabled: bool = false
var _pions: Array = []  # {color, rank, order, node}
var _drop_tweens: Dictionary = {}  # pion_node -> Tween de chute en cours
var _drag_hover_color = null  # Color ou null : couleur du joueur qui drague, appliquée au survol par-dessus le zoom habituel


func _ready() -> void:
	_idle_time_offset = randf() * TAU
	click_area.mouse_entered.connect(_on_mouse_entered)
	click_area.mouse_exited.connect(_on_mouse_exited)
	click_area.input_event.connect(_on_input_event)


func _process(_delta: float) -> void:
	# Respiration = grossissement, jamais de déplacement ni de rétrécissement
	# sous la taille de base : on ne veut jamais découvrir ce qu'il y a derrière la case.
	var t := Time.get_ticks_msec() / 1000.0 + _idle_time_offset
	var idle_factor := 1.0 + (sin(t * IDLE_SPEED) * 0.5 + 0.5) * IDLE_SCALE_AMPLITUDE
	case_sprite.scale = Vector2.ONE * idle_factor * _hover_scale_factor


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
	_hover_tween.tween_property(self, "_hover_scale_factor", target, HOVER_DURATION)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		spot_clicked.emit(self)


func _animate_pion_drop(pion_node: Node2D) -> void:
	var target_position := pion_node.position
	pion_node.position = target_position - Vector2(0, PION_DROP_HEIGHT)
	pion_node.modulate.a = 0.0
	var duration: float = Settings.anim_duration(PION_DROP_DURATION)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(pion_node, "position", target_position, duration)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(pion_node, "modulate:a", 1.0, duration * 0.7)
	_drop_tweens[pion_node] = tween
	tween.finished.connect(func():
		if _drop_tweens.get(pion_node) == tween:
			_drop_tweens.erase(pion_node)
	)


func _relayout_pions() -> void:
	var positions: Array[Vector2] = GameFlow.layout_positions_for_case(_pions.size())
	for i in range(_pions.size()):
		var node: Node2D = _pions[i]["node"]
		# Si cette pièce est encore en train de "tomber" (spam-clic rapide sur
		# la case), on tue son tween avant de la replacer : sinon le tween,
		# toujours actif, continue d'écrire une position obsolète par-dessus
		# celle qu'on vient de recalculer, et la pièce finit décalée.
		if _drop_tweens.has(node) and _drop_tweens[node]:
			_drop_tweens[node].kill()
			_drop_tweens.erase(node)
			node.modulate.a = 1.0
		node.position = positions[i]

	# Les pièces plus en avant du polygone doivent s'afficher devant celles plus
	# en arrière, peu importe l'ordre d'ajout. On classe les indices par y croissant
	# (arrière -> avant) et on attribue un z_index toujours >= 1, pour rester
	# devant le sprite de la case (z_index 0).
	var order := range(_pions.size())
	order.sort_custom(func(a, b): return positions[a].y < positions[b].y)
	for rank in range(order.size()):
		_pions[order[rank]]["node"].z_index = rank + 1


func _update_case_color() -> void:
	var color: Color = GameFlow.compute_case_color(_pions)
	var base := color if color.a > 0.0 else Color.WHITE
	if _is_hovering and _drag_hover_color != null:
		case_sprite.modulate = _drag_hover_color
	else:
		case_sprite.modulate = base * UiTheme.HOVER_TINT if _is_hovering else base


## Teinte appliquée au survol PAR-DESSUS l'effet de zoom habituel pendant
## qu'un joueur drague une pièce depuis le panneau de sélection (couleur du
## joueur en train de jouer, pour bien montrer où la pièce va atterrir).
## Passer null pour revenir à la teinte de survol par défaut.
func set_drag_hover_color(color) -> void:
	_drag_hover_color = color
	_update_case_color()


## Vrai si la souris est actuellement au-dessus de la collision de la case
## (utilisé par pion_placement_phase.gd pour savoir où lâcher une pièce
## en drag & drop, en plus de l'effet de zoom au survol).
func is_hovering() -> bool:
	return _is_hovering


func has_player_pion(color: String) -> bool:
	for p in _pions:
		if p["color"] == color:
			return true
	return false


func set_hover_enabled(enabled: bool) -> void:
	hover_enabled = enabled
	if not enabled:
		_is_hovering = false
		_tween_scale(1.0)
		_update_case_color()


func add_pion(pion_node: Node2D, color: String, rank: int, animate: bool = true) -> void:
	var order := _pions.size()
	_pions.append({"color": color, "rank": rank, "order": order, "node": pion_node})
	add_child(pion_node)
	_relayout_pions()
	_update_case_color()
	if animate:
		_animate_pion_drop(pion_node)


func get_pions_snapshot() -> Array:
	var out := []
	for p in _pions:
		out.append({"color": p["color"], "rank": p["rank"]})
	return out


## Retire toutes les pièces de la case (début d'un nouveau tour de jeu).
func clear_pions() -> void:
	for p in _pions:
		p["node"].queue_free()
	_pions.clear()
	_update_case_color()
