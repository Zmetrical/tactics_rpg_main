extends Resource
## Settings for one biome. A new biome is a new .tres plus a folder of map scenes under
## res://scenes/maps/<biome>/<size>/. Only the enemy COUNT is random; enemy TYPES come from the roster.

## Spawn order: the first N entries appear (UnitData resources). Repeats are allowed.
@export var enemy_roster: Array[Resource] = []
## N is random in this range, clamped to the roster length and the map's enemy markers.
@export var enemy_count_min: int = 3
@export var enemy_count_max: int = 4
