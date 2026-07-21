class_name ActivityBoard
extends Resource

## Une "planche" d'activité : l'overlay affiché sur une carte pour détailler
## l'action à résoudre (jet de dés, symboles, chiffres...). Plusieurs cartes
## peuvent partager la même ActivityBoard (ex: toutes les cartes "planche
## rouge" utilisent la même règle).
##
## Les champs sous "détails d'activité" sont des emplacements pour plus
## tard : les assets (dés, symboles, chiffres) ne sont pas encore tous
## disponibles, donc ils restent vides pour l'instant.

@export var id: String = ""
@export var texture: Texture2D

## -- Détails d'activité, à compléter plus tard --
@export var dice_count: int = 0
@export var numbers: Array[int] = []
@export var symbols: Array[Texture2D] = []
