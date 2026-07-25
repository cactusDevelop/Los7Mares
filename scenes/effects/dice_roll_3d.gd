extends Node3D

## Orchestre un lancer de N dés physiques et renvoie les résultats une fois
## que tous les dés sont immobiles.

signal roll_finished(results: Array[String])

@export var dice_scene: PackedScene
@export var spawn_point: Node3D ## Point d'où les dés tombent
@export var dice_count: int = 2

var _dice: Array[RigidBody3D] = []
var _results: Array[String] = []


func roll(count: int = -1) -> void:
	if count < 0:
		count = dice_count

	for dice in _dice:
		dice.queue_free()
	_dice.clear()
	_results.clear()

	for i in range(count):
		var dice: RigidBody3D = dice_scene.instantiate()
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
	roll_finished.connect(func(results): print("RESULTAT DES DES: ", results))
	roll()
