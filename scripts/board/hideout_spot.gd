extends Node2D

## Emplacement de cachette autour du plateau central. Modelé sur action_spot.gd
## mais simplifié : un seul joueur peut prendre l'emplacement (pas d'empilement
## de pièces), et le retour visuel au survol utilise le contour (HoverOutline)
## plutôt qu'une teinte de case.

signal spot_clicked(spot: Node2D)

const CACHETTE_TEXTURE_PATH := "res://assets/art/board/cachette-%s.png"

## Animation "tombé du ciel" du bateau à la sélection de la cachette (fondu +
## chute), identique dans son principe à celle des pièces (action_spot.gd)
## et des piles de cartes (board.gd).
const BOAT_DROP_HEIGHT := 220.0
const BOAT_DROP_DURATION := 0.35

## Effet 3D (épaisseur) du bateau : mêmes constantes de style que les jetons
## de player_board_expanded.gd (couches assombries décalées). x5 par rapport
## aux jetons pour rester visible sur un sprite de bateau plus grand.
const BOAT_THICKNESS_PX := 30.0
const BOAT_THICKNESS_LAYERS := 3
const BOAT_EDGE_DARKEN := 0.45

@onready var case_sprite: Sprite2D = $CaseSprite
@onready var boat_sprite: Sprite2D = $BoatSprite
@onready var click_area: Area2D = $ClickArea
@onready var hover_prompt: Node2D = $HoverPrompt

var hover_enabled: bool = false
var is_taken: bool = false
var owner_color: String = ""


func _ready() -> void:
	boat_sprite.visible = false
	click_area.mouse_entered.connect(_on_mouse_entered)
	click_area.mouse_exited.connect(_on_mouse_exited)
	click_area.input_event.connect(_on_input_event)


func _on_mouse_entered() -> void:
	if hover_enabled and not is_taken:
		hover_prompt.show_prompt()


func _on_mouse_exited() -> void:
	hover_prompt.hide_prompt()


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not hover_enabled or is_taken:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		spot_clicked.emit(self)


## Attribue définitivement cet emplacement à un joueur : affiche sa cachette
## colorée et désactive le survol/clic.
func claim(color: String) -> void:
	is_taken = true
	owner_color = color
	case_sprite.texture = load(CACHETTE_TEXTURE_PATH % color)
	case_sprite.modulate = Color(1, 1, 1, 1)
	_show_boat(color)
	set_hover_enabled(false)


## Fait apparaître le bateau du joueur avec le même effet "tombé du ciel"
## (fondu + chute) que le reste du jeu, et lui donne une épaisseur 3D.
## Chaque cachette a sa propre rotation (pour pointer vers l'extérieur du
## plateau, cf board.gd), mais le bateau doit toujours rester À L'ENDROIT à
## l'écran : on annule donc la rotation héritée du parent en fixant la
## rotation locale du bateau à l'opposé de la rotation globale de la
## cachette. Cette annulation est indépendante de la valeur de cette
## rotation : elle continuera de fonctionner si les cachettes changent
## d'orientation, et surtout le jour où le bateau ne sera plus un enfant de
## HideoutSpot (une fois qu'il pourra se déplacer sur le plateau) puisque le
## calcul ne dépend que de la rotation globale au moment de l'appel.
## L'épaisseur (UiTheme.DEPTH_DIRECTION) reste calculée en repère global
## puis reconvertie en repère local du bateau, donc l'axe de perspective
## reste parallèle à l'écran pour tous les bateaux quelle que soit leur
## orientation ou celle de leur parent.
func _show_boat(color: String) -> void:
	var base_color: Color = GameFlow.COLOR_VALUES[color]
	boat_sprite.rotation = -global_rotation
	boat_sprite.modulate = base_color
	boat_sprite.visible = true

	# Les offsets (épaisseur, chute) sont ajoutés à boat_sprite.position, qui
	# est dans le repère LOCAL de la cachette (self) : c'est donc la rotation
	# de self (la cachette) qu'il faut annuler pour rester droit à l'écran,
	# pas celle du bateau (qu'on vient déjà d'annuler ci-dessus à part).
	var depth_local: Vector2 = UiTheme.DEPTH_DIRECTION.rotated(-global_rotation)
	var step: Vector2 = depth_local * (BOAT_THICKNESS_PX / float(BOAT_THICKNESS_LAYERS))
	var boat_target_pos: Vector2 = boat_sprite.position

	# Couches assombries formant l'épaisseur, sous le bateau (z_index inférieur).
	var shadow_layers: Array = []
	for layer in range(BOAT_THICKNESS_LAYERS, 0, -1):
		var shadow := Sprite2D.new()
		shadow.texture = boat_sprite.texture
		shadow.centered = boat_sprite.centered
		shadow.offset = boat_sprite.offset
		shadow.scale = boat_sprite.scale
		shadow.rotation = boat_sprite.rotation
		shadow.z_index = boat_sprite.z_index - 1
		shadow.modulate = base_color.darkened(BOAT_EDGE_DARKEN)
		add_child(shadow)
		shadow_layers.append({"node": shadow, "target": boat_target_pos + step * layer})

	# Départ : tout le monde en l'air et transparent. Le décalage doit être
	# vertical à L'ÉCRAN (comme pour la pile de cartes), pas dans le repère
	# local de la cachette : on part donc du "haut" global (0,-1) qu'on
	# reconvertit en repère local via la rotation de self, comme pour
	# l'épaisseur ci-dessus, sinon la chute apparaît en diagonale sur les
	# cachettes tournées.
	var screen_up_local: Vector2 = Vector2(0, -1).rotated(-global_rotation)
	var start_offset := screen_up_local * BOAT_DROP_HEIGHT
	boat_sprite.modulate.a = 0.0
	boat_sprite.position = boat_target_pos + start_offset
	for entry in shadow_layers:
		entry["node"].modulate.a = 0.0
		entry["node"].position = entry["target"] + start_offset

	var duration: float = Settings.anim_duration(BOAT_DROP_DURATION)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(boat_sprite, "position", boat_target_pos, duration)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(boat_sprite, "modulate:a", 1.0, duration * 0.7)
	for entry in shadow_layers:
		tween.tween_property(entry["node"], "position", entry["target"], duration)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(entry["node"], "modulate:a", 1.0, duration * 0.7)


func set_hover_enabled(enabled: bool) -> void:
	hover_enabled = enabled
	if not enabled:
		hover_prompt.hide_prompt()


## Change la couleur du contour affiché au survol (ex : couleur du joueur
## dont c'est le tour). Blanc par défaut tant que rien n'est précisé.
func set_outline_color(color: Color) -> void:
	hover_prompt.outline_color = color
