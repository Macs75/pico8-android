shader_type canvas_item;

/*
   LCD3x Shader
   Author: Gigaherz
   License: Public domain
   
   Ported to Godot shader format by Macs
*/

uniform float brighten_scanlines : hint_range(1.0, 32.0, 0.5) = 16.0;
uniform float brighten_lcd : hint_range(1.0, 12.0, 0.1) = 4.0;
uniform float SATURATION : hint_range(0.0, 2.0, 0.05) = 1.0;

void fragment() {
    // Get source texture size
    vec2 SourceSize = 1.0 / TEXTURE_PIXEL_SIZE;
    
    // Calculate omega (frequency for sine waves)
    vec2 omega = vec2(3.141592654) * vec2(2.0) * SourceSize;
    
    // RGB color channel offsets (for LCD subpixel effect)
    const vec3 offsets = vec3(3.141592654) * vec3(1.0/2.0, 1.0/2.0 - 2.0/3.0, 1.0/2.0 - 4.0/3.0);
    
    // Sample the texture
    vec3 res = texture(TEXTURE, UV).rgb;
    
    // Calculate angle for sine waves
    vec2 angle = UV * omega;
    
    // Scanline effect (vertical)
    float yfactor = (brighten_scanlines + sin(angle.y)) / (brighten_scanlines + 1.0);
    
    // LCD subpixel effect (horizontal, per color channel)
    vec3 xfactors = (brighten_lcd + sin(angle.x + offsets)) / (brighten_lcd + 1.0);
    
    // Combine effects
    vec3 color = yfactor * xfactors * res;
    
    // Apply saturation
    vec3 gray = vec3(dot(color, vec3(0.299, 0.587, 0.114)));
    color = mix(gray, color, SATURATION);
    
    COLOR = vec4(color, 1.0);
}
