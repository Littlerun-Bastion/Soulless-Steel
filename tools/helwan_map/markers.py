"""Picks starting places for the master map's gameplay markers, in map-frame
metres. Only used when helwan_master.tscn is first written; move them by
hand afterwards.

Every marker is inside the play area (the map less its border band, see
frame.PLAY_HALF_M), at least PLAY_INSET_M inside the play area's edge.

  exits   one per edge: the main-road point nearest that edge, no closer to
          it than PLAY_INSET_M
  starts  nine points on main roads, spread out (farthest-point sampling),
          the first nearest the map centre (the player spawn)
  spawns  eight points round the map at SPAWN_RING of the play area's
          half-width, moved to the nearest open ground
  cysts   four points on open ground at least CYST_FROM_NPC_M from every NPC
          start and CYST_FROM_PLAYER_M from the player start
"""
import numpy as np
from shapely.geometry import Point
from shapely.ops import unary_union

from frame import PLAY_HALF_M

PLAY_INSET_M = 150.0
SPAWN_RING = 0.75
CYST_FROM_NPC_M = 150.0
CYST_FROM_PLAYER_M = 325.0


def _road_points(roads, min_width):
    pts = []
    for _, _, w, _, kind, line in roads:
        if line is None or kind.startswith("rail:") or w < min_width:
            continue
        for d in np.arange(0, line.length, 10.0):
            p = line.interpolate(d)
            pts.append((p.x, p.y))
    return np.asarray(pts)


def _open_points(half_m, blocked, rng, n=6000):
    pts = rng.uniform(-half_m, half_m, (n, 2))
    keep = [not blocked.contains(Point(x, y)) for x, y in pts]
    return pts[np.asarray(keep)]


def pick(roads, buildings, water, seed=3):
    rng = np.random.default_rng(seed)
    lim = PLAY_HALF_M - PLAY_INSET_M
    main = _road_points(roads, 8.0)
    if len(main) < 20:
        main = _road_points(roads, 4.0)
    main = main[np.all(np.abs(main) <= lim, axis=1)]

    exits = []
    for axis, sign in ((1, -1), (0, 1), (1, 1), (0, -1)):
        score = main[:, axis] * sign
        exits.append(tuple(main[int(np.argmax(score))]))

    starts = [tuple(main[int(np.argmin(np.hypot(main[:, 0], main[:, 1])))])]
    dist = np.hypot(main[:, 0] - starts[0][0], main[:, 1] - starts[0][1])
    while len(starts) < 9:
        i = int(np.argmax(dist))
        starts.append(tuple(main[i]))
        dist = np.minimum(dist, np.hypot(main[:, 0] - main[i, 0], main[:, 1] - main[i, 1]))

    blocked = unary_union([b for b in buildings] + [water]).buffer(6.0)
    open_pts = _open_points(lim, blocked, rng)
    spawns = []
    for a in np.linspace(0, 2 * np.pi, 8, endpoint=False):
        target = np.array([np.cos(a), np.sin(a)]) * PLAY_HALF_M * SPAWN_RING
        i = int(np.argmin(np.hypot(*(open_pts - target).T)))
        spawns.append(tuple(open_pts[i]))

    s = np.asarray(starts)
    d_npc = np.min(np.hypot(open_pts[:, None, 0] - s[None, 1:, 0], open_pts[:, None, 1] - s[None, 1:, 1]), axis=1)
    d_player = np.hypot(open_pts[:, 0] - s[0, 0], open_pts[:, 1] - s[0, 1])
    ok = open_pts[(d_npc >= CYST_FROM_NPC_M) & (d_player >= CYST_FROM_PLAYER_M)]
    cysts = []
    if len(ok):
        cysts.append(tuple(ok[rng.integers(len(ok))]))
        dist = np.hypot(ok[:, 0] - cysts[0][0], ok[:, 1] - cysts[0][1])
        while len(cysts) < min(4, len(ok)):
            i = int(np.argmax(dist))
            cysts.append(tuple(ok[i]))
            dist = np.minimum(dist, np.hypot(ok[:, 0] - ok[i, 0], ok[:, 1] - ok[i, 1]))
    return exits, starts, spawns, cysts
