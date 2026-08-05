shader_type canvas_item;

// Fond animé pour l'écran de jeu (board.tscn) : de nombreuses sinusoïdes
// remplies en bande (pas une silhouette cumulée sous la courbe : chaque
// vague ne colore qu'une bande autour de sa propre courbe, ce qui les
// répartit vraiment sur toute la hauteur de l'écran). Toutes les valeurs
// (fréquence, vitesse, sens, position, épaisseur, teinte) sont tirées
// aléatoirement par couche (hash de l'index) : rien ne dépend de l'ordre
// des couches.

uniform vec4 background_color : source_color = vec4(0.01, 0.03, 0.10, 1.0);
uniform float speed : hint_range(0.0, 2.0) = 0.15;
uniform float speed_jitter : hint_range(0.0, 2.0) = 0.9;
// Amplitude commune : toutes les vagues partent de cette taille (celle
// des plus grosses), avec +/- amplitude_jitter de bruit aléatoire.
uniform float amplitude : hint_range(0.0, 0.3) = 0.1;
uniform float amplitude_jitter : hint_range(0.0, 0.2) = 0.05;
// Épaisseur de la bande colorée autour de chaque courbe (en fraction de
// la hauteur d'écran).
uniform float band_thickness : hint_range(0.02, 0.3) = 0.1;
uniform float band_thickness_jitter : hint_range(0.0, 0.15) = 0.04;
uniform float base_hue : hint_range(0.0, 1.0) = 0.55;
uniform float hue_spread : hint_range(0.0, 1.0) = 0.4;
uniform float layer_alpha : hint_range(0.0, 1.0) = 0.35;
uniform float overall_alpha : hint_range(0.0, 1.0) = 0.85;

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

void fragment() {
	vec3 col = background_color.rgb;
	float t = TIME * speed;

	for (int i = 0; i < WAVE_COUNT; i++) {
		float fi = float(i);

		// Chaque propriété est un tirage indépendant (aucun lien avec fi
		// hormis la graine) : rien ne varie progressivement d'une couche
		// à l'autre.
		float r_dir = hash11(fi * 12.9);
		float r_freq = hash11(fi * 3.7 + 1.0);
		float r_speed = hash11(fi * 7.1 + 2.0);
		float r_phase = hash11(fi * 5.3 + 3.0);
		float r_amp = hash11(fi * 9.7 + 4.0);
		float r_y = hash11(fi * 4.1 + 5.0);
		float r_thick = hash11(fi * 1.9 + 5.7);
		float r_hue = hash11(fi * 6.3 + 6.0);
		float r_sat = hash11(fi * 8.9 + 7.0);
		float r_val = hash11(fi * 2.3 + 8.0);

		float dir = r_dir < 0.5 ? 1.0 : -1.0;
		float freq = 2.5 + r_freq * 9.0;
		// Vitesse de défilement aléatoire par couche, plus lente
		// globalement (speed_jitter contrôle l'écart entre couches).
		float phase_speed = (0.2 + r_speed * speed_jitter) * dir;

		// Toutes les vagues ont (à peu près) la taille des plus grosses :
		// amplitude commune + bruit aléatoire ajouté/retiré, pas de
		// réduction progressive vers le haut de l'écran.
		float amp = amplitude + (r_amp * 2.0 - 1.0) * amplitude_jitter;
		float thickness = max(0.01, band_thickness + (r_thick * 2.0 - 1.0) * band_thickness_jitter);

		// Position verticale : répartie aléatoirement sur toute la
		// hauteur de l'écran (r_y ∈ [0, 1]).
		float base_y = r_y;
		float wave_y = base_y + sin(UV.x * freq * TAU + t * phase_speed + r_phase * TAU) * amp;

		// Bande colorée centrée sur la courbe (pas de remplissage cumulé
		// vers le bas) : chaque couche ne peint que son propre ruban.
		float dist = abs(UV.y - wave_y);
		float half_thickness = thickness * 0.5;
		float band = 1.0 - smoothstep(half_thickness * 0.5, half_thickness, dist);

		// Teinte aléatoire indépendante par couche (pas de dégradé), dans
		// un voisinage réglable autour de base_hue.
		float hue = fract(base_hue + (r_hue - 0.5) * hue_spread);
		float sat = 0.4 + r_sat * 0.5;
		float val = 0.35 + r_val * 0.55;
		vec3 layer_color = hsv2rgb(vec3(hue, sat, val));

		col = mix(col, layer_color, band * layer_alpha);
	}

	// Vagues (et fond) un peu transparents : laisse transparaître ce qu'il
	// y a derrière ce calque.
	COLOR = vec4(col, overall_alpha);
}
