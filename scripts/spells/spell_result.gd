extends RefCounted
## What a spell would do right now. The SAME object feeds the real resolution and the hover preview,
## so the two can never disagree.

## Rows of {"unit": Unit, "scale": float, "tag": String}, in the order they are struck.
var hits: Array[Dictionary] = []
## Rows of {"cell": Vector2i, "tag": String} for telegraphs and highlights.
## Tags: "main" (full strength), "echo" (reduced), "path" (the drawn route).
var cells: Array[Dictionary] = []

func add_hit(unit: Object, scale: float, tag: String = "") -> void:
	hits.append({"unit": unit, "scale": scale, "tag": tag})

func add_cell(cell: Vector2i, tag: String) -> void:
	cells.append({"cell": cell, "tag": tag})

func has_hit(unit: Object) -> bool:
	for h in hits:
		if h["unit"] == unit:
			return true
	return false

func units() -> Array:
	var out: Array = []
	for h in hits:
		out.append(h["unit"])
	return out

## unit -> damage multiplier, for Battle._resolve.
func scales() -> Dictionary:
	var out: Dictionary = {}
	for h in hits:
		out[h["unit"]] = h["scale"]
	return out

func cell_list() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for row in cells:
		out.append(row["cell"])
	return out

func tag_of_cell(cell: Vector2i) -> String:
	for row in cells:
		if row["cell"] == cell:
			return row["tag"]
	return ""
