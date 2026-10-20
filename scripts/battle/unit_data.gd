extends Resource

const Ability = preload("res://scripts/battle/ability.gd")
const Item = preload("res://scripts/inventory/item.gd")

@export var display_name: String = ""
@export var max_hp: int = 10
@export var ac: int = 10
@export var prof: int = 2
@export var str_mod: int = 0
@export var dex_mod: int = 0
@export var con_mod: int = 0
@export var int_mod: int = 0
@export var wis_mod: int = 0
## Ablative defense pools (soak damage before Core Health) and damage resistance as a fraction:
## 0.25 = 25% less damage of that type, negative = vulnerable.
@export var physical_armor: int = 0
@export var magic_barrier: int = 0
@export var physical_resistance: float = 0.0
@export var magic_resistance: float = 0.0
@export var spd: int = 10
@export var move: int = 4
@export var jump: int = 1
@export var abilities: Array[Ability] = []
## Max learned skills / spells at once (weapon attacks and gear use none). -1 = CombatTuning.DEFAULT_SKILL_SLOTS.
@export var skill_slots: int = -1
## Ranks in each skill discipline: id (&"rogue", &"cinder", ...) -> rank. Missing = 0. A SkillDef needs a rank
## here ("Requires 2 Rogue"). Attributes are not checked. See scripts/skills/discipline.gd.
@export var discipline_ranks: Dictionary = {}
## Worn at battle start. Weapon attacks come ONLY from worn weapons; the abilities above are for
## spells and class skills that stay no matter what is equipped. Don't list weapon attacks there.
@export var starting_equipment: Array[Item] = []
