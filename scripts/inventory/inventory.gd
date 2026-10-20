extends RefCounted
## The party's bag, Diablo 2 style: a grid of COLS x ROWS cells and items that each cover a rectangle of cells
## (Item.bag_size()). Pure logic, no nodes.
##
## An item is in the bag OR worn, never both: equipping takes it out of the grid, unequipping puts it back. Whatever
## an equip pushes off a slot has to fit in the grid, so callers ask can_fit_all() / find_space() first.
## Each Placement is one stack position. Two copies of the same Item resource are two placements.

const Item = preload("res://scripts/inventory/item.gd")

## Fired whenever a placement is added, moved or removed.
signal changed

const COLS := 8
const ROWS := 8
const NO_SPACE := Vector2i(-1, -1)

## One item and the top-left cell it sits on.
class Placement extends RefCounted:
	var item: Item
	var pos: Vector2i

	func _init(p_item: Item, p_pos: Vector2i) -> void:
		item = p_item
		pos = p_pos

	func size() -> Vector2i:
		return item.bag_size()

	func rect() -> Rect2i:
		return Rect2i(pos, item.bag_size())

var _placements: Array[Placement] = []

# --- queries ------------------------------------------------------------------

func placements() -> Array[Placement]:
	return _placements

## The placement covering `cell`, or null.
func placement_at(cell: Vector2i) -> Placement:
	for p in _placements:
		if p.rect().has_point(cell):
			return p
	return null

## Some placement of `item` (copies are interchangeable), or null.
func placement_of(item: Item) -> Placement:
	for p in _placements:
		if p.item == item:
			return p
	return null

## Does `item` fit with its top-left on `pos`? `ignoring` is a placement treated as already lifted out
## (the one being moved, or the one being equipped).
func can_place(item: Item, pos: Vector2i, ignoring: Placement = null) -> bool:
	return _fits(_occupancy(ignoring), item.bag_size(), pos)

## First free top-left (row by row) where `item` fits, or NO_SPACE.
func find_space(item: Item, ignoring: Placement = null) -> Vector2i:
	return _first_fit(_occupancy(ignoring), item.bag_size())

## Would every item in `items` fit together, placed one after another with the same first-fit rule add() uses?
func can_fit_all(items: Array, ignoring: Placement = null) -> bool:
	var occ := _occupancy(ignoring)
	for item: Item in items:
		var spot := _first_fit(occ, item.bag_size())
		if spot == NO_SPACE:
			return false
		_mark(occ, item.bag_size(), spot)
	return true

# --- changes ------------------------------------------------------------------

## Puts `item` with its top-left on `pos`. Null when it does not fit.
func place(item: Item, pos: Vector2i) -> Placement:
	if not can_place(item, pos):
		return null
	var p := Placement.new(item, pos)
	_placements.append(p)
	changed.emit()
	return p

## Puts `item` in the first free spot. Null when the bag has no room.
func add(item: Item) -> Placement:
	var spot := find_space(item)
	if spot == NO_SPACE:
		return null
	return place(item, spot)

func remove(p: Placement) -> void:
	if _placements.has(p):
		_placements.erase(p)
		changed.emit()

## Moves a placement to a new top-left. False (and nothing changes) when it does not fit there.
func move(p: Placement, pos: Vector2i) -> bool:
	if not can_place(p.item, pos, p):
		return false
	p.pos = pos
	changed.emit()
	return true

# --- grid helpers -------------------------------------------------------------

## One flag per cell, true = taken. `ignoring`'s cells count as free.
func _occupancy(ignoring: Placement = null) -> PackedByteArray:
	var occ := PackedByteArray()
	occ.resize(COLS * ROWS)
	for p in _placements:
		if p != ignoring:
			_mark(occ, p.size(), p.pos)
	return occ

static func _mark(occ: PackedByteArray, size: Vector2i, pos: Vector2i) -> void:
	for y in size.y:
		for x in size.x:
			occ[(pos.y + y) * COLS + pos.x + x] = 1

static func _fits(occ: PackedByteArray, size: Vector2i, pos: Vector2i) -> bool:
	if pos.x < 0 or pos.y < 0 or pos.x + size.x > COLS or pos.y + size.y > ROWS:
		return false
	for y in size.y:
		for x in size.x:
			if occ[(pos.y + y) * COLS + pos.x + x] != 0:
				return false
	return true

static func _first_fit(occ: PackedByteArray, size: Vector2i) -> Vector2i:
	for y in ROWS - size.y + 1:
		for x in COLS - size.x + 1:
			if _fits(occ, size, Vector2i(x, y)):
				return Vector2i(x, y)
	return NO_SPACE
