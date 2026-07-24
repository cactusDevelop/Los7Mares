extends Sprite2D

## Effet 3D (épaisseur) : scripts/common/piece_thickness.gd (constantes
## partagées avec captain_piece.gd et piece_selection_panel.gd).
func _ready() -> void:
	if texture:
		centered = true
		offset = Vector2(0, -texture.get_height() / 2.0)

	PieceThickness.add_to_sprite(self)
