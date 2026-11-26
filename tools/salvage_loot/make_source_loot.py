"""Writes the salvage source loot tables (SalvageLoot resources) for
SalvageField: one file per source kind, project/database/loot-tables/sources/
<kind>.tres, from the TABLES below.

Usage: python make_source_loot.py <repo>/project

Each entry is (item id, chance, min count, max count[, per_amount]). The item
is project/database/items/salvage/<item id>.tres (the item catalogue). In a
table marked pick_one, exactly one entry is chosen and `chance` is its weight.
With per_amount, the count is the source's amount (intact solar modules, AC
boxes) divided by it, between min and max.

Change the numbers here and run the script again; it rewrites every table.
"""
import os
import sys

TABLES = {
    # Vehicles (searched).
    "bus": [
        ("bus_engine", 1.0, 1, 1),
        ("bus_battery", 0.25, 1, 1),
        ("wiring_harness", 0.8, 1, 2),
    ],
    "tank": [
        ("tank_engine", 1.0, 1, 1),
        ("military_battery", 0.6, 1, 1),
        ("shell_120", 0.5, 2, 6),
        ("shell_125", 0.5, 2, 6),
        ("cartridge_50", 0.7, 50, 250),
        ("track_links", 0.8, 1, 3),
        ("fire_control", 0.4, 1, 1),
    ],
    "military_vehicle": [
        ("bulk_small_ammo", 0.3, 1, 1),
        ("guided_missile", 0.25, 1, 2),
        ("rocket_122", 0.2, 1, 2),
        ("military_radio", 0.5, 1, 1),
        ("cartridge_50", 0.6, 30, 200),
        ("jerry_can", 0.6, 1, 3),
        ("military_battery", 0.5, 1, 1),
    ],
    "container_truck": "shipping_container",
    "tanker": [
        ("jerry_can", 0.9, 2, 6),
        ("oil_drum", 0.5, 1, 3),
        ("valve_assembly", 0.5, 1, 2),
        ("industrial_pump", 0.35, 1, 1),
        ("wiring_harness", 0.4, 1, 1),
    ],
    "dump_truck": [
        ("scrap_metal", 0.9, 2, 6),
        ("bulk_steel", 0.12, 1, 1),
        ("industrial_pump", 0.3, 1, 1),
        ("jerry_can", 0.4, 1, 2),
        ("wiring_harness", 0.5, 1, 2),
    ],
    "shipping_container": {"pick_one": True, "entries": [
        ("bulk_steel", 0.15, 1, 1),
        ("bulk_copper", 0.08, 1, 1),
        ("bulk_electronics", 0.15, 1, 1),
        ("bulk_aluminium", 0.12, 1, 1),
        ("bulk_batteries", 0.10, 1, 1),
        ("cable_drum", 0.15, 1, 2),
        ("wiring_harness", 0.10, 3, 5),
        ("electric_motor", 0.08, 1, 2),
        ("control_cabinet", 0.07, 1, 2),
    ]},
    # Roofs.
    "solar_panels": [("solar_panel", 1.0, 1, 12, 4)],
    "roof_ac": [("air_conditioner", 1.0, 1, 6, 1)],
    # Machinery and yards.
    "diesel_generator": [
        ("diesel_generator", 1.0, 1, 1),
        ("jerry_can", 0.5, 1, 2),
    ],
    "transformer": [("transformer", 1.0, 1, 1)],
    "electric_motor": [("electric_motor", 1.0, 1, 1)],
    "industrial_pump": [("industrial_pump", 1.0, 1, 1)],
    "control_cabinet": [("control_cabinet", 1.0, 1, 1)],
    "valve_assembly": [("valve_assembly", 1.0, 1, 2)],
    "oil_drums": [("oil_drum", 1.0, 1, 3)],
    "cable_drum": [("cable_drum", 1.0, 1, 1)],
    "tractor": [
        ("tractor_engine", 1.0, 1, 1),
        ("jerry_can", 0.3, 1, 1),
    ],
    "relay_mast": [("rtg_core", 1.0, 1, 1)],
    # A search point in a collapsed building: a few small things.
    "rubble": [
        ("scrap_metal", 0.8, 1, 3),
        ("wiring_harness", 0.3, 1, 1),
        ("air_conditioner", 0.2, 1, 1),
        ("solar_panel", 0.15, 1, 2),
    ],
    # Landmarks: a telescope in an observatory dome (its drive motors,
    # electronics and aluminium tube), cases of laboratory equipment, a
    # hospital's store room.
    "telescope": [
        ("electric_motor", 0.9, 1, 2),
        ("control_cabinet", 0.5, 1, 1),
        ("bulk_electronics", 0.6, 1, 2),
        ("bulk_aluminium", 0.5, 1, 1),
        ("wiring_harness", 0.5, 1, 2),
    ],
    "lab_equipment": [
        ("bulk_electronics", 0.8, 1, 2),
        ("wiring_harness", 0.6, 1, 2),
        ("control_cabinet", 0.35, 1, 1),
        ("electric_motor", 0.2, 1, 1),
        ("solar_panel", 0.2, 1, 2),
    ],
    "medical_store": [
        ("bulk_electronics", 0.7, 1, 2),
        ("bulk_batteries", 0.6, 1, 2),
        ("wiring_harness", 0.6, 1, 3),
        ("air_conditioner", 0.15, 1, 1),
    ],
    # The parts shelf and bench of a garage, truck yard or depot workshop
    # (sites.py): car parts and scrap, never fuel.
    "car_parts": [
        ("car_battery", 0.6, 1, 2),
        ("alloy_wheel", 0.5, 1, 4),
        ("catalytic_converter", 0.25, 1, 1),
        ("wiring_harness", 0.5, 1, 2),
        ("scrap_metal", 0.8, 1, 4),
        ("electric_motor", 0.15, 1, 1),
    ],
    # A destroyed car's pieces (picked up, no window).
    "car_wreck": [
        ("scrap_metal", 1.0, 1, 3),
        ("car_battery", 0.15, 1, 1),
        ("alloy_wheel", 0.6, 1, 4),
        ("catalytic_converter", 0.08, 1, 1),
    ],
    # Rail: a metro car (traction gear under the floor, roof air
    # conditioning) and a goods wagon (one kind of load).
    "railcar": [
        ("electric_motor", 0.7, 1, 2),
        ("wiring_harness", 0.8, 1, 3),
        ("air_conditioner", 0.5, 1, 2),
        ("control_cabinet", 0.35, 1, 1),
        ("bulk_copper", 0.25, 1, 1),
        ("bulk_batteries", 0.15, 1, 1),
        ("scrap_metal", 0.6, 1, 3),
    ],
    "freight_wagon": {"pick_one": True, "entries": [
        ("bulk_steel", 0.25, 1, 2),
        ("scrap_metal", 0.2, 2, 5),
        ("bulk_aluminium", 0.12, 1, 1),
        ("bulk_copper", 0.08, 1, 1),
        ("cable_drum", 0.12, 1, 2),
        ("electric_motor", 0.08, 1, 2),
        ("industrial_pump", 0.07, 1, 1),
        ("valve_assembly", 0.08, 1, 2),
    ]},
    # An electrical substation's switchgear bay: copper busbars, breakers
    # and their control gear.
    "switchgear": [
        ("bulk_copper", 0.7, 1, 2),
        ("control_cabinet", 0.6, 1, 1),
        ("wiring_harness", 0.6, 1, 2),
        ("bulk_electronics", 0.3, 1, 1),
        ("cable_drum", 0.25, 1, 1),
    ],
    # Rebar stacks and the yard of a building site.
    "building_materials": [
        ("bulk_steel", 0.7, 1, 2),
        ("scrap_metal", 0.8, 2, 5),
        ("wiring_harness", 0.2, 1, 1),
    ],
}

ITEM_DIR = "res://database/items/salvage/"
SCRIPTS = {
    "loot": "res://game/map/salvage/SalvageLoot.gd",
    "entry": "res://game/map/salvage/SalvageLootEntry.gd",
}


def table_text(spec):
    pick_one = False
    entries = spec
    if isinstance(spec, dict):
        pick_one = spec.get("pick_one", False)
        entries = spec["entries"]
    items = []
    for e in entries:
        if e[0] not in items:
            items.append(e[0])
    out = [f'[gd_resource type="Resource" script_class="SalvageLoot" format=3]\n\n']
    out.append(f'[ext_resource type="Script" path="{SCRIPTS["loot"]}" id="loot"]\n')
    out.append(f'[ext_resource type="Script" path="{SCRIPTS["entry"]}" id="entry"]\n')
    for k, item in enumerate(items):
        out.append(f'[ext_resource type="Resource" path="{ITEM_DIR}{item}.tres" id="item_{k}"]\n')
    out.append("\n")
    for n, e in enumerate(entries):
        item, chance, lo, hi = e[:4]
        per = e[4] if len(e) > 4 else 0
        out.append(f'[sub_resource type="Resource" id="e{n}"]\n')
        out.append('script = ExtResource("entry")\n')
        out.append(f'item = ExtResource("item_{items.index(item)}")\n')
        out.append(f"chance = {float(chance)}\n")
        out.append(f"count = Vector2i({lo}, {hi})\n")
        if per:
            out.append(f"per_amount = {per}\n")
        out.append("\n")
    out.append("[resource]\n")
    out.append('script = ExtResource("loot")\n')
    refs = ", ".join(f'SubResource("e{n}")' for n in range(len(entries)))
    out.append(f'entries = Array[ExtResource("entry")]([{refs}])\n')
    if pick_one:
        out.append("pick_one = true\n")
    return "".join(out)


def main(project):
    out_dir = os.path.join(project, "database", "loot-tables", "sources")
    os.makedirs(out_dir, exist_ok=True)
    missing = set()
    for kind, spec in TABLES.items():
        if isinstance(spec, str):
            spec = TABLES[spec]
        entries = spec["entries"] if isinstance(spec, dict) else spec
        for e in entries:
            if not os.path.exists(os.path.join(project, "database", "items", "salvage", e[0] + ".tres")):
                missing.add(e[0])
        with open(os.path.join(out_dir, kind + ".tres"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(table_text(spec))
    print("wrote", len(TABLES), "tables to", out_dir)
    if missing:
        print("MISSING items:", ", ".join(sorted(missing)))
        sys.exit(1)


if __name__ == "__main__":
    main(sys.argv[1])
