extends Sprite2D

## Effet 3D (épaisseur) : scripts/common/pion_thickness.gd (constantes
## partagées avec captain_pion.gd et pion_selection_panel.gd).
func _ready() -> void:
	if texture:
		centered = true
		offset = Vector2(0, -texture.get_height() / 2.0)

	PionThickness.add_to_sprite(self)
