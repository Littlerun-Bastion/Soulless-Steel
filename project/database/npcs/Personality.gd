extends Resource
class_name Personality

enum Type { SCAVENGER, GUARDIAN, PROFESSIONAL, HUNTER, RAT }

@export var type: Type = Type.PROFESSIONAL
@export_range(0.0, 1.0) var aggression: float = 0.5
@export_range(0.0, 1.0) var courage: float = 0.5
@export_range(0.0, 1.0) var greed: float = 0.5
@export_range(0.0, 1.0) var loyalty: float = 0.0
@export_range(0.0, 1.0) var treachery: float = 0.0
## How good a pilot it is (0 to 1): how long it takes to find a mech for a
## lock, and how often its reticle slips off one it can't see
## (Enemy.update_enemy_locking). Drawn per type (SKILL_RANGES).
@export_range(0.0, 1.0) var skill: float = 0.5

## Each type's skill range, drawn when a personality is made from its type
## (NPCManager). Placeholders.
const SKILL_RANGES := {
	Type.SCAVENGER: Vector2(0.1, 0.5),
	Type.RAT: Vector2(0.3, 0.7),
	Type.GUARDIAN: Vector2(0.3, 0.7),
	Type.PROFESSIONAL: Vector2(0.5, 0.9),
	Type.HUNTER: Vector2(0.6, 1.0),
}


## A skill drawn from `type`'s SKILL_RANGES.
static func roll_skill(of_type: Type) -> float:
	var span: Vector2 = SKILL_RANGES.get(of_type, Vector2(0.5, 0.5))
	return randf_range(span.x, span.y)
