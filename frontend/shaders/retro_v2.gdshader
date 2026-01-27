shader_type canvas_item;

/*
   Hyllian - Retro Shader - 2013
   
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
uniform float RETRO_PIXEL_SIZE : hint_range(0.0, 1.0, 0.01) = 0.84;
uniform float SATURATION : hint_range(0.0, 2.0, 0.05) = 1.0;

void fragment() {
    // Get texture info (in Godot, TEXTURE_PIXEL_SIZE gives us 1/SourceSize)
    vec2 SourceSize = 1.0 / TEXTURE_PIXEL_SIZE;  // e.g., vec2(128.0, 128.0)
    vec2 OutputSize = 1.0 / SCREEN_PIXEL_SIZE;   // Screen resolution
    
    // Reading the texel with gamma correction (convert to linear space)
    vec3 texel_linear = pow(texture(TEXTURE, UV).rgb, vec3(2.4));
    
    // Calculate fractional position within pixel
    vec2 fp = fract(UV * SourceSize);
    
    // Calculate pixel scale (source pixels per output pixel)
    vec2 ps = SourceSize * SCREEN_PIXEL_SIZE;
    
    // Calculate fade factor for grid lines
    // This is the core algorithm from the original shader
    vec2 f = clamp(clamp(fp + 0.5 * ps, 0.0, 1.0) - RETRO_PIXEL_SIZE, vec2(0.0), ps) / ps;
    
    float max_coord = max(f.x, f.y);
    
    // Mix bright center (1.04 + fp.x*fp.y) with dark edges (0.36)
    vec3 res = mix(texel_linear * (1.04 + fp.x * fp.y), texel_linear * 0.36, max_coord);
    
    // Convert back to gamma space
    res = clamp(pow(res, vec3(1.0 / 2.2)), 0.0, 1.0);
    
    // Apply saturation
    vec3 gray = vec3(dot(res, vec3(0.299, 0.587, 0.114)));
    res = mix(gray, res, SATURATION);
    
    COLOR.rgb = res;
    COLOR.a = 1.0;
}
