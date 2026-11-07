extends TestSuite

# RibbonTrailTest: a round's smoke as a Line2D ribbon (RibbonTrail). The
# head rides on the round, points are laid every POINT_SPACING px of flight,
# the tail ages out, the ribbon outlives the round and fades, the placeholder
# strip has the shape the art should have.

const TRAIL := preload("res://game/weapons/SmokeTrail.tscn")


func run_tests() -> void:
	await case("the ribbon follows the round and lays points behind it", _test_follow)
	await case("the ribbon outlives its round, fades and goes", _test_outlive)
	await case("the placeholder strip is a seamless, soft-edged tile", _test_strip)
	await case("three trails: cloudy, stable and clean, each on its rounds", _test_variants)


func _test_follow() -> void:
	var shell := Node2D.new()
	add_child(shell)
	shell.global_position = Vector2(100, 100)
	var trail = TRAIL.instantiate()
	add_child(trail)
	trail.setup(shell)
	check_eq(trail.get_point_count(), 2, "a laid point and the head to start")
	check(trail.top_level, "its points are in world space")
	check(trail.texture != null and trail.width_curve != null and trail.gradient != null, "it has a strip, a width curve and a gradient")
	var moved := 0.0
	for i in 20:
		shell.global_position += Vector2(10, 0)
		moved += 10.0
		await get_tree().process_frame
	var last: int = trail.get_point_count() - 1
	check(trail.get_point_position(last).is_equal_approx(shell.global_position), "the head is on the round")
	# A point is laid once the head is point_spacing past the last one, so
	# with 10 px steps the spacing lands between point_spacing and that + 10.
	var spacing: float = trail.point_spacing
	var at_least := int(moved / (spacing + 10.0))
	var at_most := int(moved / spacing) + 3
	check(trail.get_point_count() >= at_least and trail.get_point_count() <= at_most,
			"about one point per %.0f px of flight (%d for %.0f px)" % [spacing, trail.get_point_count(), moved])
	check(trail.get_point_position(0).distance_to(Vector2(100, 100)) < float(trail.drift_speed) * 3.0,
			"the tail is still near where it started (it drifts a little)")
	check(is_equal_approx(trail.lifetime, RibbonTrail.LIFETIME_FALLBACK), "a round with no smoke_lifetime gets the fallback")
	trail.queue_free()
	shell.queue_free()
	await wait_frames(1)


func _test_outlive() -> void:
	var shell := Node2D.new()
	add_child(shell)
	shell.global_position = Vector2.ZERO
	var trail = TRAIL.instantiate()
	add_child(trail)
	trail.setup(shell)
	trail.lifetime = 0.5
	for i in 10:
		shell.global_position += Vector2(20, 0)
		await get_tree().process_frame
	var laid: int = trail.get_point_count()
	check(laid >= 8, "points laid (%d)" % laid)
	shell.queue_free()
	await wait_frames(2)
	check(is_instance_valid(trail), "the ribbon is still there with the round gone")
	await wait_seconds(0.2)
	check(is_instance_valid(trail) and trail.modulate.a < 1.0 and trail.modulate.a > 0.0, "and fading")
	await wait_seconds(0.5)
	check(not is_instance_valid(trail), "gone once its points have aged out")


const STABLE := preload("res://game/weapons/SmokeTrailStable.tscn")
const CLEAN := preload("res://game/weapons/SmokeTrailClean.tscn")
const ROUNDS := {
	"res://database/parts/projectiles/V4_missile.tscn": "res://game/weapons/SmokeTrail.tscn",
	"res://database/parts/projectiles/AR8_rocket.tscn": "res://game/weapons/SmokeTrail.tscn",
	"res://database/parts/projectiles/TORI-ML_subprojectile.tscn": "res://game/weapons/SmokeTrail.tscn",
	"res://database/parts/projectiles/RP6_rocket.tscn": "res://game/weapons/SmokeTrailStable.tscn",
	"res://database/parts/projectiles/GL44_projectile.tscn": "res://game/weapons/SmokeTrailClean.tscn",
	"res://database/parts/projectiles/NS-H150_shell.tscn": "res://game/weapons/SmokeTrailClean.tscn",
	"res://database/parts/projectiles/M120_shell.tscn": "res://game/weapons/SmokeTrailClean.tscn",
}


func _test_variants() -> void:
	var cloudy = TRAIL.instantiate()
	var stable = STABLE.instantiate()
	var clean = CLEAN.instantiate()
	for t in [cloudy, stable, clean]:
		add_child(t)
	check(cloudy.texture.resource_path.ends_with("trail_cloudy_hi.png"), "the cloudy trail wears trail_cloudy_hi")
	check(stable.texture.resource_path.ends_with("trail_cloudy.png"), "the stable one trail_cloudy")
	check(clean.texture.resource_path.ends_with("trail_clean.png"), "the clean one trail_clean")
	check(cloudy.drift_speed > stable.drift_speed and stable.drift_speed > clean.drift_speed and clean.drift_speed == 0.0,
			"drift falls from cloudy to stable to clean, which holds its line")
	check(cloudy.width > stable.width and stable.width > clean.width, "and so does the width")
	check(cloudy.lifetime_scale > stable.lifetime_scale and stable.lifetime_scale > clean.lifetime_scale, "and how long it hangs")
	check(cloudy.tail_width > clean.tail_width and is_equal_approx(clean.tail_width, 1.0), "the clean trail doesn't widen")
	var shell := Node2D.new()
	add_child(shell)
	clean.setup(shell)
	check(is_equal_approx(clean.lifetime, RibbonTrail.LIFETIME_FALLBACK * clean.lifetime_scale), "the lifetime scale applies")
	for i in 8:
		shell.global_position += Vector2(12, 0)
		await get_tree().process_frame
	check(clean.get_point_position(0).is_equal_approx(Vector2.ZERO), "a clean trail's tail stays exactly where it was laid")
	for path in ROUNDS:
		var scene: PackedScene = load(path)
		var state := scene.get_state()
		var trail_path := ""
		for i in state.get_node_property_count(0):
			if state.get_node_property_name(0, i) == &"trail":
				var trail_scene = state.get_node_property_value(0, i)
				trail_path = trail_scene.resource_path if trail_scene is PackedScene else ""
		check_eq(trail_path, ROUNDS[path], "%s flies with %s" % [path.get_file(), ROUNDS[path].get_file()])
	# A trail with no round frees itself on its first frame (cloudy and
	# stable here), so only what is left is freed.
	for t in [cloudy, stable, clean, shell]:
		if is_instance_valid(t):
			t.queue_free()
	await wait_frames(1)


func _test_strip() -> void:
	var strip := RibbonTrail.placeholder_strip()
	check_eq(Vector2i(strip.get_width(), strip.get_height()), RibbonTrail.PLACEHOLDER_SIZE, "the stand-in has the strip's size")
	var image := strip.get_image()
	var w := image.get_width()
	var h := image.get_height()
	var edge_alpha := 0.0
	var middle_alpha := 0.0
	var seam := 0.0
	for x in w:
		edge_alpha = maxf(edge_alpha, maxf(image.get_pixel(x, 0).a, image.get_pixel(x, h - 1).a))
		@warning_ignore("integer_division")
		middle_alpha += image.get_pixel(x, h / 2).a
	for y in h:
		seam = maxf(seam, absf(image.get_pixel(0, y).a - image.get_pixel(w - 1, y).a))
	middle_alpha /= w
	check(edge_alpha < 0.15, "its top and bottom rows are all but clear (%.2f)" % edge_alpha)
	check(middle_alpha > 0.25, "its middle carries the smoke (%.2f)" % middle_alpha)
	check(seam < 0.35, "its left and right edges meet (%.2f)" % seam)
	check(is_same(strip, RibbonTrail.placeholder_strip()), "made once")
