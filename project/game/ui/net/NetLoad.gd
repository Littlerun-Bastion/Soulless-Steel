class_name NetLoad
extends RefCounted

## How one page load plays out over time, like a 1999 modem: the host is
## looked up, then contacted, then the browser waits for a reply, then the
## page comes in, in jumps of 3-18 % with stalls of 0.05-0.4 s between them
## and, on most loads, one longer stall of 0.4-0.9 s while the bar sits
## between 60 % and 95 %. The stalls are scaled together so the whole load
## takes exactly `duration`; progress never goes down, reaches 100 % a moment
## before `duration` and stays there until the page shows. A failed load (no
## such server) stops after the lookup with nothing transferred.

enum Phase { LOOKUP, CONTACT, WAIT, TRANSFER, DONE }

const JUMP_MIN := 3
const JUMP_MAX := 18
const STALL_MIN := 0.05
const STALL_MAX := 0.4
const LONG_STALL_MIN := 0.4
const LONG_STALL_MAX := 0.9
const LONG_STALL_FROM := 60
const LONG_STALL_TO := 95
const LONG_STALL_CHANCE := 0.85
## The share of the load spent before any data arrives.
const CONNECT_SHARE_MIN := 0.15
const CONNECT_SHARE_MAX := 0.3
## The share it sits full at 100 % before the page shows.
const FULL_HOLD_MIN := 0.04
const FULL_HOLD_MAX := 0.08

var duration := 0.0
var lookup_end := 0.0
var contact_end := 0.0
var connect_time := 0.0
var failed := false
## [time, percent] pairs, in order.
var steps: Array = []


static func plan(rng: RandomNumberGenerator, total: float) -> NetLoad:
	var result := NetLoad.new()
	result.duration = total
	var pre := total * rng.randf_range(CONNECT_SHARE_MIN, CONNECT_SHARE_MAX)
	result.lookup_end = pre * 0.4
	result.contact_end = pre * 0.75
	result.connect_time = pre

	var values: Array[int] = []
	var percent := 0
	while percent < 100:
		percent = mini(100, percent + rng.randi_range(JUMP_MIN, JUMP_MAX))
		values.append(percent)
	var gaps: Array[float] = []
	for i in values.size() - 1:
		gaps.append(rng.randf_range(STALL_MIN, STALL_MAX))
	if rng.randf() < LONG_STALL_CHANCE:
		var eligible := []
		for i in gaps.size():
			if values[i] >= LONG_STALL_FROM and values[i] <= LONG_STALL_TO:
				eligible.append(i)
		if not eligible.is_empty():
			gaps[eligible[rng.randi_range(0, eligible.size() - 1)]] = rng.randf_range(LONG_STALL_MIN, LONG_STALL_MAX)
	var stalls := 0.0
	for gap in gaps:
		stalls += gap
	var hold := total * rng.randf_range(FULL_HOLD_MIN, FULL_HOLD_MAX)
	var scale := (total - pre - hold) / stalls if stalls > 0.0 else 0.0
	var t := pre
	result.steps.append([t, values[0]])
	for i in gaps.size():
		t += gaps[i] * scale
		result.steps.append([t, values[i + 1]])
	result.steps[-1][0] = total - hold
	return result


## A lookup that finds no server: the whole time is spent looking.
static func plan_failed(total: float) -> NetLoad:
	var result := NetLoad.new()
	result.duration = total
	result.lookup_end = total
	result.contact_end = total
	result.connect_time = total
	result.failed = true
	return result


## The percent loaded at time t.
func progress_at(t: float) -> int:
	var percent := 0
	for step in steps:
		if step[0] > t:
			break
		percent = step[1]
	return percent


func phase_at(t: float) -> Phase:
	if t >= duration:
		return Phase.DONE
	if t < lookup_end:
		return Phase.LOOKUP
	if t < contact_end:
		return Phase.CONTACT
	if t < connect_time or progress_at(t) == 0:
		return Phase.WAIT
	return Phase.TRANSFER
