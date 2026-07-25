extends RigidBody3D

## Un dé physique 3D. Le résultat est déterminé par la simulation physique
## (vitesse/rotation initiales aléatoires), pas par un tirage forcé a posteriori.

signal settled(face_value: int)

## Normale locale de chaque face -> valeur affichée.
## A adapter si l'orientation de ton mesh/texture ne correspond pas.
const FACE_NORMALS := {
	Vector3.UP: 1,
	Vector3.DOWN: 6,
	Vector3.RIGHT: 2,
	Vector3.LEFT: 5,
	Vector3.FORWARD: 3, # -Z
	Vector3.BACK: 4,     # +Z
}

const REST_TIME := 0.35
const LINEAR_SLEEP_THRESHOLD := 0.05
const ANGULAR_SLEEP_THRESHOLD := 0.05

var _settled := false
var _rest_timer := 0.0


func _physics_process(delta: float) -> void:
	if _settled:
		return
	if linear_velocity.length() < LINEAR_SLEEP_THRESHOLD and angular_velocity.length() < ANGULAR_SLEEP_THRESHOLD:
		_rest_timer += delta
		if _rest_timer >= REST_TIME:
			_settled = true
			settled.emit(_get_face_up())
	else:
		_rest_timer = 0.0


## Lance le dé depuis from_position vers target_position avec une rotation aléatoire.
func throw(from_position: Vector3, target_position: Vector3, spin_strength: float = 12.0) -> void:
	global_position = from_position
	rotation = Vector3(randf_range(0, TAU), randf_range(0, TAU), randf_range(0, TAU))
	_settled = false
	_rest_timer = 0.0
	sleeping = false

	var direction: Vector3 = (target_position - from_position).normalized()
	linear_velocity = direction * randf_range(4.0, 6.0)
	angular_velocity = Vector3(
		randf_range(-spin_strength, spin_strength),
		randf_range(-spin_strength, spin_strength),
		randf_range(-spin_strength, spin_strength)
	)


func _get_face_up() -> int:
	var best_value := 1
	var best_dot := -INF
	for local_normal: Vector3 in FACE_NORMALS.keys():
		var world_normal: Vector3 = global_transform.basis * local_normal
		var d := world_normal.dot(Vector3.UP)
		if d > best_dot:
			best_dot = d
			best_value = FACE_NORMALS[local_normal]
	return best_value
