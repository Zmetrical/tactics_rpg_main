extends RefCounted
## Battle loop and state machine. No rendering; talks to the UI through signals.

const Ability = preload("res://scripts/battle/ability.gd")
const Grid = preload("res://scripts/battle/grid.gd")
const Rules = preload("res://scripts/battle/rules.gd")
const SpellContext = preload("res://scripts/spells/spell_context.gd")
const SpellDef = preload("res://scripts/spells/spell_def.gd")
const SpellPlan = preload("res://scripts/spells/spell_plan.gd")
const SpellResult = preload("res://scripts/spells/spell_result.gd")
const Unit = preload("res://scripts/battle/unit.gd")

enum State { WAIT_INPUT, MOVING, TARGETING, ENDED }

## A charged spell locked onto a tile. Resolves when ticks_left reaches 0.
class PendingCast extends RefCounted:
	var caster: Unit
	var ability: Ability
	var cell: Vector2i
	var ticks_left: int = 0
	var order: int = 0
	## Set when the cast is locked onto a UNIT: `cell` then follows it. null = locked to the tile.
	var target: Unit = null
	## Aim data for SpellDef casts (direction, path, pivot...). null for plain abilities.
	var plan: SpellPlan = null

const STEP_DELAY := 0.12
const AI_DELAY := 0.45
## How long an AI unit waits, lined up on its target, before it strikes.
const AI_LINEUP_PAUSE := 0.4

signal state_changed(state: int)
signal turn_started(unit: Unit)
signal turn_ended(unit: Unit)
signal resources_changed
signal unit_stepped(unit: Unit, cell: Vector2i)
## Fired on every move step. Reactions hang off this; add new triggers as new handlers.
signal unit_left_tile(mover: Unit, from_cell: Vector2i, to_cell: Vector2i)
signal reaction_prompt(reactor: Unit, mover: Unit)
signal reaction_answered(take_it: bool)
signal reaction_finished
signal opportunity_attack(reactor: Unit, mover: Unit)
signal ability_used(user: Unit, ability: Ability, cell: Vector2i)
## Charged spells: committed to a tile, resolved later, or cancelled / fizzled.
signal cast_started(cast: PendingCast)
signal cast_resolved(cast: PendingCast)
signal cast_cancelled(cast: PendingCast, reason: String)
signal damage_dealt(attacker: Unit, victim: Unit, amount: int, info: Dictionary)
## One fully resolved action (weapon, skill, spell, opportunity attack), emitted AFTER every roll
## and every HP change. `results` rows: {"unit", "amount", "info", "died", "hp_after"}.
## `tag` is "" (normal), "cast" (a charged spell resolving) or "reaction" (opportunity attack).
## This is what the on-map combat presentation plays back; rules never wait on it directly.
signal action_executed(user: Unit, ability: Ability, cell: Vector2i, results: Array, tag: String)
## Fired when `presenting` drops back to false.
signal presentation_finished
## An AI unit is in position and about to attack `target`: the view frames the pair and shows the
## target's panel. attack_lineup_ended follows if no attack actually started (so they can be dropped).
signal attack_lineup(user: Unit, target: Unit)
signal attack_lineup_ended
## Optional: Callable() -> bool, true while the UI is still showing the attack's battle log. The enemy AI waits for it
## to be dismissed (Enter / click) before ending its turn.
var log_gate := Callable()
signal unit_died(unit: Unit)
signal log_message(text: String)
signal battle_ended(player_won: bool)

var grid: Grid
var units: Array[Unit] = []
var rng: RandomNumberGenerator
var state: State = State.WAIT_INPUT
var current: Unit = null
var targeting_ability: Ability = null
var player_won := false
## Optional: set to a SceneTree to pace steps and AI with timers. Null = instant (tests).
var tree: SceneTree = null
## Optional: Callable(reactor, mover) -> bool that answers player reaction prompts synchronously (tests).
var oa_decider: Callable = Callable()

## Charged casts in commit order (oldest first).
var pending_casts: Array[PendingCast] = []

## True while a presenter (combat_director.gd) is still playing an action out. Input, enemy AI and
## turn changes wait for it. Nothing sets it in tests, so rules there stay instant.
var presenting := false:
	set(value):
		if presenting == value:
			return
		presenting = value
		if not value:
			presentation_finished.emit()

var _reaction_busy := false
var _cast_counter := 0

func _init(p_grid: Grid, p_units: Array, p_rng: RandomNumberGenerator) -> void:
	grid = p_grid
	units.assign(p_units)
	rng = p_rng
	unit_left_tile.connect(_on_unit_left_tile)

# --- Start / turn order ------------------------------------------------------

## Opening facing: toward the closest unit of the other side.
func _face_nearest_enemy(u: Unit) -> void:
	var best: Unit = null
	for o in units:
		if o.side != u.side and (best == null or Grid.distance(u.cell, o.cell) < Grid.distance(u.cell, best.cell)):
			best = o
	if best != null:
		u.face_toward(best.cell)

func start() -> void:
	for u in units:
		u.height = grid.height_at(u.cell)
		_face_nearest_enemy(u)
	_set_state(State.WAIT_INPUT)
	_next_turn()

func _goes_before(a: Unit, b: Unit) -> bool:
	if a.ct != b.ct:
		return a.ct > b.ct
	if a.spd != b.spd:
		return a.spd > b.spd
	return a.side == Unit.Side.PLAYER and b.side != Unit.Side.PLAYER

## Ticks CT (CT += SPD for every living unit) until someone has CT >= 100, then returns
## that unit. Order: higher CT, then higher SPD, then player side. Units with a pending cast
## are skipped (their CT keeps building). After every tick, pending casts count down and
## the ones that reach 0 resolve before the next turn is picked.
func pick_next() -> Unit:
	for _i in 1000:
		var best: Unit = null
		for u in units:
			if u.is_alive() and u.ct >= 100 and not is_charging(u) and (best == null or _goes_before(u, best)):
				best = u
		if best != null:
			return best
		var any_alive := false
		for u in units:
			if u.is_alive():
				u.ct += u.spd
				any_alive = true
		if not any_alive:
			return null
		_tick_casts()
		if state == State.ENDED:
			return null
	return null

func _next_turn() -> void:
	var u := pick_next()
	if u == null:
		return
	# Charged spells can resolve inside pick_next(); let their animation finish before the
	# next unit's turn is announced.
	if presenting:
		await presentation_finished
		if state == State.ENDED:
			return
	_begin_turn(u)

func _begin_turn(unit: Unit) -> void:
	current = unit
	unit.start_turn()
	_set_state(State.WAIT_INPUT)
	turn_started.emit(unit)
	resources_changed.emit()
	if unit.side == Unit.Side.ENEMY:
		_run_ai(unit)

func end_turn() -> void:
	if state == State.ENDED or state == State.MOVING or current == null or presenting:
		return
	var unit := current
	unit.ct -= 100
	_set_state(State.WAIT_INPUT)
	turn_ended.emit(unit)
	if check_end():
		return
	_next_turn()

## No enemies left = win, no players left = lose.
func check_end() -> bool:
	if state == State.ENDED:
		return true
	var players := 0
	var enemies := 0
	for u in units:
		if u.is_alive():
			if u.side == Unit.Side.PLAYER:
				players += 1
			else:
				enemies += 1
	if enemies == 0:
		_finish(true)
	elif players == 0:
		_finish(false)
	return state == State.ENDED

func _finish(won: bool) -> void:
	player_won = won
	_set_state(State.ENDED)
	battle_ended.emit(won)

func _set_state(s: State) -> void:
	state = s
	match s:
		State.WAIT_INPUT, State.MOVING, State.ENDED:
			targeting_ability = null
		State.TARGETING:
			pass
	state_changed.emit(s)

# --- Input -------------------------------------------------------------------

func handle_cell_click(cell: Vector2i, lock_on_unit: bool = false) -> void:
	if presenting:
		return
	match state:
		State.WAIT_INPUT:
			await move_unit(current, cell)
		State.TARGETING:
			use_ability(current, targeting_ability, cell, lock_on_unit)
		State.MOVING, State.ENDED:
			pass

func enter_targeting(ability: Ability) -> bool:
	if (state != State.WAIT_INPUT and state != State.TARGETING) or current == null or presenting:
		return false
	if is_charging(current) or not current.can_use(ability):
		return false
	_set_state(State.TARGETING)
	targeting_ability = ability
	return true

func cancel_targeting() -> void:
	if state == State.TARGETING:
		_set_state(State.WAIT_INPUT)

func answer_reaction(take_it: bool) -> void:
	reaction_answered.emit(take_it)

# --- Queries -----------------------------------------------------------------

func unit_at(cell: Vector2i) -> Unit:
	for u in units:
		if u.is_alive() and u.cell == cell:
			return u
	return null

func occupied(except: Unit = null) -> Dictionary:
	var out: Dictionary = {}
	for u in units:
		if u.is_alive() and u != except:
			out[u.cell] = true
	return out

var _reach_key := ""
var _reach_unit: Unit = null
var _reach_dist: Dictionary = {}

## Cached: the hover preview asks for this on every mouse-cell change. Recomputed only when the unit, its
## stats or anybody's position changed.
func reachable_cells(unit: Unit) -> Dictionary:
	var key := "%d:%d,%d,%d,%d" % [grid.get_instance_id(), unit.cell.x, unit.cell.y, unit.movement, unit.jump]
	for u in units:
		if u.is_alive() and u != unit:
			key += ";%d,%d" % [u.cell.x, u.cell.y]
	if unit == _reach_unit and key == _reach_key:
		return _reach_dist
	var info := grid.reach(unit.cell, unit.movement, unit.jump, occupied(unit))
	_reach_unit = unit
	_reach_key = key
	_reach_dist = info["dist"]
	return _reach_dist

## Single target: the hostile unit on the cell. Area: every living unit within the radius
## of the cell, friendly fire (and the caster) included.
func victims_at(user: Unit, ability: Ability, cell: Vector2i) -> Array:
	var out: Array = []
	if ability.area_radius <= 0:
		var u := unit_at(cell)
		if u != null and u.side != user.side:
			out.append(u)
	elif grid.has_tile(cell):
		for u in units:
			if u.is_alive() and Grid.distance(u.cell, cell) <= ability.area_radius:
				out.append(u)
	return out

## Rows of {"unit", "mode"} for the targeting preview.
func preview(user: Unit, ability: Ability, cell: Vector2i) -> Array:
	var rows: Array = []
	if Grid.distance(user.cell, cell) > ability.range_tiles:
		return rows
	for v: Unit in victims_at(user, ability, cell):
		rows.append({"unit": v, "mode": Rules.get_roll_mode(user, v, ability, units)})
	return rows

func is_charging(u: Unit) -> bool:
	return pending_cast_of(u) != null

func pending_cast_of(u: Unit) -> PendingCast:
	for c in pending_casts:
		if c.caster == u:
			return c
	return null

## Cells a pending cast will hit, as locked at commit time.
func cast_cells(cast: PendingCast) -> Array[Vector2i]:
	if cast.plan != null:
		return spell_result(cast.caster, cast.ability, cast.plan).cell_list()
	var out: Array[Vector2i] = []
	for c: Vector2i in grid.heights.keys():
		if Grid.distance(c, cast.cell) <= cast.ability.area_radius:
			out.append(c)
	return out

# --- Movement ----------------------------------------------------------------

func move_unit(unit: Unit, dest: Vector2i) -> bool:
	if state != State.WAIT_INPUT or unit == null or not unit.is_alive() or is_charging(unit) or presenting:
		return false
	var info := grid.reach(unit.cell, unit.movement, unit.jump, occupied(unit))
	var dist: Dictionary = info["dist"]
	if dest == unit.cell or not dist.has(dest):
		return false
	var path := grid.path_to(info["prev"], unit.cell, dest)
	# The whole walk is paid on the click (the HUD already previewed the cost on hover), not step by step.
	unit.movement -= path.size()
	resources_changed.emit()
	_set_state(State.MOVING)
	for step: Vector2i in path:
		unit_left_tile.emit(unit, unit.cell, step)
		if _reaction_busy:
			await reaction_finished
		if state == State.ENDED or not unit.is_alive():
			break
		unit.facing = step - unit.cell
		unit.cell = step
		unit.height = grid.height_at(step)
		_sync_follow_casts(unit)
		unit_stepped.emit(unit, step)
		await _pace(STEP_DELAY)
	if state != State.ENDED:
		_set_state(State.WAIT_INPUT)
	resources_changed.emit()
	if state != State.ENDED and not unit.is_alive() and unit == current:
		end_turn()
	return true

# --- Reactions: Opportunity Attack -------------------------------------------

func _on_unit_left_tile(mover: Unit, from_cell: Vector2i, to_cell: Vector2i) -> void:
	_reaction_busy = true
	for reactor in units:
		if not _can_opportunity_attack(reactor, mover, from_cell, to_cell):
			continue
		var take: bool = await _ask_reaction(reactor, mover)
		if not take:
			continue
		var melee := _melee_ability(reactor)
		if state == State.ENDED or not mover.is_alive() or melee == null or not reactor.can_use(melee):
			break
		reactor.spend(melee)
		opportunity_attack.emit(reactor, mover)
		log_message.emit("%s makes an opportunity attack on %s (-%s AP)" % [reactor.unit_name, mover.unit_name, ap_str(melee.ap_cost)])
		_resolve(reactor, melee, [mover], mover.cell, "reaction")
		if presenting:
			await presentation_finished
		check_end()
		if state == State.ENDED or not mover.is_alive():
			break
	_reaction_busy = false
	reaction_finished.emit()

func _can_opportunity_attack(reactor: Unit, mover: Unit, from_cell: Vector2i, to_cell: Vector2i) -> bool:
	if reactor == mover or not reactor.is_alive() or reactor.side == mover.side:
		return false
	var melee := _melee_ability(reactor)
	if melee == null or is_charging(reactor) or not reactor.can_use(melee):
		return false
	return Grid.distance(reactor.cell, from_cell) == 1 and Grid.distance(reactor.cell, to_cell) > 1

func _melee_ability(u: Unit) -> Ability:
	for a in u.abilities:
		if a.range_tiles == 1 and a.slot_level == 0 and a.damage_dice != "":
			return a
	return null

func _ask_reaction(reactor: Unit, mover: Unit) -> bool:
	if reactor.side == Unit.Side.ENEMY:
		return true
	if oa_decider.is_valid():
		return bool(oa_decider.call(reactor, mover))
	reaction_prompt.emit(reactor, mover)
	var answer: bool = await reaction_answered
	return answer

# --- Abilities ---------------------------------------------------------------

## lock_on_unit only matters for charged abilities: lock onto the unit standing on `cell` (the
## cast follows it) instead of the tile.
func use_ability(user: Unit, ability: Ability, cell: Vector2i, lock_on_unit: bool = false, plan: SpellPlan = null) -> bool:
	if state != State.WAIT_INPUT and state != State.TARGETING:
		return false
	if user == null or ability == null or is_charging(user):
		log_message.emit("Can't use that ability right now")
		return false
	if not user.can_use(ability):
		log_message.emit("Not enough AP: %s needs %s, %s has %s" % [ability.display_name, ap_str(ability.ap_cost), user.unit_name, ap_str(user.ap)])
		return false
	if ability is SpellDef:
		return _use_spell(user, ability, plan)
	if Grid.distance(user.cell, cell) > ability.range_tiles:
		log_message.emit("Out of range")
		return false
	if ability.is_charged():
		return _commit_cast(user, ability, cell, lock_on_unit)
	var victims := victims_at(user, ability, cell)
	if victims.is_empty():
		log_message.emit("No valid target there")
		return false
	user.spend(ability)
	ability_used.emit(user, ability, cell)
	log_message.emit("%s uses %s" % [user.unit_name, ability.display_name])
	_resolve(user, ability, victims, cell)
	_set_state(State.WAIT_INPUT)
	resources_changed.emit()
	check_end()
	return true

## Charged spell: the TILE is locked now, any in-range tile is legal (even empty), and the
## AP is spent now and never refunded. Nothing is rolled until resolution.
func _commit_cast(user: Unit, ability: Ability, cell: Vector2i, lock_on_unit: bool = false, plan: SpellPlan = null) -> bool:
	if not grid.can_aim_at(cell):
		log_message.emit("No valid target there")
		return false
	var locked_unit: Unit = null
	if lock_on_unit:
		locked_unit = unit_at(cell)
		if locked_unit == null:
			log_message.emit("No unit there to lock onto")
			return false
	user.spend(ability, plan.tier if plan != null else 1)
	var cast := PendingCast.new()
	cast.caster = user
	cast.ability = ability
	cast.cell = cell
	cast.ticks_left = ability.charge_ticks()
	_cast_counter += 1
	cast.order = _cast_counter
	cast.target = locked_unit
	cast.plan = plan
	pending_casts.append(cast)
	cast_started.emit(cast)
	var on_text := "" if locked_unit == null else " on %s" % locked_unit.unit_name
	log_message.emit("%s begins casting %s%s (resolves in %d ticks)" % [user.unit_name, ability.display_name, on_text, cast.ticks_left])
	_set_state(State.WAIT_INPUT)
	resources_changed.emit()
	return true

func _tick_casts() -> void:
	if pending_casts.is_empty():
		return
	for c in pending_casts:
		c.ticks_left -= 1
	for c in pending_casts.duplicate():
		if state == State.ENDED:
			return
		if c.ticks_left <= 0 and pending_casts.has(c):
			_resolve_cast(c)

## Victims are whoever is on the locked tile (or in its radius) NOW; rolls happen NOW.
func _resolve_cast(cast: PendingCast) -> void:
	pending_casts.erase(cast)
	var scales: Dictionary = {}
	var focus := cast.cell
	var victims: Array
	if cast.plan != null:
		var result := spell_result(cast.caster, cast.ability, cast.plan)
		victims = result.units()
		scales = result.scales()
		if not victims.is_empty():
			focus = victims[0].cell
	else:
		victims = victims_at(cast.caster, cast.ability, cast.cell)
	if victims.is_empty():
		log_message.emit("%s fizzles" % cast.ability.display_name)
		cast_cancelled.emit(cast, "fizzle")
	else:
		ability_used.emit(cast.caster, cast.ability, cast.cell)
		log_message.emit("%s's %s resolves" % [cast.caster.unit_name, cast.ability.display_name])
		cast_resolved.emit(cast)
		_resolve(cast.caster, cast.ability, victims, focus, "cast", scales)
	resources_changed.emit()
	check_end()

## Casts locked onto a unit follow it: their cell is always where the unit stands.
func _sync_follow_casts(mover: Unit) -> void:
	for c in pending_casts:
		if c.target == mover:
			c.cell = mover.cell
			if c.plan != null:
				c.plan.cell = mover.cell

## A cast locked onto a unit that dies has nothing to hit: cancelled, AP not refunded.
func _cancel_casts_targeting(target: Unit) -> void:
	for c in pending_casts.duplicate():
		if c.target == target:
			pending_casts.erase(c)
			log_message.emit("%s's %s loses its target and is cancelled" % [c.caster.unit_name, c.ability.display_name])
			cast_cancelled.emit(c, "target died")

func _cancel_casts_of(caster: Unit) -> void:
	for c in pending_casts.duplicate():
		if c.caster == caster:
			pending_casts.erase(c)
			log_message.emit("%s's %s is cancelled" % [caster.unit_name, c.ability.display_name])
			cast_cancelled.emit(c, "caster died")

## `scales` (unit -> multiplier) lets one roll deal different fractions to different victims
## (echoes, bounces, shockwaves). Missing unit = 1.0.
func _resolve(user: Unit, ability: Ability, victims: Array, cell: Vector2i, tag: String = "", scales: Dictionary = {}) -> void:
	user.face_toward(cell)
	var results: Array = []
	# Non-attack abilities roll damage once for everyone.
	var shared := 0
	if ability.roll != Ability.Roll.ATTACK:
		shared = Rules.roll_damage(rng, ability, false, user)
	for v: Unit in victims:
		if not v.is_alive():
			continue
		var info: Dictionary = {}
		var amount := 0
		var scale := float(scales.get(v, 1.0))
		match ability.roll:
			Ability.Roll.ATTACK:
				var mode := Rules.get_roll_mode(user, v, ability, units)
				info = Rules.attack_roll(rng, user, v, ability, mode)
				info["mode"] = mode
				amount = roundi(int(info["damage"]) * scale)
			Ability.Roll.SAVE:
				info = Rules.save_throw(rng, user, v, ability)
				amount = Rules.save_damage(roundi(shared * scale), info["success"])
			Ability.Roll.AUTO:
				amount = roundi(shared * scale)
		var rider_vs: Variant = ability.get("vs_status")
		if rider_vs != null and rider_vs != &"" and v.has_status(rider_vs):
			amount = roundi(amount * float(ability.get("vs_status_mult")))
		results.append(_apply_damage(user, v, amount, info, ability.damage_type))
		_apply_skill_status(ability, v, info)
	if not results.is_empty():
		action_executed.emit(user, ability, cell, results, tag)

## SkillDef.apply_status: put the status on a victim that survived and was not missed / did not save.
func _apply_skill_status(ability: Ability, victim: Unit, info: Dictionary) -> void:
	var id: Variant = ability.get("apply_status")
	if id == null or id == &"" or not victim.is_alive():
		return
	if info.has("hit") and not info["hit"]:
		return
	if info.get("success", false):
		return
	victim.statuses[id] = maxi(int(victim.statuses.get(id, 0)), int(ability.get("apply_status_turns")))
	log_message.emit("%s is %s" % [victim.unit_name, String(id).capitalize()])

func _apply_damage(attacker: Unit, victim: Unit, amount: int, info: Dictionary, damage_type: int = Ability.DamageType.PHYSICAL) -> Dictionary:
	var report := victim.take_damage(amount, damage_type, attacker)
	damage_dealt.emit(attacker, victim, amount, info)
	# Two short lines instead of one long one: what was rolled, then what it did.
	var who := victim.unit_name
	var dmg_text := "no damage" if amount <= 0 else "%d damage" % amount
	if info.has("hit"):
		var roll := "Roll %d vs %d%% to hit" % [info["roll"], info["chance"]]
		if int(info.get("mode", Rules.Mode.NORMAL)) != Rules.Mode.NORMAL:
			roll += " (%s)" % Rules.mode_name(int(info.get("mode", Rules.Mode.NORMAL)))
		log_message.emit(roll)
		if not info["hit"]:
			log_message.emit("Miss! %s takes no damage" % who)
		else:
			log_message.emit("%s %s takes %s" % ["Critical hit!" if info["crit"] else "Hit!", who, dmg_text])
	elif info.has("success"):
		log_message.emit("%s saves: Roll %d %+d = %d vs DC %d" % [who, info["d20"], int(info["total"]) - int(info["d20"]), info["total"], info["dc"]])
		log_message.emit("Save %s - %s takes %s" % ["passed" if info["success"] else "failed", who, dmg_text])
	else:
		log_message.emit("%s takes %s" % [who, dmg_text])
	if not victim.is_alive():
		_cancel_casts_of(victim)
		_cancel_casts_targeting(victim)
		unit_died.emit(victim)
		log_message.emit("%s falls" % victim.unit_name)
	return {"unit": victim, "amount": amount, "info": info, "died": not victim.is_alive(), "hp_after": victim.hp, "report": report}

# --- Spells (SpellDef) -------------------------------------------------------

## `tier` is the player's per-cast choice (1 = Base). It is paid for in AP, not learned.
func spell_context(user: Unit, spell: SpellDef, tier: int = 1) -> SpellContext:
	return SpellContext.new(grid, units, user, spell, tier)

## What a spell would do right now with this plan. Pure: nothing is rolled or changed.
func spell_result(user: Unit, spell: SpellDef, plan: SpellPlan) -> SpellResult:
	return spell.behavior().resolve(spell_context(user, spell, plan.tier if plan != null else 1), plan)

## Spells are aimed with a SpellPlan (see spell_targeting.gd). Instant spells resolve now, charged
## ones commit the plan and resolve it later against whoever is there then.
func _use_spell(user: Unit, spell: SpellDef, plan: SpellPlan) -> bool:
	if plan == null:
		log_message.emit("Aim the spell first")
		return false
	var ctx := spell_context(user, spell, plan.tier)
	plan.tier = ctx.tier  # clamped to the spell's max tier
	var cost := spell.ap_cost_for_tier(plan.tier)
	if not user.can_afford(cost):
		log_message.emit("Not enough AP for %s at Tier %d: needs %s, %s has %s" % [spell.display_name, plan.tier, ap_str(cost), user.unit_name, ap_str(user.ap)])
		return false
	var err: String = spell.behavior().validate_plan(ctx, plan)
	if err != "":
		log_message.emit(err)
		return false
	if spell.is_charged():
		return _commit_cast(user, spell, plan.cell, plan.lock_unit, plan)
	var result := spell_result(user, spell, plan)
	if result.hits.is_empty():
		log_message.emit("No valid target there")
		return false
	user.spend(spell, plan.tier)
	var focus: Vector2i = result.hits[0]["unit"].cell
	ability_used.emit(user, spell, focus)
	log_message.emit("%s uses %s (Tier %d, -%s AP)" % [user.unit_name, spell.display_name, plan.tier, ap_str(cost)])
	_resolve(user, spell, result.units(), focus, "", result.scales())
	_set_state(State.WAIT_INPUT)
	resources_changed.emit()
	check_end()
	return true

# --- Enemy AI ----------------------------------------------------------------

## Move into range of the nearest player, use the first usable damaging Ability, End Turn.
func _run_ai(unit: Unit) -> void:
	await _pace(AI_DELAY)
	if state == State.ENDED or current != unit:
		return
	var target := _nearest_hostile(unit)
	if target == null:
		end_turn()
		return
	var ability := _first_damaging(unit)
	var want_range := 1
	if ability != null:
		want_range = ability.range_tiles
	var dist := reachable_cells(unit)
	var best_cell := unit.cell
	var best_score := _ai_score(unit.cell, target.cell, want_range, 0)
	for c: Vector2i in dist.keys():
		var steps: int = dist[c]
		var score := _ai_score(c, target.cell, want_range, steps)
		if score < best_score:
			best_score = score
			best_cell = c
	if best_cell != unit.cell:
		await move_unit(unit, best_cell)
	if state == State.ENDED or current != unit or not unit.is_alive():
		return
	if ability != null and unit.can_use(ability) and Grid.distance(unit.cell, target.cell) <= ability.range_tiles:
		attack_lineup.emit(unit, target)
		await _pace(AI_LINEUP_PAUSE)   # the camera glides over before the strike
		if state == State.ENDED or current != unit:
			attack_lineup_ended.emit()
			return
		use_ability(unit, ability, target.cell)
		if not presenting:
			attack_lineup_ended.emit()
	if presenting:
		await presentation_finished
	while log_gate.is_valid() and log_gate.call() and tree != null and state != State.ENDED:
		await tree.process_frame
	await _pace(AI_DELAY * 0.5)
	if state != State.ENDED and current == unit:
		end_turn()

## Cells already in range score by travel cost only; others by how far out of range they are.
func _ai_score(cell: Vector2i, target_cell: Vector2i, want_range: int, steps: int) -> int:
	return maxi(0, Grid.distance(cell, target_cell) - want_range) * 100 + steps

func _nearest_hostile(unit: Unit) -> Unit:
	var best: Unit = null
	var best_d := 1 << 30
	for u in units:
		if u.is_alive() and u.side != unit.side:
			var d := Grid.distance(u.cell, unit.cell)
			if d < best_d:
				best_d = d
				best = u
	return best

func _first_damaging(unit: Unit) -> Ability:
	for a in unit.abilities:
		if a.damage_dice != "" and not (a is SpellDef) and unit.can_use(a):
			return a
	return null

## 1.5 -> "1.5", 3.0 -> "3" (AP are always multiples of 0.5).
static func ap_str(v: float) -> String:
	return String.num(v, 1).trim_suffix(".0")

func _pace(seconds: float) -> void:
	if tree != null:
		await tree.create_timer(seconds).timeout
