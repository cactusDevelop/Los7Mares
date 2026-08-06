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

## Émis si la Release GitHub la plus récente est plus récente que
## CURRENT_VERSION. latest_version est sans le préfixe "v" (ex: "1.1.0").
signal update_available(latest_version: String)
## Émis si la vérification échoue (hors-ligne, GitHub injoignable, pas de
## Release, etc.) ou si aucune mise à jour n'est disponible. A utiliser
## uniquement pour des logs/debug : ne doit jamais bloquer le joueur.
signal check_failed

var _http: HTTPRequest


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
	if _is_newer(latest, CURRENT_VERSION):
		update_available.emit(latest)
	else:
		check_failed.emit()


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
