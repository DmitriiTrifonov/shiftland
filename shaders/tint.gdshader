shader_type canvas_item;

// Body sprites are white silhouettes with alpha (see GDD §12.2).
// Treat the source texture as a pure alpha mask and paint it with tint_color,
// instead of shipping a separate texture per color/skin.
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(tint_color.rgb, tex.a * tint_color.a);
}
