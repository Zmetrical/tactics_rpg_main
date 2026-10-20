extends StyleBox
## The flat Game Boy Color frame: an ink border with its corners nicked (pixel-rounded), a flat face,
## and optionally a thin inner ring one pixel inside the border (the double line of the Pokemon text box).
## No bevel, no shadow, no gradient. Build it through hud_style.gd rather than by hand.

var face := Color("f8f8f8")
var edge := Color("181820")
var edge_w := 2
## Draw the inner ring.
var ring := false
var ring_color := Color("787880")

func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if edge_w > 0:
		if rect.size.x > 4.0 and rect.size.y > 4.0:
			_fill(to_canvas_item, Rect2(rect.position + Vector2(1.0, 0.0), rect.size - Vector2(2.0, 0.0)), edge)
			_fill(to_canvas_item, Rect2(rect.position + Vector2(0.0, 1.0), rect.size - Vector2(0.0, 2.0)), edge)
		else:
			_fill(to_canvas_item, rect, edge)
	var r := rect.grow(-float(edge_w))
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	_fill(to_canvas_item, r, face)
	if ring:
		var q := r.grow(-1.0)
		if q.size.x > 4.0 and q.size.y > 4.0:
			_fill(to_canvas_item, Rect2(q.position + Vector2(1.0, 0.0), Vector2(q.size.x - 2.0, 1.0)), ring_color)
			_fill(to_canvas_item, Rect2(Vector2(q.position.x + 1.0, q.end.y - 1.0), Vector2(q.size.x - 2.0, 1.0)), ring_color)
			_fill(to_canvas_item, Rect2(q.position + Vector2(0.0, 1.0), Vector2(1.0, q.size.y - 2.0)), ring_color)
			_fill(to_canvas_item, Rect2(Vector2(q.end.x - 1.0, q.position.y + 1.0), Vector2(1.0, q.size.y - 2.0)), ring_color)

func _fill(canvas_item: RID, rect: Rect2, color: Color) -> void:
	RenderingServer.canvas_item_add_rect(canvas_item, rect, color)
