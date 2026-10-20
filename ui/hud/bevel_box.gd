extends StyleBox
## A chunky pixel bevel, drawn straight to the canvas so it works as any theme / override stylebox.
## Layers, outside in: optional drop shadow, ink edge (corners nicked for a pixel-rounded look), face,
## then a light line on the top + left and a shade line on the bottom + right. `inset` flips the
## light / shade so the surface looks pressed in (empty slots, bar troughs, pressed buttons).
## Build it through hud_style.gd rather than by hand.

var face := Color("e8ece4")
var edge := Color("181820")
var hi := Color("ffffff")
var lo := Color("a0a8a0")
var edge_w := 2
var bevel := 2
var inset := false
var chamfer := true
## Drop shadow thickness (down and right). It is drawn outside the control's rectangle.
var shadow := 0

func _get_draw_rect(rect: Rect2) -> Rect2:
	return Rect2(rect.position, rect.size + Vector2(shadow, shadow))

func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if shadow > 0:
		_fill(to_canvas_item, Rect2(rect.position + Vector2(shadow, shadow), rect.size), Color(0.0, 0.0, 0.0, 0.3))
	if edge_w > 0:
		if chamfer and rect.size.x > 4.0 and rect.size.y > 4.0:
			_fill(to_canvas_item, Rect2(rect.position + Vector2(1.0, 0.0), rect.size - Vector2(2.0, 0.0)), edge)
			_fill(to_canvas_item, Rect2(rect.position + Vector2(0.0, 1.0), rect.size - Vector2(0.0, 2.0)), edge)
		else:
			_fill(to_canvas_item, rect, edge)
	var r := rect.grow(-float(edge_w))
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	_fill(to_canvas_item, r, face)
	var b := float(bevel)
	if b <= 0.0 or r.size.x <= b * 2.0 or r.size.y <= b * 2.0:
		return
	var top_left := lo if inset else hi
	var bottom_right := hi if inset else lo
	_fill(to_canvas_item, Rect2(r.position, Vector2(r.size.x, b)), top_left)
	_fill(to_canvas_item, Rect2(r.position, Vector2(b, r.size.y)), top_left)
	_fill(to_canvas_item, Rect2(Vector2(r.position.x, r.end.y - b), Vector2(r.size.x, b)), bottom_right)
	_fill(to_canvas_item, Rect2(Vector2(r.end.x - b, r.position.y), Vector2(b, r.size.y)), bottom_right)

func _fill(canvas_item: RID, rect: Rect2, color: Color) -> void:
	RenderingServer.canvas_item_add_rect(canvas_item, rect, color)
