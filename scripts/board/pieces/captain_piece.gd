extends Sprite2D

## Effet 3D (épaisseur) géré entièrement par un shader (shaders/piece_thickness.gdshader)
## plutôt que des nodes enfants empilés : évite tout conflit d'ordre
## d'affichage (z-index) avec les autres pièces posées sur la même case.
const THICKNESS_SHADER := preload("res://shaders/piece_thickness.gdshader")
const THICKNESS_PX := 12.0
const THICKNESS_LAYERS := 8
const EDGE_DARKEN := 0.5


func _ready() -> void:
	if texture:
		centered = true
		offset = Vector2(0, -texture.get_height() / 2.0)

	var mat := ShaderMaterial.new()
	mat.shader = THICKNESS_SHADER
	mat.set_shader_parameter("depth_direction", UiTheme.DEPTH_DIRECTION)
	mat.set_shader_parameter("thickness_px", THICKNESS_PX)
	mat.set_shader_parameter("layers", THICKNESS_LAYERS)
	mat.set_shader_parameter("edge_darken", EDGE_DARKEN)
	material = mat
