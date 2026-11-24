class_name TensionMeter
extends RefCounted

# How much the ExpeditionDirector wants something to happen to the player,
# 0 to 1. It rises while the player is out of a fight, faster the longer the
# expedition has run (QUIET_RISE, TIME_RAMP), once QUIET_AFTER s have passed
# since the last one; it falls during a fight (FIGHT_FALL) and when the
# player comes upon an encounter (found_encounter). pressure() is what the
# director acts on: the tension, eased off while the player's mecha is in a
# bad way (RELIEF), so a battered player gets a breather.

## Placeholders.
const QUIET_AFTER := 20.0
const QUIET_RISE := 1.0 / 240.0
const TIME_RAMP := 600.0
const FIGHT_FALL := 1.0 / 20.0
const FOUND_DROP := 0.35
const RELIEF := 0.6

var value := 0.0
var since_fight := 0.0


## `dt` s more of the expedition, `elapsed` s into it.
func advance(dt: float, in_fight: bool, elapsed: float) -> void:
	if in_fight:
		since_fight = 0.0
		value -= FIGHT_FALL * dt
	else:
		since_fight += dt
		if since_fight >= QUIET_AFTER:
			value += QUIET_RISE * (1.0 + maxf(elapsed, 0.0) / TIME_RAMP) * dt
	value = clampf(value, 0.0, 1.0)


## The tension as the director acts on it, for a mecha `wholeness` whole
## (0 to 1, NPCKnowledge._structural_health).
func pressure(wholeness: float) -> float:
	return value * lerpf(1.0 - RELIEF, 1.0, clampf(wholeness, 0.0, 1.0))


func found_encounter() -> void:
	value = clampf(value - FOUND_DROP, 0.0, 1.0)
