extends RefCounted
## Wording and slot data for the Status section of the equipment window: one icon per status effect on a unit
## (Unit.statuses) plus its Armor Shred and Fracture stacks. Plain data, same shape the hotbar slots take.

const Palette = preload("res://ui/theme/gbc_palette.gd")
const Unit = preload("res://scripts/battle/unit.gd")

## id -> {name, short, text}. Unknown ids still show, with a capitalised name.
const INFO := {
	&"exposed": {"name": "Exposed", "short": "EX", "text": "Attacks against this unit have Advantage."},
	&"restrained": {"name": "Restrained", "short": "RS", "text": "Attacks against this unit have Advantage."},
	&"obscured": {"name": "Obscured", "short": "OB", "text": "Attacks against this unit have Disadvantage."},
	&"wet": {"name": "Wet", "short": "WT", "text": "Soaked. Some water and ice skills hit it harder."},
	&"stun": {"name": "Stunned", "short": "ST", "text": "Overload from Armor Shred. Attacks against this unit have Advantage."},
	&"silence": {"name": "Silenced", "short": "SL", "text": "Overload from Fracture. Attacks against this unit have Advantage."},
	&"movement_cripple": {"name": "Movement Breach", "short": "MB", "text": "Breach from Armor Shred stacks."},
	&"cast_cripple": {"name": "Cast Breach", "short": "CB", "text": "Breach from Fracture stacks."},
}

static func _turns(n: int) -> String:
	return "%d turn%s left" % [n, "" if n == 1 else "s"]

static func _color_for(id: StringName) -> Color:
	match id:
		&"wet":
			return Palette.ACCENT
		&"obscured":
			return Palette.INK_LIGHT
	return Palette.HP_RED

## One slot row per thing worth showing, in a stable order: stacks first, then status effects by id.
## Row keys match HotbarSlot.set_data: id, short, usable, cooldown (the number drawn in the corner), tip. `accent` is extra.
static func entries(u: Unit) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if u.armor_shred_stacks > 0:
		out.append(_stack_row(out.size(), "Armor Shred", "AS", u.armor_shred_stacks, Palette.ARMOR_SHRED,
			"Physical hits have worn this unit down. At 3 stacks it is Breached, at 5 it is Overloaded."))
	if u.fracture_stacks > 0:
		out.append(_stack_row(out.size(), "Fracture", "FR", u.fracture_stacks, Palette.FRACTURE,
			"Magical hits have cracked this unit. At 3 stacks it is Breached, at 5 it is Overloaded."))
	var ids: Array = u.statuses.keys()
	ids.sort()
	for id: StringName in ids:
		var turns := int(u.statuses[id])
		if turns <= 0:
			continue
		var info: Dictionary = INFO.get(id, {"name": String(id).capitalize(), "short": String(id).substr(0, 2).to_upper(), "text": ""})
		out.append({
			"id": out.size(), "short": info["short"], "usable": true, "cooldown": turns, "accent": _color_for(id),
			"tip": {"title": info["name"], "subtitle": "STATUS", "body": info["text"], "footer": [_turns(turns)]},
		})
	return out

static func _stack_row(index: int, title: String, short: String, stacks: int, color: Color, text: String) -> Dictionary:
	return {
		"id": index, "short": short, "usable": true, "cooldown": stacks, "accent": color,
		"tip": {"title": title, "subtitle": "STACKS", "body": text, "footer": ["%d stack%s" % [stacks, "" if stacks == 1 else "s"]]},
	}
