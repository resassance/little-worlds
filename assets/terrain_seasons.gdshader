shader_type canvas_item;

uniform float autumn_amount = 0.0;
uniform float winter_amount = 0.0;
uniform float atlas_columns = 18.0;

void vertex() {
	if (INSTANCE_CUSTOM.g > 0.5) {
		UV.x = (UV.x + INSTANCE_CUSTOM.r) / atlas_columns;
	}
}

void fragment() {
	float mask = COLOR.a;
	if (mask > 0.979 && mask < 0.982 && COLOR.g > COLOR.r) {
		COLOR.rgb = mix(COLOR.rgb, vec3(0.733333, 0.654902, 0.462745), autumn_amount);
		COLOR.rgb = mix(COLOR.rgb, vec3(0.862745, 0.898039, 0.866667), winter_amount);
		COLOR.a /= mask;
	}
}
