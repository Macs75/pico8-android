shader_type canvas_item;

/*
   Hyllian - Retro Shader V3 - 2022

   Ported to Godot shader format by Macs

   A re-implementation from the original made by Hyllian and DOLLS!
   
   This program is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License
   as published by the Free Software Foundation; either version 2
   of the License, or (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.
*/

// This value must be between 0.0 (totally black) and 1.0 (nearest neighbor)
uniform float RETRO_PIXEL_SIZE : hint_range(0.0, 1.0, 0.01) = 0.50;
uniform float RETRO_COLOR_BOOST : hint_range(1.0, 2.0, 0.01) = 1.36;
uniform float RETRO_GAMMA_IN : hint_range(1.0, 3.0, 0.05) = 2.20;
uniform float RETRO_GAMMA_OUT : hint_range(1.0, 3.0, 0.05) = 2.20;
uniform float SATURATION : hint_range(0.0, 2.0, 0.05) = 1.0;
uniform float STRENGTH : hint_range(0.0, 1.0, 0.01) = 1.0;

varying vec2 v_texcoord_scaled;

void vertex() {
	// Apply slight texture coordinate scaling to avoid edge artifacts
	v_texcoord_scaled = UV * 1.0001;
}

void fragment() {
	vec3 original = texture(TEXTURE, UV).rgb;
	vec2 SourceSize = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 OutputSize = 1.0 / SCREEN_PIXEL_SIZE;
	
	vec2 p = v_texcoord_scaled;
	
	// Convert to pixel coordinates
	p = p * SourceSize + vec2(0.5);
	
	// Quintic Hermite interpolation for smoother upscaling
	vec2 i = floor(p);
	vec2 f = p - i;
	f = f * f * f * (f * (f * 6.0 - vec2(15.0)) + vec2(10.0));
	p = i + f;
	
	// Convert back to UV coordinates
	p = (p - vec2(0.5)) / SourceSize;
	
	// Sample with gamma correction (convert to linear)
	vec3 sampled_color = pow(texture(TEXTURE, p).rgb, vec3(RETRO_GAMMA_IN));
	
	// Calculate fractional position and pixel scale
	vec2 fp = fract(p * SourceSize);
	vec2 ps = SourceSize * SCREEN_PIXEL_SIZE;
	
	// Calculate fade factor for grid lines
	vec2 fr = clamp(clamp(fp + 0.5 * ps, 0.0, 1.0) - RETRO_PIXEL_SIZE, vec2(0.0), ps) / ps;
	float max_coord = max(fr.x, fr.y);
	
	// Mix bright center with dark edges
	vec3 res = mix(sampled_color * (1.04 + fp.x * fp.y), sampled_color * 0.36, max_coord);
	
	// Apply color boost and gamma correction
	res = clamp(pow(RETRO_COLOR_BOOST * res, vec3(1.0 / RETRO_GAMMA_OUT)), 0.0, 1.0);
	
	// Apply saturation
	vec3 gray = vec3(dot(res, vec3(0.299, 0.587, 0.114)));
	res = mix(gray, res, SATURATION);
	
	COLOR = vec4(mix(original, res, STRENGTH), 1.0);
}
