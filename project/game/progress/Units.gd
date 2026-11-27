class_name Units
extends RefCounted

# Readable amounts for the UI.
#
# Every weight in the game is in tonnes: part and item weight, cargo weight,
# weight_capacity and Mecha.get_total_weight(). weight() shows a weight in t,
# in kg below 1 t and in g below 1 kg.
#
# amount() does the same for any unit: it starts at the unit it is asked to
# show and steps down while the value is below 1 of it (t > kg > g,
# L > mL, kWh > Wh). Materials.format_amount uses it with each material's
# stored and display units.

## unit -> [family, size in the family's smallest unit]
const SCALE := {
	"g": ["mass", 1.0], "kg": ["mass", 1000.0], "t": ["mass", 1000000.0],
	"mL": ["volume", 1.0], "L": ["volume", 1000.0],
	"Wh": ["energy", 1.0], "kWh": ["energy", 1000.0],
	"u": ["count", 1.0],
}
## Each family's units, largest first.
const STEPS := {"mass": ["t", "kg", "g"], "volume": ["L", "mL"], "energy": ["kWh", "Wh"], "count": ["u"]}
## Decimals shown at most (trailing zeros are dropped).
const DECIMALS := 2


## "15.7 t", "400 kg", "115 g".
static func weight(tonnes: float) -> String:
	return amount(tonnes, "t", "t")


## value (in `unit`) shown in `top`, or a smaller unit of the same family
## when it is below 1 of `top`. Zero shows in `top`.
static func amount(value: float, unit: String, top: String) -> String:
	if not SCALE.has(unit) or not SCALE.has(top):
		return number(value) + " " + unit
	var family: String = SCALE[unit][0]
	var base := value * float(SCALE[unit][1])
	var steps: Array = STEPS[family]
	var shown := top
	if not is_zero_approx(base):
		for i in range(maxi(steps.find(top), 0), steps.size()):
			shown = steps[i]
			if absf(base) >= float(SCALE[shown][1]) - 0.000001:
				break
	return "%s %s" % [number(base / float(SCALE[shown][1])), shown]


## Up to DECIMALS places, no trailing zeros: 1.1, 12, 0.25.
static func number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return String.num(value, DECIMALS)
