shader_type canvas_item;

// LCD + GBC Color shader
// Original authors: jdgleaver, hunterk, Pokefan531, SoltanGris42
// License: GPL v2+
// Ported to Godot shader format by Macs
//
// A textured LCD shader for non-backlit handheld systems (Game Boy, GBC, etc.)
// Includes GBC color correction and optional paper texture background

// Adjustable parameters
uniform float grid_intensity : hint_range(0.0, 1.0, 0.05) = 0.15;
uniform float grid_width : hint_range(0.0, 1.0, 0.05) = 0.5;
uniform float grid_bias : hint_range(0.0, 1.0, 0.05) = 0.5;
uniform float darken_grid : hint_range(0.0, 1.0, 0.05) = 0.0;
uniform float darken_colour : hint_range(0.0, 2.0, 0.05) = 0.0;
uniform float background_intensity : hint_range(0.0, 1.0, 0.05) = 0.0;
uniform float lcd_background_blend : hint_range(0.0, 1.0, 0.05) = 0.8;
uniform float SATURATION : hint_range(0.0, 2.0, 0.05) = 1.0;

// LCD screen background color (yellowish-green tint of original GBC)
uniform vec3 lcd_bg_color : source_color = vec3(0.77, 0.82, 0.62);

// Optional background texture (paper/screen texture)
// If not provided, the background effect is disabled
uniform sampler2D background_texture : hint_default_white, filter_linear;

// Constants
const float LINE_WEIGHT_A = 48.0;
const float LINE_WEIGHT_B = 8.0 / 3.0;

// RGB -> Luminosity (ITU BT.709)
const float LUMA_R = 0.2126;
const float LUMA_G = 0.7152;
const float LUMA_B = 0.0722;

// GBC Color correction
const float TARGET_GAMMA = 2.2;
const float INV_DISPLAY_GAMMA = 1.0 / 2.2;
const float CC_LUM = 0.94;
const float CC_R = 0.82;
const float CC_G = 0.665;
const float CC_B = 0.73;
const float CC_RG = 0.125;
const float CC_RB = 0.195;
const float CC_GR = 0.24;
const float CC_GB = 0.075;
const float CC_BR = -0.06;
const float CC_BG = 0.21;

void fragment() {
	// Get pixel coordinates in texture space
	vec2 img_pixel_coord = UV / TEXTURE_PIXEL_SIZE;
	vec2 img_center_coord = floor(img_pixel_coord) + vec2(0.5);
	
	// Sample current pixel at center
	vec3 colour = texture(TEXTURE, TEXTURE_PIXEL_SIZE * img_center_coord).rgb;
	
	// Darken and apply GBC color correction
	colour = pow(colour, vec3(TARGET_GAMMA - 0.5 + darken_colour));
	colour = mat3(
		vec3(CC_R,  CC_RG, CC_RB),
		vec3(CC_GR, CC_G,  CC_GB),
		vec3(CC_BR, CC_BG, CC_B)
	) * (colour * CC_LUM);
	colour = clamp(pow(colour, vec3(INV_DISPLAY_GAMMA)), 0.0, 1.0);
	
	// Apply LCD background color blend (simulate non-backlit transparent LCD)
	// Bright pixels show the LCD's natural yellowish-green color
	float luma = dot(colour, vec3(LUMA_R, LUMA_G, LUMA_B));
	colour = mix(colour, colour * lcd_bg_color, luma * lcd_background_blend);
	
	// Generate grid pattern at pixel boundaries
	vec2 dist_from_center = abs(fract(img_pixel_coord) - vec2(0.5));
	
	// Use the maximum distance component (Manhattan distance to nearest edge)
	float x = max(dist_from_center.x, dist_from_center.y);
	float x_squared = x * x;
	float x_quarted = x_squared * x_squared;
	float x_sixth = x_quarted * x_squared;
	
	// Line weighting: y = 48 * (x^4 - (8/3) * x^6)
	float line_weight = LINE_WEIGHT_A * (x_quarted - (LINE_WEIGHT_B * x_sixth));
	
	// Apply grid width adjustment
	// grid_width controls line thickness (1.0 = thick, 0.0 = thin)
	line_weight = mix(line_weight * line_weight, line_weight, grid_width);
	
	// Apply grid intensity
	line_weight *= grid_intensity;
	
	// Apply grid bias based on pixel luminosity  
	// (darker pixels show less grid)
	luma = dot(colour, vec3(LUMA_R, LUMA_G, LUMA_B));
	line_weight *= mix(1.0, luma, grid_bias);
	
	// Apply grid pattern (mix with LCD background color instead of white)
	colour = mix(colour, lcd_bg_color * (1.0 - darken_grid), line_weight);
	
	// Apply background texture if background_intensity > 0
	if (background_intensity > 0.0) {
		// Sample background texture using screen coordinates
		vec2 bg_pixel_coord = floor(UV * (1.0 / SCREEN_PIXEL_SIZE)) + vec2(0.5);
		vec3 bg_texture = texture(background_texture, bg_pixel_coord * SCREEN_PIXEL_SIZE).rgb * colour;
		
		// Blend with background based on luminosity
		luma = dot(colour, vec3(LUMA_R, LUMA_G, LUMA_B));
		colour = mix(colour, bg_texture, luma * background_intensity);
	}
	
	// Apply saturation
	vec3 gray = vec3(dot(colour, vec3(0.299, 0.587, 0.114)));
	colour = mix(gray, colour, SATURATION);
	
	COLOR = vec4(colour, 1.0);
}
