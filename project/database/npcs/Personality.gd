extends Resource
class_name Personality

enum Type { SCAVENGER, GUARDIAN, PROFESSIONAL, HUNTER, RAT }

@export var type: Type = Type.PROFESSIONAL
@export_range(0.0, 1.0) var aggression: float = 0.5
@export_range(0.0, 1.0) var courage: float = 0.5
@export_range(0.0, 1.0) var greed: float = 0.5
@export_range(0.0, 1.0) var loyalty: float = 0.0
@export_range(0.0, 1.0) var treachery: float = 0.0
