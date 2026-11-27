class_name LegacySave
extends RefCounted

# Reads progress saved before materials had real units (PlayerProgress
# set_save_data).
#
# Those saves count materials in abstract units, and Silicon is gone. A save
# without "materials_units" (or below UNITS_VERSION) is of that kind: each
# old unit becomes OLD_UNIT of the new material, in its stored unit. These
# are the amounts the parts' compositions were converted with, so a save
# keeps what its materials could build.
#
# The salvage items of that time were removed. One of them found in a saved
# stash or cargo is recycled on load: its old composition (OLD_ITEMS),
# converted the same way, goes into the materials.

## The "materials_units" a save of real units carries.
const UNITS_VERSION := 2

## Old material id -> [new material id, stored units per old unit].
const OLD_UNIT := {
	"steel": ["steel", 1000.0],                  # 1 t
	"copper": ["copper", 250.0],                 # 250 kg
	"silicon": ["electronics", 10.0],            # 10 kg
	"oil": ["oil", 100000.0],                    # 100 L
	"nt_fluid": ["nt_fluid", 10000.0],           # 10 L
	"noble_metals": ["noble_metals", 5.0],       # 5 g
	"fissile_materials": ["fissile_materials", 0.5],  # 0.5 kg
	"neural_biomatter": ["neural_biomatter", 2.0],    # 2 kg
	"myofibrilium": ["myofibrilium", 5000.0],         # 5 kg
	"avidendrites": ["avidendrites", 1.0],            # 1 kg
	"nt_engines": ["nt_engines", 1.0],                # 1 u
	"avi_polymer": ["avi_polymer", 2000.0],           # 2 kg
}

## Removed item path -> its composition in old units.
const OLD_ITEMS := {
	"res://database/items/salvage/armor_plate_fragment.tres": {"steel": 3},
	"res://database/items/salvage/avidendrite_lattice.tres": {"avidendrites": 1, "silicon": 1},
	"res://database/items/salvage/circuit_board.tres": {"silicon": 2, "copper": 1},
	"res://database/items/salvage/control_module.tres": {"silicon": 2, "noble_metals": 1, "neural_biomatter": 1},
	"res://database/items/salvage/coolant_canister.tres": {"nt_fluid": 2},
	"res://database/items/salvage/damaged_nt_engine.tres": {"nt_engines": 1, "nt_fluid": 2},
	"res://database/items/salvage/generator_core_fragment.tres": {"fissile_materials": 2, "steel": 1},
	"res://database/items/salvage/hydraulic_actuator.tres": {"steel": 2, "oil": 2},
	"res://database/items/salvage/myofibrilium_bundle.tres": {"myofibrilium": 2},
	"res://database/items/salvage/servo_assembly.tres": {"steel": 2, "copper": 1, "avi_polymer": 1},
	"res://database/items/salvage/wiring_loom.tres": {"copper": 2, "silicon": 1},
	"res://database/items/bio/acid_gland.tres": {"nt_fluid": 1, "avi_polymer": 1},
	"res://database/items/bio/avi_polymer_nodule.tres": {"avi_polymer": 2},
	"res://database/items/bio/avidendrite_node.tres": {"avidendrites": 1},
	"res://database/items/bio/chitin_plate.tres": {"avi_polymer": 1},
	"res://database/items/bio/myofibrilium_strand.tres": {"myofibrilium": 1},
	"res://database/items/bio/neural_cluster.tres": {"neural_biomatter": 2},
	"res://database/items/bio/nt_engine_heart.tres": {"nt_engines": 1, "nt_fluid": 1},
	"res://database/items/bio/nt_fluid_sac.tres": {"nt_fluid": 2},
}


static func is_legacy(data: Dictionary) -> bool:
	return int(data.get("materials_units", 0)) < UNITS_VERSION


## Old-unit counts -> new material id -> stored units (rounded up, so
## nothing is lost to rounding). Unknown ids are left out.
static func convert_materials(old: Dictionary) -> Dictionary:
	var result := {}
	for material_id in old:
		var id := str(material_id)
		var units := int(old[material_id])  # JSON numbers load as floats
		if not OLD_UNIT.has(id) or units <= 0:
			if units > 0:
				push_warning("LegacySave: dropping unknown material '%s'" % id)
			continue
		var target: Array = OLD_UNIT[id]
		var new_id: String = target[0]
		result[new_id] = int(result.get(new_id, 0)) + ceili(units * float(target[1]))
	return result


static func is_old_item(item_path: String) -> bool:
	return OLD_ITEMS.has(item_path)


## What `quantity` of a removed item recycles into, in the new units.
static func old_item_materials(item_path: String, quantity: int) -> Dictionary:
	var old := {}
	var composition: Dictionary = OLD_ITEMS.get(item_path, {})
	for material_id in composition:
		old[material_id] = int(composition[material_id]) * maxi(quantity, 1)
	return convert_materials(old)
