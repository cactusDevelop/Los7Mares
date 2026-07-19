shader_type canvas_item;

// Effet 3D (épaisseur) appliqué directement sur la texture, en un seul
// draw call : plus de nodes enfants empilés, donc plus aucun souci
// d'ordre d'affichage (z-index) quand plusieurs pièces partagent une case.
// Principe : on ré-échantillonne la texture plusieurs fois, décalée dans
// depth_direction, assombrie, et on ne la montre que là où le pixel du
// dessus (non décalé) est transparent -> ça "fait déborder" une tranche
// sombre sous le sprite d'origine, comme une épaisseur de carton.

uniform vec2 depth_direction = vec2(-0.70710678, 0.70710678);
uniform float thickness_px = 10.0;
uniform int layers = 8;
uniform float edge_darken : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec4 modulate = COLOR; // couleur du node (modulate/teinte), déjà interpolée par Godot
	vec4 top = texture(TEXTURE, UV);

	float shadow_alpha = 0.0;
	for (int i = 1; i <= layers; i++) {
		vec2 offset = depth_direction * TEXTURE_PIXEL_SIZE * thickness_px * (float(i) / float(layers));
		shadow_alpha = max(shadow_alpha, texture(TEXTURE, UV - offset).a);
	}

	vec3 shadow_rgb = top.rgb * (1.0 - edge_darken);
	vec4 result = mix(vec4(shadow_rgb, shadow_alpha), top, top.a);

	COLOR = result * modulate;
}
