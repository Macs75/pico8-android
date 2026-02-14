shader_type canvas_item;

/*
    zfast_crt_standard - A simple, fast CRT shader.

    Copyright (C) 2017 Greg Hogan (SoltanGris42)
    Ported to Godot shader form by Macs

    This program is free software; you can redistribute it and/or modify it
    under the terms of the GNU General Public License as published by the Free
    Software Foundation; either version 2 of the License, or (at your option)
    any later version.

Notes:  This shader does scaling with a weighted linear filter for adjustable
	sharpness on the x and y axes based on the algorithm by Inigo Quilez here:
	http://www.iquilezles.org/www/articles/texture/texture.htm
	but modified to be somewhat sharper. Then a scanline effect that varies
	based on pixel brightness is applied along with a monochrome aperture mask.
*/
/*
   PICO-8 ADAPTATION NOTES:
   
   Original shader was designed for higher resolution content (SNES ~224p+).
   PICO-8's 128x128 resolution requires much more subtle effects to avoid
   overwhelming the image with scanlines and mask artifacts.
   
   Parameter adjustments from original defaults:
   - BLURSCALEX: 0.30 → 0.20 (slightly sharper)
   - LOWLUMSCAN: 6.0 → 2.0 (much lighter scanlines on dark pixels)
   - HILUMSCAN: 8.0 → 3.0 (much lighter scanlines on bright pixels)
   - BRIGHTBOOST: 1.25 → 1.35 (compensate for brightness loss)
   - MASK_DARK: 0.25 → 0.10 (much subtler aperture mask)
   - MASK_FADE: 0.8 → 0.5 (reduced mask fade for consistency)
   
   Also changed aperture mask to use TextureSize instead of OutputSize
   to prevent visible banding on low-res content scaled to high-res displays.
*/

// Adjustable parameters (defaults tuned for PICO-8's low 128x128 resolution)
uniform float BLURSCALEX : hint_range(0.0, 1.0, 0.05) = 0.20;
uniform float LOWLUMSCAN : hint_range(0.0, 10.0, 0.5) = 2.0;
uniform float HILUMSCAN : hint_range(0.0, 50.0, 1.0) = 3.0;
uniform float BRIGHTBOOST : hint_range(0.5, 1.5, 0.05) = 1.35;
uniform float MASK_DARK : hint_range(0.0, 1.0, 0.05) = 0.10;
uniform float MASK_FADE : hint_range(0.0, 1.0, 0.05) = 0.5;
uniform float SATURATION : hint_range(0.0, 2.0, 0.05) = 1.0;
uniform float STRENGTH : hint_range(0.0, 1.0, 0.01) = 1.0;

// Use fine mask (comment out for coarser 3-pixel mask)
#define FINEMASK

void fragment() {
	// Get texture and output sizes
	vec2 TextureSize = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 OutputSize = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 invDims = TEXTURE_PIXEL_SIZE;
	
	float maskFade = 0.3333 * MASK_FADE;
	
	// Quilez scaling (sharper version)
	vec2 p = UV * TextureSize;
	vec2 i = floor(p) + 0.50;
	vec2 f = p - i;
	p = (i + 4.0 * f * f * f) * invDims;
	p.x = mix(p.x, UV.x, BLURSCALEX);
	
	float Y = f.y * f.y;
	float YY = Y * Y;
	
	// Aperture mask calculation - use texture pixels not screen pixels to avoid strong banding
	// For PICO-8's small resolution, we need a more subtle mask
	
#ifdef FINEMASK
	float whichmask = floor(UV.x * TextureSize.x) * -0.5;
	float mask = 1.0 + float(fract(whichmask) < 0.5) * -MASK_DARK;
#else
	float whichmask = floor(UV.x * TextureSize.x) * -0.3333;
	float mask = 1.0 + float(fract(whichmask) < 0.3333) * -MASK_DARK;
#endif
	
	// Sample texture
	vec3 colour = texture(TEXTURE, p).rgb;
	
	// Scanline weights
	float scanLineWeight = (BRIGHTBOOST - LOWLUMSCAN * (Y - 2.05 * YY));
	float scanLineWeightB = 1.0 - HILUMSCAN * (YY - 2.8 * YY * Y);
	
	// Final color with scanlines and mask
	colour = colour * mix(scanLineWeight * mask, scanLineWeightB, dot(colour, vec3(maskFade)));
	
	vec3 original = texture(TEXTURE, UV).rgb;
	// Apply saturation
	vec3 gray = vec3(dot(colour, vec3(0.299, 0.587, 0.114)));
	colour = mix(gray, colour, SATURATION);
	
	COLOR.rgb = mix(original, colour, STRENGTH);
	COLOR.a = 1.0;
}
