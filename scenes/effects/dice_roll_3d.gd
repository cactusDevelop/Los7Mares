extends Node3D

## Orchestre un lancer de N dés physiques (tous du même type, via roll()) ou
## d'un mélange de types de dés (via roll_mixed(), ex: 1 dé noir de combat +
## 1 dé blanc d'exploration, cf DEV_RULES_REFERENCE.txt section 5 étape 7) et renvoie
## les résultats une fois que tous les dés sont immobiles.
##
## Réseau : la simulation physique (RigidBody3D) n'est PAS déterministe d'une
## machine à l'autre (cf dice_3d.gd), donc seul l'hôte fait réellement rouler
## les dés via roll()/roll_mixed() ; pendant ce lancer, la transform de
## chaque dé est enregistrée à chaque frame physique (cf _record_frame).
## board.gd (roll_dice_synced) diffuse ensuite cet enregistrement aux
## clients, qui le rejouent à l'identique via play_recorded() : mêmes dés,
## même trajectoire, même résultat visible partout, sans re-simuler quoi que
## ce soit localement.

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
var _settled_count: int = 0

## Trajectoire enregistrée du dernier lancer réel (_frames[i] = Array de
## Transform3D du dé d'indice i, un élément par frame physique), lisible via
## get_last_recorded_frames() une fois roll_finished émis. Jamais rempli par
## play_recorded() (qui rejoue une trajectoire déjà enregistrée ailleurs).
var _frames: Array = []
var _recording: bool = false


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
	_recording = false
	for dice in _dice:
		dice.queue_free()
	_dice.clear()
	_results.clear()
	_results.resize(scenes.size())
	_settled_count = 0
	_frames = []
	for i in range(scenes.size()):
		_frames.append([])

	for i in range(scenes.size()):
		var dice: RigidBody3D = scenes[i].instantiate()
		add_child(dice)
		_dice.append(dice)
		# On fige l'index de CE dé dans la closure pour ranger son résultat
		# au bon endroit dans _results, quel que soit l'ordre réel dans
		# lequel les dés s'immobilisent (imprévisible en physique).
		var dice_index := i
		dice.settled.connect(func(face_result: String) -> void: _on_dice_settled(dice_index, face_result))

		var offset := Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3))
		var from_pos: Vector3 = spawn_point.global_position + offset
		var target_pos: Vector3 = from_pos + Vector3(randf_range(-0.2, 0.2), -3.0, 0.6)
		dice.throw(from_pos, target_pos)

	_recording = true


## Échantillonne la transform de chaque dé une fois par frame physique tant
## qu'un lancer réel (_roll_scenes) est en cours : c'est cet historique qui
## est ensuite rejoué à l'identique côté clients réseau par play_recorded().
func _physics_process(_delta: float) -> void:
	if not _recording:
		return
	for i in range(_dice.size()):
		_frames[i].append(_dice[i].global_transform)


func _on_dice_settled(dice_index: int, face_result: String) -> void:
	_results[dice_index] = face_result
	_settled_count += 1
	if _settled_count == _dice.size():
		_recording = false
		roll_finished.emit(_results)


## Trajectoire du dernier lancer réel (roll/roll_mixed), à lire une fois
## roll_finished émis. Utilisé par board.gd (roll_dice_synced, côté hôte)
## pour la diffuser aux clients réseau.
func get_last_recorded_frames() -> Array:
	return _frames


## Rejoue EXACTEMENT un lancer déjà simulé ailleurs (cf hôte), à partir des
## transforms enregistrés par get_last_recorded_frames() sur cette autre
## machine, et des résultats déjà connus (reçus par RPC). Aucune simulation
## physique locale : les dés instanciés ici sont gelés (freeze = true) et
## leur transform est directement imposé frame par frame, donc rigoureusement
## identique chez tout le monde. Utilisé côté client réseau uniquement
## (cf board.gd, roll_dice_synced).
func play_recorded(scenes: Array[PackedScene], frames: Array, results: Array[String]) -> void:
	_recording = false
	for dice in _dice:
		dice.queue_free()
	_dice.clear()
	_results = results

	for i in range(scenes.size()):
		var dice: RigidBody3D = scenes[i].instantiate()
		add_child(dice)
		dice.freeze = true
		_dice.append(dice)
		if i < frames.size() and frames[i].size() > 0:
			dice.global_transform = frames[i][0]

	var frame_count := 0
	for track in frames:
		frame_count = max(frame_count, track.size())

	for frame_i in range(frame_count):
		for i in range(_dice.size()):
			if i < frames.size() and frame_i < frames[i].size():
				_dice[i].global_transform = frames[i][frame_i]
		await get_tree().physics_frame

	roll_finished.emit(_results)


func _ready() -> void:
	if auto_roll_on_ready:
		roll_finished.connect(func(results): print("RESULTAT DES DES: ", results))
		roll()
