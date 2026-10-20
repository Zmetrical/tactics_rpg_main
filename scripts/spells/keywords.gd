extends RefCounted
## Keyword glossary for ability tooltips. A rule that several abilities share is written ONCE here.
## An ability's text marks a keyword as [Name] (e.g. "[Bounce]"). The hotbar tooltip lists every keyword the
## text uses as its own small card beside the ability card (ui/hud/tooltip_card.gd).
##
## Numbers come from spell_tuning.gd / combat_tuning.gd through {tokens}, so a tuning change updates the
## text. To add a keyword: add one entry to DEFS, then write [Name] in any ability text. Nothing else.

const Tuning = preload("res://scripts/spells/spell_tuning.gd")

## name -> definition. Keep each one to about 3 short lines.
const DEFS := {
	"Bounce": "A {reach}-tile line from the target, in one of 8 directions. Deals {echo} of the roll to up to {units} units on it. A cast never hits a unit twice.",
	"Spread": "Ignores walls and cover. A tile only has to exist to be hit.",
	"Pierce": "Passes through every unit, allies included. Stops at a wall or the map edge.",
}

## "33%" for 0.33.
static func _pct(fraction: float) -> String:
	return "%d%%" % roundi(fraction * 100.0)

## Every {token} that ability text and keyword definitions may use.
static func tokens() -> Dictionary:
	return {
		"echo": _pct(Tuning.ECHO_FRACTION),
		"reach": Tuning.ARC_BOUNCE_REACH,
		"units": Tuning.ARC_BOUNCE_MAX_UNITS,
		"last": _pct(Tuning.BOLT_LAST_UNIT_BONUS),
		"side": Tuning.BOLT_PARALLEL_LENGTH,
		"path": Tuning.SURGE_PATH_LENGTH,
		"f1len": Tuning.SURGE_FORK_LENGTHS[0],
		"f1pct": _pct(Tuning.SURGE_FORK_SCALES[0]),
		"f2len": Tuning.SURGE_FORK_LENGTHS[1],
		"f2pct": _pct(Tuning.SURGE_FORK_SCALES[1]),
	}

## Replaces every {token} in `text`. Pass `extra` for per-ability tokens such as {dmg}.
static func fill(text: String, extra: Dictionary = {}) -> String:
	var all := tokens()
	all.merge(extra, true)
	return text.format(all)

## The definition of one keyword, tokens filled in. "" for an unknown name.
static func definition(word: String) -> String:
	if not DEFS.has(word):
		return ""
	return fill(String(DEFS[word]))

## Keywords written as [Name] in `text`, in the order they first appear. Unknown names are ignored.
static func in_text(text: String) -> Array[String]:
	var found: Array[String] = []
	var from := 0
	while true:
		var left := text.find("[", from)
		if left == -1:
			break
		var right := text.find("]", left)
		if right == -1:
			break
		var word := text.substr(left + 1, right - left - 1)
		if DEFS.has(word) and not found.has(word):
			found.append(word)
		from = right + 1
	return found
