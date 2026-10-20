shader_type canvas_item;
// Fakes a flat panel turned away from the camera, in 2D, with no filtering.
//
// The panel is first drawn flat into a SubViewport. This shader draws that texture onto a quad
// that is panel_size wide and (panel_size.y + lift) tall. Moving along x, the panel loses `taper`
// of its height and rises by `lift` pixels at the far edge, so it reads as a card in perspective.
// Every output pixel is mapped back to ONE source pixel (floor, no blending) and pixels outside the
// panel are discarded, so edges are hard staircases: no anti-aliasing, no smoothing.
// Set the node's texture_filter to Nearest as well.
//
// Forward map for a source pixel (sx, sy), with t = x / W (mirrored when the far edge is the left):
//   k  = 1 - taper * t                      height scale at this column
//   oy = (lift + H/2 - lift * t) + (sy - H/2) * k
// Inverted below so each OUTPUT pixel picks its source pixel.

uniform vec2 panel_size = vec2(320.0, 112.0);
uniform float lift = 16.0;
uniform float taper : hint_range(0.0, 0.5) = 0.16;
uniform bool far_is_right = true;

void fragment() {
	vec2 quad = vec2(panel_size.x, panel_size.y + lift);
	vec2 o = floor(UV * quad) + 0.5;
	float t = o.x / panel_size.x;
	if (!far_is_right) {
		t = 1.0 - t;
	}
	float k = 1.0 - taper * t;
	float center_y = lift + panel_size.y * 0.5 - lift * t;
	float sy = panel_size.y * 0.5 + (o.y - center_y) / k;
	if (sy < 0.0 || sy >= panel_size.y) {
		discard;
	}
	vec2 src = vec2(floor(o.x), floor(sy)) + 0.5;
	COLOR = texture(TEXTURE, src / panel_size);
}
