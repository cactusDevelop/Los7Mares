class_name GameCardView
extends Node2D

## Assemble visuellement une GameCard : fond, icône de type, planche
## d'activité, et badges d'activité (coût/récompense par piste), générés
## dynamiquement depuis card.activities (chaque carte a un nombre et un
## type d'icônes différents, impossible à placer à la main par carte).
##
## Fond, icône et planche sont des Sprite2D affichés à leur taille native
## (pas de stretch/crop) : leurs transforms respectifs se règlent à l'oeil
## dans l'éditeur pour les aligner sur l'artwork du fond.
##
## Layout des badges : ajuste ROW_SPACING / activity_details.position /
## l'échelle de IconBadge directement ici ou dans l'éditeur (scène
## card_playground.tscn prévue pour itérer vite, cf scenes/debug/).

const IconBadgeScene := preload("res://scenes/board/icon_badge.tscn")
const TRACK_ORDER := ["exploration", "commerce", "combat"]
const ROW_SPACING := 40.0

@onready var background: Sprite2D = $Background
@onready var icon: Sprite2D = $Icon
@onready var planche: Sprite2D = $Planche
@onready var activity_details: Node2D = $ActivityDetails


## background_override permet d'imposer une texture de fond précise (carte
## déjà révélée) plutôt que d'en tirer une au hasard.
func set_card(card: GameCard, background_override: Texture2D = null) -> void:
	background.texture = background_override if background_override else card.get_random_background()
	icon.texture = card.get_icon()
	planche.texture = card.get_planche_texture()
	_build_activity_details(card)


## Taille native (non mise à l'échelle) du fond de carte, utile pour calculer
## un scale d'ajustement (aspect-fit, sans crop) depuis l'extérieur.
func get_native_size() -> Vector2:
	return background.texture.get_size() if background.texture else Vector2.ZERO


func _build_activity_details(card: GameCard) -> void:
	for child in activity_details.get_children():
		child.queue_free()

	var row_y := 0.0
	for track in TRACK_ORDER:
		if not card.activities.has(track):
			continue
		var activity: Dictionary = card.activities[track]
		var row := _build_activity_row(activity)
		activity_details.add_child(row)
		row.position = Vector2(0, row_y)
		row_y += ROW_SPACING


func _build_activity_row(activity: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	var cost: Array = activity.get("cost", [])
	var reward: Array = activity.get("reward", [])
	for token in cost:
		row.add_child(_build_badge(token))
	if not cost.is_empty() and not reward.is_empty():
		var arrow := Label.new()
		arrow.text = "->"
		row.add_child(arrow)
	for token in reward:
		row.add_child(_build_badge(token))
	return row


func _build_badge(token: Dictionary) -> IconBadge:
	var badge: IconBadge = IconBadgeScene.instantiate()
	var icon_keys: Array = token.get("icons", [token.get("icon", "")])
	badge.set_data.call_deferred(icon_keys, int(token.get("amount", 1)))
	return badge
