extends Node3D
## Input and HUD wiring. Drawing lives in stage_3d.gd; all rules live in battle.gd / rules.gd.
## Every HUD widget is a scene under res://ui/; this script owns the Battle connection and feeds
## the widgets through typed methods. The widgets never see Battle.

const Ability = preload("res://scripts/battle/ability.gd")
const Battle = preload("res://scripts/battle/battle.gd")
const CombatDirector = preload("res://scripts/battle/combat_director.gd")
const BiomeData = preload("res://scripts/battle/biome_data.gd")
const EncounterBuilder = preload("res://scripts/run/encounter_builder.gd")
const Equipment = preload("res://scripts/inventory/equipment.gd")
const Grid = preload("res://scripts/battle/grid.gd")
const Inventory = preload("res://scripts/inventory/inventory.gd")
const Item = preload("res://scripts/inventory/item.gd")
const MapLoader = preload("res://scripts/battle/map_loader.gd")
const Rules = preload("res://scripts/battle/rules.gd")
const RunTuning = preload("res://scripts/run/run_tuning.gd")
const ElectricSpells = preload("res://scripts/spells/aeromancy/electric_spells.gd")
const SkillCatalog = preload("res://scripts/skills/skill_catalog.gd")
const SpellDef = preload("res://scripts/spells/spell_def.gd")
const SpellGeo = preload("res://scripts/spells/spell_geometry.gd")
const SpellTargeting = preload("res://scripts/spells/spell_targeting.gd")
const Stage3D = preload("res://scripts/battle/stage_3d.gd")
const Unit = preload("res://scripts/battle/unit.gd")
const UnitSprites = preload("res://scripts/battle/unit_sprites.gd")
const UnitData = preload("res://scripts/battle/unit_data.gd")

# HUD scripts are preloaded (not referenced by class_name) so the scene runs without the
# editor's global-class cache, like the rest of this project.
const TurnForecast = preload("res://ui/turn_forecast.gd")
const AttackForecast = preload("res://ui/attack_forecast.gd")
const TurnOrderBarScript = preload("res://ui/turn_order_bar.gd")
const BattleUIScript = preload("res://ui/hud/battle_ui.gd")
## Camera framing while aiming: seconds to glide, and how far to push in on a close pair.
const AIM_CAMERA_TIME := 0.3
const AIM_ZOOM := 0.8
## Seconds to glide to the current unit at the start of its turn and after it moves.
const CENTER_CAMERA_TIME := 0.45
const UnitView = preload("res://ui/hud/unit_view.gd")
const ChargeTrackerScript = preload("res://ui/charge_tracker.gd")
const ReactionPromptScript = preload("res://ui/reaction_prompt.gd")
const BattleBannerScript = preload("res://ui/battle_banner.gd")
const EquipmentWindowScript = preload("res://ui/equipment_window.gd")

var biome_name := ""

## Run mode only (RunState.active): which Unit stands for which RunState party member, and whether this is the boss fight.
var _run_members := {}
var _run_is_boss := false
## Seconds the VICTORY / DEFEAT banner stays up before the run moves on.
const RESULT_HOLD := 2.0

## The party's shared stash. Gear taken off a unit lands here; the equipment window (key I) draws from it.
const STARTING_BAG: Array[String] = [
	"res://data/items/shortsword.tres",
	"res://data/items/greataxe.tres",
	"res://data/items/tower_shield.tres",
	"res://data/items/spellbook.tres",
	"res://data/items/iron_greaves.tres",
	"res://data/items/leather_brace.tres",
	"res://data/items/copper_ring.tres",
	"res://data/items/silver_ring.tres",
	"res://data/items/jade_ring.tres",
	"res://data/items/sun_amulet.tres",
]

## Map legend (produced by map_loader.gd): '.' = no tile, '0'-'3' = height, '#' = wall,
## 'P' / 'E' = player / enemy start. Start tile heights come from MapResult.start_heights.
const PLAYER_UNITS: Array[String] = [
	"res://data/units/fighter.tres",
	"res://data/units/mage.tres",
	"res://data/units/ranger.tres",
]
const HL_REACH := Color(0.2, 0.5, 1.0, 0.35)    # blue: where the current unit can walk
const HL_RANGE := Color(1.0, 0.3, 0.2, 0.25)    # red: ability range
const HL_AREA := Color(1.0, 0.75, 0.1, 0.5)    # orange: area under the cursor
const HL_CURRENT := Color(1.0, 1.0, 0.3, 0.5)  # yellow: the unit whose turn it is
const HL_PENDING := Color(0.7, 0.3, 1.0, 0.4)  # purple: tiles a charging spell is locked onto
const HL_CHARGER := Color(0.9, 0.55, 1.0, 0.55)  # light purple: a unit that is mid-cast
const HL_SPELL_ECHO := Color(0.3, 0.9, 1.0, 0.45)  # cyan: reduced-damage tiles (bounce, shockwave, side arcs)
const HL_SPELL_PATH := Color(1.0, 0.95, 0.4, 0.5)  # yellow: a drawn path or bolt line

## How many upcoming turns the turn order bar asks the forecast for.
const FORECAST_TURNS := 8

## Swap this to play another biome (plains, forest, ridge, or your own .tres).
@export_file("*.tres") var biome_path: String = "res://data/biomes/plains.tres"
## Size folder to pick a map from: res://scenes/maps/<biome>/<size>/.
@export_enum("small", "medium", "large") var map_size: String = "medium"
## 0 = random map every run. Any other value replays the same map.
@export var map_seed: int = 0
## Testing: play exactly this map scene instead of a random one from the biome / size folder.
## Leave empty for the normal random pick.
@export_file("*.tscn") var force_map_path: String = ""
## Sample content: gives every player unit with spellcasting (the Mage) the four Aeromancy / Electric
## spells so the spell system can be tried in the live battle. Turn off to play the original kit.
## Spells cost Action Points; the tier is picked per cast (click the aimed spell again, or keys 1 / 2 / 3 while aiming).
@export var grant_sample_spells := true
## Sample content: every player unit learns the catalog skills (scripts/skills/skill_catalog.gd) it meets the attribute and
## discipline requirements for, until its skill slots are full. Turn off to start with none.
@export var grant_class_skills := true

@onready var stage: Stage3D = $Stage
@onready var ui: CanvasLayer = $UI

@onready var turn_bar: TurnOrderBarScript = %TurnOrderBar
@onready var hud: BattleUIScript = %BattleUI
@onready var charge_tracker: ChargeTrackerScript = %ChargeTracker
@onready var reaction_prompt: ReactionPromptScript = %ReactionPrompt
@onready var banner: BattleBannerScript = %BattleBanner
@onready var equipment_window: EquipmentWindowScript = %EquipmentWindow

var battle: Battle
## Plays every resolved action out on the map (camera push-in, lunge, projectile, hit feel).
## Tune it live: director.speed, .enabled, .shake_enabled, .hit_stop_enabled, .camera_focus_enabled.
var director: CombatDirector
var grid: Grid
var rng := RandomNumberGenerator.new()
var hover_cell := Vector2i(-99, -99)
var _highlights_queued := false
var _refresh_queued := false
## What a charged spell locks onto when you click: false = the tile, true = the unit on it.
var lock_on_unit := false
## Aiming session for spells that need more than one click (pivot, path, fork, direction).
var spell_session: SpellTargeting = null
## Tier (1-3) the player has chosen for the spell being aimed. Resets to 1 for every new aim.
var aim_tier := 1
var _aim_spell: Ability = null
## Shared by every player unit. Filled from STARTING_BAG. A grid, Diablo 2 style: equipping takes an item out, unequipping
## puts it back. The equipment window edits it.
var party_bag: Inventory = Inventory.new()

func _ready() -> void:
	if RunState.active:
		rng = RunState.rng  # one rng per run, seeded by RunState.seed
	elif map_seed != 0:
		rng.seed = map_seed
	else:
		rng.randomize()

	var run_enc := {}
	var player_count := PLAYER_UNITS.size()
	if RunState.active:
		run_enc = EncounterBuilder.build(RunState.map.nodes[RunState.current_node], rng)
		biome_path = run_enc["biome_path"]
		map_size = run_enc["map_size"]
		force_map_path = run_enc["force_map_path"]
		_run_is_boss = run_enc["is_boss"]
		player_count = RunState.party.size()

	var biome: BiomeData = load(biome_path)
	if RunState.active:
		biome = EncounterBuilder.scaled_biome(biome, run_enc["enemy_scale"])
	var biome_folder := biome_path.get_file().get_basename()
	biome_name = biome_folder.capitalize()
	var generated: MapLoader.MapResult
	if force_map_path.is_empty():
		generated = MapLoader.load_map(biome_folder, map_size, biome, rng, player_count)
	else:
		generated = MapLoader.build(force_map_path, biome, rng, player_count)
		generated.size_name = map_size
	if not generated.valid:
		return  # map_loader already reported why via push_error

	banner.set_map_info(biome_name, map_size.capitalize(), generated.scene_path.get_file().get_basename().capitalize(),
		generated.enemy_cells.size(), _population_category(generated))

	var starts := _build_grid(generated)
	stage.build_map(grid, Vector2i(generated.width, generated.height))
	stage.build_props(generated.props)
	stage.build_tile_layers(generated.scene_path)

	var units: Array[Unit] = []
	for i in starts["P"].size():
		units.append(_make_player_unit(i, starts["P"][i]))
	for i in starts["E"].size():
		var ed: UnitData = generated.enemy_units[i]
		var enemy := Unit.new(ed, Unit.Side.ENEMY, starts["E"][i])
		if RunState.active:
			EncounterBuilder.scale_enemy(enemy, run_enc["enemy_scale"])
		units.append(enemy)

	if grant_sample_spells:
		for u in units:
			if u.side == Unit.Side.PLAYER and _is_caster(u):
				for spell in ElectricSpells.all():
					u.learn(spell)

	if grant_class_skills:
		for u in units:
			if u.side == Unit.Side.PLAYER:
				for skill in SkillCatalog.all():
					u.learn(skill)  # silently skipped when requirements or slots say no

	battle = Battle.new(grid, units, rng)
	battle.tree = get_tree()
	for u in units:
		u.height = grid.height_at(u.cell)
		stage.add_unit(u)
	_face_opponents(units)

	director = CombatDirector.new()
	director.name = "CombatDirector"
	add_child(director)
	director.setup(stage, battle)
	director.finished.connect(_queue_refresh)
	director.unit_hit.connect(func(u: Unit) -> void: hud.unit_stats_changed.emit(u))
	director.finished.connect(hud.unlock_victim)
	battle.action_executed.connect(_on_action_for_hud)
	battle.attack_lineup.connect(_on_attack_lineup)
	battle.attack_lineup_ended.connect(_on_attack_lineup_ended)
	battle.log_gate = hud.is_log_busy

	# HUD: intent out (hud signals -> Battle), facts in (Battle signals -> hud signals).
	hud.setup(stage.camera, _hud_anchor, Stage3D.PIXEL_SIZE * float(UnitSprites.FRAME) * 0.5, stage.map_center)
	hud.action_chosen.connect(_on_action_chosen)
	hud.target_confirmed.connect(_on_target_confirmed)
	hud.end_turn_requested.connect(_on_end_pressed)
	hud.zoom_requested.connect(func(zoom_in: bool) -> void: stage.zoom(Stage3D.ZOOM_FACTOR if zoom_in else 1.0 / Stage3D.ZOOM_FACTOR))
	hud.inventory_requested.connect(func() -> void: _open_equipment(battle.current))
	hud.aim_back_requested.connect(_aim_back)
	hud.aim_tier_up_requested.connect(_on_aim_tier_up)
	hud.lock_mode_changed.connect(_set_lock_mode)
	hud.confirm_cancelled.connect(_on_confirm_cancelled)
	reaction_prompt.answered.connect(_on_reaction_answered)
	if RunState.active:
		party_bag = RunState.bag  # the run's shared stash
	else:
		for path in STARTING_BAG:
			if party_bag.add(load(path)) == null:
				push_warning("Starting bag is full, dropped %s" % path)
	equipment_window.equipment_changed.connect(_on_equipment_changed)
	equipment_window.unit_requested.connect(_open_equipment)
	var party: Array[Unit] = []
	for u in units:
		if u.side == Unit.Side.PLAYER:
			party.append(u)
	equipment_window.set_party(party)
	equipment_window.closed.connect(_queue_refresh)
	equipment_window.closed.connect(hud.inventory_closed.emit)

	# Signal -> widget map (every HUD refresh goes through _queue_refresh):
	#   turn_started / turn_ended / state_changed / resources_changed -> active panel, command menu, turn bar
	#   cast_started / cast_resolved / cast_cancelled                  -> charge tracker, turn bar
	#   damage_dealt / unit_died                                       -> active panel HP, turn bar, inspect
	#   log_message -> combat log; reaction_prompt -> reaction modal; battle_ended -> banner
	battle.state_changed.connect(_on_battle_state_changed)
	battle.turn_started.connect(func(u: Unit) -> void:
		_center_on(u)
		_queue_refresh())
	battle.turn_ended.connect(func(_u: Unit) -> void: _queue_refresh())
	battle.resources_changed.connect(_queue_refresh)
	battle.unit_stepped.connect(_on_unit_stepped)
	battle.damage_dealt.connect(_on_damage_dealt)
	battle.unit_died.connect(_on_unit_died)
	battle.log_message.connect(hud.log_line_pushed.emit)
	battle.reaction_prompt.connect(_on_reaction_prompt)
	battle.battle_ended.connect(_on_battle_ended)
	battle.battle_ended.connect(func(_won: bool) -> void: hud.battle_finished.emit())
	battle.cast_started.connect(func(_c: Battle.PendingCast) -> void: _queue_refresh())
	battle.cast_resolved.connect(func(_c: Battle.PendingCast) -> void: _queue_refresh())
	battle.cast_cancelled.connect(func(_c: Battle.PendingCast, _r: String) -> void: _queue_refresh())

	battle.start()

# --- Run ---------------------------------------------------------------------

## Player unit `i`: the standalone roster, or (in a run) the party member's current HP and worn gear.
func _make_player_unit(i: int, cell: Vector2i) -> Unit:
	if not RunState.active:
		return Unit.new(load(PLAYER_UNITS[i % PLAYER_UNITS.size()]), Unit.Side.PLAYER, cell)
	var member = RunState.party[i]
	var u := Unit.new(member.unit_data, Unit.Side.PLAYER, cell)
	for slot in Equipment.ALL_SLOTS:
		u.equipment.unequip(slot)
	for slot in Equipment.ALL_SLOTS:
		var worn: Item = member.equipment.get_item(slot)
		if worn != null:
			u.equipment.try_equip(worn, slot)
	u.hp = clampi(member.current_hp, 1, u.max_hp)
	_run_members[u] = member
	return u

## Writes HP and worn gear back into RunState.party, then moves the run on after the banner.
func _leave_battle(player_won: bool) -> void:
	for u: Unit in _run_members:
		var member = _run_members[u]
		member.current_hp = maxi(u.hp, RunTuning.REVIVE_HP if player_won else 0)
		var worn := Equipment.new()
		for slot in Equipment.ALL_SLOTS:
			var item: Item = u.equipment.get_item(slot)
			if item != null:
				worn.try_equip(item, slot)
		member.equipment = worn
	await get_tree().create_timer(RESULT_HOLD).timeout
	if not player_won:
		RunFlow.go("defeat")
	elif _run_is_boss:
		RunFlow.go("victory")
	else:
		RunFlow.go("reward")

# --- Map ---------------------------------------------------------------------

## Builds `grid` straight from the loaded rows and returns the P / E start cells.
## Every non-'.' character is a tile; '#' is a wall at Stage3D.WALL_LEVEL; P / E tiles take
## their painted height from MapResult.start_heights.
func _build_grid(generated: MapLoader.MapResult) -> Dictionary:
	grid = Grid.new()
	var starts := {"P": [] as Array[Vector2i], "E": [] as Array[Vector2i]}
	for y in generated.rows.size():
		var row: String = generated.rows[y]
		for x in row.length():
			var ch: String = row[x]
			var cell := Vector2i(x, y)
			if ch == ".":
				continue
			elif ch == "#":
				grid.set_tile(cell, Stage3D.WALL_LEVEL, true)
			elif ch == "P" or ch == "E":
				grid.set_tile(cell, int(generated.start_heights.get(cell, 0)))
				starts[ch].append(cell)
			else:
				grid.set_tile(cell, int(ch))
	for rec: Dictionary in generated.grid_props:
		grid.add_prop(int(rec["id"]), rec["cells"], bool(rec["blocks_movement"]),
			bool(rec["blocks_projectiles"]), bool(rec["targetable"]))
	return starts

## Screen position -> tile, through the stage's camera. NO_CELL when the ray hits nothing.
func _mouse_cell() -> Vector2i:
	var pos := get_viewport().get_mouse_position()
	return Stage3D.pick_cell(stage.camera.project_ray_origin(pos), stage.camera.project_ray_normal(pos), grid)

# --- Units -------------------------------------------------------------------

## At the start of a battle everyone looks at the nearest unit on the other side, so units that face
## away from the camera show their backs. (After walking or fighting they turn to the camera.)
func _face_opponents(units: Array[Unit]) -> void:
	for u in units:
		var nearest: Unit = null
		var best := INF
		for other in units:
			if other.side == u.side:
				continue
			var d := Vector2(other.cell - u.cell).length()
			if d < best:
				best = d
				nearest = other
		if nearest != null:
			stage.face_toward(u, stage.unit_rest(nearest))

func _on_unit_stepped(u: Unit, _cell: Vector2i) -> void:
	stage.move_unit(u)
	_update_highlights()

## HP labels, hit reactions and the death fade are timed by the director (it receives the same
## fight through Battle.action_executed), so nothing is drawn here: only the HUD refresh.
## Every attack shows its victim's panel while it plays. Attacks the player confirmed already lock the
## panel through the target panel; this covers the rest (enemy turns, opportunity attacks, casts landing).
func _on_action_for_hud(user: Unit, _ability: Ability, _cell: Vector2i, results: Array, _tag: String) -> void:
	if hud.state == BattleUIScript.State.EXECUTING or hud.is_hover_locked():
		return
	for r: Dictionary in results:
		var victim: Unit = r["unit"]
		if victim != null and victim != user and stage.has_unit(victim):
			hud.lock_victim(victim)
			return

## An AI unit is in position: frame it with its target and show the target's panel right away, so the
## pair is already in view when the strike starts (the director keeps the same framing from there).
func _on_attack_lineup(user: Unit, target: Unit) -> void:
	if _busy() or not stage.has_unit(user) or not stage.has_unit(target):
		return
	_frame_pair(user, target)
	hud.lock_victim(target)

func _on_attack_lineup_ended() -> void:
	stage.camera_release(AIM_CAMERA_TIME)
	hud.unlock_victim()

## The camera rests on the current unit, so its panel (beside the unit) always has room on screen.
## During an attack animation only the resting point changes; the director releases to it afterwards.
func _center_on(u: Unit) -> void:
	if u == null or stage == null or not stage.has_unit(u):
		return
	stage.set_camera_home(stage.holder_of(u).global_position, not _busy(), CENTER_CAMERA_TIME)

## While aiming, frame the current unit and the unit under the cursor (or the picked target) together.
func _frame_aim(target: Unit) -> void:
	var cur := battle.current
	if cur == null or _busy() or not stage.has_unit(cur):
		return
	if target == null or target == cur or not stage.has_unit(target):
		stage.camera_release(AIM_CAMERA_TIME)
		return
	_frame_pair(cur, target)

## Glide the camera to the midpoint of two units (pushes in when they are close).
func _frame_pair(a: Unit, b: Unit) -> void:
	var mid: Vector3 = stage.holder_of(a).global_position.lerp(stage.holder_of(b).global_position, 0.5)
	var gap := Vector2(a.cell - b.cell).length()
	var zoom := lerpf(AIM_ZOOM, 1.0, clampf((gap - 2.0) / 5.0, 0.0, 1.0))
	stage.camera_focus(mid, zoom, AIM_CAMERA_TIME)

func _on_damage_dealt(_a: Unit, _victim: Unit, _amount: int, _info: Dictionary) -> void:
	_queue_refresh()

func _on_unit_died(_u: Unit) -> void:
	_queue_refresh()

# --- HUD ---------------------------------------------------------------------

func _population_category(g: MapLoader.MapResult) -> String:
	var n := g.enemy_cells.size()
	if n <= 3:
		return "Sparse"
	if n == 4:
		return "Moderate"
	return "Crowded"

func _unit_at(cell: Vector2i) -> Unit:
	for u in battle.units:
		if u.is_alive() and u.cell == cell:
			return u
	return null

## True while an attack is playing out on the map.
func _busy() -> bool:
	return director != null and director.busy

func _player_turn() -> bool:
	return battle.current != null and battle.current.side == Unit.Side.PLAYER and battle.state != Battle.State.ENDED and not _busy()

## Battle emits state_changed(TARGETING) BEFORE it assigns targeting_ability, and does not
## emit again when the player switches straight from one ability to another. Reading the
## state inside the signal would mark the wrong command entry, so the HUD refreshes once,
## at the end of the frame, like the highlights do.
func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_refresh_hud.call_deferred()

func _refresh_hud() -> void:
	_refresh_queued = false
	if battle == null:
		return
	if _busy():
		# The HUD keeps showing the pre-action numbers until the hit lands; director.finished
		# queues the real refresh. Only the controls are locked.
		_update_highlights()
		return
	var cur := battle.current
	var moving := battle.state == Battle.State.MOVING
	var can_act := cur != null and _player_turn() and not battle.is_charging(cur) and not moving
	var cast_rows := _cast_rows()

	hud.set_context(cur, can_act, _player_turn() and not moving)
	for u in battle.units:
		hud.unit_stats_changed.emit(u)
	turn_bar.update_order(TurnForecast.predict_timeline(battle.units, cast_rows, cur, FORECAST_TURNS))
	charge_tracker.update_casts(cast_rows)
	_update_highlights()
	_update_move_preview()

## One row per pending cast, oldest first: {"caster": Unit, "spell": String, "ticks": int}.
func _cast_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for cast: Battle.PendingCast in battle.pending_casts:
		var spell: String = cast.ability.display_name
		if cast.target != null:
			spell += " on %s" % cast.target.unit_name
		rows.append({"caster": cast.caster, "spell": spell, "ticks": cast.ticks_left})
	return rows

func _forecast_rows(cur: Unit, a: Ability, cell: Vector2i) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for row: Dictionary in battle.preview(cur, a, cell):
		rows.append(AttackForecast.build(cur, row["unit"], a, int(row["mode"])))
	return rows

## The aiming session for the spell being targeted, created on demand and dropped when targeting ends.
func _session() -> SpellTargeting:
	var a := battle.targeting_ability if battle != null and battle.state == Battle.State.TARGETING else null
	if a == null or not (a is SpellDef) or battle.current == null:
		spell_session = null
		return null
	if a != _aim_spell:
		_aim_spell = a
		aim_tier = 1
	if spell_session == null or spell_session.ctx.spell != a or spell_session.ctx.caster != battle.current or spell_session.ctx.tier != aim_tier:
		spell_session = SpellTargeting.new(battle.spell_context(battle.current, a, aim_tier))
	return spell_session

## Spellcasters are the units that start with a spell level on any ability (the Mage's Burning Burst).
func _is_caster(u: Unit) -> bool:
	for a in u.abilities:
		if a.slot_level > 0:
			return true
	return false

## The aimed spell's slot was clicked again: one tier up (Base -> Tier 2 -> Tier 3). Nothing happens when the spell has no
## higher tier; when the unit can't pay for the next tier a log line says what it costs.
func _on_aim_tier_up() -> void:
	var sess := _session()
	if sess == null or aim_tier >= sess.ctx.spell.max_tier:
		return
	_set_aim_tier(aim_tier + 1)

## Keys 1 / 2 / 3 while aiming: pick the tier for this cast. Costs more AP, so an unaffordable
## tier is refused. Tiers change the aim steps, so the aim starts over.
func _set_aim_tier(tier: int, announce := true) -> void:
	var sess := _session()
	if sess == null:
		return
	var spell: SpellDef = sess.ctx.spell
	tier = clampi(tier, 1, spell.max_tier)
	if tier == aim_tier:
		return
	var cost := spell.ap_cost_for_tier(tier)
	if not battle.current.can_afford(cost):
		if announce:
			battle.log_message.emit("Tier %d needs %s AP, %s has %s" % [tier, Battle.ap_str(cost), battle.current.unit_name, Battle.ap_str(battle.current.ap)])
		return
	aim_tier = tier
	spell_session = null
	hud.set_aim_tier(aim_tier)
	_update_highlights()

static func _tier_for_key(keycode: int) -> int:
	match keycode:
		KEY_1, KEY_KP_1:
			return 1
		KEY_2, KEY_KP_2:
			return 2
		KEY_3, KEY_KP_3:
			return 3
	return 0

## Tile / Unit lock for charged casts. The forecast box's TILE / UNIT buttons and the L key both land here, while
## aiming and while the target panel is open (then the pending cast is switched too, nothing is re-aimed).
func _set_lock_mode(on_unit: bool) -> void:
	if on_unit and _confirming() and _unit_at(_pending_cell) == null:
		battle.log_message.emit("No unit there to lock onto")
		on_unit = false
	lock_on_unit = on_unit
	if _pending_session != null and not _pending_session.steps.is_empty() and _pending_session.steps[0].lockable:
		_pending_session.lock_unit = on_unit
		_pending_session.plan.lock_unit = on_unit
	_push_lock_mode()

func _confirming() -> bool:
	return hud.state == BattleUIScript.State.CONFIRM and hud.confirm_kind == BattleUIScript.Confirm.ATTACK

## Tells the forecast box what the buttons should show.
func _push_lock_mode() -> void:
	hud.set_lock_mode(lock_on_unit, not _confirming() or _unit_at(_pending_cell) != null)

## One left click while aiming a spell. Commits the cast once every aim step is answered.
func _spell_click(sess: SpellTargeting, cell: Vector2i) -> void:
	sess.lock_unit = lock_on_unit
	if not sess.click(cell):
		if sess.last_error != "":
			battle.log_message.emit(sess.last_error)
		return
	if sess.is_complete():
		_begin_spell_confirm(sess)
	else:
		_update_highlights()

func _commit_spell(sess: SpellTargeting) -> void:
	var spell: SpellDef = sess.ctx.spell
	spell_session = null
	_aim_spell = null
	battle.use_ability(battle.current, spell, sess.plan.cell, sess.plan.lock_unit, sess.plan)

## Preview rows for a spell: the usual forecast per victim, with the damage scaled by that victim's share.
func _spell_rows(cur: Unit, a: Ability, sess: SpellTargeting) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for h: Dictionary in sess.preview().hits:
		var u: Unit = h["unit"]
		var row := AttackForecast.build(cur, u, a, Rules.get_roll_mode(cur, u, a, battle.units))
		var scale: float = h["scale"]
		if not is_equal_approx(scale, 1.0):
			row["dmg"] = roundi(int(row["dmg"]) * scale)
			row["note"] = "%s  x%d%%" % [row["note"], roundi(scale * 100.0)]
		row["scale"] = scale
		rows.append(row)
	return rows

## --- Attack flow (HUD intent -> Battle) -------------------------------------------
## action menu -> enter targeting -> click a target -> target panel -> CONFIRM -> use_ability.
## Nothing reaches Battle's rules until CONFIRM; CANCEL spends nothing.

var _pending_cell := Vector2i.ZERO
var _pending_session: SpellTargeting = null
var _prev_battle_state: int = Battle.State.WAIT_INPUT

func _on_action_chosen(action_id: int) -> void:
	var cur := battle.current
	if cur == null or action_id < 0 or action_id >= cur.abilities.size():
		hud.aim_cancelled()
		return
	aim_tier = 1
	spell_session = null
	_aim_spell = null
	_push_lock_mode()
	if not battle.enter_targeting(cur.abilities[action_id]):
		hud.aim_cancelled()

func _on_battle_state_changed(s: int) -> void:
	if _prev_battle_state == Battle.State.MOVING and s == Battle.State.WAIT_INPUT:
		_center_on(battle.current)
	_prev_battle_state = s
	_queue_refresh()

## Left click on the map while the HUD is in TARGET_SELECT.
func _target_click(cell: Vector2i) -> void:
	var cur := battle.current
	var a := battle.targeting_ability
	if cur == null or a == null:
		return
	var sess := _session()
	if sess != null:
		_spell_click(sess, cell)
		return
	if Grid.distance(cur.cell, cell) > a.range_tiles:
		battle.log_message.emit("Out of range")
		return
	if a.is_charged():
		if not grid.can_aim_at(cell):
			battle.log_message.emit("No valid target there")
			return
		if lock_on_unit and _unit_at(cell) == null:
			battle.log_message.emit("No unit there to lock onto")
			return
	var rows := _forecast_rows(cur, a, cell)
	if rows.is_empty() and not a.is_charged():
		battle.log_message.emit("No valid target there")
		return
	_pending_cell = cell
	_pending_session = null
	_open_confirm(cur, a, cell, rows, 1)

func _begin_spell_confirm(sess: SpellTargeting) -> void:
	var cur := battle.current
	var spell: SpellDef = sess.ctx.spell
	var rows := _spell_rows(cur, spell, sess)
	if rows.is_empty() and not spell.is_charged():
		battle.log_message.emit("No valid target there")
		sess.back()
		_update_highlights()
		return
	_pending_cell = sess.plan.cell
	_pending_session = sess
	_open_confirm(cur, spell, sess.plan.cell, rows, aim_tier)

## Builds the forecast for the primary target (the unit on the clicked tile, else the first victim)
## and opens the target panel through the HUD.
func _open_confirm(cur: Unit, a: Ability, cell: Vector2i, rows: Array[Dictionary], tier: int) -> void:
	var primary := _unit_at(cell)
	var row: Dictionary = {}
	for r: Dictionary in rows:
		if r["defender"] == primary:
			row = r
	if row.is_empty() and not rows.is_empty():
		row = rows[0]
		primary = row["defender"]
	elif row.is_empty():
		primary = null
	var foot := ""   # the Tile / Unit lock line is the forecast box's own; only a warning goes here
	for r: Dictionary in rows:
		if (r["defender"] as Unit).side == cur.side:
			foot = "FRIENDLY FIRE"
	var forecast := UnitView.forecast(row, a, tier, rows.size() - 1, foot) if not row.is_empty() else UnitView.forecast_empty(a, tier, foot)
	hud.begin_confirm(primary, cell, forecast)
	_push_lock_mode()   # UNIT is greyed out when the picked tile is empty
	if primary != null:
		_frame_aim(primary)   # keep the pair framed while the target panel is open

func _on_confirm_cancelled() -> void:
	_push_lock_mode()
	# The spell's last aim step is answered; reopen it so the next click re-aims.
	if _pending_session != null:
		_pending_session.back()
		_pending_session = null
	_update_highlights()
	_frame_aim(_unit_at(hover_cell))

## aim back (Esc / right-click / B in TARGET_SELECT): undo one aim step, else drop a raised tier back to Base,
## else leave targeting.
func _aim_back() -> void:
	var sess := _session()
	if sess != null and sess.back():
		_update_highlights()
		return
	if sess != null and aim_tier > 1:
		# Nothing left to undo but a raised tier: Esc drops it back to Base (the aim restarts) and keeps the spell aimed.
		aim_tier = 1
		spell_session = null
		hud.set_aim_tier(aim_tier)
		_update_highlights()
		return
	spell_session = null
	_aim_spell = null
	stage.camera_release(AIM_CAMERA_TIME)
	battle.cancel_targeting()
	hud.aim_cancelled()

func _on_target_confirmed(_target: Unit) -> void:
	_run_confirmed_attack()

func _run_confirmed_attack() -> void:
	var cur := battle.current
	var a := battle.targeting_ability
	if _pending_session != null:
		var sess := _pending_session
		_pending_session = null
		_commit_spell(sess)
	elif cur != null and a != null:
		battle.use_ability(cur, a, _pending_cell, lock_on_unit)
	if battle.presenting:
		await battle.presentation_finished
	if battle.state == Battle.State.TARGETING:
		battle.cancel_targeting()   # the attack was refused (the reason is in the log)
	spell_session = null
	_aim_spell = null
	_queue_refresh()
	hud.attack_resolved.emit()

## World point the HUD panels follow: the unit's chest (follows hops and knockback), or a tile.
func _hud_anchor(subject: Variant) -> Vector3:
	if subject is Vector2i:
		return stage.cell_top(subject) + Vector3(0.0, 0.5, 0.0)
	var u: Unit = subject
	if u == null or not stage.has_unit(u):
		return Vector3.ZERO
	return stage.holder_of(u).global_position + (stage.unit_chest(u) - stage.unit_rest(u))

func _on_end_pressed() -> void:
	if _player_turn():
		battle.end_turn()

func _on_reaction_prompt(reactor: Unit, mover: Unit) -> void:
	reaction_prompt.open(reactor, mover)

func _on_reaction_answered(take_it: bool) -> void:
	battle.answer_reaction(take_it)

func _on_battle_ended(player_won: bool) -> void:
	if battle.presenting:
		await battle.presentation_finished
	banner.show_result(player_won)
	reaction_prompt.close()
	_queue_refresh()
	if RunState.active:
		_leave_battle(player_won)

# --- Equipment ---------------------------------------------------------------

func _is_equipment_key(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_I

## Opens the equipment window for `unit` (null = whoever's turn it is). Your units are editable on
## your turn while idle; enemies, and your units at any other time, are a read-only preview.
func _open_equipment(unit: Unit) -> void:
	if battle == null or _busy():
		return
	var target: Unit = unit if unit != null else battle.current
	if target == null:
		return
	var editable := target.side == Unit.Side.PLAYER and _player_turn() and battle.state != Battle.State.MOVING
	var note := ""
	if target.side == Unit.Side.PLAYER and not editable:
		note = "Preview only. Gear can be changed on your turn."
	elif target.side == Unit.Side.ENEMY:
		note = "Enemy gear is preview only."
	if editable and battle.state == Battle.State.TARGETING:
		battle.cancel_targeting()
		hud.aim_cancelled()
	equipment_window.open(target, party_bag, editable, note)

## Gear changed: the unit's ability list was rebuilt, so any aim in progress is stale.
func _on_equipment_changed(_unit: Unit) -> void:
	if battle.state == Battle.State.TARGETING:
		battle.cancel_targeting()
		hud.aim_cancelled()
	_queue_refresh()

# --- Input and highlights ----------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if battle == null:
		return
	# The equipment window is modal: it swallows everything except the keys that close it.
	if equipment_window.visible:
		if event.is_action_pressed("ui_cancel") or _is_equipment_key(event):
			equipment_window.close()
		return
	# The HUD state machine gets first refusal (menu navigation, Back, log advance, confirm panel).
	if hud.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if _is_equipment_key(event):
		_open_equipment(_unit_at(hover_cell))
		return
	var aiming: bool = hud.state == BattleUIScript.State.TARGET_SELECT
	if event is InputEventMouseMotion:
		var c := _mouse_cell()
		if c != hover_cell:
			hover_cell = c
			if aiming and _session() != null:
				spell_session.hover(c)
			_update_highlights()
			_update_move_preview()
			hud.set_hover_unit(_unit_at(c))
			if aiming:
				_frame_aim(_unit_at(c))
	elif event is InputEventMouseButton and event.pressed:
		var clicked := _unit_at(_mouse_cell())
		# Clicking a unit opens its gear, except while aiming (then the click picks a target).
		if event.button_index == MOUSE_BUTTON_LEFT and clicked != null and battle.state != Battle.State.TARGETING:
			_open_equipment(clicked)
		elif _player_turn() and event.button_index == MOUSE_BUTTON_LEFT:
			if aiming:
				_target_click(_mouse_cell())
			elif hud.state == BattleUIScript.State.ROOT_MENU:   # clicking a blue tile walks there, no MOVE button
				battle.handle_cell_click(_mouse_cell(), lock_on_unit)
				_update_move_preview()
	elif event is InputEventKey and event.pressed and not event.echo and aiming and _player_turn():
		if event.keycode == KEY_L:
			_set_lock_mode(not lock_on_unit)   # same as the TILE / UNIT buttons on the forecast box
		elif _tier_for_key(event.keycode) > 0 and _session() != null:
			_set_aim_tier(_tier_for_key(event.keycode))
	elif event.is_action_pressed("ui_accept") and aiming and _player_turn() and _session() != null:
		# Enter skips an optional aim step (the pivot, a fork).
		if spell_session.skip():
			_begin_spell_confirm(spell_session)

## Hovering a blue tile on the player's turn marks its cost on the movement bar; anywhere else clears it.
func _update_move_preview() -> void:
	var cost := 0
	var cur := battle.current
	if cur != null and _player_turn() and hud.state == BattleUIScript.State.ROOT_MENU and battle.state == Battle.State.WAIT_INPUT and hover_cell != cur.cell:
		var reach := battle.reachable_cells(cur)
		if reach.has(hover_cell):
			cost = int(reach[hover_cell])
	hud.set_move_preview(cost)

## Highlights are rebuilt once at the end of the frame, not inside the signal that asked.
## Battle emits state_changed(TARGETING) before it assigns targeting_ability, so a
## synchronous rebuild would see TARGETING with no ability.
func _update_highlights() -> void:
	if _highlights_queued:
		return
	_highlights_queued = true
	_rebuild_highlights.call_deferred()

## Colours: blue reachable, red range, orange area, yellow current.
## Later entries win when two layers cover one cell.
func _rebuild_highlights() -> void:
	_highlights_queued = false
	if stage == null or grid == null:
		return
	if _busy():
		stage.set_highlights({})
		return
	var colors := {}
	if battle != null:
		for cast: Battle.PendingCast in battle.pending_casts:
			for c: Vector2i in battle.cast_cells(cast):
				colors[c] = HL_PENDING
		for cast: Battle.PendingCast in battle.pending_casts:
			colors[cast.caster.cell] = HL_CHARGER
	if battle != null and battle.current != null and battle.state != Battle.State.ENDED:
		var cur := battle.current
		if _player_turn():
			if battle.state == Battle.State.WAIT_INPUT:
				for c: Vector2i in battle.reachable_cells(cur).keys():
					if c != cur.cell:
						colors[c] = HL_REACH
			elif battle.state == Battle.State.TARGETING and battle.targeting_ability != null:
				var a := battle.targeting_ability
				var sess := _session()
				if sess != null:
					_spell_highlights(sess, colors)
				else:
					for c: Vector2i in grid.heights.keys():
						if grid.is_aim_tile(c) and Grid.distance(cur.cell, c) <= a.range_tiles:
							colors[c] = HL_RANGE
					if grid.can_aim_at(hover_cell) and Grid.distance(cur.cell, hover_cell) <= a.range_tiles:
						for c: Vector2i in grid.heights.keys():
							if grid.is_aim_tile(c) and Grid.distance(hover_cell, c) <= a.area_radius:
								colors[c] = HL_AREA
		colors[cur.cell] = HL_CURRENT
	stage.set_highlights(colors)

## Spell aiming colours: the range diamond while picking a unit / tile, then the spell's own preview
## (orange full strength, cyan reduced, yellow path) and the tiles already drawn.
func _spell_highlights(sess: SpellTargeting, colors: Dictionary) -> void:
	var step := sess.current_step()
	if step != null and (step.kind == step.Kind.UNIT or step.kind == step.Kind.TILE):
		for c: Vector2i in grid.heights.keys():
			if grid.is_aim_tile(c) and Grid.distance(battle.current.cell, c) <= sess.ctx.spell.range_tiles:
				colors[c] = HL_RANGE
	for row: Dictionary in sess.preview().cells:
		match String(row["tag"]):
			"main":
				colors[row["cell"]] = HL_AREA
			"echo":
				colors[row["cell"]] = HL_SPELL_ECHO
			_:
				colors[row["cell"]] = HL_SPELL_PATH
	for c: Vector2i in sess.draft:
		colors[c] = HL_SPELL_PATH
