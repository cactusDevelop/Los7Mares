extends Node

## Vérifie si une nouvelle version JOUEUR a été publiée sur GitHub (Release),
## pour proposer une mise à jour depuis l'écran titre. Le serveur dédié
## (Raspberry Pi) n'est PAS concerné : il continue d'être mis à jour à la
## main via "scp" + "systemctl restart" (cf "export custom template/"),
## donc ce système s'auto-désactive sur un export "Serveur dédié"
## (cf Network.is_dedicated_server_launch()).
##
## A CHAQUE nouvelle version publiée pour les joueurs :
## 1. Incrémenter CURRENT_VERSION ci-dessous (avant d'exporter les binaires).
## 2. Sur GitHub -> Releases -> "Draft a new release", créer un tag au
##    format "vX.Y.Z" correspondant EXACTEMENT à CURRENT_VERSION
##    (ex: CURRENT_VERSION = "1.1.0" -> tag "v1.1.0"), puis publier.
## Sans Release GitHub correspondante, aucune mise à jour n'est proposée
## (silencieux : pas d'erreur affichée aux joueurs).

const CURRENT_VERSION := "1.0.0"
const GITHUB_REPO := "cactusDevelop/Los7Mares"
const RELEASES_API_URL := "https://api.github.com/repos/" + GITHUB_REPO + "/releases/latest"
const RELEASES_PAGE_URL := "https://github.com/" + GITHUB_REPO + "/releases/latest"
const REQUEST_TIMEOUT := 6.0

## Nom EXACT de l'asset .exe joint à la Release GitHub (doit correspondre au
## nom de fichier choisi dans le preset d'export Windows).
const ASSET_NAME := "Los7Mares.exe"

## Émis si la Release GitHub la plus récente est plus récente que
## CURRENT_VERSION. latest_version est sans le préfixe "v" (ex: "1.1.0").
signal update_available(latest_version: String)
## Émis si la vérification échoue (hors-ligne, GitHub injoignable, pas de
## Release, pas d'asset nommé ASSET_NAME, etc.) ou si aucune mise à jour
## n'est disponible. A utiliser uniquement pour des logs/debug : ne doit
## jamais bloquer le joueur à la vérification initiale.
signal check_failed
## Émis pendant le téléchargement de l'exécutable, fraction entre 0.0 et 1.0.
signal download_progress(fraction: float)
## Émis si le téléchargement/l'installation de la mise à jour échoue (celui-
## ci, contrairement à check_failed, doit être affiché au joueur : on est
## déjà dans le flux forcé, on ne peut pas le laisser bloqué sans info).
signal download_failed(reason: String)

var _http: HTTPRequest
var _download_http: HTTPRequest
var _download_url: String = ""
var _download_target_path: String = ""


## Lance la vérification en arrière-plan (non bloquant). Sans effet si une
## vérification est déjà en cours ou si cette instance est un serveur dédié.
func check_for_update() -> void:
	if Network.is_dedicated_server_launch():
		return
	if _http:
		return
	_http = HTTPRequest.new()
	_http.timeout = REQUEST_TIMEOUT
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	var err := _http.request(RELEASES_API_URL, ["User-Agent: Los7Mares-UpdateChecker"])
	if err != OK:
		_cleanup()
		check_failed.emit()


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_cleanup()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		check_failed.emit()
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary) or not parsed.has("tag_name"):
		check_failed.emit()
		return
	var latest: String = String(parsed["tag_name"]).strip_edges()
	if latest.begins_with("v") or latest.begins_with("V"):
		latest = latest.substr(1)
	if not _is_newer(latest, CURRENT_VERSION):
		check_failed.emit()
		return
	var found_url := ""
	for asset in parsed.get("assets", []):
		if typeof(asset) == TYPE_DICTIONARY and asset.get("name", "") == ASSET_NAME:
			found_url = asset.get("browser_download_url", "")
			break
	if found_url.is_empty():
		push_warning("UpdateChecker: version %s trouvée mais aucun asset nommé '%s' sur la Release." % [latest, ASSET_NAME])
		check_failed.emit()
		return
	_download_url = found_url
	update_available.emit(latest)


func _cleanup() -> void:
	if _http:
		_http.queue_free()
		_http = null


## Compare deux versions "X.Y.Z" (nombre de segments libre, ex: "1.2").
## Retourne vrai si `a` est strictement plus récente que `b`.
static func _is_newer(a: String, b: String) -> bool:
	var parts_a := a.split(".")
	var parts_b := b.split(".")
	var count: int = max(parts_a.size(), parts_b.size())
	for i in range(count):
		var va: int = int(parts_a[i]) if i < parts_a.size() else 0
		var vb: int = int(parts_b[i]) if i < parts_b.size() else 0
		if va != vb:
			return va > vb
	return false


## Lance le téléchargement de l'exécutable de la dernière Release (URL
## trouvée lors de check_for_update) puis, une fois terminé, remplace
## automatiquement le jeu et le relance. A appeler uniquement après avoir
## reçu update_available (sinon _download_url est vide -> download_failed).
func begin_update() -> void:
	if _download_url.is_empty():
		download_failed.emit("URL de téléchargement introuvable.")
		return
	if _download_http:
		return  # Téléchargement déjà en cours.

	var exe_dir := OS.get_executable_path().get_base_dir()
	_download_target_path = exe_dir.path_join("Los7Mares_update.tmp")

	_download_http = HTTPRequest.new()
	add_child(_download_http)
	_download_http.download_file = _download_target_path
	_download_http.request_completed.connect(_on_download_completed)
	set_process(true)
	var err := _download_http.request(_download_url, ["User-Agent: Los7Mares-UpdateChecker"])
	if err != OK:
		set_process(false)
		_download_http.queue_free()
		_download_http = null
		download_failed.emit("Impossible de démarrer le téléchargement (erreur %s)." % err)


func _process(_delta: float) -> void:
	if not is_instance_valid(_download_http):
		set_process(false)
		return
	var total := _download_http.get_body_size()
	if total > 0:
		download_progress.emit(float(_download_http.get_downloaded_bytes()) / float(total))


func _on_download_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	set_process(false)
	_download_http.queue_free()
	_download_http = null
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		download_failed.emit("Échec du téléchargement (erreur réseau).")
		return
	_install_update_and_restart()


## Écrit un script .bat à côté de l'exécutable : il attend que le processus
## actuel (identifié par son PID) se termine, remplace l'ancien .exe par le
## nouveau téléchargé, relance le jeu, puis se supprime lui-même. Nécessaire
## car Windows interdit d'écraser un .exe en cours d'exécution.
func _install_update_and_restart() -> void:
	var exe_path := OS.get_executable_path()
	var exe_dir := exe_path.get_base_dir()
	var bat_path := exe_dir.path_join("los7mares_update.bat")
	var pid := OS.get_process_id()

	var bat_content := "@echo off\r\n"
	bat_content += ":wait\r\n"
	bat_content += "tasklist /FI \"PID eq %d\" 2>NUL | find \"%d\" >NUL\r\n" % [pid, pid]
	bat_content += "if \"%ERRORLEVEL%\"==\"0\" (\r\n"
	bat_content += "  timeout /t 1 /nobreak > NUL\r\n"
	bat_content += "  goto wait\r\n"
	bat_content += ")\r\n"
	bat_content += "move /Y \"%s\" \"%s\" > NUL\r\n" % [_download_target_path.replace("/", "\\"), exe_path.replace("/", "\\")]
	bat_content += "start \"\" \"%s\"\r\n" % exe_path.replace("/", "\\")
	bat_content += "del \"%%~f0\"\r\n"

	var file := FileAccess.open(bat_path, FileAccess.WRITE)
	if file == null:
		download_failed.emit("Impossible d'écrire le script d'installation (dossier en lecture seule ?).")
		return
	file.store_string(bat_content)
	file.close()

	OS.create_process("cmd.exe", ["/c", "start", "", bat_path.replace("/", "\\")], true)
	get_tree().quit()
