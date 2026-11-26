"""Salvage sources: world objects the player searches for items (see the
SalvageField in the game). The generator places them while it builds the
things that show them (a bus prop, a roof's AC boxes, a pump on a skid), and
writes them as spawn points; the game makes no nodes for them until the
player is near.

salvage.json: {"kinds": [...], "items": [[kind index, x, y, rotation (rad),
width, height, building id, amount, vehicle flag], ...]} with positions and
sizes in px.

  width, height  the source's outline box, centred on (x, y) and turned by
                 rotation; the HUD bracket fits it
  building id    the footprint id whose roof holds the source; -1 on the ground
  amount         intact solar modules for solar_panels, AC boxes for roof_ac,
                 0 for the other kinds
  vehicle flag   1 when the source is a vehicle prop spawned at exactly (x, y)
                 in props.json (the game ties the source to that vehicle)

No source is placed in the border band (frame.PLAY_HALF_M) or in a KeepOut
area: add() drops it.
"""
import json

import numpy as np
from shapely import prepare
from shapely.geometry import Point

from frame import PLAY_HALF_M, PX_PER_M

KINDS = [
    "bus", "tank", "military_vehicle", "container_truck", "shipping_container",
    "solar_panels", "roof_ac", "diesel_generator", "transformer", "electric_motor",
    "industrial_pump", "control_cabinet", "valve_assembly", "oil_drums", "cable_drum",
    "tractor", "relay_mast", "rubble", "tanker", "dump_truck",
    "telescope", "lab_equipment", "medical_store",
    "railcar", "freight_wagon", "switchgear",
    "building_materials",
    "car_parts",
]
VEHICLE_KINDS = {"bus", "tank", "military_vehicle", "container_truck", "shipping_container", "tanker", "dump_truck",
                 "railcar", "freight_wagon"}


class Salvage:
    def __init__(self, keep_out=None):
        self.items = []
        self.keep_out = keep_out if keep_out is not None and not keep_out.is_empty else None
        if self.keep_out is not None:
            prepare(self.keep_out)

    def allowed(self, x, y, w=0.0, h=0.0):
        """True where a source of outline w x h (metres) centred on (x, y) is
        wholly inside the play area and outside every KeepOut area."""
        r = 0.5 * float(np.hypot(w, h))
        if abs(x) + r > PLAY_HALF_M or abs(y) + r > PLAY_HALF_M:
            return False
        return self.keep_out is None or not self.keep_out.contains(Point(x, y))

    def add(self, kind, x, y, rot, w, h, building=-1, amount=0, vehicle=False):
        """Adds a source (metres, map frame). Returns False when it falls in
        the border band or a KeepOut area."""
        if not self.allowed(x, y, w, h):
            return False
        self.items.append((KINDS.index(kind), float(x), float(y), float(rot), float(w), float(h),
                           int(building), int(amount), int(bool(vehicle))))
        return True

    def counts(self):
        out = {}
        for k, *_ in self.items:
            out[KINDS[k]] = out.get(KINDS[k], 0) + 1
        return out

    def write(self, path):
        data = {
            "kinds": KINDS,
            "items": [[k, round(x * PX_PER_M, 1), round(y * PX_PER_M, 1), round(rot, 3),
                       round(w * PX_PER_M, 1), round(h * PX_PER_M, 1), b, a, v]
                      for k, x, y, rot, w, h, b, a, v in self.items],
        }
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(data, fh, separators=(",", ":"))
