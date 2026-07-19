shader_type canvas_item;

// Effet 3D (épaisseur) appliqué directement sur la texture, en un seul
// draw call : plus de nodes enfants empilés, donc plus aucun souci
// d'ordre d'affichage (z-index) quand plusieurs pièces partagent une case.
// Principe : on ré-échantillonne la texture plusieurs fois, décalée dans
// depth_direction, et on garde la couleur du décalage qui "dépasse" le plus
// loin sous le sprite d'origine -> ça donne une tranche assombrie sous le
// sprite, comme une épaisseur de carton.

uniform vec2 depth_direction = vec2(-0.70710678, 0.70710678);
// Épaisseur voulue, en pixels RÉELLEMENT AFFICHÉS À L'ÉCRAN (pas en pixels
// de la texture source). display_scale = pixels affichés / pixels texture
// (ex : 0.58 si une texture de 190px est dessinée sur 110px) : c'est ce qui
// permet à chaque objet (jeton, pièce, bateau...) de garder sa PROPRE
// épaisseur visuelle quelle que soit la résolution de son image source ou
// sa taille d'affichage. À régler depuis le script appelant.
uniform float thickness_px = 10.0;
uniform float display_scale = 1.0;
uniform int layers = 8;
uniform float edge_darken : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec4 modulate = COLOR; // couleur du node (modulate/teinte), déjà interpolée par Godot
	vec4 top = texture(TEXTURE, UV);

	// Pixels-texture équivalents à l'épaisseur voulue en pixels-écran.
	float thickness_tex_px = thickness_px / max(display_scale, 0.0001);

	// Parmi les couches décalées, on garde celle dont l'alpha est le plus
	// fort à cet endroit (celle qui "dépasse" le plus loin) ET sa VRAIE
	// couleur à cet endroit-là (jamais celle du pixel courant, transparent
	// ici -> RGB non significatif, souvent noir dans les PNG).
	vec4 shadow = vec4(0.0);
	for (int i = 1; i <= layers; i++) {
		vec2 offset = depth_direction * TEXTURE_PIXEL_SIZE * thickness_tex_px * (float(i) / float(layers));
		vec4 sample_color = texture(TEXTURE, UV - offset);
		if (sample_color.a > shadow.a) {
			shadow = sample_color;
		}
	}

	vec3 shadow_rgb = shadow.rgb * (1.0 - edge_darken);
	vec4 result = mix(vec4(shadow_rgb, shadow.a), top, top.a);

	COLOR = result * modulate;
}