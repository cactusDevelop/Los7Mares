extends RigidBody3D

## Un dé physique 3D (dé blanc). Le résultat est déterminé par la simulation
## physique (vitesse/rotation initiales aléatoires), pas par un tirage forcé.

signal settled(face_result: String)

## Normale locale de chaque face -> symbole affiché.
## Dé blanc : 1 face "double", 4 faces "un", 1 face "vide".
const FACE_RESULTS := {
	Vector3.UP: "double",
	Vector3.DOWN: "un",
	Vector3.RIGHT: "un",
	Vector3.LEFT: "un",
	Vector3.FORWARD: "un", # -Z
	Vector3.BACK: "vide",  # +Z
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


func _get_face_up() -> String:
	var best_result := "vide"
	var best_dot := -INF
	for local_normal: Vector3 in FACE_RESULTS.keys():
		var world_normal: Vector3 = global_transform.basis * local_normal
		var d := world_normal.dot(Vector3.UP)
		if d > best_dot:
			best_dot = d
			best_result = FACE_RESULTS[local_normal]
	return best_result
