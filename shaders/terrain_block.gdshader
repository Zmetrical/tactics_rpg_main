shader_type spatial;
render_mode specular_disabled;
// Draws one terrain block (a box whose origin is its x/z centre) from a 16x16 tile sheet.
//
//   top face   one tile per cell, chosen at random from `top_rect`, optionally flipped / rotated
//   side faces one tile column per face, chosen from `side_rect`; the tile is anchored to the
//              block's TOP edge, so a cliff always starts with its grass fringe and a block that
//              is only partly exposed shows the top part of the tile.
//
// Rects are in TILES on the sheet: (x, y, width, height). Which tiles go with which block is
// decided in scripts/battle/terrain_tiles.gd, not here.
//
// The choice is hashed from the cell position, so it is stable (no flicker, same every run) and
// works for GridMap's MultiMesh instances without any extra data.
//
// Everything that feeds the hash is a FLAT varying (identical for every pixel of a face). Never hash
// an interpolated value such as the normal: the hash is chaotic, so a one-ulp interpolation error
// picks a different tile per pixel and the side face tears into sub-texel noise.
//
// Sampling is done in whole texels (integer x/y inside the tile, then texel-centre fetches), so
// there are no fract() wrap-arounds that could flicker a row between two tiles.
//
// Anti-aliased pixels: each pixel blends the 4 nearest texels, but only across a band one SCREEN
// pixel(s) wide (`edge_px`) at the seam between texels ("sharp bilinear"). Up close the texels stay crisp, yet
// zooming in no longer shows hard stair-stepped blocks. Neighbour texels are looked up through the
// same tile logic and clamped to the tile, so nothing bleeds in from the next tile of the sheet.
// Set `smoothing` to 0 for the old pure-nearest look.

const int TILE_PX = 16;
const float TILE_PXF = 16.0;

uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
uniform ivec4 top_rect = ivec4(0, 0, 1, 1);
uniform ivec4 side_rect = ivec4(0, 0, 1, 1);
uniform bool top_flip = false;
uniform float block_height = 1.0;   // world units from the bottom face to the top face
uniform vec3 tint : source_color = vec3(1.0);
uniform float smoothing : hint_range(0.0, 1.0) = 0.0;   // 0 = hard PS1 texels, 1 = anti-aliased seams
uniform float edge_px : hint_range(0.5, 12.0) = 4.0;     // width of the soft seam between texels, in SCREEN pixels

varying vec3 v_pos;
varying flat vec2 v_cell;
// 0 = top, 1 = +x, 2 = -x, 3 = +z, 4 = -z, 5 = bottom. Taken from the vertex normal, so it is
// exactly the same number for every pixel of the face.
varying flat float v_face;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	v_pos = VERTEX;
	// Per-instance origin (the cell), rounded to kill float noise.
	v_cell = floor(MODEL_MATRIX[3].xz + 0.5);

	vec3 a = abs(NORMAL);
	float face = 0.0;
	if (a.y >= a.x && a.y >= a.z) {
		face = NORMAL.y > 0.0 ? 0.0 : 5.0;
	} else if (a.x >= a.z) {
		face = NORMAL.x > 0.0 ? 1.0 : 2.0;
	} else {
		face = NORMAL.z > 0.0 ? 3.0 : 4.0;
	}
	v_face = face;
}

// One texel of the block's face. `p` is the texel inside `tile` for the top face, or (column inside
// the tile, texel rows counted down from the block's top edge) for a side face. Out-of-range
// neighbours are clamped, so a blend never reaches into another tile of the sheet.
vec3 fetch_texel(int face, ivec4 rect, ivec2 tile, ivec2 p) {
	ivec2 t = tile;
	ivec2 q;
	q.x = clamp(p.x, 0, TILE_PX - 1);
	if (face == 0) {
		q.y = clamp(p.y, 0, TILE_PX - 1);
	} else {
		int iy = max(p.y, 0);
		int rows_px = rect.w * TILE_PX;
		if (iy >= rows_px) {
			// Taller than the tile rows we were given. Do NOT restart the tile (that would repeat its
			// top fringe halfway down the cliff). Instead ping-pong over the lower half of the last
			// row: it runs on from the last texel row and the joins are seamless.
			int m = (iy - rows_px) % TILE_PX;
			iy = rows_px - TILE_PX + (m < 8 ? 15 - m : m);
		}
		t.y = iy / TILE_PX;
		q.y = iy - t.y * TILE_PX;
	}
	t = clamp(t, ivec2(0), rect.zw - ivec2(1));
	ivec2 texel = (rect.xy + t) * TILE_PX + q;
	// Texel centre: no bleeding from neighbouring tiles.
	return textureLod(atlas, (vec2(texel) + 0.5) / vec2(textureSize(atlas, 0)), 0.0).rgb;
}

void fragment() {
	int face = int(v_face + 0.5);
	ivec4 rect;
	ivec2 tile;   // which tile of the rect (column, row) this pixel reads
	vec2 pf;      // continuous position in texels (top: inside the tile; side: x inside tile, y = rows down from the top edge)

	if (face == 0) {
		rect = top_rect;
		tile = ivec2(int(hash21(v_cell + 1.7) * float(rect.z)), int(hash21(v_cell + 9.1) * float(rect.w)));
		vec2 uv = v_pos.xz + 0.5;
		if (top_flip) {
			int o = int(hash21(v_cell + 4.3) * 8.0);
			if ((o & 1) != 0) { uv.x = 1.0 - uv.x; }
			if ((o & 2) != 0) { uv.y = 1.0 - uv.y; }
			if ((o & 4) != 0) { uv = uv.yx; }
		}
		pf = uv * TILE_PXF;
	} else {
		rect = side_rect;
		// Horizontal: 0..1 left to right as seen from OUTSIDE the face, so no face is mirrored.
		float along;
		if (face == 1) { along = -v_pos.z; }
		else if (face == 2) { along = v_pos.z; }
		else if (face == 3) { along = v_pos.x; }
		else { along = -v_pos.x; }
		tile.x = int(hash21(v_cell + vec2(float(face) * 7.31, float(face) * 3.17)) * float(rect.z));
		tile.y = 0;
		// Vertical: texel rows counted down from the block's top edge.
		float depth_px = max(block_height * 0.5 - v_pos.y, 0.0) * TILE_PXF;
		pf = vec2((along + 0.5) * TILE_PXF, depth_px);
	}

	vec3 c;
	if (smoothing <= 0.0) {
		// Pure nearest (the default): one texel fetch instead of four. Uniform branch, so it is free.
		c = fetch_texel(face, rect, tile, ivec2(floor(pf)));
	} else {
		// Sharp bilinear: blend width = one screen pixel measured in texels. Capped at 1 texel.
		vec2 box = clamp(fwidth(pf) * edge_px * smoothing, vec2(0.0001), vec2(1.0));
		vec2 tx = pf - 0.5 * box;
		ivec2 base = ivec2(floor(tx));
		vec2 w = smoothstep(vec2(1.0) - box, vec2(1.0), fract(tx));
		vec3 c00 = fetch_texel(face, rect, tile, base);
		vec3 c10 = fetch_texel(face, rect, tile, base + ivec2(1, 0));
		vec3 c01 = fetch_texel(face, rect, tile, base + ivec2(0, 1));
		vec3 c11 = fetch_texel(face, rect, tile, base + ivec2(1, 1));
		c = mix(mix(c00, c10, w.x), mix(c01, c11, w.x), w.y);
	}

	ALBEDO = c * tint;
	ROUGHNESS = 1.0;
}
