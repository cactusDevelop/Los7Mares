class_name IconArt
extends RefCounted

## Résout la texture d'une icône (clé "bois", "etoile", "canon", ...) pour
## les badges affichés sur ActivityDetails. Deux sources possibles :
##   1. Assets déjà présents dans le dépôt (dés, fortune, trésor) : chemins
##      explicites ci-dessous.
##   2. Convention "res://assets/art/icons/icon-{key}.png" pour toute
##      nouvelle icône ajoutée plus tard (bois, bouffe, acier, toile, rhum,
##      planche, réussite, voile, ressource...) : pas besoin de toucher au
##      code, il suffit de déposer le fichier au bon nom.
## Si aucune texture n'existe encore pour une clé, retourne null (le badge
## reste sans icône en attendant l'asset, même logique que CardArt).

const EXPLICIT_PATHS := {
	"etoile": "res://assets/art/dice/dé-blanc-un.png",
	"etoile_double": "res://assets/art/dice/dé-blanc-double.png",
	"canon": "res://assets/art/dice/dé-noir-canon.png",
	"abordage": "res://assets/art/dice/dé-noir-abordage.png",
	"fortune": "res://assets/art/tokens/fortune.png",
	"tresor": "res://assets/art/tokens/tresor.png",
}

const CONVENTION_DIR := "res://assets/art/icons/icon-%s.png"


static func get_icon(key: String) -> Texture2D:
	var path: String = EXPLICIT_PATHS.get(key, CONVENTION_DIR % key)
	if not ResourceLoader.exists(path):
		return null
	return load(path)
