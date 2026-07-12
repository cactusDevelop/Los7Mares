extends Node

## Gère la musique de fond globale (persiste entre les scènes puisque c'est
## un autoload). Un seul AudioStreamPlayer : on baisse son volume jusqu'au
## silence, on change de morceau, puis on remonte le volume — pas besoin de
## deux lecteurs pour un simple fondu enchaîné séquentiel.
##
## IMPORTANT : pense à activer le bouclage (Loop) de chaque fichier .mp3
## dans Godot : sélectionne le fichier dans FileSystem → onglet Import →
## coche "Loop" → Reimport. Sans ça, la musique s'arrête au bout d'une lecture.

const MENU_TRACK := preload("res://assets/audio/Bastille Unbound.mp3")
const GAME_TRACKS_DIR := "res://assets/audio/in-game bgm/"
const GAME_TRACK_EXTENSIONS := ["mp3", "ogg", "wav"]

const FADE_DURATION := 2.0
const NORMAL_VOLUME_DB := 0.0
const SILENT_VOLUME_DB := -40.0
const MENU_MUSIC_START_DELAY := 2.0
const GAME_MUSIC_SWITCH_GAP := 0.5

var _player: AudioStreamPlayer


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	add_child(_player)


func play_menu_music() -> void:
	if _player.playing:
		var fade_out := create_tween()
		fade_out.tween_property(_player, "volume_db", SILENT_VOLUME_DB, FADE_DURATION)
		await fade_out.finished
	else:
		_player.volume_db = SILENT_VOLUME_DB

	_player.stream = MENU_TRACK
	await get_tree().create_timer(MENU_MUSIC_START_DELAY).timeout
	_player.play()
	var fade_in := create_tween()
	fade_in.tween_property(_player, "volume_db", NORMAL_VOLUME_DB, FADE_DURATION)


func play_random_game_music() -> void:
	var tracks := _get_game_tracks()
	if tracks.is_empty():
		push_warning("Aucune musique trouvée dans %s" % GAME_TRACKS_DIR)
		return
	var track: AudioStream = tracks[randi() % tracks.size()]
	_play_track(track)


func _play_track(stream: AudioStream) -> void:
	_player.volume_db = NORMAL_VOLUME_DB
	_player.stream = stream
	_player.play()


## Baisse le morceau en cours jusqu'au silence, puis lance un morceau de jeu
## aléatoire et remonte le volume. À appeler sans "await" : elle continue de
## tourner sur cet autoload même après le changement de scène.
func fade_to_random_game_music() -> void:
	var fade_out := create_tween()
	fade_out.tween_property(_player, "volume_db", SILENT_VOLUME_DB, FADE_DURATION)
	await fade_out.finished
	await get_tree().create_timer(GAME_MUSIC_SWITCH_GAP).timeout

	play_random_game_music()
	_player.volume_db = SILENT_VOLUME_DB

	var fade_in := create_tween()
	fade_in.tween_property(_player, "volume_db", NORMAL_VOLUME_DB, FADE_DURATION)


## Scanne assets/audio/in-game bgm/ et retourne tous les fichiers audio
## trouvés, sans qu'il soit nécessaire de les lister à la main ici.
func _get_game_tracks() -> Array[AudioStream]:
	var tracks: Array[AudioStream] = []
	var dir := DirAccess.open(GAME_TRACKS_DIR)
	if dir == null:
		push_warning("Impossible d'ouvrir %s" % GAME_TRACKS_DIR)
		return tracks

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.get_extension().to_lower() in GAME_TRACK_EXTENSIONS:
			var stream: AudioStream = load(GAME_TRACKS_DIR + file_name)
			if stream:
				tracks.append(stream)
		file_name = dir.get_next()
	dir.list_dir_end()

	return tracks
