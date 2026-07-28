class_name IconBadge
extends HBoxContainer

## Un badge = 1 (ou plusieurs, ex: acier/toile interchangeables) icône(s) de
## ressource/dé + son montant. Instancié dynamiquement par ActivityDetails,
## jamais placé à la main dans une scène de carte.

@onready var icon_rects: Array[TextureRect] = [$Icon1, $Icon2]
@onready var amount_label: Label = $Amount
@onready var key_label: Label = $KeyLabel


## icon_keys : une ou deux clés IconArt (ex: ["bois"] ou ["acier","toile"]).
## En attendant les icônes définitives (cf GAME_RULES.txt section 14), le
## nom textuel de la ressource s'affiche à la place de l'image manquante.
func set_data(icon_keys: Array, amount: int) -> void:
	amount_label.text = "x%d" % amount
	var missing_keys: Array = []
	for i in icon_rects.size():
		var rect := icon_rects[i]
		if i < icon_keys.size():
			var tex := IconArt.get_icon(icon_keys[i])
			rect.texture = tex
			rect.visible = tex != null
			if tex == null:
				missing_keys.append(icon_keys[i])
		else:
			rect.visible = false
	key_label.text = "/".join(missing_keys)
	key_label.visible = not missing_keys.is_empty()
