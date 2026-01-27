shader_type canvas_item;

/*
    Hyllian's CRT Shader

    Copyright (C) 2011-2016 Hyllian - sergiogdb@gmail.com
    Ported to Godot shader format by Macs

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
    THE SOFTWARE.
*/

/*
   PICO-8 ADAPTATION NOTES:
   
   Adjusted default parameters for PICO-8's 128x128 resolution:
   - BEAM_MIN_WIDTH: 0.86 → 0.90 (wider beam)
   - SHARPNESS: 1.0 → 2.0 (sharper)
   - BEAM_MAX_WIDTH: 1.0 (unchanged)
   - COLOR_BOOST: 1.5 → 1.3 (less aggressive color boost)
   - PHOSPHOR: 1.0 → 0.5 (subtler phosphor mask)
   - Removed horizontal scanlines option (VSCANLINES always 0)
   - Disabled phosphor mask by default for cleaner look on low-res content
*/

// Adjustable parameters (defaults tuned for PICO-8)
uniform float PHOSPHOR : hint_range(0.0, 1.0, 0.1) = 0.0;
uniform float InputGamma : hint_range(0.0, 5.0, 0.1) = 2.5;
uniform float OutputGamma : hint_range(0.0, 5.0, 0.1) = 2.2;
uniform float SHARPNESS : hint_range(1.0, 5.0, 0.1) = 2.0;
uniform float COLOR_BOOST : hint_range(1.0, 2.0, 0.05) = 1.3;
uniform float RED_BOOST : hint_range(1.0, 2.0, 0.01) = 1.0;
uniform float GREEN_BOOST : hint_range(1.0, 2.0, 0.01) = 1.0;
uniform float BLUE_BOOST : hint_range(1.0, 2.0, 0.01) = 1.0;
uniform float SCANLINES_STRENGTH : hint_range(0.0, 1.0, 0.02) = 0.50;
uniform float BEAM_MIN_WIDTH : hint_range(0.0, 1.0, 0.02) = 0.80;
uniform float BEAM_MAX_WIDTH : hint_range(0.0, 1.0, 0.02) = 0.95;
uniform float CRT_ANTI_RINGING : hint_range(0.0, 1.0, 0.1) = 0.8;
uniform float SATURATION : hint_range(0.0, 2.0, 0.05) = 1.0;

// Horizontal cubic filter constants
// Using Catmull-Rom Spline filter (B = 0.0, C = 0.5)
const float B = 0.0;
const float C = 0.5;

// Gamma functions
vec3 GAMMA_IN(vec3 color) {
    return pow(color, vec3(InputGamma));
}

vec3 GAMMA_OUT(vec3 color) {
    return pow(color, vec3(1.0 / OutputGamma));
}

void fragment() {
    vec2 TextureSize = vec2(SHARPNESS, 1.0) / TEXTURE_PIXEL_SIZE;
    vec2 OutputSize = 1.0 / SCREEN_PIXEL_SIZE;
    
    vec2 dx = vec2(1.0 / TextureSize.x, 0.0);
    vec2 dy = vec2(0.0, 1.0 / TextureSize.y);
    
    vec2 pix_coord = UV * TextureSize + vec2(-0.5, 0.5);
    vec2 tc = (floor(pix_coord) + vec2(0.5, 0.5)) / TextureSize;
    vec2 fp = fract(pix_coord);
    
    // Sample 8 neighbors for bicubic interpolation
    vec3 c00 = GAMMA_IN(texture(TEXTURE, tc - dx - dy).rgb);
    vec3 c01 = GAMMA_IN(texture(TEXTURE, tc - dy).rgb);
    vec3 c02 = GAMMA_IN(texture(TEXTURE, tc + dx - dy).rgb);
    vec3 c03 = GAMMA_IN(texture(TEXTURE, tc + 2.0*dx - dy).rgb);
    vec3 c10 = GAMMA_IN(texture(TEXTURE, tc - dx).rgb);
    vec3 c11 = GAMMA_IN(texture(TEXTURE, tc).rgb);
    vec3 c12 = GAMMA_IN(texture(TEXTURE, tc + dx).rgb);
    vec3 c13 = GAMMA_IN(texture(TEXTURE, tc + 2.0*dx).rgb);
    
    // Get min/max samples for anti-ringing
    vec3 min_sample = min(min(c01, c11), min(c02, c12));
    vec3 max_sample = max(max(c01, c11), max(c02, c12));
    
    // Bicubic filter matrix (column-major order for Godot)
    // Transposed from original row-major version
    mat4 invX = mat4(
        vec4((-B - 6.0*C)/6.0, (12.0 - 9.0*B - 6.0*C)/6.0, -(12.0 - 9.0*B - 6.0*C)/6.0, (B + 6.0*C)/6.0),
        vec4((3.0*B + 12.0*C)/6.0, (-18.0 + 12.0*B + 6.0*C)/6.0, (18.0 - 15.0*B - 12.0*C)/6.0, -C),
        vec4((-3.0*B - 6.0*C)/6.0, 0.0, (3.0*B + 6.0*C)/6.0, 0.0),
        vec4(B/6.0, (6.0 - 2.0*B)/6.0, B/6.0, 0.0)
    );
    
    // Apply horizontal cubic filter
    vec4 invX_Px = invX * vec4(fp.x*fp.x*fp.x, fp.x*fp.x, fp.x, 1.0);
    vec3 color0 = c00 * invX_Px.x + c01 * invX_Px.y + c02 * invX_Px.z + c03 * invX_Px.w;
    vec3 color1 = c10 * invX_Px.x + c11 * invX_Px.y + c12 * invX_Px.z + c13 * invX_Px.w;
    
    // Anti-ringing
    vec3 aux = color0;
    color0 = clamp(color0, min_sample, max_sample);
    color0 = mix(aux, color0, CRT_ANTI_RINGING);
    aux = color1;
    color1 = clamp(color1, min_sample, max_sample);
    color1 = mix(aux, color1, CRT_ANTI_RINGING);
    
    // Scanline calculation
    float pos0 = fp.y;
    float pos1 = 1.0 - fp.y;
    
    vec3 lum0 = mix(vec3(BEAM_MIN_WIDTH), vec3(BEAM_MAX_WIDTH), color0);
    vec3 lum1 = mix(vec3(BEAM_MIN_WIDTH), vec3(BEAM_MAX_WIDTH), color1);
    
    vec3 d0 = clamp(pos0 / (lum0 + 0.0000001), 0.0, 1.0);
    vec3 d1 = clamp(pos1 / (lum1 + 0.0000001), 0.0, 1.0);
    
    d0 = exp(-10.0 * SCANLINES_STRENGTH * d0 * d0);
    d1 = exp(-10.0 * SCANLINES_STRENGTH * d1 * d1);
    
    vec3 color = clamp(color0 * d0 + color1 * d1, 0.0, 1.0);
    
    // Color boost
    color *= COLOR_BOOST * vec3(RED_BOOST, GREEN_BOOST, BLUE_BOOST);
    
    // Phosphor mask (dot mask pattern)
    float mod_factor = UV.x * OutputSize.x;
    vec3 dotMaskWeights = mix(
        vec3(1.0, 0.7, 1.0),
        vec3(0.7, 1.0, 0.7),
        floor(mod(mod_factor, 2.0))
    );
    
    color.rgb *= mix(vec3(1.0), dotMaskWeights, PHOSPHOR);
    
    // Output gamma correction
    color = GAMMA_OUT(color);
    
    // Apply saturation
    vec3 gray = vec3(dot(color, vec3(0.299, 0.587, 0.114)));
    color = mix(gray, color, SATURATION);
    
    COLOR.rgb = color;
    COLOR.a = 1.0;
}
