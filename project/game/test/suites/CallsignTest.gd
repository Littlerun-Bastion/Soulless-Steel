extends TestSuite

# CallsignTest: NPC callsigns (CallsignGenerator, database/npcs/callsigns.json).
#   - the data file parses and every list the generator reads has names
#   - 2,000 seeded callsigns: at most 16 characters, only letters, digits,
#     _ . and -, no blocklist word, every style
#   - the same seed gives the same callsigns
#   - excludes: names in use, named NPCs, the player's callsign, callsigns
#     retired on the Memorial Wall
#   - a number on the end after ten failed rolls
#   - LocalPilots.join gives twelve NPCs twelve callsigns

const COUNT := 2000
const SEED := 2035


class FakePilot extends Node2D:
	var callsign := ""
	var is_anonymous := false
	var mecha_name := "Fake"
	var is_dead := false
	func _init() -> void:
		add_to_group("mecha")


func run_tests() -> void:
	await case("the data file", _test_data)
	await case("two thousand callsigns keep the rules", _test_rules)
	await case("the same seed, the same callsigns", _test_seeded)
	await case("excludes", _test_excludes)
	await case("a number after ten failed rolls", _test_fallback)
	await case("a match of twelve", _test_match)
	CallsignGenerator.reload_data()


func before_each() -> void:
	CallsignGenerator.reload_data()
	PlayerProgress.reset()
	PilotNet.reset(false)


func _test_data() -> void:
	var problems := CallsignGenerator.check_content()
	check(problems.is_empty(), "callsigns.json is valid (%s)" % "; ".join(problems))
	var data := CallsignGenerator.data()
	for pool in CallsignGenerator.POOLS:
		check(data.get(pool) is Array and not data[pool].is_empty(), "'%s' has names" % pool)
	check_eq(data.get("words", []).slice(0, 3), ["Ash", "Basalt", "Bishop"], "the old names are kept")
	for pool in ["words", "myth", "compound_a", "compound_b", "first_names", "last_names"]:
		var blocked: Array = data.get(pool, []).filter(func(n): return CallsignGenerator.is_blocked(str(n)))
		check(blocked.is_empty(), "no '%s' name trips the blocklist (%s)" % [pool, str(blocked)])


func _test_rules() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var regex := RegEx.create_from_string(CallsignGenerator.VALID_PATTERN)
	var styles := {}
	var bad := []
	for i in COUNT:
		var callsign := CallsignGenerator.generate(rng, {})
		styles[CallsignGenerator.last_style] = int(styles.get(CallsignGenerator.last_style, 0)) + 1
		if callsign.length() > CallsignGenerator.MAX_LENGTH or regex.search(callsign) == null or CallsignGenerator.is_blocked(callsign):
			bad.append(callsign)
	check(bad.is_empty(), "every callsign is at most 16 valid characters with no blocklist word (%s)" % str(bad.slice(0, 5)))
	for style in CallsignGenerator.STYLES:
		check(int(styles.get(style, 0)) > 0, "the style '%s' appears (%d)" % [style, int(styles.get(style, 0))])
	check(CallsignGenerator.is_blocked("x_5HiT_x") and CallsignGenerator.is_blocked("P1.55-er"), "the blocklist reads leetspeak back")


func _test_seeded() -> void:
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = SEED
	b.seed = SEED
	var first := []
	var second := []
	for i in 50:
		first.append(CallsignGenerator.generate(a, {}))
		second.append(CallsignGenerator.generate(b, {}))
	check_eq(first, second, "the same seed gives the same callsigns")


func _test_excludes() -> void:
	var data := {"weights": {"word": 1}, "words": ["Ash", "Lark", "Lady Volk", "Drifter", "Wren"], "blocklist": []}
	CallsignGenerator.use_data(data)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	PlayerProgress.set_callsign("Drifter", false)
	PilotNet.memorial.retire("Wren")
	var seen := {}
	for i in 200:
		seen[CallsignGenerator.generate(rng, {"ash": true})] = true
	check(not seen.has("Ash"), "a name in use (any case)")
	check(CallsignGenerator.is_reserved("LADY VOLK") and not seen.has("Lady Volk"), "a named NPC's name")
	check(not seen.has("Drifter"), "the player's callsign")
	check(not seen.has("Wren"), "a callsign retired on the Memorial Wall")
	check(seen.has("Lark"), "the free name is used")


func _test_fallback() -> void:
	CallsignGenerator.use_data({"weights": {"word": 1}, "words": ["Kestrel"], "blocklist": []})
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var callsign := CallsignGenerator.generate(rng, {"Kestrel": true})
	check(callsign.begins_with("Kestrel") and callsign != "Kestrel" and callsign.substr(7).is_valid_int(),
			"after ten failed rolls the last one gets a number (%s)" % callsign)
	check(callsign.length() <= CallsignGenerator.MAX_LENGTH, "still at most 16 characters")
	var taken := {"Kestrel": true}
	for i in 30:
		var more := CallsignGenerator.generate(rng, taken)
		check(not taken.has(more), "and a new number each time (%s)" % more)
		taken[more] = true


func _test_match() -> void:
	var local := LocalPilots.new()
	local.rng.seed = SEED
	var names := {}
	var pilots := []
	for i in 12:
		var pilot := FakePilot.new()
		add_child(pilot)
		pilots.append(pilot)
		local.join(pilot)
		names[pilot.callsign.to_lower()] = true
	check_eq(names.size(), 12, "twelve NPCs, twelve callsigns (%s)" % ", ".join(pilots.map(func(p): return p.callsign)))
	for pilot in pilots:
		pilot.queue_free()
