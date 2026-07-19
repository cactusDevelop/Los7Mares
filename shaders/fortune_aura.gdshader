shader_type canvas_item;

// Aura radiale blanche clignotante, à poser sur un ColorRect (ou tout
// CanvasItem) centré derrière le jeton. N'utilise pas l'alpha d'une
// texture : indépendant du détourage du sprite.

uniform vec4 aura_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float radius : hint_range(0.0, 1.0) = 0.5; // rayon du disque plein, en UV (0.5 = touche les bords)
uniform float softness : hint_range(0.0, 1.0) = 0.35; // largeur du dégradé de sortie
uniform float pulse_period_sec : hint_range(0.5, 10.0) = 1.2;
uniform float pulse_min_intensity : hint_range(0.0, 1.0) = 0.25;

void fragment() {
	vec2 centered = UV - vec2(0.5);
	// corrige le ratio si le ColorRect n'est pas carré
	centered.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float dist = length(centered);

	float disk = 1.0 - smoothstep(radius - softness, radius, dist);

	float wave = 0.5 + 0.5 * sin(TIME * TAU / pulse_period_sec);
	float pulse = mix(pulse_min_intensity, 1.0, wave);

	float out_a = disk * pulse * aura_color.a;
	COLOR = vec4(aura_color.rgb, out_a);
}