extends "res://game/mecha/enemy_logic/BaseBehaviour.gd"

# Default balanced behaviour. Uses BaseBehaviour's tunables unchanged — this is
# the reference the base is tuned against. Override nothing here; to make a
# variant, add a sibling that extends BaseBehaviour and tweaks tunables in
# _init() (see aggressive.gd / cautious.gd).
