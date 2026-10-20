shader_type canvas_item;
// PS1-style finish for the whole 3D view. Runs as a full-screen pass over the finished 3D image
// (below the HUD), so the HUD, mouse picking and the camera are untouched.
//
//   1. LOW RES        every `virtual_height`-th of the screen becomes one chunky pixel. The screen is
//                     point-sampled at the pixel centre: no filtering, no smoothing, no anti-aliasing.
//                     Cells are a whole number of screen pixels so they are all the same size.
//   2. DITHER + DEPTH  colour is cut down to `color_levels` steps per channel (32 = the PS1's 15-bit
//                     colour) after adding a 4x4 Bayer pattern, exactly like the PS1's GPU dither.
//                     Smooth gradients (light falloff, fog, the sky) turn into the classic crosshatch
//                     instead of clean banding or smooth blends.
//
// The 4x4 pattern is laid on the LOW-RES pixel grid, so each dither dot is one chunky pixel.

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_nearest;
uniform float virtual_height = 270.0;   // vertical resolution of the look (1080 / 4 = 270)
uniform float color_levels = 32.0;      // steps per channel. 32 = PS1 15-bit, 16 = chunkier
uniform float dither_strength = 1.0;    // 0 = plain posterize, 1 = PS1 amount, >1 = rougher
uniform float pixelate_mix : hint_range(0.0, 1.0) = 1.0;  // 0 = native resolution
// Colour grade, applied BEFORE the colour cut so the dither works on the final colours.
uniform float brightness = 1.15;
uniform float contrast = 1.05;
uniform float saturation = 1.2;

const float BAYER4[16] = float[16](
	 0.0,  8.0,  2.0, 10.0,
	12.0,  4.0, 14.0,  6.0,
	 3.0, 11.0,  1.0,  9.0,
	15.0,  7.0, 13.0,  5.0
);

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;                       // real screen size in pixels
	float cell = max(floor(res.y / virtual_height + 0.5), 1.0);     // screen pixels per chunky pixel
	cell = mix(1.0, cell, pixelate_mix);

	vec2 cell_id = floor(FRAGCOORD.xy / cell);
	vec2 uv = (cell_id + 0.5) * cell / res;                   // centre of the chunky pixel
	vec3 c = texture(screen_tex, uv).rgb;

	ivec2 p = ivec2(int(mod(cell_id.x, 4.0)), int(mod(cell_id.y, 4.0)));
	float b = BAYER4[p.y * 4 + p.x];
	float threshold = (b + 0.5) / 16.0 - 0.5;                 // -0.47 .. +0.47 of one colour step

	c = (c - 0.5) * contrast + 0.5;
	c *= brightness;
	c = mix(vec3(dot(c, vec3(0.299, 0.587, 0.114))), c, saturation);

	float steps = max(color_levels - 1.0, 1.0);
	c = floor(c * steps + 0.5 + threshold * dither_strength) / steps;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
