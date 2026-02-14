shader_type canvas_item;

/*
    CRT Shader by EasyMode
    License: GPL
    Ported to Godot shader format by Macs
    
    Features:
    - Gaussian blur for glow effects
    - Lanczos filtering for sharp edges
    - Configurable scanlines
    - RGB aperture grille mask
*/

/*
   PICO-8 ADAPTATION NOTES:
   
   This shader is quite demanding with multiple passes (gaussian blur + lanczos).
   Adjusted for PICO-8's 128x128 resolution:
   - SHARPNESS_IMAGE: 1.0 → 2.0 (sharper base image)
   - SHARPNESS_EDGES: 3.0 → 4.0 (sharper edges)
   - GLOW_WIDTH/HEIGHT: 0.5 → 0.3 (less blur for low-res)
   - GLOW_HALATION: 0.1 → 0.05 (subtler glow)
   - MASK_STRENGTH: 0.3 → 0.15 (much lighter aperture mask)
   - SCANLINE_SIZE_MIN: 0.5 → 0.6 (slightly wider scanlines)
   - BRIGHTNESS: 1.5 → 1.4 (less aggressive brightness boost)
*/

// Adjustable parameters (defaults tuned for PICO-8)
uniform float SHARPNESS_IMAGE : hint_range(1.0, 5.0, 1.0) = 2.0;
uniform float SHARPNESS_EDGES : hint_range(1.0, 5.0, 1.0) = 4.0;
uniform float GLOW_WIDTH : hint_range(0.05, 0.65, 0.05) = 0.3;
uniform float GLOW_HEIGHT : hint_range(0.05, 0.65, 0.05) = 0.3;
uniform float GLOW_HALATION : hint_range(0.0, 1.0, 0.01) = 0.05;
uniform float GLOW_DIFFUSION : hint_range(0.0, 1.0, 0.01) = 0.05;
uniform float MASK_COLORS : hint_range(2.0, 3.0, 1.0) = 2.0;
uniform float MASK_STRENGTH : hint_range(0.0, 1.0, 0.05) = 0.15;
uniform float MASK_SIZE : hint_range(1.0, 9.0, 1.0) = 1.0;
uniform float SCANLINE_SIZE_MIN : hint_range(0.5, 1.5, 0.05) = 0.6;
uniform float SCANLINE_SIZE_MAX : hint_range(0.5, 1.5, 0.05) = 1.5;
uniform float SCANLINE_SHAPE : hint_range(1.0, 100.0, 0.1) = 2.5;
uniform float SCANLINE_OFFSET : hint_range(0.0, 1.0, 1.0) = 1.0;
uniform float GAMMA_INPUT : hint_range(1.0, 5.0, 0.1) = 2.4;
uniform float GAMMA_OUTPUT : hint_range(1.0, 5.0, 0.1) = 2.4;
uniform float BRIGHTNESS : hint_range(0.0, 2.0, 0.05) = 1.4;
uniform float SATURATION : hint_range(0.0, 2.0, 0.05) = 1.0;
uniform float STRENGTH : hint_range(0.0, 1.0, 0.01) = 1.0;

vec3 TEX2D(sampler2D tex, vec2 c) {
    return pow(texture(tex, c).rgb, vec3(GAMMA_INPUT));
}

mat3 get_color_matrix(sampler2D tex, vec2 co, vec2 dx) {
    return mat3(TEX2D(tex, co - dx), TEX2D(tex, co), TEX2D(tex, co + dx));
}

vec3 blur(mat3 m, float dist, float rad) {
    vec3 x = vec3(dist - 1.0, dist, dist + 1.0) / rad;
    vec3 w = exp2(x * x * -1.0);
    return (m[0] * w.x + m[1] * w.y + m[2] * w.z) / (w.x + w.y + w.z);
}

vec3 filter_gaussian(sampler2D tex, vec2 co, vec2 tex_size) {
    vec2 dx = vec2(1.0 / tex_size.x, 0.0);
    vec2 dy = vec2(0.0, 1.0 / tex_size.y);
    vec2 pix_co = co * tex_size;
    vec2 tex_co = (floor(pix_co) + 0.5) / tex_size;
    vec2 dist = (fract(pix_co) - 0.5) * -1.0;
    
    mat3 line0 = get_color_matrix(tex, tex_co - dy, dx);
    mat3 line1 = get_color_matrix(tex, tex_co, dx);
    mat3 line2 = get_color_matrix(tex, tex_co + dy, dx);
    mat3 column = mat3(
        blur(line0, dist.x, GLOW_WIDTH),
        blur(line1, dist.x, GLOW_WIDTH),
        blur(line2, dist.x, GLOW_WIDTH)
    );
    
    return blur(column, dist.y, GLOW_HEIGHT);
}

vec3 filter_lanczos(sampler2D tex, vec2 co, vec2 tex_size, float sharp) {
    tex_size.x *= sharp;
    
    vec2 dx = vec2(1.0 / tex_size.x, 0.0);
    vec2 pix_co = co * tex_size - vec2(0.5, 0.0);
    vec2 tex_co = (floor(pix_co) + vec2(0.5, 0.001)) / tex_size;
    vec2 dist = fract(pix_co);
    vec4 coef = PI * vec4(dist.x + 1.0, dist.x, dist.x - 1.0, dist.x - 2.0);
    
    coef = max(abs(coef), vec4(1e-5));
    coef = 2.0 * sin(coef) * sin(coef / 2.0) / (coef * coef);
    coef /= dot(coef, vec4(1.0));
    
    vec4 col1 = vec4(TEX2D(tex, tex_co), 1.0);
    vec4 col2 = vec4(TEX2D(tex, tex_co + dx), 1.0);
    
    return (mat4(col1, col1, col2, col2) * coef).rgb;
}

vec3 get_scanline_weight(float x, vec3 col) {
    vec3 beam = mix(vec3(SCANLINE_SIZE_MIN), vec3(SCANLINE_SIZE_MAX), 
                    pow(col, vec3(1.0 / SCANLINE_SHAPE)));
    vec3 x_mul = 2.0 / beam;
    vec3 x_offset = x_mul * 0.5;
    
    return smoothstep(0.0, 1.0, 1.0 - abs(x * x_mul - x_offset)) * x_offset;
}

vec3 get_mask_weight(float x, vec2 OutputSize, vec2 SourceSize) {
    float i = mod(floor(x * OutputSize.x * SourceSize.x / (SourceSize.x * MASK_SIZE)), MASK_COLORS);
    
    if (i == 0.0) return mix(vec3(1.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0), MASK_COLORS - 2.0);
    else if (i == 1.0) return vec3(0.0, 1.0, 0.0);
    else return vec3(0.0, 0.0, 1.0);
}

void fragment() {
    vec2 SourceSize = 1.0 / TEXTURE_PIXEL_SIZE;
    vec2 OutputSize = 1.0 / SCREEN_PIXEL_SIZE;
    
    float scale = floor(OutputSize.y * TEXTURE_PIXEL_SIZE.y);
    float offset = 1.0 / scale * 0.5;
    
    if (mod(scale, 2.0) > 0.5) offset = 0.0;
    
    vec2 co = (UV * SourceSize - vec2(0.0, offset * SCANLINE_OFFSET)) / SourceSize;
    vec3 col_glow = filter_gaussian(TEXTURE, co, SourceSize);
    vec3 col_soft = filter_lanczos(TEXTURE, co, SourceSize, SHARPNESS_IMAGE);
    vec3 col_sharp = filter_lanczos(TEXTURE, co, SourceSize, SHARPNESS_EDGES);
    vec3 col = sqrt(col_sharp * col_soft);
    
    col *= get_scanline_weight(fract(co.y * SourceSize.y), col_soft);
    col_glow = clamp(col_glow - col, 0.0, 1.0);
    col += col_glow * col_glow * GLOW_HALATION;
    col = mix(col, col * get_mask_weight(UV.x, OutputSize, SourceSize) * MASK_COLORS, MASK_STRENGTH);
    col += col_glow * GLOW_DIFFUSION;
    col = pow(col * BRIGHTNESS, vec3(1.0 / GAMMA_OUTPUT));
    
    // Apply saturation
    vec3 gray = vec3(dot(col, vec3(0.299, 0.587, 0.114)));
    col = mix(gray, col, SATURATION);
    
    vec3 original = texture(TEXTURE, UV).rgb;
    COLOR.rgb = mix(original, col, STRENGTH);
    COLOR.a = 1.0;
}
