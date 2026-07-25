extends Node3D

## Orchestre un lancer de N dés physiques (tous du même type, via roll()) ou
## d'un mélange de types de dés (via roll_mixed(), ex: 1 dé noir de combat +
## 1 dé blanc d'exploration, cf GAME_RULES.txt section 5 étape 7) et renvoie
## les résultats une fois que tous les dés sont immobiles.

signal roll_finished(results: Array[String])

@export var dice_scene: PackedScene
@export var spawn_point: Node3D ## Point d'où les dés tombent
@export var dice_count: int = 2
## Si true, lance automatiquement dice_count dés de dice_scene au chargement
## de la scène (utile pour tester la scène seule dans l'éditeur). À laisser
## à false quand la scène est pilotée par du code de jeu (cf
## first_player_dice_phase.gd), sans quoi un lancer parasite se déclenche
## dès que le plateau charge.
@export var auto_roll_on_ready: bool = false

var _dice: Array[RigidBody3D] = []
var _results: Array[String] = []


## Lance count dés, tous instanciés depuis dice_scene (comportement d'origine).
func roll(count: int = -1) -> void:
	if count < 0:
		count = dice_count
	var scenes: Array[PackedScene] = []
	for i in range(count):
		scenes.append(dice_scene)
	_roll_scenes(scenes)


## Lance un dé par entrée de scenes, dans l'ordre donné (types mélangés
## possibles, ex: [dice_3d_noir, dice_white_3d]).
func roll_mixed(scenes: Array[PackedScene]) -> void:
	_roll_scenes(scenes)


func _roll_scenes(scenes: Array[PackedScene]) -> void:
	for dice in _dice:
		dice.queue_free()
	_dice.clear()
	_results.clear()

	for scene in scenes:
		var dice: RigidBody3D = scene.instantiate()
		add_child(dice)
		_dice.append(dice)
		dice.settled.connect(_on_dice_settled)

		var offset := Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3))
		var from_pos: Vector3 = spawn_point.global_position + offset
		var target_pos: Vector3 = from_pos + Vector3(randf_range(-0.2, 0.2), -3.0, 0.6)
		dice.throw(from_pos, target_pos)


func _on_dice_settled(face_result: String) -> void:
	_results.append(face_result)
	if _results.size() == _dice.size():
		roll_finished.emit(_results)


func _ready() -> void:
	if auto_roll_on_ready:
		roll_finished.connect(func(results): print("RESULTAT DES DES: ", results))
		roll()
