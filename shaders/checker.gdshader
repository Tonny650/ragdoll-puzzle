shader_type spatial;
// Cuadricula en espacio mundo (triplanar) para leer bien la escala en el nivel de pruebas.

uniform vec4 color_a : source_color = vec4(0.82, 0.84, 0.88, 1.0);
uniform vec4 color_b : source_color = vec4(0.70, 0.72, 0.77, 1.0);
uniform vec4 line_color : source_color = vec4(0.55, 0.58, 0.64, 1.0);
uniform float cell_size = 1.0;
uniform float roughness_value = 0.85;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float checker(vec2 p) {
	vec2 c = floor(p / cell_size);
	return mod(c.x + c.y, 2.0);
}

float grid(vec2 p) {
	vec2 g = abs(fract(p / cell_size - 0.5) - 0.5) / fwidth(p / cell_size);
	return 1.0 - clamp(min(g.x, g.y), 0.0, 1.0);
}

void fragment() {
	vec3 n = abs(world_normal);
	vec2 uv = n.y > 0.5 ? world_pos.xz : (n.x > n.z ? world_pos.zy : world_pos.xy);
	vec3 col = mix(color_a.rgb, color_b.rgb, checker(uv));
	col = mix(col, line_color.rgb, grid(uv) * 0.6);
	ALBEDO = col;
	ROUGHNESS = roughness_value;
}
