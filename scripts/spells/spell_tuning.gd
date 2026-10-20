extends RefCounted
## Every spell-system balance number lives here. Spell scripts contain no magic values.

## Cast speed is NOT tuned here: spells use Ability.charge_speed like Burning Burst
## (ticks = ceil(100 / charge_speed), higher = faster). See electric_spells.gd.

## Secondary hits ("echoes": bounces, shockwaves, parallel arcs) deal this fraction of the damage roll.
const ECHO_FRACTION := 0.33

## Directional aiming and pivots snap to 8 compass directions. Set false for cardinal-only.
const ALLOW_DIAGONAL_AIM := true

# --- Chain Arc ---------------------------------------------------------------
## Chain Arc's pivot and fork aim in 8 directions. Set false for cardinal only.
const ARC_PIVOT_DIAGONAL := true
const ARC_BOUNCE_REACH := 2          # tiles each bounce arm travels from the anchor
const ARC_BOUNCE_MAX_UNITS := 2      # units one arm can hit
## Bounce arms per tier. Base has no bounce. Tier 2 = Pivot Targeting (one arm, rotated by the player).
## Tier 3 = Manual Fork (two arms mirrored 180 degrees apart; rotating one swings the other).
const ARC_ARMS_BY_TIER: Array[int] = [0, 1, 2]

# --- Thunder -----------------------------------------------------------------
## Cross arm length (in tiles) that deals full damage. 1 = the 5-tile plus sign.
const THUNDER_CORE_ARM := 1
## Shockwave arm length per tier. Tier 1 has none. Tier 2 stretches the cross (+4 tiles),
## Tier 3 stretches it once more and fills the 4 corners (+8 tiles over Tier 2).
const THUNDER_WAVE_ARM_BY_TIER: Array[int] = [0, 2, 3]
const THUNDER_WAVE_CORNERS_BY_TIER: Array[bool] = [false, false, true]

# --- Bolt --------------------------------------------------------------------
## Extra damage multiplier on the LAST unit the bolt pierces (Tier 2 and 3).
const BOLT_LAST_UNIT_BONUS := 0.33
const BOLT_PARALLEL_LENGTH := 3      # Tier 3: tiles in each side arc, centred on the last unit
const BOLT_PARALLEL_OFFSET := 1      # lanes beside the bolt line

# --- Surge -------------------------------------------------------------------
const SURGE_PATH_LENGTH := 8
## Fork segments per tier (tile cap and damage fraction of the ORIGINAL roll).
const SURGE_FORK_LENGTHS: Array[int] = [6, 4]
const SURGE_FORK_SCALES: Array[float] = [0.5, 0.25]
const SURGE_FORKS_BY_TIER: Array[int] = [0, 1, 2]
