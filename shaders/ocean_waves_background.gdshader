shader_type canvas_item;

// Fond animé pour l'écran de jeu (board.tscn) : de nombreuses sinusoïdes,
// chacune colorant toute la zone SOUS sa courbe (silhouette), mélangées
// entre elles par transparence. Les positions verticales sont réparties
// en "stratifié aléatoire" (un tirage aléatoire dans chacune des
// WAVE_COUNT tranches de hauteur d'écran) pour garantir une couverture
// du haut jusqu'au bas de l'écran, tout en restant aléatoire. Fréquence,
// vitesse, sens et teinte restent des tirages indépendants par couche.

uniform float speed : hint_range(0.0, 2.0) = 0.5;
uniform float speed_jitter : hint_range(0.0, 2.0) = 1.3;
// Amplitude commune : toutes les vagues partent de cette taille (celle
// des plus grosses), avec +/- amplitude_jitter de bruit aléatoire.
uniform float amplitude : hint_range(0.0, 0.3) = 0.06;
uniform float amplitude_jitter : hint_range(0.0, 0.2) = 0.03;
// Largeur de la transition (anti-aliasing) entre "au-dessus" et
// "au-dessous" de la courbe.
uniform float edge_softness : hint_range(0.001, 0.05) = 0.015;
uniform float base_hue : hint_range(0.0, 1.0) = 0.58;
uniform float hue_spread : hint_range(0.0, 1.0) = 0.12;
uniform float layer_alpha : hint_range(0.0, 1.0) = 0.42;
uniform float overall_alpha : hint_range(0.0, 1.0) = 1.0;

const int WAVE_COUNT = 16;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

vec3 hsv2rgb(vec3 c) {
	vec4 k = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
	return c.z * mix(k.xxx, clamp(p - k.xxx, 0.0, 1.0), c.y);
}

// Plage de saturation/luminosité utilisée par couche (voir plus bas) :
// centralisée ici pour que la couleur de fond moyenne reste toujours en
// phase avec la palette réelle des vagues.
const float SAT_MIN = 0.3;
const float SAT_RANGE = 0.35;
const float VAL_MIN = 0.5;
const float VAL_RANGE = 0.4;

void fragment() {
	// Fond = couleur moyenne de la palette des vagues (même teinte de
	// base, saturation/luminosité au milieu de leur plage), pour qu'il
	// n'y ait aucun contraste franc qui dessine le contour des
	// sinusoïdes contre un fond figé.
	vec3 col = hsv2rgb(vec3(base_hue, SAT_MIN + SAT_RANGE * 0.5, VAL_MIN + VAL_RANGE * 0.5));
	float t = TIME * speed;
	float slot = 1.1 / float(WAVE_COUNT);

	for (int i = 0; i < WAVE_COUNT; i++) {
		float fi = float(i);

		// Chaque propriété est un tirage indépendant (aucun lien avec fi
		// hormis la graine) : rien ne varie progressivement d'une couche
		// à l'autre, hormis la position (stratifiée pour couvrir tout
		// l'écran, voir base_y ci-dessous).
		float r_dir = hash11(fi * 12.9);
		float r_freq = hash11(fi * 3.7 + 1.0);
		float r_speed = hash11(fi * 7.1 + 2.0);
		float r_phase = hash11(fi * 5.3 + 3.0);
		float r_amp = hash11(fi * 9.7 + 4.0);
		float r_y = hash11(fi * 4.1 + 5.0);
		float r_hue = hash11(fi * 6.3 + 6.0);
		float r_sat = hash11(fi * 8.9 + 7.0);
		float r_val = hash11(fi * 2.3 + 8.0);

		float dir = r_dir < 0.5 ? 1.0 : -1.0;
		float freq = 2.5 + r_freq * 9.0;
		// Vitesse de défilement aléatoire et indépendante par couche.
		float phase_speed = (0.2 + r_speed * speed_jitter) * dir;

		// Toutes les vagues ont (à peu près) la taille des plus grosses :
		// amplitude commune + bruit aléatoire ajouté/retiré.
		float amp = amplitude + (r_amp * 2.0 - 1.0) * amplitude_jitter;

		// Position verticale stratifiée : la couche i tombe aléatoirement
		// dans sa propre tranche [i/N, (i+1)/N[, ce qui garantit qu'il y a
		// toujours au moins une vague près du haut ET près du bas de
		// l'écran, tout en gardant un placement aléatoire.
		float base_y = -0.05 + (fi + r_y) * slot;
		float wave_y = base_y + sin(UV.x * freq * TAU + t * phase_speed + r_phase * TAU) * amp;

		// Colore toute la zone SOUS la courbe (silhouette), pas juste une
		// bande : c'est ce qui donne l'effet "vagues remplies" empilées.
		float fill = smoothstep(wave_y - edge_softness, wave_y + edge_softness, UV.y);

		// Teinte aléatoire indépendante par couche (pas de dégradé), dans
		// un voisinage réglable autour de base_hue.
		float hue = fract(base_hue + (r_hue - 0.5) * hue_spread);
		float sat = SAT_MIN + r_sat * SAT_RANGE;
		float val = VAL_MIN + r_val * VAL_RANGE;
		vec3 layer_color = hsv2rgb(vec3(hue, sat, val));

		col = mix(col, layer_color, fill * layer_alpha);
	}

	// Vagues (et fond) un peu transparents : laisse transparaître ce qu'il
	// y a derrière ce calque.
	COLOR = vec4(col, overall_alpha);
}
