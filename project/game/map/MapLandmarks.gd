@tool
class_name MapLandmarks
extends Resource

# The named places of a generated map (the generator's landmarks.json, made
# by build_meshes.gd): landmark i is called names[i] ("Japanese Garden"), of
# kind kinds[i] (the generator module's word for it: "garden", "cemetery",
# "station" ...), centred on centres[i] with radius radii[i] (map px). Its
# outline is points[starts[i]] .. points[starts[i + 1] - 1] (map px); a
# landmark with fewer than three outline points is the circle of its radius.

@export var names := PackedStringArray()
@export var kinds := PackedStringArray()
@export var centres := PackedVector2Array()
@export var radii := PackedFloat32Array()
@export var points := PackedVector2Array()
@export var starts := PackedInt32Array([0])


func count() -> int:
	return names.size()


func outline(i: int) -> PackedVector2Array:
	if i < 0 or i + 1 >= starts.size():
		return PackedVector2Array()
	return points.slice(starts[i], starts[i + 1])


# Adds a landmark (tests, hand-made maps). `outline_points` may be empty.
func add(landmark_name: String, kind: String, centre: Vector2, radius: float,
		outline_points := PackedVector2Array()) -> int:
	if starts.is_empty():
		starts.append(0)
	names.append(landmark_name)
	kinds.append(kind)
	centres.append(centre)
	radii.append(radius)
	points.append_array(outline_points)
	starts.append(points.size())
	return names.size() - 1


# A MapLandmarks from landmarks.json's parsed data: {"items": [{name, kind,
# x, y, radius, outline: [[x, y], ...]}]}, world px.
static func from_json(data) -> MapLandmarks:
	var out := MapLandmarks.new()
	if not (data is Dictionary) or not (data.get("items") is Array):
		return out
	for it in data.items:
		if not (it is Dictionary):
			continue
		var ring := PackedVector2Array()
		var raw = it.get("outline", [])
		if raw is Array:
			for p in raw:
				if p is Array and p.size() >= 2:
					ring.append(Vector2(float(p[0]), float(p[1])))
		out.add(str(it.get("name", "")), str(it.get("kind", "")),
				Vector2(float(it.get("x", 0.0)), float(it.get("y", 0.0))), float(it.get("radius", 0.0)), ring)
	return out
