shader_type canvas_item;

/*
    crt-1tap v1.2 by fishku
    Copyright (C) 2023
    Public domain license (CC0)
    Ported to Godot shader format by Macs

    Extremely fast and lightweight dynamic scanline shader.
    Contrasty and sharp output. Easy to configure.
    Can be combined with other shaders.

    How it works: Uses a single texture "tap" per pixel, hence the name.
    Exploits bilinear interpolation plus local coordinate distortion to shape
    the scanline. A pseudo-sigmoid function with a configurable slope at the
    inflection point is used to control horizontal smoothness.
    Uses a clamped linear function to anti-alias the edge of the scanline while
    avoiding further branching. The final thickness is shaped with a gamma-like
    operation to control overall image contrast.
    The scanline subpixel position can be controlled to achieve the best
    sharpness and uniformity of the output given different input sizes, e.g.,
    for even and odd integer scaling.
*/

/*
   PICO-8 ADAPTATION NOTES:
   
   This shader is extremely lightweight and well-suited for PICO-8.
   Adjusted for better visibility on 128x128 resolution:
   - MIN_THICK: 0.3 → 0.4 (slightly thicker minimum scanlines)
   - MAX_THICK: 0.9 → 1.0 (allow full brightness)
   - V_SHARP: 0.5 → 0.6 (slightly sharper scanlines)
   - SUBPX_POS: 0.3 → 0.35 (optimized for integer scaling)
*/

// Adjustable parameters (defaults tuned for PICO-8)
uniform float MIN_THICK : hint_range(0.0, 1.4, 0.05) = 0.4;
uniform float MAX_THICK : hint_range(0.0, 1.4, 0.05) = 1.0;
uniform float V_SHARP : hint_range(0.0, 1.0, 0.05) = 0.6;
uniform float H_SHARP : hint_range(0.0, 1.0, 0.05) = 0.15;
uniform float SUBPX_POS : hint_range(-0.5, 0.5, 0.01) = 0.35;
uniform float THICK_FALLOFF : hint_range(0.2, 2.0, 0.05) = 0.65;
uniform float SATURATION : hint_range(0.0, 2.0, 0.05) = 1.0;
uniform float STRENGTH : hint_range(0.0, 1.0, 0.01) = 1.0;

void fragment() {
    vec2 SourceSize = 1.0 / TEXTURE_PIXEL_SIZE;
    
    float src_x_int;
    float src_x_fract = fract(UV.x * SourceSize.x - 0.5);
    src_x_int = floor(UV.x * SourceSize.x - 0.5);
    
    float src_y_int;
    float src_y_fract = fract(UV.y * SourceSize.y - SUBPX_POS) - 0.5;
    src_y_int = floor(UV.y * SourceSize.y - SUBPX_POS);
    
    // Function similar to smoothstep and sigmoid
    float s = sign(src_x_fract - 0.5);
    float o = (1.0 + s) * 0.5;
    float src_x = src_x_int + o - 0.5 * s * pow(2.0 * (o - s * src_x_fract), mix(1.0, 6.0, H_SHARP));
    
    vec3 signal = texture(TEXTURE, vec2((src_x + 0.5) * TEXTURE_PIXEL_SIZE.x,
                                        (src_y_int + 0.5) * TEXTURE_PIXEL_SIZE.y)).rgb;
    
    // Vectorize operations for speed
    float eff_v_sharp = 3.0 + 50.0 * V_SHARP * V_SHARP;
    vec3 radius = pow(mix(vec3(MIN_THICK), vec3(MAX_THICK), signal), vec3(THICK_FALLOFF)) * 0.5;
    
    vec3 col = signal * clamp(0.25 - eff_v_sharp * (src_y_fract * src_y_fract - radius * radius), 0.0, 1.0);
    
    // Apply saturation
    vec3 gray = vec3(dot(col, vec3(0.299, 0.587, 0.114)));
    col = mix(gray, col, SATURATION);
    
    vec3 original = texture(TEXTURE, UV).rgb;
    COLOR.rgb = mix(original, col, STRENGTH);
    COLOR.a = 1.0;
}
