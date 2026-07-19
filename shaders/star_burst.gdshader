shader_type canvas_item;

// Éclat de lumière tournant derrière un jeton : des rayons de longueur et
// largeur légèrement aléatoires (façon éclat d'étoile réaliste, pas un
// éventail parfaitement régulier), qui tournent en continu via TIME
// (calcul GPU, aucune logique _process/queue_redraw côté script), plus un
// halo doux au centre.

uniform float rotation_speed : hint_range(-2.0, 2.0) = 0.15; // tours par seconde
uniform int ray_count : hint_range(4, 32) = 14;
uniform float ray_sharpness : hint_range(1.0, 32.0) = 6.0;
uniform float glow_radius : hint_range(0.05, 1.0) = 0.32;
uniform vec4 light_color : source_color = vec4(1.0, 0.97, 0.85, 1.0);

float hash11(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0; // repère centré [-1, 1]
	float r = length(p);
	float ang = atan(p.y, p.x) - TIME * rotation_speed * TAU;

	float slice = TAU / float(ray_count);
	float norm_ang = (ang + PI) / slice;
	float idx = floor(norm_ang);
	float local_a = fract(norm_ang) - 0.5; // position dans le rayon courant [-0.5, 0.5]

	// Longueur/largeur légèrement aléatoires par rayon (hash stable par
	// index) : évite l'aspect "ventilateur" parfaitement régulier.
	float rand_len = mix(0.55, 1.0, hash11(idx));
	float rand_width = mix(0.5, 1.0, hash11(idx + 91.7));

	float beam = 1.0 - smoothstep(0.0, rand_width * 0.5, abs(local_a));
	beam = pow(beam, ray_sharpness);
	float fade = 1.0 - smoothstep(0.0, rand_len, r);
	float rays = beam * fade;

	float core = smoothstep(glow_radius, 0.0, r);

	float intensity = clamp(rays * 0.9 + core * 0.6, 0.0, 1.0);
	COLOR = vec4(light_color.rgb, intensity * light_color.a);
}
