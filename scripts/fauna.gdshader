shader_type canvas_item;
render_mode unshaded;

void vertex() {
	float across = INSTANCE_CUSTOM.y > 0.5 ? 1.0 - UV.x : UV.x;
	UV.x = (across + INSTANCE_CUSTOM.x) / 3.0;
}

void fragment() {
	COLOR = texture(TEXTURE, UV) * COLOR;
}
