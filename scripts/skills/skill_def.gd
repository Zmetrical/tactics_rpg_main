extends "res://scripts/battle/ability.gd"
## A learnable class skill. It is an Ability (cost, range, dice, hotbar, tooltips all keep working) plus the
## learning requirement: a rank in one or more disciplines ("Requires 2 Rogue", or "Requires 2 Cinder, 1 Torrent").
##
## `school` / `subschool` (read by the tooltip) are filled from discipline / archetype, so the card subtitle
## shows e.g. "ROGUE . ASSASSIN" with no UI change.

const Discipline = preload("res://scripts/skills/discipline.gd")

## Key into Discipline.DEFS.
@export var discipline: StringName = &""
## Key into that discipline's archetypes.
@export var archetype: StringName = &""
## Stable id, used by the catalog and saves.
@export var skill_id: StringName = &""
## Discipline id -> minimum rank. The unit needs ALL of them. `discipline` (above) is the primary one: it sets the
## stat and the school label. Empty = 1 rank in `discipline`.
@export var requirements: Dictionary = {}
@export var school: String = ""
@export var subschool: String = ""

## Optional status this skill puts on every victim it damages (Unit.statuses id -> turns). "" = none.
## Ids Rules already reads: exposed, restrained, obscured. `wet` is read by `vs_status` below.
@export var apply_status: StringName = &""
@export var apply_status_turns: int = 1
## Optional rider: victims that have this status take their damage multiplied by `vs_status_mult`.
@export var vs_status: StringName = &""
@export var vs_status_mult: float = 1.0

## The requirements that apply, never empty.
func all_requirements() -> Dictionary:
	return requirements if not requirements.is_empty() else {discipline: 1}

func is_hybrid() -> bool:
	return all_requirements().size() > 1

## "Requires 2 Rogue" or "Requires 2 Cinder, 1 Torrent".
func requirement_text() -> String:
	var parts: Array[String] = []
	var reqs := all_requirements()
	for id: StringName in reqs.keys():
		parts.append("%d %s" % [int(reqs[id]), Discipline.display_name(id)])
	return "Requires " + ", ".join(parts)
