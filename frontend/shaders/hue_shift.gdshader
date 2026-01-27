shader_type canvas_item;

/*
    Hue Shift Shader
    
    Shifts the hue of all pixels in HSV color space.
    This properly maintains color relationships in multi-color images,
    unlike simple RGB multiplication (self_modulate).
    
    Usage: Set hue_shift parameter to rotate hue (-180 to +180 degrees)
    - 0 = Original colors
    - Positive values = Shift clockwise through color wheel
    - Negative values = Shift counter-clockwise through color wheel
*/

uniform float hue_shift : hint_range(-180.0, 180.0, 1.0) = 0.0;
uniform float saturation_mult : hint_range(0.0, 2.0, 0.05) = 1.0;
uniform float lightness_mult : hint_range(0.0, 2.0, 0.05) = 1.0;

// Convert RGB to HSV
vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// Convert HSV to RGB
vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
    // Sample the texture
    vec4 color = texture(TEXTURE, UV);
    
    // If all adjustments are at default, use original color (optimization)
    if (abs(hue_shift) < 0.001 && abs(saturation_mult - 1.0) < 0.001 && abs(lightness_mult - 1.0) < 0.001) {
        COLOR = color;
    } else {
        // Convert to HSV
        vec3 hsv = rgb2hsv(color.rgb);
        
        // Shift the hue (convert degrees to 0-1 range)
        hsv.x = fract(hsv.x + hue_shift / 360.0);
        
        // Adjust saturation (multiply and clamp)
        hsv.y = clamp(hsv.y * saturation_mult, 0.0, 1.0);
        
        // Adjust lightness/value (multiply and clamp)
        hsv.z = clamp(hsv.z * lightness_mult, 0.0, 1.0);
        
        // Convert back to RGB
        vec3 shifted = hsv2rgb(hsv);
        
        // Output with original alpha
        COLOR = vec4(shifted, color.a);
    }
}
