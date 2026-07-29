shader_type canvas_item;

// Remplace uniquement les pixels (quasi-)blancs de la texture par
// replace_color, en conservant leur alpha d'origine ; tous les autres
// pixels (contours, ombres, autres couleurs) restent inchangés. Utilisé
// pour teinter les gemmes mer (assets/art/pieces/gemme-*.png, fond blanc)
// avec la couleur du joueur, sans appliquer un filtre de couleur global
// façon "modulate" qui altérerait aussi les couleurs déjà présentes.

uniform vec4 replace_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Un pixel est considéré "blanc" quand son canal le plus faible dépasse ce
// seuil : permet d'englober l'anti-aliasing / léger hors-blanc sans
// mordre sur les couleurs voisines.
uniform float white_threshold : hint_range(0.0, 1.0) = 0.85;

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	float min_channel = min(tex_color.r, min(tex_color.g, tex_color.b));
	vec3 rgb = min_channel > white_threshold ? replace_color.rgb : tex_color.rgb;
	// * COLOR : respecte le modulate du node (ex. assombrissement des
	// couches d'ombre de l'effet 3D, cf sea_gem_pile.gd/PionThickness) au
	// lieu de l'ignorer complètement. Sans ça, COLOR (blanc, alpha 1, par
	// défaut) ne change rien pour un modulate neutre (multiplication par
	// 1), donc aucune régression sur les usages existants.
	COLOR = vec4(rgb, tex_color.a) * COLOR;
}
