class_name SeaCard
extends Resource

## Une carte de mer : contenu générique pour l'instant (à remplacer par les
## vraies cartes du jeu plus tard). "type" détermine l'icône/couleur affichée
## et pourra plus tard piloter la résolution (gain de ressource, combat, etc).
enum CardType { TRESOR, RENCONTRE, TEMPETE, COMMERCE }

@export var sea_key: String = ""
@export var type: CardType = CardType.TRESOR
@export var title: String = ""
@export var description: String = ""
