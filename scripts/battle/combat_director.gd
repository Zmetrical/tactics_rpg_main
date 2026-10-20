extends Node
## Seamless on-map combat ("grid-based attack execution").
##
## No battle scene swap. The camera stays in its isometric view, pushes in a little on the
## action, and every attack plays out directly on the tile layout:
##   toast -> camera focus -> windup -> strike / projectile / spell -> impact -> recovery -> release
##
## Rules never wait on this node's visuals. Battle resolves an action instantly and emits
## `action_executed`; the director queues it and plays it back while `battle.presenting` is true
## (input, enemy AI and turn changes wait on that flag). Everything drawn here is a placeholder
## built in code (tinted quads, spheres, rings, particles, labels): swap the bodies of the
## small `_make_*` / `_burst` / `_slash` helpers for real sprites or particles later without
## touching the sequencing.
##
## Feel knobs live at the top: the @export switches, then the timing constants.

const Ability = preload("res://scripts/battle/ability.gd")
const Battle = preload("res://scripts/battle/battle.gd")
const Grid = preload("res://scripts/battle/grid.gd")
const Stage3D = preload("res://scripts/battle/stage_3d.gd")
const Unit = preload("res://scripts/battle/unit.gd")

## How an ability is staged on the map.
enum Kind {
	MELEE,   ## range 1: wind back, lunge into the target
	ARROW,   ## weapon at range: draw, arrow flies
	BOLT,    ## single-target magic at range: magic circle, orb flies
	BURST,   ## area magic: tiles light up, orb lobs in, shockwave across the area
}

## Emitted once the queue is empty and the camera is released.
signal finished
## A victim's HP has just visibly changed (hit landed or miss resolved): the HUD refreshes its panel.
signal unit_hit(unit: Unit)
signal _impacts_done

# --- Feel switches (editable on the node, or set from code) -------------------
@export_group("Switches")
## Off = no animation at all: HP labels and deaths update instantly, like before this system.
@export var enabled := true
@export var camera_focus_enabled := true
@export var hit_stop_enabled := true
@export var shake_enabled := true
@export var show_toast := true
@export_group("Pace")
## 1.0 = normal. 2.0 = everything twice as fast.
@export var speed := 1.0
## Holding SPACE multiplies speed by this, so a long enemy phase can be skimmed.
@export var fast_forward_mult := 2.5
## Camera distance multiplier while an action plays (< 1 = push in).
@export var focus_zoom := 0.78

# --- Timing (seconds at speed 1.0) ---------------------------------------------
const CAMERA_IN_TIME := 0.28
const CAMERA_OUT_TIME := 0.35
const CAMERA_HOLD_AFTER := 0.3     # how long the framing stays after the last impact, before the camera lets go
const CAMERA_SETTLE_WAIT := 0.18   # how long to wait on the pan before the windup starts
const MELEE_WINDUP := 0.16
const MELEE_STRIKE := 0.07
const MELEE_BACKSWING := 0.16      # how far the attacker leans back, in tiles
const MELEE_LUNGE_MAX := 0.65      # how far toward the target the lunge travels, in tiles
const ARROW_WINDUP := 0.18
const SPELL_WINDUP := 0.42
const RECOVER_TIME := 0.2
const AFTER_IMPACT_LINGER := 0.12
const IMPACT_STAGGER := 0.07       # per tile of distance from an area's centre
const TILE_FX_LIFT := 0.025
const TOAST_FADE := 0.15

# --- Hit feel ----------------------------------------------------------------
const STOP_NORMAL := 0.06          # real seconds the game freezes on a hit
const STOP_CRIT := 0.12
const STOP_KILL := 0.10
const SLOWMO_KILL_TIME := 0.35     # real seconds of slow motion after a killing blow
const SLOWMO_KILL_SCALE := 0.25
const STOP_SCALE := 0.04           # Engine.time_scale during a freeze
const SHAKE_HIT := 0.10
const SHAKE_CRIT := 0.28
const SHAKE_KILL := 0.34
const SHAKE_BURST := 0.18
const KNOCKBACK_DIST := 0.28

# --- Placeholder colours ---------------------------------------------------------
const COLOR_WEAPON := Color(1.0, 0.92, 0.6)
const COLOR_TARGET_TILE := Color(1.0, 0.3, 0.2)
const COLOR_MISS := Color(0.75, 0.75, 0.8)
const SPELL_COLORS: Array[Color] = [
	Color(1.0, 0.55, 0.15), Color(0.35, 0.75, 1.0), Color(0.75, 0.45, 1.0),
	Color(0.4, 1.0, 0.55), Color(1.0, 0.4, 0.55), Color(1.0, 0.9, 0.3),
]

var stage: Stage3D
var battle: Battle
## True from the moment an action is queued until the camera is released.
var busy := false

var _queue: Array[Dictionary] = []
var _running := false
var _fx_root: Node3D
var _toast_panel: PanelContainer
var _toast_label: Label
var _toast_tween: Tween
var _stop_count := 0
var _impacts_left := 0
var _tile_mesh: PlaneMesh
var _slash_tex: ImageTexture
var _circle_tex: ImageTexture

func setup(p_stage: Stage3D, p_battle: Battle) -> void:
	stage = p_stage
	battle = p_battle
	_fx_root = Node3D.new()
	_fx_root.name = "CombatFx"
	stage.add_child(_fx_root)
	_tile_mesh = PlaneMesh.new()
	_tile_mesh.size = Vector2(Stage3D.HIGHLIGHT_SIZE, Stage3D.HIGHLIGHT_SIZE)
	_build_toast()
	battle.action_executed.connect(_on_action_executed)
	battle.cast_cancelled.connect(_on_cast_cancelled)
	_prewarm()

func _exit_tree() -> void:
	Engine.time_scale = 1.0

# =============================================================================
# Pure helpers (static, no scene needed: these are what the tests cover)
# =============================================================================

static func classify(a: Ability) -> int:
	if a.area_radius > 0:
		return Kind.BURST
	if a.range_tiles <= 1:
		return Kind.MELEE
	return Kind.BOLT if is_magic(a) else Kind.ARROW

## Spell slots, saves, auto-damage and INT / WIS attacks read as magic; the rest as weapons.
static func is_magic(a: Ability) -> bool:
	return a.slot_level > 0 or a.roll != Ability.Roll.ATTACK or a.stat >= Ability.Stat.INT

static func ability_color(a: Ability) -> Color:
	if not is_magic(a):
		return COLOR_WEAPON
	return SPELL_COLORS[absi(a.display_name.hash()) % SPELL_COLORS.size()]

## True when the victim actually took damage (decides hit-stop, shake, knockback vs. dodge).
static func landed(result: Dictionary) -> bool:
	return int(result["amount"]) > 0

## What floats over a victim: {"kind", "text", "color", "size"}. Kinds: miss, crit, hit, resist, save_fail.
static func describe_result(result: Dictionary) -> Dictionary:
	var info: Dictionary = result["info"]
	var amount := int(result["amount"])
	if info.has("hit"):
		if not info["hit"]:
			return {"kind": "miss", "text": "MISS", "color": COLOR_MISS, "size": 1.0}
		if info["crit"]:
			return {"kind": "crit", "text": "%d!" % amount, "color": Color(1.0, 0.85, 0.2), "size": 1.6}
		return {"kind": "hit", "text": str(amount), "color": Color.WHITE, "size": 1.0}
	if info.has("success"):
		if info["success"]:
			var text := "RESIST" if amount <= 0 else str(amount)
			return {"kind": "resist", "text": text, "color": Color(0.55, 0.9, 1.0), "size": 0.9}
		return {"kind": "save_fail", "text": str(amount), "color": Color(1.0, 0.72, 0.4), "size": 1.1}
	return {"kind": "hit", "text": str(amount), "color": Color.WHITE, "size": 1.0}

# =============================================================================
# Queue
# =============================================================================

func _on_action_executed(user: Unit, ability: Ability, cell: Vector2i, results: Array, tag: String) -> void:
	if not _can_animate():
		_apply_instant(results)
		return
	_enqueue({"type": "action", "user": user, "ability": ability, "cell": cell, "results": results, "tag": tag})

func _on_cast_cancelled(cast: Battle.PendingCast, reason: String) -> void:
	# Only a spell that resolves onto nothing is worth a beat. Losing caster / target is silent.
	if reason != "fizzle" or not _can_animate():
		return
	_enqueue({"type": "fizzle", "ability": cast.ability, "cell": cast.cell, "caster": cast.caster})

func _can_animate() -> bool:
	return enabled and stage != null and battle != null and is_inside_tree()

## Disabled / headless path: land the numbers and the deaths with no animation.
func _apply_instant(results: Array) -> void:
	if stage == null:
		return
	for r: Dictionary in results:
		var u: Unit = r["unit"]
		if not stage.has_unit(u):
			continue
		stage.update_hp(u, int(r["hp_after"]))
		if r["died"]:
			stage.hide_unit(u)

func _enqueue(ev: Dictionary) -> void:
	_queue.append(ev)
	# Set synchronously: Battle's very next lines (AI end_turn, next turn) must already see it.
	busy = true
	battle.presenting = true
	if not _running:
		_run_queue()

func _run_queue() -> void:
	_running = true
	while not _queue.is_empty():
		var ev: Dictionary = _queue.pop_front()
		match ev["type"]:
			"action":
				await _play_action(ev)
			"fizzle":
				await _play_fizzle(ev)
	_hide_toast()
	if camera_focus_enabled:
		await _wait(CAMERA_HOLD_AFTER)   # hold the framing while the HUD still shows the victim
		stage.camera_release(CAMERA_OUT_TIME / _spd())
	# Order matters: flags drop first so whatever Battle does on presentation_finished
	# (begin the next turn, run the AI) sees an idle director.
	_running = false
	busy = false
	battle.presenting = false
	finished.emit()

# =============================================================================
# One action
# =============================================================================

func _play_action(ev: Dictionary) -> void:
	var user: Unit = ev["user"]
	var ability: Ability = ev["ability"]
	var cell: Vector2i = ev["cell"]
	var results: Array = ev["results"]
	var tag: String = ev["tag"]
	if not stage.has_unit(user):
		_apply_instant(results)
		return

	var kind := classify(ability)
	var color := ability_color(ability)
	for u in _participants(user, results):
		stage.settle_unit(u)

	var origin := stage.unit_rest(user)
	var center := stage.cell_top(cell)
	var primary := _primary_chest(results, center)
	var ctx := {
		"kind": kind, "color": color, "user": user, "ability": ability,
		"origin": origin, "center": center, "center_cell": cell,
	}

	_show_toast("Opportunity Attack" if tag == "reaction" else ability.display_name)
	_focus_camera(origin, center, kind)
	await _wait(CAMERA_SETTLE_WAIT)
	stage.face_toward(user, center)

	var dir := _flat_dir(origin, center)
	match kind:
		Kind.MELEE:
			await _stage_melee(user, origin, center, dir, cell)
		Kind.ARROW:
			await _stage_arrow(user, origin, primary, dir, results, cell, color)
		Kind.BOLT:
			await _stage_bolt(user, origin, primary, results, cell, color)
		Kind.BURST:
			await _stage_burst(user, origin, center, cell, ability, color)

	await _run_impacts(results, ctx)
	await _recover(user, origin)
	await _wait(AFTER_IMPACT_LINGER)
	for u in _participants(user, results):
		if stage.has_unit(u) and u.is_alive():
			stage.settle_unit(u)

func _participants(user: Unit, results: Array) -> Array[Unit]:
	var out: Array[Unit] = []
	if stage.has_unit(user):
		out.append(user)
	for r: Dictionary in results:
		var u: Unit = r["unit"]
		if stage.has_unit(u) and not out.has(u):
			out.append(u)
	return out

## Where projectiles aim: the first victim's chest, or the tile for an empty area.
func _primary_chest(results: Array, fallback: Vector3) -> Vector3:
	for r: Dictionary in results:
		var u: Unit = r["unit"]
		if stage.has_unit(u):
			return stage.unit_chest(u)
	return fallback + Vector3(0.0, 0.5, 0.0)

func _focus_camera(origin: Vector3, center: Vector3, kind: int) -> void:
	if not camera_focus_enabled:
		return
	var gap := _flat_dist(origin, center)
	var mid := origin.lerp(center, 0.65 if kind == Kind.BURST else 0.5)
	# Long shots stay wider so both ends of the action are in frame.
	var zoom := lerpf(focus_zoom, 1.0, clampf((gap - 2.0) / 5.0, 0.0, 1.0))
	stage.camera_focus(mid, zoom, CAMERA_IN_TIME / _spd())

# --- Staging per kind ---------------------------------------------------------

func _stage_melee(user: Unit, origin: Vector3, center: Vector3, dir: Vector3, cell: Vector2i) -> void:
	var lunge := clampf(_flat_dist(origin, center) - 0.5, 0.0, MELEE_LUNGE_MAX)
	_flash_tile(cell, COLOR_TARGET_TILE, MELEE_WINDUP + MELEE_STRIKE + 0.2, 0.45)
	await _move_holder(user, origin - dir * MELEE_BACKSWING, MELEE_WINDUP, Tween.TRANS_SINE, Tween.EASE_OUT)
	await _move_holder(user, origin + dir * lunge, MELEE_STRIKE, Tween.TRANS_CUBIC, Tween.EASE_IN)

func _stage_arrow(user: Unit, origin: Vector3, aim: Vector3, dir: Vector3, results: Array, cell: Vector2i, color: Color) -> void:
	_flash_tile(cell, COLOR_TARGET_TILE, ARROW_WINDUP + 0.3, 0.45)
	await _move_holder(user, origin - dir * 0.1, ARROW_WINDUP, Tween.TRANS_SINE, Tween.EASE_OUT)
	# A miss grazes past the target instead of hitting it.
	var end := aim
	if not results.is_empty() and not landed(results[0]):
		var side := dir.cross(Vector3.UP)
		end = aim + side * 0.5 + dir * 0.2
	var from := stage.unit_chest(user)
	_recoil(user, origin, dir)
	await _fly(from, end, clampf(from.distance_to(end) * 0.045, 0.16, 0.45), 0.25, color, true)

func _stage_bolt(user: Unit, origin: Vector3, aim: Vector3, results: Array, cell: Vector2i, color: Color) -> void:
	_flash_tile(cell, COLOR_TARGET_TILE, SPELL_WINDUP + 0.3, 0.4)
	var circle := _magic_circle(origin, color, SPELL_WINDUP + 0.2)
	_cast_pose(user, color)
	await _wait(SPELL_WINDUP)
	var from := stage.unit_chest(user)
	var end := aim
	if not results.is_empty() and not landed(results[0]):
		end = aim + _side_of(origin, aim) * 0.5
	_fade_out_free(circle, 0.15, &"circle")
	await _fly(from, end, clampf(from.distance_to(end) * 0.05, 0.18, 0.5), 0.2, color, false)

func _stage_burst(user: Unit, origin: Vector3, center: Vector3, cell: Vector2i, ability: Ability, color: Color) -> void:
	var telegraph := _telegraph(_area_cells(cell, ability.area_radius), color, SPELL_WINDUP)
	var circle := _magic_circle(origin, color, SPELL_WINDUP + 0.3)
	_cast_pose(user, color)
	await _wait(SPELL_WINDUP)
	_fade_out_free(circle, 0.15, &"circle")
	var from := stage.unit_chest(user)
	var to := center + Vector3(0.0, 0.1, 0.0)
	var gap := from.distance_to(to)
	await _fly(from, to, clampf(0.25 + gap * 0.04, 0.3, 0.6), 1.2 + gap * 0.1, color, false)
	_ring(center, color, 0.3, ability.area_radius + 0.8, 0.5)
	_burst(center + Vector3(0.0, 0.2, 0.0), color, true)
	if shake_enabled:
		stage.camera_shake(SHAKE_BURST, 0.3)
	for q in telegraph:
		_fade_out_free(q, 0.25, &"quad")

func _play_fizzle(ev: Dictionary) -> void:
	var ability: Ability = ev["ability"]
	var cell: Vector2i = ev["cell"]
	var center := stage.cell_top(cell)
	_show_toast("%s fizzles" % ability.display_name)
	if camera_focus_enabled:
		stage.camera_focus(center, lerpf(focus_zoom, 1.0, 0.4), CAMERA_IN_TIME / _spd())
	await _wait(CAMERA_SETTLE_WAIT)
	for c in _area_cells(cell, ability.area_radius):
		_flash_tile(c, COLOR_MISS, 0.5, 0.4)
	_float_text(center + Vector3(0.0, 0.4, 0.0), {"text": "FIZZLE", "color": COLOR_MISS, "size": 1.0})
	await _wait(0.5)

# =============================================================================
# Impact
# =============================================================================

func _run_impacts(results: Array, ctx: Dictionary) -> void:
	var live: Array[Dictionary] = []
	for r: Dictionary in results:
		if stage.has_unit(r["unit"]):
			live.append(r)
	if live.is_empty():
		return
	_impacts_left = live.size()
	for r in live:
		var delay := 0.0
		if ctx["kind"] == Kind.BURST:
			var u: Unit = r["unit"]
			delay = IMPACT_STAGGER * Grid.distance(u.cell, ctx["center_cell"])
		_impact(r, ctx, delay)
	if _impacts_left > 0:
		await _impacts_done

func _impact(r: Dictionary, ctx: Dictionary, delay: float) -> void:
	if delay > 0.0:
		await _wait(delay)
	await _impact_visuals(r, ctx)
	_impacts_left -= 1
	if _impacts_left <= 0:
		_impacts_done.emit()

func _impact_visuals(r: Dictionary, ctx: Dictionary) -> void:
	var u: Unit = r["unit"]
	var desc := describe_result(r)
	var chest := stage.unit_chest(u)
	var push := _knock_dir(ctx, u)
	var color: Color = ctx["color"]
	var kind: int = ctx["kind"]

	if not landed(r):
		stage.update_hp(u, int(r["hp_after"]))
		unit_hit.emit(u)
		_float_text(chest, desc)
		_flash_tile(u.cell, COLOR_MISS, 0.3, 0.35)
		await _dodge(u, push)
		return

	var crit: bool = desc["kind"] == "crit"
	var died: bool = r["died"]
	_flash_tile(u.cell, color, 0.4, 0.7)
	_burst(chest, color, crit or died)
	if kind == Kind.MELEE:
		_slash(chest, crit)
	elif kind == Kind.BOLT:
		_ring(stage.unit_rest(u), color, 0.2, 0.9, 0.3)
	_flash_unit(u, crit or died)
	stage.update_hp(u, int(r["hp_after"]))
	unit_hit.emit(u)
	_float_text(chest, desc)

	# The freeze lands on the flash frame; shake and knockback burst out of it.
	if died:
		await _hit_stop(STOP_KILL, STOP_SCALE)
		_hit_stop(SLOWMO_KILL_TIME, SLOWMO_KILL_SCALE)
	elif crit:
		await _hit_stop(STOP_CRIT, STOP_SCALE)
	else:
		await _hit_stop(STOP_NORMAL, STOP_SCALE)
	if shake_enabled and kind != Kind.BURST:
		stage.camera_shake(SHAKE_KILL if died else (SHAKE_CRIT if crit else SHAKE_HIT), 0.3 if (crit or died) else 0.2)

	if died:
		await _death(u, push)
	else:
		await _knockback(u, push, KNOCKBACK_DIST * (1.6 if crit else 1.0))

## Direction a victim is shoved: away from the attacker, or away from the blast centre.
## Standing on the centre (or hitting yourself) pops the unit upward instead.
func _knock_dir(ctx: Dictionary, u: Unit) -> Vector3:
	var from: Vector3 = ctx["center"] if ctx["kind"] == Kind.BURST else ctx["origin"]
	var d := stage.unit_rest(u) - from
	d.y = 0.0
	if d.length() < 0.01:
		return Vector3.UP * 0.8
	return d.normalized()

func _knockback(u: Unit, dir: Vector3, dist: float) -> void:
	var holder := stage.holder_of(u)
	var rest := stage.unit_rest(u)
	var t := _tween()
	t.tween_property(holder, "position", rest + dir * dist, 0.06).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(holder, "position", rest, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await t.finished

func _dodge(u: Unit, dir: Vector3) -> void:
	var holder := stage.holder_of(u)
	var rest := stage.unit_rest(u)
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized() * (1.0 if randf() < 0.5 else -1.0)
	var t := _tween()
	t.tween_property(holder, "position", rest + side * 0.38, 0.08).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(holder, "position", rest, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await t.finished

func _death(u: Unit, dir: Vector3) -> void:
	var holder := stage.holder_of(u)
	var sprite := stage.sprite_of(u)
	var rest := stage.unit_rest(u)
	var t := _tween().set_parallel(true)
	t.tween_property(holder, "position", rest + dir * 0.4 + Vector3(0.0, -0.25, 0.0), 0.5) \
		.set_delay(0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_property(sprite, "modulate", Color(0.5, 0.5, 0.5, 0.0), 0.5).set_delay(0.1)
	await t.finished
	stage.hide_unit(u)

func _flash_unit(u: Unit, strong: bool) -> void:
	var sprite := stage.sprite_of(u)
	sprite.shaded = false
	sprite.modulate = Color(3.0, 3.0, 3.0)
	var fade_to := Color(1.0, 0.55, 0.3) if strong else Color(1.0, 0.45, 0.45)
	var t := _tween()
	t.tween_property(sprite, "modulate", fade_to, 0.05)
	t.tween_property(sprite, "modulate", Color.WHITE, 0.25)
	t.tween_callback(func() -> void:
		if is_instance_valid(sprite):
			sprite.shaded = true)

# =============================================================================
# Attacker poses
# =============================================================================

func _move_holder(u: Unit, to: Vector3, time: float, trans_type: int, ease_type: int) -> void:
	var t := _tween()
	t.tween_property(stage.holder_of(u), "position", to, time).set_trans(trans_type).set_ease(ease_type)
	await t.finished

## Quick kick back on release, not awaited.
func _recoil(u: Unit, origin: Vector3, dir: Vector3) -> void:
	var t := _tween()
	t.tween_property(stage.holder_of(u), "position", origin - dir * 0.2, 0.05).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(stage.holder_of(u), "position", origin, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Caster rises a little and takes on the spell colour. Reset by _recover / settle_unit.
func _cast_pose(u: Unit, color: Color) -> void:
	var sprite := stage.sprite_of(u)
	var t := _tween().set_parallel(true)
	t.tween_property(sprite, "position:y", stage.sprite_rest_y(u) + 0.14, SPELL_WINDUP * 0.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(sprite, "modulate", Color.WHITE.lerp(color, 0.55), SPELL_WINDUP * 0.7)

func _recover(u: Unit, origin: Vector3) -> void:
	if not stage.has_unit(u) or not u.is_alive():
		return
	var sprite := stage.sprite_of(u)
	var t := _tween().set_parallel(true)
	t.tween_property(stage.holder_of(u), "position", origin, RECOVER_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(sprite, "position:y", stage.sprite_rest_y(u), RECOVER_TIME)
	t.tween_property(sprite, "modulate", Color.WHITE, RECOVER_TIME)
	await t.finished

# =============================================================================
# Placeholder visuals (swap these bodies for real art later)
# =============================================================================

# --- Effect pooling -----------------------------------------------------------
# Every effect below is taken from a pool and handed back when it ends, so a fight allocates nodes, meshes and
# materials a handful of times (the first use of each effect) instead of on every hit. Meshes, glow materials and
# colour ramps are shared. Only materials that are faded per instance (rings, tile quads, rune circle) are owned.

const POOL_MAX := 48
var _pool: Dictionary = {}          # kind -> Array of idle nodes (hidden, still in the tree)
var _shared_meshes: Dictionary = {} # key -> Mesh
var _glow_mats: Dictionary = {}     # "rgba|vertex" -> StandardMaterial3D (never modified after creation)
var _ramps: Dictionary = {}         # Color -> Gradient

func _take(kind: StringName, factory: Callable) -> Node3D:
	var idle: Array = _pool.get(kind, [])
	var n: Node3D = null
	while n == null and not idle.is_empty():
		var c: Node3D = idle.pop_back()
		if is_instance_valid(c):
			n = c
	if n == null:
		n = factory.call()
		_fx_root.add_child(n)
	n.visible = true
	return n

func _give(kind: StringName, n: Node3D) -> void:
	if not is_instance_valid(n):
		return
	n.visible = false
	if not _pool.has(kind):
		_pool[kind] = []
	var idle: Array = _pool[kind]
	if idle.has(n):
		return
	if idle.size() >= POOL_MAX:
		n.queue_free()
	else:
		idle.append(n)

## Pays every first-use cost up front (textures, shared materials / ramps, node creation, shader / pipeline
## compile) so the first attack of each kind does not hitch. Effects are drawn once, buried under the board.
func _prewarm() -> void:
	_get_slash_texture()
	_get_circle_texture()
	var colors: Array[Color] = [COLOR_WEAPON, COLOR_MISS, COLOR_TARGET_TILE, Color.WHITE]
	colors.append_array(SPELL_COLORS)
	for c in colors:
		_glow_material(c, false)
		_glow_material(c, true)
		_fade_ramp(c)
	var cells: Array = battle.grid.heights.keys()
	var spot := stage.cell_top(cells[0] if not cells.is_empty() else Vector2i.ZERO) - Vector3(0.0, 3.0, 0.0)
	var tiny := Vector3.ONE * 0.001
	var held: Array = []   # [kind, node]
	for spec: Array in [
		[&"arrow", _make_projectile.bind(true)], [&"orb", _make_projectile.bind(false)],
		[&"slash", _make_slash], [&"ring", _make_ring], [&"circle", _make_circle],
		[&"quad", _make_tile_quad], [&"text", _make_float_text],
		[&"burst_small", _make_burst.bind(false, &"burst_small")],
		[&"burst_big", _make_burst.bind(true, &"burst_big")],
	]:
		var kind: StringName = spec[0]
		var n := _take(kind, spec[1])
		n.position = spot
		n.scale = tiny
		if n is CPUParticles3D:
			(n as CPUParticles3D).emitting = true
		elif n.get_child_count() > 1 and n.get_child(1) is CPUParticles3D:
			(n.get_child(1) as CPUParticles3D).emitting = true
		held.append([kind, n])
	for _i in 3:
		await get_tree().process_frame
		if not is_inside_tree():
			return
	for h: Array in held:
		var n: Node3D = h[1]
		if n is CPUParticles3D:
			(n as CPUParticles3D).emitting = false
		elif n.get_child_count() > 1 and n.get_child(1) is CPUParticles3D:
			(n.get_child(1) as CPUParticles3D).emitting = false
		n.scale = Vector3.ONE
		_give(h[0], n)

func _mesh(key: String, build: Callable) -> Mesh:
	if not _shared_meshes.has(key):
		_shared_meshes[key] = build.call()
	return _shared_meshes[key]

## Projectile along a (lobbed) arc. Arrows are slim and point along their path; orbs trail sparks.
func _fly(from: Vector3, to: Vector3, time: float, arc: float, color: Color, arrow: bool) -> void:
	var kind: StringName = &"arrow" if arrow else &"orb"
	var p := _take(kind, _make_projectile.bind(arrow))
	var body: MeshInstance3D = p.get_child(0)
	body.material_override = _glow_material(color, false)
	if not arrow:
		var trail: CPUParticles3D = p.get_child(1)
		trail.color_ramp = _fade_ramp(color)
		trail.restart()
		trail.emitting = true
	p.transform = Transform3D(Basis.IDENTITY, from)
	var t := _tween()
	t.tween_method(func(v: float) -> void:
		var here := from.lerp(to, v) + Vector3.UP * sin(PI * v) * arc
		p.position = here
		if arrow:
			var ahead := from.lerp(to, minf(v + 0.03, 1.0)) + Vector3.UP * sin(PI * minf(v + 0.03, 1.0)) * arc
			if here.distance_squared_to(ahead) > 0.000001 and absf((ahead - here).normalized().dot(Vector3.UP)) < 0.99:
				p.look_at_from_position(here, ahead, Vector3.UP), 0.0, 1.0, time)
	await t.finished
	if not arrow:
		(p.get_child(1) as CPUParticles3D).emitting = false
	_give(kind, p)

func _make_projectile(arrow: bool) -> Node3D:
	var p := Node3D.new()
	var body := MeshInstance3D.new()
	if arrow:
		body.mesh = _mesh("arrow", func() -> Mesh:
			var box := BoxMesh.new()
			box.size = Vector3(0.05, 0.05, 0.5)
			return box)
	else:
		body.mesh = _mesh("orb", func() -> Mesh:
			var orb := SphereMesh.new()
			orb.radius = 0.2
			orb.height = 0.4
			return orb)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(body)
	if not arrow:
		p.add_child(_trail())
	return p

func _trail() -> CPUParticles3D:
	var tr := CPUParticles3D.new()
	tr.amount = 18
	tr.lifetime = 0.3
	tr.local_coords = false
	tr.direction = Vector3.UP
	tr.spread = 180.0
	tr.initial_velocity_min = 0.1
	tr.initial_velocity_max = 0.5
	tr.gravity = Vector3.ZERO
	tr.scale_amount_min = 0.4
	tr.scale_amount_max = 0.9
	tr.mesh = _mesh("trail_dot", func() -> Mesh:
		var m := SphereMesh.new()
		m.radius = 0.08
		m.height = 0.16
		return m)
	tr.material_override = _glow_material(Color.WHITE, true)
	tr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return tr

## One-shot spray of cubes. `big` for crits, kills and area blasts.
func _burst(pos: Vector3, color: Color, big: bool) -> void:
	var kind: StringName = &"burst_big" if big else &"burst_small"
	var p := _take(kind, _make_burst.bind(big, kind)) as CPUParticles3D
	p.color_ramp = _fade_ramp(color)
	p.position = pos
	p.restart()
	p.emitting = true

func _make_burst(big: bool, kind: StringName) -> Node3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 24 if big else 12
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.5 if big else 3.2
	p.gravity = Vector3(0.0, -9.0, 0.0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	p.mesh = _mesh("burst_cube", func() -> Mesh:
		var m := BoxMesh.new()
		m.size = Vector3(0.07, 0.07, 0.07)
		return m)
	p.material_override = _glow_material(Color.WHITE, true)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.finished.connect(_give.bind(kind, p))
	return p

## Diagonal slash streak that grows and fades. Billboarded, so it faces the camera.
func _slash(pos: Vector3, crit: bool) -> void:
	var s := _take(&"slash", _make_slash) as Sprite3D
	s.pixel_size = 0.03 * (1.4 if crit else 1.0)
	s.modulate = Color(1.0, 0.95, 0.7, 1.0)
	s.position = pos
	s.scale = Vector3.ONE * 0.4
	var t := _tween().set_parallel(true)
	t.tween_property(s, "scale", Vector3.ONE * 1.1, 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(s, "modulate:a", 0.0, 0.14).set_delay(0.06)
	t.finished.connect(_give.bind(&"slash", s))

func _make_slash() -> Node3D:
	var s := Sprite3D.new()
	s.texture = _get_slash_texture()
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.double_sided = true
	s.no_depth_test = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return s

## Expanding flat ring on the ground (shockwave / spell hit).
func _ring(pos: Vector3, color: Color, from_radius: float, to_radius: float, time: float) -> void:
	var mi := _take(&"ring", _make_ring) as MeshInstance3D
	var mat := mi.material_override as StandardMaterial3D
	mat.albedo_color = color
	mi.position = pos + Vector3(0.0, 0.06, 0.0)
	mi.scale = Vector3(from_radius * 2.0, 1.0, from_radius * 2.0)
	var t := _tween().set_parallel(true)
	t.tween_property(mi, "scale", Vector3(to_radius * 2.0, 1.0, to_radius * 2.0), time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(mat, "albedo_color:a", 0.0, time)
	t.finished.connect(_give.bind(&"ring", mi))

func _make_ring() -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh("ring", func() -> Mesh:
		var torus := TorusMesh.new()
		torus.inner_radius = 0.42
		torus.outer_radius = 0.5
		return torus)
	var mat := StandardMaterial3D.new()   # owned: its alpha is faded per ring
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Rune circle under the caster: grows in and spins until faded by _fade_out_free.
func _magic_circle(origin: Vector3, color: Color, time: float) -> MeshInstance3D:
	var mi := _take(&"circle", _make_circle) as MeshInstance3D
	var mat := mi.material_override as StandardMaterial3D
	mat.albedo_color = Color(color.r, color.g, color.b, 0.0)
	mi.rotation = Vector3.ZERO
	mi.position = origin + Vector3(0.0, 0.04, 0.0)
	mi.scale = Vector3.ONE * 0.3
	var t := _tween().set_parallel(true)
	t.tween_property(mi, "scale", Vector3.ONE, time * 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(mi, "rotation:y", PI, time)
	t.tween_property(mat, "albedo_color:a", 0.9, time * 0.3)
	return mi

func _make_circle() -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh("circle", func() -> Mesh:
		var plane := PlaneMesh.new()
		plane.size = Vector2(1.7, 1.7)
		return plane)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = _get_circle_texture()
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Tiles of an area light up while the spell charges. Returns the quads so the caller can clear them.
func _telegraph(cells: Array[Vector2i], color: Color, time: float) -> Array[MeshInstance3D]:
	var quads: Array[MeshInstance3D] = []
	for c in cells:
		var q := _tile_quad(c, Color(color.r, color.g, color.b, 0.0))
		var mat := q.material_override as StandardMaterial3D
		var t := _tween()
		t.tween_property(mat, "albedo_color:a", 0.6, time).set_trans(Tween.TRANS_SINE)
		quads.append(q)
	return quads

func _flash_tile(cell: Vector2i, color: Color, time: float, peak: float = 0.55) -> void:
	if battle == null or not battle.grid.has_tile(cell):
		return
	var q := _tile_quad(cell, Color(color.r, color.g, color.b, 0.0))
	var mat := q.material_override as StandardMaterial3D
	var t := _tween()
	t.tween_property(mat, "albedo_color:a", peak, time * 0.25)
	t.tween_property(mat, "albedo_color:a", 0.0, time * 0.75)
	t.finished.connect(_give.bind(&"quad", q))

func _tile_quad(cell: Vector2i, color: Color) -> MeshInstance3D:
	var q := _take(&"quad", _make_tile_quad) as MeshInstance3D
	(q.material_override as StandardMaterial3D).albedo_color = color
	q.position = stage.cell_top(cell) + Vector3(0.0, TILE_FX_LIFT, 0.0)
	return q

func _make_tile_quad() -> Node3D:
	var mat := StandardMaterial3D.new()   # owned: its alpha is faded per quad
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var q := MeshInstance3D.new()
	q.mesh = _tile_mesh
	q.material_override = mat
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return q

## Floating number / word that pops, rises and fades. `desc`: {"text", "color", "size"}.
func _float_text(pos: Vector3, desc: Dictionary) -> void:
	var l := _take(&"text", _make_float_text) as Label3D
	l.text = str(desc["text"])
	l.pixel_size = 0.0085 * float(desc["size"])
	l.modulate = desc["color"]
	l.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	l.position = pos + Vector3(randf_range(-0.12, 0.12), 0.35, 0.0)
	l.scale = Vector3.ONE * 0.4
	var t := _tween().set_parallel(true)
	t.tween_property(l, "position:y", l.position.y + 0.9, 0.75).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "modulate:a", 0.0, 0.25).set_delay(0.55)
	t.tween_property(l, "outline_modulate:a", 0.0, 0.25).set_delay(0.55)
	t.finished.connect(_give.bind(&"text", l))

func _make_float_text() -> Node3D:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 64
	l.outline_size = 16
	l.render_priority = 10
	l.outline_render_priority = 9
	return l

## Fades `node` out, then returns it to the pool under `kind` (&"circle" or &"quad").
func _fade_out_free(node: MeshInstance3D, time: float, kind: StringName) -> void:
	if not is_instance_valid(node):
		return
	var mat := node.material_override as StandardMaterial3D
	var t := _tween()
	t.tween_property(mat, "albedo_color:a", 0.0, time)
	t.finished.connect(_give.bind(kind, node))

## Shared, never modified after creation (effects that fade their own colour own a material instead).
func _glow_material(color: Color, vertex_color: bool) -> StandardMaterial3D:
	var key := "%s|%s" % [color.to_html(true), vertex_color]
	if _glow_mats.has(key):
		return _glow_mats[key]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.vertex_color_use_as_albedo = vertex_color
	if vertex_color:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mats[key] = mat
	return mat

func _fade_ramp(color: Color) -> Gradient:
	if _ramps.has(color):
		return _ramps[color]
	var g := Gradient.new()
	g.set_color(0, color)
	g.set_color(1, Color(color.r, color.g, color.b, 0.0))
	_ramps[color] = g
	return g

func _get_slash_texture() -> ImageTexture:
	if _slash_tex != null:
		return _slash_tex
	var n := 48
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in n:
		for y in n:
			# Streak along x + y = n, tapered at both ends.
			var along := (float(x) - 6.0) / 36.0
			if along < 0.0 or along > 1.0:
				continue
			var d := absf(float(x + y) - float(n)) * 0.7071
			var half_width := 2.6 * sin(PI * along)
			var a := clampf(1.0 - d / maxf(half_width, 0.01), 0.0, 1.0)
			if a > 0.0:
				img.set_pixel(x, y, Color(1, 1, 1, a))
	_slash_tex = ImageTexture.create_from_image(img)
	return _slash_tex

func _get_circle_texture() -> ImageTexture:
	if _circle_tex != null:
		return _circle_tex
	var n := 64
	var c := (n - 1) * 0.5
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in n:
		for y in n:
			var v := Vector2(x - c, y - c)
			var r := v.length() / c
			var on := (r > 0.9 and r < 0.97) or (r > 0.58 and r < 0.64)
			# Eight rune ticks between the rings.
			var ang := fposmod(v.angle(), TAU / 8.0)
			if r > 0.64 and r < 0.9 and (ang < 0.06 or ang > TAU / 8.0 - 0.06):
				on = true
			if on:
				img.set_pixel(x, y, Color.WHITE)
	_circle_tex = ImageTexture.create_from_image(img)
	return _circle_tex

# =============================================================================
# Toast (ability name at the top of the screen)
# =============================================================================

func _build_toast() -> void:
	var layer := CanvasLayer.new()
	layer.name = "CombatToastLayer"
	layer.layer = 2
	add_child(layer)
	_toast_panel = PanelContainer.new()
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.modulate.a = 0.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.1, 0.78)
	style.set_corner_radius_all(6)
	style.content_margin_left = 22.0
	style.content_margin_right = 22.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	_toast_panel.add_theme_stylebox_override("panel", style)
	layer.add_child(_toast_panel)
	_toast_label = Label.new()
	_toast_label.add_theme_font_size_override("font_size", 30)
	_toast_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast_label.add_theme_constant_override("outline_size", 6)
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.add_child(_toast_label)
	_toast_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_panel.offset_top = 150.0

func _show_toast(text: String) -> void:
	if not show_toast:
		return
	_toast_label.text = text
	_toast_panel.reset_size()
	_toast_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast_panel.offset_top = 150.0
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_tween = _tween()
	_toast_tween.tween_property(_toast_panel, "modulate:a", 1.0, TOAST_FADE)

func _hide_toast() -> void:
	if _toast_panel == null or _toast_panel.modulate.a <= 0.0:
		return
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_tween = _tween()
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, TOAST_FADE)

# =============================================================================
# Time: speed, waits, hit-stop
# =============================================================================

func _spd() -> float:
	var s := maxf(speed, 0.05)
	if Input.is_key_pressed(KEY_SPACE):
		s *= fast_forward_mult
	return s

func _tween() -> Tween:
	var t := create_tween()
	t.set_speed_scale(_spd())
	return t

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds / _spd()).timeout

## Freezes (or crawls) the whole game for `real_seconds` of wall-clock time. Stackable.
func _hit_stop(real_seconds: float, time_scale: float) -> void:
	if not hit_stop_enabled or real_seconds <= 0.0:
		return
	_stop_count += 1
	Engine.time_scale = minf(Engine.time_scale, time_scale)
	await get_tree().create_timer(real_seconds / _spd(), true, false, true).timeout
	_stop_count -= 1
	if _stop_count <= 0:
		_stop_count = 0
		Engine.time_scale = 1.0

# =============================================================================
# Small geometry helpers
# =============================================================================

func _flat_dir(a: Vector3, b: Vector3) -> Vector3:
	var d := b - a
	d.y = 0.0
	return d.normalized() if d.length() > 0.001 else Vector3.ZERO

func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()

func _side_of(a: Vector3, b: Vector3) -> Vector3:
	var side := _flat_dir(a, b).cross(Vector3.UP)
	return side if side.length() > 0.01 else Vector3.RIGHT

func _area_cells(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Vector2i in battle.grid.heights.keys():
		if Grid.distance(c, center) <= radius:
			out.append(c)
	return out
