shader_type canvas_item;

/*
   LCD Transparency Shader - Combined version
   
   Combines:
   - zfast_lcd by SoltanGris42 (LCD grid with border darkening)
   - Pixel Transparency v1.1 by mattakins (transparent pixels simulation)
   
   Simulates non-backlit LCD screens where white/bright pixels appear
   transparent, showing the screen's background color/texture through them.
   
   Ported to Godot shader format by Macs
*/

// LCD Grid parameters (from zfast_lcd)
uniform float border_mult : hint_range(-40.0, 40.0, 1.0) = 14.0;
uniform float gba_gamma_hack : hint_range(0.0, 1.0, 1.0) = 1.0;

// Transparency parameters (from pixel_transparency)
uniform float transparency_enable : hint_range(0.0, 1.0, 1.0) = 1.0;
uniform float pixel_mode : hint_range(0.0, 2.0, 1.0) = 1.0; // 0=White only, 1=Bright, 2=All
uniform float base_alpha : hint_range(0.0, 1.0, 0.01) = 0.20;
uniform float white_threshold : hint_range(0.0, 1.0, 0.01) = 0.90;
uniform float white_boost_enable : hint_range(0.0, 1.0, 1.0) = 0.0;
uniform float white_transparency : hint_range(0.0, 1.0, 0.01) = 0.50;

// Background tint (0=off, 1=Pocket green, 2=Gray, 3=White)
uniform float palette_mode : hint_range(0.0, 3.0, 1.0) = 1.0;
uniform float palette_intensity : hint_range(0.0, 2.0, 0.05) = 1.0;

// Shadow parameters
uniform float shadow_enable : hint_range(0.0, 1.0, 1.0) = 1.0;
uniform vec2 shadow_offset = vec2(3.0, 3.0);
uniform float shadow_opacity : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float shadow_blur : hint_range(0.0, 5.0, 0.1) = 1.0;

uniform float SATURATION : hint_range(0.0, 2.0, 0.05) = 1.0;
uniform float STRENGTH : hint_range(0.0, 1.0, 0.01) = 1.0;

// ITU-R BT.709 luminance constants
const float LUMA_R = 0.2126;
const float LUMA_G = 0.7152;
const float LUMA_B = 0.0722;

// Perceptual brightness
float get_brightness(vec3 color) {
	return dot(color, vec3(LUMA_R, LUMA_G, LUMA_B));
}

// White pixel detection
bool is_white_pixel(vec3 color, float threshold) {
	float brightness = get_brightness(color);
	float min_channel = min(min(color.r, color.g), color.b);
	return (brightness > threshold && min_channel > threshold * 0.9);
}

// Paper grain noise
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float paper_noise(vec2 uv, float scale) {
	vec2 p = uv * scale * 512.0;
	float n = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;
	
	for (int i = 0; i < 3; i++) {
		n += hash(p * frequency) * amplitude;
		amplitude *= 0.5;
		frequency *= 2.0;
	}
	return n;
}

vec3 generate_background(vec2 uv) {
	const vec3 base_color = vec3(0.4773);
	const float grain_intensity = 0.065;
	const float scale = 0.25;
	
	float grain = paper_noise(uv, scale);
	float grain_offset = (grain - 0.4375) * grain_intensity;
	return base_color + vec3(grain_offset);
}

void fragment() {
	vec2 source_size = 1.0 / TEXTURE_PIXEL_SIZE;
	
	// === PASS 1: LCD Grid Effect (zfast_lcd) ===
	vec2 texcoord_in_pixels = UV * source_size;
	vec2 center_coord = floor(texcoord_in_pixels) + vec2(0.5);
	vec2 dist_from_center = abs(center_coord - texcoord_in_pixels);
	
	float Y = max(dist_from_center.x, dist_from_center.y);
	Y = Y * Y;
	float YY = Y * Y;
	float YYY = YY * Y;
	
	float line_weight = YY - 2.7 * YYY;
	line_weight = 1.0 - border_mult * line_weight;
	
	vec3 lcd_color = texture(TEXTURE, TEXTURE_PIXEL_SIZE * center_coord).rgb * line_weight;
	
	// GBA gamma hack
	if (gba_gamma_hack > 0.5) {
		lcd_color = lcd_color * (0.6 + 0.4 * lcd_color);
	}
	
	// === PASS 2: Pixel Transparency Effect ===
	vec3 original_pixel = texture(TEXTURE, UV).rgb;
	vec4 output_color = vec4(lcd_color, 1.0);
	
	if (transparency_enable > 0.5) {
		// Generate background with paper grain
		vec3 background = generate_background(UV);
		
		// Apply drop shadow
		if (shadow_enable > 0.5) {
			vec2 shadow_uv = UV + (shadow_offset * TEXTURE_PIXEL_SIZE);
			vec3 shadow_source = texture(TEXTURE, shadow_uv).rgb;
			
			if (!is_white_pixel(shadow_source, white_threshold)) {
				float shadow_brightness = get_brightness(shadow_source);
				float shadow_strength = (1.0 - shadow_brightness) * shadow_opacity;
				
				// Simple blur
				if (shadow_blur > 0.1) {
					float blur_dist = shadow_blur * TEXTURE_PIXEL_SIZE.x;
					float blurred = 0.0;
					
					for (int x = -1; x <= 1; x++) {
						for (int y = -1; y <= 1; y++) {
							vec2 offset = shadow_uv + vec2(float(x), float(y)) * blur_dist;
							vec3 sample_col = texture(TEXTURE, offset).rgb;
							blurred += (1.0 - get_brightness(sample_col));
						}
					}
					shadow_strength = (blurred / 9.0) * shadow_opacity;
				}
				
				background = mix(background, background * 0.2, shadow_strength);
			}
		}
		
		// Apply palette tint
		if (palette_mode > 0.5) {
			vec3 tint_color;
			if (palette_mode < 1.5) {
				tint_color = vec3(0.651, 0.675, 0.518); // Pocket green
			} else if (palette_mode < 2.5) {
				tint_color = vec3(0.737); // Gray
			} else {
				tint_color = vec3(1.0); // White
			}
			
			vec3 tinted = clamp(
				tint_color + mix(vec3(-1.0), vec3(1.0), background),
				0.0, 1.0
			);
			background = mix(background, tinted, palette_intensity);
		}
		
		// Apply transparency based on mode
		bool current_is_white = is_white_pixel(original_pixel, white_threshold);
		
		if (pixel_mode > 0.5 && pixel_mode < 1.5) {
			// Mode 1: Bright pixels
			float intensity = get_brightness(lcd_color);
			float transparency = (base_alpha * intensity) * 2.665;
			
			if (current_is_white && white_boost_enable > 0.5) {
				transparency = max(transparency, white_transparency);
			}
			transparency = clamp(transparency, 0.0, 1.0);
			output_color.rgb = mix(lcd_color, background, transparency);
		} else {
			// Mode 0 (white only) / Mode 2 (all)
			bool should_apply = (pixel_mode < 0.5) ? current_is_white : true;
			
			if (should_apply) {
				float intensity = get_brightness(lcd_color);
				float alpha = (intensity / 3.0) + base_alpha;
				
				if (current_is_white && white_boost_enable > 0.5) {
					alpha = max(alpha, white_transparency);
				}
				alpha = clamp(alpha, 0.0, 1.0);
				output_color.rgb = mix(lcd_color, background, alpha);
			}
		}
	}
	
	// Apply saturation
	vec3 gray_col = vec3(dot(output_color.rgb, vec3(0.299, 0.587, 0.114)));
	output_color.rgb = mix(gray_col, output_color.rgb, SATURATION);
	
	vec3 original = texture(TEXTURE, UV).rgb;
	COLOR = vec4(mix(original, output_color.rgb, STRENGTH), 1.0);
}
