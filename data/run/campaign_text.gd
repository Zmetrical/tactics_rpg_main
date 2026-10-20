extends RefCounted
## Campaign text for the run map: what the player reads on arriving at a room. Data only.
## A line comes from the room's type (what is here) and one from the biome around it (where it is).
## Room types are the lowercase RunMap.NodeType names; biomes are OverworldStyle.BIOME_NAMES.

## Room type -> lines about the room. 3-4 each.
const ROOM_LINES := {
	"battle": [
		"Fresh tracks cross the ground, and they are not yours.",
		"Something stirs ahead. Steel rattles in the quiet.",
		"The way is blocked by those who mean to hold it.",
	],
	"elite": [
		"Whatever lives here has not lost a fight in a long time.",
		"The ground is scarred. Nothing small made these marks.",
		"A hard silence hangs over the place, like a held breath.",
		"Lesser creatures keep their distance from this spot.",
	],
	"campfire": [
		"A ring of stones, still warm, waits for a fire.",
		"The wind drops here, and the ground is dry and soft.",
		"Someone left firewood stacked beside the old ashes.",
	],
	"shop": [
		"A lone trader has spread a worn cloth across the ground.",
		"A cart sits by the road, its wares laid out in rows.",
		"Lanterns and bundles hang from a wagon. The seller waves you over.",
	],
	"boss": [
		"The road ends here. Everything that came before led to this.",
		"The air is heavy and the land is bare. Nothing else will move.",
		"A shadow much larger than any you have met falls across the ground.",
		"There is no path beyond this place, and no way to go around.",
	],
}

## Room type -> the one-line outcome shown with it.
const OUTCOME_LINES := {
	"battle": "Prepare for battle",
	"elite": "Something powerful waits here",
	"campfire": "A place to rest",
	"shop": "Goods for sale",
	"boss": "The final stand",
}

## Biome -> 2 opening lines.
const BIOME_LINES := {
	"meadow": [
		"The grass is long and bright, and the wind carries it in waves.",
		"Open ground stretches in every direction under a wide sky.",
	],
	"forest": [
		"The trees press close and the light turns green.",
		"Branches knit overhead, and every step falls soft on old leaves.",
	],
	"rock": [
		"Bare stone rises on all sides, cold and grey.",
		"Loose rock shifts underfoot, and your footsteps echo off the cliffs.",
	],
}

## One biome line and one room line for a room of `room_type` standing in `biome`. The biome line is drawn first,
## then the room line, so the same rng state, room type and biome always give the same result.
## Returns {title, text, outcome}: title is the room type's name ("Battle"), text is both lines, outcome is the
## room type's outcome line. Unknown room type or biome: push_warning and an empty entry for that part.
static func pick(room_type: String, biome: String, rng: RandomNumberGenerator) -> Dictionary:
	var parts: PackedStringArray = []
	if BIOME_LINES.has(biome):
		var lines: Array = BIOME_LINES[biome]
		parts.append(lines[rng.randi_range(0, lines.size() - 1)])
	else:
		push_warning("CampaignText: unknown biome '%s'" % biome)
	if not ROOM_LINES.has(room_type):
		push_warning("CampaignText: unknown room type '%s'" % room_type)
		return {"title": "", "text": " ".join(parts), "outcome": ""}
	var room: Array = ROOM_LINES[room_type]
	parts.append(room[rng.randi_range(0, room.size() - 1)])
	return {"title": room_type.capitalize(), "text": " ".join(parts), "outcome": OUTCOME_LINES[room_type]}
