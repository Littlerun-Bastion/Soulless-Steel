extends Resource

# An internal bay part: the mecha's one optional extra (design slot
# "internal", not required to deploy). `function` says what it does:
#   ward    a sensor post: placed at the mecha (tap) or thrown a short way
#           (hold and aim); pings what is within sensor_range every
#           update_interval s, through walls, until destroyed
#   drone   flies in a straight line toward the aim (or straight ahead on a
#           tap), over buildings, pinging what is within sensor_range of it,
#           and self-destructs after device_max_distance
#   ecm     passive: while on (tap toggles; on when fitted) the mecha gets
#           this part's ECM / ECM_frequency against lock-ons and
#           sensor_reduction against active sensors (Mecha.sensor_reduction)
#   seeker  passive: while on, a small drone follows the mecha, gives the
#           owner vision of what is within sensor_range of it through walls,
#           and makes a quiet sound every sound_interval s that NPCs within
#           sound_range hear. Shot down, it is lost for the deployment.
#   flare   fired at a point (or straight ahead on a tap), at most
#           throw_range away; for device_lifetime s it gives every mecha
#           vision of what is within sensor_range of it, and lights the
#           ground there. Not affected by ECM; can't be shot.
#   biosensor  passive: while on, the owner has vision of the Entities
#           within sensor_range of the mecha. Not affected by ECM.
#   decoy   placed like a ward; for device_lifetime s it gives off a mecha's
#           heat (decoy_heat): sweeps, wards, drones and NPC sight take it for
#           a mecha, and NPCs may shoot it.
# Parts that put something out (wards, drones, flares, decoys) use charges
# like ammunition: a fresh load each deployment. Passive parts have none.
# Mecha.use_internal is where it all happens, for the player and NPCs alike.

@export var part_name : String
@export var manufacturer_name : String
@export var manufacturer_name_short : String
@export var tagline : String
@export var description : String
@export var price := 0.0
# Recycling and the Fabricator: the tech tier and what one of these breaks
# down into (or takes to build), material id (see Materials) -> amount.
@export var tech_tier: item_data.TechTier = item_data.TechTier.LOW
@export var composition: Dictionary[String, int] = {}
## False keeps the part out of the store and out of the Compare window's
## STORE list, for secret parts.
@export var store_listed := true
@export var image : Texture2D

@export_group("Function")
@export_enum("ward", "drone", "ecm", "seeker", "flare", "biosensor", "decoy") var function := "ward"
## Uses per deployment; 0 for a passive part.
@export var charges := 0
## Seconds between uses.
@export var use_cooldown := 1.0
## How far (px) a held use can throw a ward.
@export var throw_range := 400.0

@export_group("Device")
## The device a use puts out (wards, drones).
@export var device_scene: PackedScene
## How far (px) the device detects mechas and Entities.
@export var sensor_range := 1500.0
## Seconds between the device's pings.
@export var update_interval := 2.0
## Damage that destroys the device.
@export var device_hp := 2.0
## A drone's speed (px/s) and how far (px) it flies before self-destructing.
@export var device_speed := 700.0
@export var device_max_distance := 10000.0
## Seconds the device lasts (flares, decoys); 0 for until destroyed.
@export var device_lifetime := 0.0
## A Seeker's quiet sound: every sound_interval s, heard within sound_range
## px.
@export var sound_interval := 3.0
@export var sound_range := 600.0
## The heat a decoy gives off, as Mecha.get_thermal_signature (0 to 1).
@export var decoy_heat := 0.6

@export_group("ECM")
## Lock-on breaking, as chipsets used to carry (Mecha.update_locking).
@export var ECM := 0.0
@export var ECM_frequency := 0.3
## Active sensors find this mecha only within (1 - sensor_reduction) of their
## range.
@export var sensor_reduction := 0.0

@export var weight := 1.0
@export var tags :Array[String] = ["internal"]
@export var item_size := [2,2]
@export var additional_components: Array[Dictionary] = []

var part_id


## Whether it is used up as it is used (wards, drones) rather than switched
## on and off.
func is_passive() -> bool:
	return charges <= 0


func get_image():
	return image
