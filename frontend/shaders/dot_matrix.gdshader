shader_type canvas_item;

// Dot Matrix shader
// Original author: Themaister
// License: Public domain
// Ported to Godot shader format by Macs

uniform float gamma : hint_range(0.0, 5.0, 0.05) = 2.4;
uniform float shine : hint_range(0.0, 0.5, 0.01) = 0.05;
uniform float blend : hint_range(0.0, 1.0, 0.01) = 0.65;
uniform float soft : hint_range(0.0, 1.0, 0.1) = 0.0;
uniform float SATURATION : hint_range(0.0, 2.0, 0.05) = 1.0;

varying vec2 pixel_no;
varying vec4 c00_10;
varying vec4 c20_01;
varying vec4 c21_02;
varying vec4 c12_22;
varying vec2 c11;

float dist_coord(vec2 coord, vec2 source) {
	vec2 delta = coord - source;
	return sqrt(dot(delta, delta));
}

float color_bloom(vec3 color) {
	const vec3 gray_coeff = vec3(0.30, 0.59, 0.11);
	float bright = dot(color, gray_coeff);
	return mix(1.0 + shine, 1.0 - shine, bright);
}

vec3 lookup(vec2 pix_no, float offset_x, float offset_y, vec3 color) {
	vec2 offset = vec2(offset_x, offset_y);
	float delta = dist_coord(fract(pix_no), offset + vec2(0.5, 0.5));
	return color * exp(-gamma * delta * color_bloom(color));
}

void vertex() {
	// Calculate pixel coordinates
	pixel_no = UV / TEXTURE_PIXEL_SIZE;
	vec2 d = TEXTURE_PIXEL_SIZE;
	
	// Pre-compute neighboring texture coordinates
	c00_10 = vec4((pixel_no + vec2(-1.0, -1.0) * soft) * d,
	              (pixel_no + vec2( 0.0, -1.0) * soft) * d);
	c20_01 = vec4((pixel_no + vec2( 1.0, -1.0) * soft) * d,
	              (pixel_no + vec2(-1.0,  0.0) * soft) * d);
	c21_02 = vec4((pixel_no + vec2( 1.0,  0.0) * soft) * d,
	              (pixel_no + vec2(-1.0,  1.0) * soft) * d);
	c12_22 = vec4((pixel_no + vec2( 0.0,  1.0) * soft) * d,
	              (pixel_no + vec2( 1.0,  1.0) * soft) * d);
	c11 = pixel_no * d;
}

void fragment() {
	vec3 mid_color = lookup(pixel_no, 0.0, 0.0, texture(TEXTURE, c11).rgb);
	vec3 color = vec3(0.0, 0.0, 0.0);
	
	color += lookup(pixel_no, -1.0, -1.0, texture(TEXTURE, c00_10.xy).rgb);
	color += lookup(pixel_no,  0.0, -1.0, texture(TEXTURE, c00_10.zw).rgb);
	color += lookup(pixel_no,  1.0, -1.0, texture(TEXTURE, c20_01.xy).rgb);
	color += lookup(pixel_no, -1.0,  0.0, texture(TEXTURE, c20_01.zw).rgb);
	color += mid_color;
	color += lookup(pixel_no,  1.0,  0.0, texture(TEXTURE, c21_02.xy).rgb);
	color += lookup(pixel_no, -1.0,  1.0, texture(TEXTURE, c21_02.zw).rgb);
	color += lookup(pixel_no,  0.0,  1.0, texture(TEXTURE, c12_22.xy).rgb);
	color += lookup(pixel_no,  1.0,  1.0, texture(TEXTURE, c12_22.zw).rgb);
	
	vec3 out_color = mix(1.2 * mid_color, color, blend);
	
	// Apply saturation
	vec3 gray = vec3(dot(out_color, vec3(0.299, 0.587, 0.114)));
	out_color = mix(gray, out_color, SATURATION);
	
	COLOR = vec4(out_color, 1.0);
}
