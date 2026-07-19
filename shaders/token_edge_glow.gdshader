shader_type canvas_item;

// Liseré lumineux blanc épais tout autour de la silhouette réelle du
// sprite (pas un simple cercle) : sert à masquer un bord mal détouré sur
// la texture source. Fonctionne par dilatation de l'alpha : dans plusieurs
// directions, on regarde s'il y a un pixel opaque à glow_radius_px de
// distance, et on peint le liseré à cet endroit.

uniform float glow_radius_px : hint_range(0.0, 30.0) = 8.0;
uniform vec4 glow_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform int direction_samples : hint_range(8, 32) = 16;
// Clignotement lent : durée d'un cycle complet (creux -> pic -> creux), en
// secondes. min_intensity évite que le liseré disparaisse totalement au
// creux (0.0 = clignote jusqu'à invisible, 1.0 = pas de clignotement).
uniform float pulse_period_sec : hint_range(0.5, 10.0) = 3.0;
uniform float pulse_min_intensity : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	vec4 top = texture(TEXTURE, UV);
	float glow = 0.0;

	for (int i = 0; i < direction_samples; i++) {
		float a = float(i) / float(direction_samples) * TAU;
		vec2 dir = vec2(cos(a), sin(a));
		vec2 offset = dir * TEXTURE_PIXEL_SIZE * glow_radius_px;
		float sample_a = texture(TEXTURE, UV + offset).a;
		glow = max(glow, sample_a);
	}

	// sin ramené en [0,1] puis étalé entre pulse_min_intensity et 1.0.
	float wave = 0.5 + 0.5 * sin(TIME * TAU / pulse_period_sec);
	float pulse = mix(pulse_min_intensity, 1.0, wave);
	glow *= pulse;

	vec3 rgb = mix(glow_color.rgb, top.rgb, top.a);
	float out_a = max(top.a, glow * glow_color.a);
	COLOR = vec4(rgb, out_a) * COLOR;
}