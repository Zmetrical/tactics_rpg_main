extends RefCounted
## Builds the hover tooltip for a discipline row on the Skills tab as plain data. TooltipCard.build() (ui/hud/tooltip_card.gd)
## draws it. Pass no unit to get the discipline's rules alone, with no live rank or progress.
##
## Card: name, "Branch  STAT", the unit's rank, then what the discipline is, its archetypes, how far the unit has
## got through its skills, and what the next rank unlocks.

const Ability = preload("res://scripts/battle/ability.gd")
const Discipline = preload("res://scripts/skills/discipline.gd")
const SkillCatalog = preload("res://scripts/skills/skill_catalog.gd")
const Unit = preload("res://scripts/battle/unit.gd")

## How many skill names to list for "next rank unlocks" before saying "and N more".
const MAX_LISTED := 4

static func tip(id: StringName, unit: Unit = null) -> Dictionary:
	if not Discipline.exists(id):
		return {}
	var live := unit != null
	var stat := Discipline.stat_of(id)
	var stat_name := Discipline.stat_letters(stat)
	var branch := String(Discipline.BRANCH_NAMES.get(Discipline.branch_of(id), ""))
	var out := {"title": Discipline.display_name(id), "subtitle": "%s  %s" % [branch, stat_name]}
	if live:
		out["stats"] = "Rank %d" % unit.discipline_rank(id)

	var about: Array = []
	var blurb := String(Discipline.DEFS[id].get("blurb", ""))
	if blurb != "":
		about.append(blurb)
	var stat_line := "Runs on %s: its skills scale with that stat." % stat_name
	if live:
		stat_line = "Runs on %s (mod %+d): its skills scale with that stat." % [stat_name, unit.mod(stat)]
	about.append(stat_line)

	var blocks: Array = [about]
	var archetypes := Discipline.archetype_ids(id)
	if archetypes.size() > 1:
		var lines: Array = []
		for a in archetypes:
			var blurb_a := String(Discipline.DEFS[id]["archetypes"][a].get("blurb", ""))
			lines.append("%s: %s" % [Discipline.archetype_name(id, a), blurb_a])
		blocks.append(lines)

	var skills := _skills_of(id)
	if not skills.is_empty():
		var progress: Array = []
		if live:
			var known := 0
			for s in skills:
				if unit.knows(s):
					known += 1
			progress.append("Skills: %d learned of %d." % [known, skills.size()])
			var next_rank := unit.discipline_rank(id) + 1
			var next_names: Array[String] = []
			for s in skills:
				if int(s.all_requirements()[id]) == next_rank and not s.is_hybrid():
					next_names.append(s.display_name)
			if not next_names.is_empty():
				progress.append("Rank %d unlocks: %s." % [next_rank, _list(next_names)])
		else:
			progress.append("%d skills need this skill attribute." % skills.size())
		blocks.append(progress)
	out["blocks"] = blocks
	out["rules"] = ["A skill needs the listed rank in every skill attribute it names. Any unit can learn any skill it has the ranks for."]
	return out

## Every catalog skill that lists `id` among its requirements (hybrids included).
static func _skills_of(id: StringName) -> Array:
	var out: Array = []
	for s in SkillCatalog.all():
		if s.all_requirements().has(id):
			out.append(s)
	return out

static func _list(names: Array[String]) -> String:
	if names.size() <= MAX_LISTED:
		return ", ".join(names)
	return "%s and %d more" % [", ".join(names.slice(0, MAX_LISTED)), names.size() - MAX_LISTED]
