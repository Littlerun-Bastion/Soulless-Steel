# Helwan map generator

This tool makes the Helwan expedition map from OpenStreetMap data and a
reference image (a satellite image or a mockup). The settings for the map
are in `inputs/map.json` (section 2.4).

The current Helwan map is 5.4 km square (108,000 px at 20 px/m). It has
approximately 76,000 buildings and 76,000 prop spawns. The outer 200 m on
each side is a border band that mechs cannot enter, so the play area is
5.0 km square (section 2.4, `border_m`).

The generator also sorts the map into districts (residential, industrial,
market, farmland; section 7), builds each district's content (factories and
process plants, markets, fields, military sites; section 9), ruins some of
the buildings (section 8) and places the salvage sources (section 10).

## 1. The two scenes

The map has two scenes in `project/database/maps/`:

| Scene | Who makes it | The generator overwrites it |
|---|---|---|
| `helwan_master.tscn` | You (hand-made content) | No. It writes this scene one time only, if the file is missing. |
| `helwan_generated.tscn` | The generator | Yes. Every run writes it again. |

`helwan_master.tscn` is the map that the game loads. It contains
`helwan_generated.tscn` as an instance at `BG/Generated`.

Do not edit `helwan_generated.tscn`. Your changes are lost on the next run.
Put all hand-made content in `helwan_master.tscn`.

### 1.1 What the generated scene contains

- `Ground`: the ground texture and road meshes.
- `City`: the meshes, in seven sublayers: ground, ground lines, halos,
  interiors, roofs, overheads (pipe bridges, strut frames, conveyor
  gantries, platform canopies, gas-station canopies and depot shelters;
  they draw above mechas and fade over the player and, within 300 px, over
  every other mecha or Entity the player can see, as talls do: section
  6.4), and talls (things that stand well above the roofs; section 6.4).
- `MapBounds`: the map's edges and the border band (section 2.4).
- `Vehicles`, `Stalls` and `Foliage`: sprite layers that draw the prop
  spawns.
- `VehicleField`: the vehicle bodies (see section 5).
- `StallField`: breaks market stalls that a mecha walks through or a shot
  passes (section 9.2).
- `MapStreamer`: hides map chunks away from the camera and loads
  `StreamedScene` nodes near mechas (see section 6).
- `ObstacleField`: pipes, pipe racks and pools. Mechas move against them;
  shots and sight pass over them (section 9.1).
- `BuildingField`: the building outlines, their ruin states and the district
  grid. It does these tasks:
  - It tells a mecha when it enters or leaves a building.
  - It fades the roofs near the player.
  - It makes the building walls for shots and sight (see section 4).
- `SalvageField`: the salvage sources (section 10).
- `Landmarks`: the named places (`assets/maps/helwan/landmarks.res`, from
  the work dir's `landmarks.json`; section 6.5).
- `Overheads`: the viaduct.

Buildings are not separate nodes. Each chunk of buildings is one mesh, and
the outlines are one resource (`assets/maps/helwan/footprints.res`). You
cannot select or move one generated building in the editor. To change a
generated building, use a KeepOut area (section 3.1) and build your own
building in the master scene.

### 1.2 What the master scene contains

| Node | Use |
|---|---|
| `BG/Generated` | The generated scene. |
| `PropSpawner` | Merges all prop spawns (section 3.2). |
| `Overheads` | Your own overhead structures (`OverheadPath` nodes). |
| `SurfaceOverlays`, `Decals`, `Props`, `Buildings`, `Trees`, `Walls`, `Texts`, `Triggers` | The usual `Map.gd` containers, for hand-made content. |
| `Exits` | `Exit_N`, `Exit_E`, `Exit_S`, `Exit_W`. |
| `StartPositions` | `Pos1` to `Pos9`. `Pos1` is the player start. |
| `SpawnZones` | `Spawn1` to `Spawn8`. |
| `CystSites` | `Cyst1` to `Cyst4`. |
| `NavigationRegion2D` | One square over the play area (the map less its border band). |
| `KeepOut` | Areas that the generator keeps empty (section 3.1). Editor only. |
| `DistrictZones` | District areas that you paint by hand (section 7.2). Editor only. |
| `Reference/MockupUnderlay` | The IR mockup, to help you align content. Editor only. |

The generator picks the first positions of the exits, starts, spawn zones
and cyst sites. After that, move them by hand. The generator does not
change them again. All of them are inside the play area, at least 150 m
from its edge. The exits are on the main roads nearest each edge.

## 2. How to run the generator

### 2.1 Requirements

- Python 3.11 or newer, with `shapely`, `numpy`, `scipy`, `opencv-python`
  and `Pillow`.
- Godot 4.7.
- At least 8 GB of memory. The generator uses approximately 6 GB for the
  5.4 km map. It takes approximately 10 minutes on a fast computer and
  20 minutes or more on a slow one.
- On Windows, set `PYTHONUTF8=1` (or use Python 3.15 or newer) if a
  script fails to read a file with a `UnicodeDecodeError`. The generator
  opens its own files as UTF-8.

### 2.2 Inputs

All inputs are in `tools/helwan_map/inputs/`:

- `map.json`: the map settings (section 2.4).
- `satellite.jpg`: the reference image. The name is set in `map.json`.
- `osm.geojson`: the OpenStreetMap export. Export more than the image area
  (10 to 20% on each side). The generator cuts off everything outside the
  map.
- `mockup_2500m.png`, `osm_2500m.geojson`: the first 2.5 km Helwan mockup
  and its OSM export. The zone rules were tuned on this mockup.
  `calibrate_image.py` uses it as its reference.
- `sprites/`: the source sprites for trees, bushes, vehicles and market
  stalls.

The OSM export covers the whole 5.4 km map with a margin: at least 600 m
past the west edge (the Nile) and the south edge (desert), and more than
1.8 km past the north and east edges.

### 2.3 Procedure

1. If you added or changed a sprite, run this command from
   `tools/helwan_map/`:

   ```
   python prep_sprites.py inputs/sprites <repo>/project
   ```

   This writes the sprites to `project/assets/images/map/props/` and writes
   `sprite_catalogue.json`. For a new vehicle, first add its real length,
   mass, prop kind and salvage source kind to the `VEHICLES` table in
   `prep_sprites.py`. A sprite whose pixels did not change keeps its file.

   The buses, tanks, APCs, military trucks, the container truck, the tanker,
   the dump truck, the shipping containers, the market stalls, the huts and
   the clutter are placeholders. To draw them
   again (for example after you change `make_placeholders.py`), run
   `python make_placeholders.py` first. When you have the real art, put it
   in `inputs/sprites/` with the same file names and do not run
   `make_placeholders.py` again. Stalls are drawn with the counter along x
   and the front (where buyers stand) towards +y, on the same canvas for
   `stall_<name>.png` and `stall_<name>_broken.png`. Huts are drawn with the
   long side along x, on the same canvas for `hut_<name>.png` and
   `hut_<name>_broken.png`; a new hut or clutter sprite also needs its real
   length in the `HUTS` or `CLUTTER` table in `prep_sprites.py`.

2. Run the generator:

   ```
   python run_all.py <repo>/project <work dir>
   ```

   Use a work folder outside the repo.

3. Build the meshes. Run this command from the `project/` folder:

   ```
   godot --headless -s <repo>/tools/helwan_map/build_meshes.gd -- <work dir>
   ```

   Use the full path to `build_meshes.gd`.

   This writes the files in `project/assets/maps/helwan/`.

4. Open the project in Godot. Let Godot import the new files.

5. Open `helwan_master.tscn` and examine the map.

You must do steps 2 and 3 together. The scene from step 2 and the meshes
from step 3 must come from the same run.

The generator writes `helwan_master.tscn` only when it is missing. If you
change the map size or the border band, delete the old master scene (after
you copy any hand-made content out of it), and delete
`project/assets/maps/helwan/`. Otherwise old markers and old chunk files
stay. Delete the `.res` files in `project/assets/maps/helwan/` before step 3
in any case: a chunk that has no content in the new run keeps its old file.

At the end of a run, the generator prints its counts (buildings by state and
district, obstacles, salvage sources by kind, props by kind, triangles),
the time of each step and its peak memory, and writes them to
`<work dir>/stats.json`.

### 2.3a Quick previews of a part of the map

A full run takes about 10 minutes. To look at one area while you change a
rule, build only a window of the map and draw it to a PNG:

```
python run_all.py <repo>/project <work dir> --window x0,y0,x1,y1 --city <full work dir>/city_cache.pkl
python render_preview.py <work dir> <repo>/project out.png --window x0,y0,x1,y1 --scale 4 --annotate
```

- The window is in metres from the map centre (x east, y south).
- `--city` reuses the roads, roofs and house lots that a full run saved in
  its work dir (`city_cache.pkl`), so the districts are the full map's, and
  the window comes out as in a full run. Without `--city`, the run builds
  only the street blocks in the window (fast, but the districts are worked
  out from that part only).
- A window run writes only to its work dir. It does not change the project.
- `--reuse` starts a run at the districts with the city layout saved in the
  same work dir.
- `render_preview.py` draws the six mesh sublayers in the game's order and
  the props as their sprites. `--annotate` adds the salvage sources (yellow
  boxes), the obstacles (red outlines) and the ruin state of each building
  (a dot: green damaged, orange gutted, red collapsed). The game's grain
  shaders are not drawn. `--districts` draws the district map of a work
  dir instead.
- `review_boards.py <repo>/project <out dir>` draws two fixed boards: every
  ruin state on the same footprints, and the six solar panel installations.

### 2.4 The map settings (map.json)

| Setting | Meaning | Helwan |
|---|---|---|
| `map_m` | Width of the map square, in metres | 5400 |
| `grid_n` | Pixels across the image grid that the generator reads the reference image into (approximately 2 m for each pixel) | 2700 |
| `geo_centre` | The latitude and longitude that real-world metres are measured from | 29.8215117, 31.3061374 |
| `image` | The reference image file, north up | satellite.jpg |
| `image_span_m` | Metres that the image spans | 5400 |
| `image_centre_m` | Real-world metres (east, south) of the image centre from `geo_centre` | 1420, -2172 |
| `image_rot_deg` | The image's rotation against north | 0 |
| `border_m` | Width of the border band round the map, in metres. Mechs, NPCs and Entities cannot enter it. The generator fills it like the rest of the map, but puts no salvage sources, spawns or exits in it | 200 |
| `zones` | Thresholds for the zone rules (section 2.6) | |
| `grey_map`, `texture_map` | Brightness and texture calibration (section 2.5) | |

The map is the image's area. If `map_m` is not the same as
`image_span_m`, the image is scaled to fill the map.

### 2.5 A new reference image

Do these steps one time for each new image:

1. Put the image in `inputs/` and set `image` in `map.json`. Set
   `image_span_m` to approximately how many metres it spans.

2. Find where the image is on the OSM data:

   ```
   python fit_image.py --write
   ```

   This writes `image_centre_m`, `image_span_m` and `image_rot_deg`, and
   draws `fit_overlay.png` (the OSM streets drawn on the image). Examine the
   overlay. The streets must sit on the streets in the image. Set `map_m`
   to `image_span_m`, and `grid_n` to `map_m / 2`.

3. Calibrate the image:

   ```
   python calibrate_image.py inputs/mockup_2500m.png 2485 -81 -94 1
   ```

   The zone rules use fixed brightness and texture values, tuned on the
   first mockup. This step finds the area that the new image and the first
   mockup both show, and writes two maps into `map.json`. These maps give the
   new image's brightness and texture the same spread of values as the first
   mockup. The two images must overlap (at least 2% of the map).

4. Look at the zones (section 2.6), and change the `zones` settings if
   necessary.

### 2.6 Zone settings

The generator sorts the image grid into four zones: open ground, dense
housing, large roofs and water. The settings under `zones` in `map.json`
change the rules. The defaults are in `zones.py`.

| Setting | Meaning | Helwan |
|---|---|---|
| `housing_tex` | Texture above this, with streets, is housing | 0.036 (default) |
| `housing_dens` | OSM street density needed for housing | 0.012 (default) |
| `housing_max_grey` | Also housing: local brightness below this, where the street density is above `housing_grey_dens` | 0.17 |
| `housing_grey_dens` | Street density needed for the brightness rule | 0.035 |
| `housing_bright` | Local brightness above this is never housing (bare sand and rock) | 0.24 |
| `roof_grey` | A large roof is brighter than this | 0.23 |
| `roof_contrast` | A roof's edge is this much brighter than the ground round it | 0.035 |
| `roof_dens` | Street density needed round a roof | 0.01 |
| `roof_max_px` | Largest roof, in grid pixels | 12000 |
| `roof_min_side` | Narrowest roof, in grid pixels | 6 |
| `roof_max_aspect` | Longest roof for its width | 5 |

The Helwan satellite image is soft (approximately 4 m for each pixel), so
the fine texture of dense housing is mostly lost. The brightness rule
(`housing_max_grey`) finds the housing that the texture rule misses.

## 3. Hand-made content

### 3.1 KeepOut areas

A KeepOut area is a `Polygon2D` node under the `KeepOut` node in the master
scene. The generator keeps these out of each area:

- buildings,
- generated props.

Roads and the ground stay. The generator adds a margin of 2 m round each
area.

To clear an area:

1. Add a `Polygon2D` as a child of `KeepOut`.
2. Draw its outline with the Godot polygon tools. You can move, turn and
   scale the node.
3. Save the master scene.
4. Run the generator again (section 2.3, steps 2 and 3).

Keep the `KeepOut` node at the origin, with no rotation and no scale. The
generator reads each area's position, rotation, scale and polygon. It does
not read the parent transform.

### 3.2 Props

The `PropSpawner` merges spawn points from three sources:

1. **Generated spawns** (`assets/maps/helwan/props.res`). The generator puts
   vehicles on roads (more on the main arterial road), clusters of 2 to 4
   bushes near buildings, and trees in open ground.
2. **PropZone** nodes. Add them as children of the `PropSpawner`.
   - `CLEAR` mode removes generated spawns of the listed kinds in the area.
     If the list is empty, it removes all kinds.
   - `SCATTER` mode adds random spawns of the listed kinds in the area.
     `density` is the number of spawns per 100 m². `min_spacing` is the
     minimum distance in px between spawns. `zone_seed` changes the
     pattern.
3. **PropSpawnPoint** nodes. Add them as children of the `PropSpawner`.
   Each one is a single prop. Set `kind`, `chance`, `variant` (-1 for a
   random sprite) and `size` (zero for the default size).

A `CLEAR` zone does not remove a `PropSpawnPoint`.

**Thinning.** The `PropSpawner`'s `kept_share` (kind -> 0..1) keeps that
share of a kind's generated spawns, without a new generator run; which
ones go is fixed by `map_seed` and each spawn's place in the list. The
master scene keeps 65% of `vehicle` and 80% of `vehicle_wreck` spawns.

**Set pieces.** Every prop the site modules place (`landmarks.py` to
`sites.py`; `run_all.py` turns `Props.set_piece` on while they run) is a
`props.SetPiece` item: props.json gives it an 8th field of 1, and it loads
into `PropSpawnSet.placed`. `kept_share` never thins a set piece, so a car
park's rows, a dealership's cars or a depot's buses stay whole (on the
merged map 1,472 cars and 159 wrecks; `stats.json` `set_piece_props` has
the count per kind). Tune `kept_share` knowing it only thins the generic
kerb parking and traffic. A `CLEAR` zone still removes set pieces.

Kinds: `vehicle`, `truck`, `vehicle_wreck`, `tree`, `bush`, `debris`,
`stall`, `bus`, `military`, `container`, `hut`, `clutter`, `railcar` and any
the generator adds (`props.KINDS`). At this time, the game draws all of them
except `debris`. Vehicles, trucks, wrecks, buses, military vehicles,
containers and rail vehicles have bodies (section 5). Stalls have none
(section 9.2).

The game reads every kind by its name (each work file lists its kind
names); nothing in the game lists them. To add a kind:

- **A vehicle kind with bodies** (for example `railcar`): append it to
  `props.KINDS` and `props.SIZE_M`; add its sprites as `VEHICLES` rows in
  `prep_sprites.py` with the new kind name (length, mass, shot block, spawn
  weight 0 if only your module places it, salvage source kind or None) and
  their `HEIGHTS`, and placeholders in `make_placeholders.py`; append the
  kind to `gen_scene.VEHICLE_KINDS` (the `Vehicles` layer and the
  `VehicleField` both use it) and to `render_preview.py`'s PROPS kinds.
  Mass decides the rest: over 3,000 kg it is a heavy vehicle (layer 12,
  can't be trampled or destroyed, costs the route grid 2.0).
- **A small kind with no body**: the simplest is a new variant of `clutter`
  (a `CLUTTER` row, a `HEIGHTS` entry and a placeholder; place it with
  kind `clutter` and that variant's index). A kind of its own needs its
  sprites under its own name in `sprite_catalogue.json` (a `prep_sprites.py`
  branch for its file prefix), the kind in `props.KINDS`/`SIZE_M`, and its
  name in `gen_scene.CLUTTER_KINDS` and `render_preview.py`'s PROPS kinds.
  A kind that breaks like a stall needs a layer and a `StallField` of its
  own in `gen_scene.py`.
- **A salvage kind**: append it to `salvage.KINDS` (and
  `salvage.VEHICLE_KINDS` if it rides on a vehicle), add its loot table to
  `tools/salvage_loot/make_source_loot.py` `TABLES` and run it (the game
  warns about a kind with no table and leaves its sources empty). The HUD
  names it from its name (`rail_freight` shows as RAIL FREIGHT) unless
  `SalvageField.KIND_NAMES` has a better name.

A work file may name at most 256 kinds (one byte per point);
`build_meshes.gd` refuses a longer list rather than load wrong kinds.

Some vehicle spawns are also salvage sources at the same spot: every bus,
container truck, tank, APC and military truck, and some of the containers
(section 10). If you remove such a vehicle with a `CLEAR` zone, its source
stays; draw a KeepOut area instead and run the generator again.

### 3.2a District zones

To set the district of an area by hand, add a `Polygon2D` under the
`DistrictZones` node of the master scene, and give it a metadata entry
`district` with the value `residential`, `industrial`, `market` or
`farmland` (in the Inspector: Add Metadata, type String). The scene text is
`metadata/district = "industrial"`. Then run the generator again. A painted
polygon wins over the generator; where two overlap, the later one in the
scene wins. Keep `DistrictZones` at the origin, as with `KeepOut`.

`PropSpawner.map_seed` changes all random choices. Spawn markers show in
the editor only (`show_markers`).

### 3.3 Overhead structures

An overhead structure is an `OverheadPath` node. It is a deck on piers,
drawn above mechas (z index 3). It has no collision. It becomes transparent
when the player goes under it.

To add one, add an `OverheadPath` under `Overheads` in the master scene and
draw its line. The generated viaduct is in the generated scene. Do not
change it there; the next run replaces it.

### 3.4 Your own buildings and compounds

You can put the existing `Building.tscn` scenes in `Buildings`. Use a
KeepOut area to clear the space first.

For a large hand-made area (a compound, a landmark), make it a scene of its
own and place it with a `StreamedScene` node (section 6.3). The map then
loads it only while a mecha is near it.

Hand-made buildings do not use the wall rules in section 4. Only generated
buildings have walls on the wall layer.

## 4. Walls, shots and sight

The rules are in `project/game/map/MapSenses.gd`.

### 4.1 Walls

Each generated building has its outline on physics layer 10 (`WALL_LAYER`).
Mechas walk through walls. Rays see the walls.

The outlines of all buildings in one 250 m square are merged into one
collision body (`BuildingField.WALL_CELL_SIZE`). Every ray pays for each
body along its path, so about 100 merged bodies cost far less than one body
for each of the 8,630 buildings. Each outline that a ray crosses still
counts as one wall.

- Each wall that a shot crosses decreases its AP by 1.
- When the AP becomes 0, the shot stops at that wall.
- A round with an impact fuse goes off at the first wall it touches.
- A round with no impact fuse does not go off at a wall. If a wall stops
  it, its timer and proximity fuses continue to operate.

### 4.2 Vehicles and shots

- A vehicle stops a shot that passes through it by chance. The chance is
  the vehicle's `shot_block` value: 0.5 for cars, up to 0.85 for the fire
  engine.
- A shot that a vehicle does not stop continues with its full AP.
- A round with an impact fuse goes off in a vehicle that stops it. Other
  rounds stop there, and their timer and proximity fuses continue to
  operate.

### 4.3 Sight

- Vehicles do not block sight. They are lower than a mecha.
- A building wall blocks sight. A mecha inside a building is hidden from
  observers outside it.
- Two points in the same building have no wall between them. Two mechas in
  the same building can see each other.
- A tree over a target decreases the detection range to 60%
  (`TREE_CONCEALMENT`).
- A bush over an Entity decreases the detection range to 50%
  (`BUSH_CONCEALMENT`). Bushes do not hide mechas.
- A tree over an observer decreases its sight range to 85% (`TREE_SIGHT`).

Enemy mechas (`Enemy.gd`) and Entities (`Entity.gd`) use these rules.

### 4.4 Ray masks

Use one of these masks for a new ray:

| Mask | Sees walls | Sees vehicles | Use |
|---|---|---|---|
| `SHOT_MASK` | No | No | The main hit ray of a projectile. Call `MapSenses.trace_shot` first for walls and vehicles. |
| `SIGHT_MASK` | Yes | No | Line of sight. |
| `NON_WALL_MASK` | No | Yes | Movement steering. |

## 5. Vehicles

`project/game/map/props/VehicleField.gd` gives the vehicles bodies. The
vehicles are not nodes.

### 5.1 How it works

- A vehicle can have a static box on physics layer 11
  (`MapSenses.VEHICLE_LAYER`). The box is the vehicle's length by its width.
- Only vehicles near the player or an NPC in full simulation have boxes
  (`VehicleField.wakes_vehicles`: not NPCs in the distant tier, which move
  with no physics, not dead mechas and not mechas a camp is taking off the
  map). The map is divided into 50 m cells. Vehicles in the cells within
  100 m of such a mecha (`stream_radius` 2000 px) have boxes. The other
  vehicles are only pictures. The cells are checked every 10 physics
  frames. NPC steering reads the vehicles directly, so it steers round
  vehicles with no box.
- Because of this, a shot that passes a vehicle more than 100 m from every
  such mecha goes through it. Set `stream` to off to give every vehicle a
  box.
- Mechas collide with the boxes. Entities do not; they go round and under
  vehicles.
- When a mecha pushes a vehicle, the vehicle wakes. It becomes a
  `RigidBody2D`, and its sprite moves from the sprite layer to the body.
- A woken vehicle that stops, with no mecha near it, settles. It becomes a
  static box again where it stopped, and its sprite goes back to the layer.
  Vehicles stay where they stopped for the rest of the expedition.
- A moving vehicle wakes the vehicles in its path, so a pushed car can push
  the next car.
- Vehicles collide with building walls. A mecha cannot push a vehicle
  through a building.
- A maximum of 24 vehicles are awake at one time (`MAX_AWAKE`).

### 5.2 Pushing

- The mecha pushes with 50 kg per point of its weight
  (`MECHA_KG_PER_WEIGHT`). A typical mecha (weight 55) pushes with
  2,750 kg.
- When the mecha first hits a vehicle, the vehicle bounces ahead
  (`RESTITUTION` 0.3).
- While the mecha pushes, the vehicle and the mecha move together. Their
  speed is the mecha's speed × mecha mass ÷ (mecha mass + vehicle mass).
- A heavy vehicle slows the mecha. For a typical mecha:

| Vehicle | Mass | Speed while pushed |
|---|---|---|
| Hatchback | 950 kg | 74% |
| SUV | 2,200 kg | 56% |
| Ambulance | 3,500 kg | 44% |
| Minibus | 4,200 kg | 40% |
| Fire engine | 14,000 kg | 16% |

- After the push, a car slides on approximately 3 to 5 m (`linear_damp` 3.5).
- A push off the vehicle's centre turns it (`SPIN`, `angular_damp`).

### 5.3 Mass and shot_block values

These values come from `sprite_catalogue.json` (the `VEHICLES` table in
`prep_sprites.py`). The generator writes them into the `VehicleField` node.
Wrecks use the values of their car sprite.

## 6. Streaming

`project/game/map/MapStreamer.gd` streams the map at runtime. It does three
things.

### 6.1 Map chunks (round the camera)

The map is drawn in chunks of approximately 500 m: meshes, and the sprite
batches of the vehicle and foliage layers. The streamer hides each chunk
while it is more than `view_margin` (2000 px) outside the camera's view. It
checks five times each second.

### 6.2 Chunk meshes (round the camera)

The 5.4 km map has 578 chunk meshes (approximately 355 MB in memory). They
do not all fit in memory on a small computer, so they are not part of the
scene. Each chunk is a `ChunkMesh` node (`project/game/map/ChunkMesh.gd`)
that holds the path to its mesh file and its bounds.

- The streamer loads a chunk's mesh on a background thread when its bounds
  are within `mesh_load_margin` (6000 px) of the camera's view.
- It frees the mesh when its bounds are more than `mesh_load_margin` +
  `mesh_unload_slack` (10,000 px) away.
- A chunk that is in view without its mesh (at the start of a run, or after
  the camera jumps) is loaded at once. The game waits for it.

In the editor, every chunk loads its mesh, so the whole map shows. The mesh
is never saved into a scene.

### 6.3 Hand-made scenes (round every mecha)

A `StreamedScene` node (`project/game/map/StreamedScene.gd`) holds a
hand-made scene that loads only when a mecha is near it.

To add one:

1. Make the hand-made area a scene of its own (for example
   `database/compounds/cement_office.tscn`).
2. In `helwan_master.tscn`, add a `Node2D` and attach `StreamedScene.gd`.
3. Move the node to where the scene goes.
4. Set `scene_path` to the scene file.
5. Set `bounds` to cover everything in the scene. The editor shows the
   bounds as a blue box, and shows the scene as a preview.

The streamer loads the scene on a background thread when any mecha comes
within `load_distance` (4000 px) of the bounds. It frees the scene when
every mecha is more than `load_distance` + `unload_slack` (5500 px) away.

Hand-made scenes stream round every mecha, not only the player, because
they have collision. NPCs far from the player must still meet their walls.

When a scene is freed, its changes are lost (for example, opened doors or
looted crates). Keep that state outside the scene.

### 6.4 Talls

The `talls` sublayer holds things that stand well above the roofs: crane
masts and jibs, pylons and wires, minarets, the upper floors of building
frames. Every vertex has a height in metres (the mesh file's channel flag
2; `build_meshes.gd` puts it in `UV.x` through
`project/game/map/MapMeshFile.gd`). The `City/Talls` node
(`project/game/map/TallsLean.gd`, shader
`project/assets/shaders/TallsLean.gdshader`) leans every vertex away from
the centre of the screen by its height:
`shift = (vertex - screen centre) * h / (150 - h)`, with h clamped to
100 m, so tall things lean as in a real top-down view. `render_preview.py`
draws them with the same rule (`EYE_M`, `MAX_H_M`; keep both in step with
`TallsLean.EYE_M` and `MAX_HEIGHT_M`). The screen centre is read every
frame from the viewport, so camera pan, shake and zoom are all in it. With
no camera (the editor) talls stand flat. Talls within 600 px of the player
fade to 0.25 alpha (measured at each vertex's ground and drawn position),
so a jib over the player never hides it. Where they are drawn within 300 px
of another mecha or Entity the player can see (`ghost_radius`), they fade
the same way, so a leaning tower top never hides an enemy far from the
tower's foot; a body the player's view hides (alpha 0) makes no hole. They
are lit by the map's lights like everything else, at their drawn position.
The grain stays fixed to the object as the camera moves; on side faces the
height runs across it too, so walls get grain both ways.

A leaned vertex is always further from the screen centre than its ground
position, so a chunk whose ground bounds are off screen also draws off
screen: chunk hiding and mesh streaming work on the ground bounds as for
the other sublayers. Each talls chunk's cull rect is still grown by 1000 px
(`cull_margin`).

To see talls in the game without the generator: `TallsRenderProbe`
(section 11).

### 6.5 Named places (Landmarks)

The site modules register named places (`Site.add_landmark`); `run_all.py`
writes them to `<work dir>/landmarks.json` and `build_meshes.gd` to
`assets/maps/helwan/landmarks.res` (`MapLandmarks`). The generated scene's
`Landmarks` node (`project/game/map/Landmarks.gd`, `Landmarks.find(node)`)
loads that file by path when it is ready (no file: no places, so the scene
still opens between `run_all.py` and `build_meshes.gd`) and answers:

- `at(pos)`: the place whose outline holds a position (a place with no
  outline: within its radius); the smaller one where two overlap.
- `nearest(pos, max_px)`: the nearest place, by the distance to its area.
- `describe(pos)`: a phrase for a hint: "near <name>" inside a place or
  within 200 m of it, "<n> m <direction> of <name>" out to 1.5 km.

When the player enters a place, the HUD shows its name as a notice (below
every other notice and the extraction countdown) and in the top strip while
the player is inside. The notice shows again only after the player has been
out of the place for 60 s (`reentry_time`). A notice still waiting behind
another is dropped when the player leaves the place first. The place the
player starts in is not announced. Nothing is saved.

## 7. Districts

`districts.py` tags every 25 m cell of the map with a district:
`residential`, `industrial`, `market` or `farmland`. Every other layer reads
its rules and densities from the district: what is built in a street block
(section 9), how much ruin there is (section 8), and which salvage sources
go where (section 10).

The game reads the grid from `assets/maps/helwan/districts.res`
(`MapDistricts`) and each building's district from `footprints.res`.

### 7.1 How the generator decides

1. OSM tags, where they exist: `landuse` (industrial, retail, commercial,
   residential, farmland, farmyard and others) and building tags
   (industrial, warehouse, hangar, retail, farm, barn and others). OSM
   coverage in Helwan is patchy: only a few areas are tagged.
2. Where there are no tags, building statistics and the reference image:
   - industrial: large plain footprints (over `BIG_PLAIN_M2`, nearly
     rectangular) cover more than `INDUSTRIAL_COVER` of the land round the
     cell;
   - market: dense housing along main roads. The generated houses are the
     same size everywhere, so the rule takes the street density times the
     housing cover beside a main road. The best places (`MARKET_SEEDS`, at
     least `MARKET_SPACING_M` apart) grow along their main road into market
     strips about `MARKET_LENGTH_M` long;
   - farmland: few buildings (cover under `FARM_MAX_COVER`), mostly open
     ground, and green in the reference image (the old fields along the
     Nile). Bare desert is not farmland;
   - everything else is residential.
3. A majority filter over the neighbour cells (`MAJORITY_PASSES` passes),
   then areas smaller than `MIN_AREA_M2` join the district round them.
4. District zones painted in the master scene (section 3.2a) win.

In Helwan this gives the industrial estate in the south-east and the cement
plant in the south-west, a large OSM industrial area in the north-east,
market strips along main roads in the old town, and farmland along the Nile.

### 7.2 Changing the districts

- To change one area, paint a district zone (section 3.2a).
- To change the rules, change the constants at the top of `districts.py`.
- `python render_preview.py <work dir> x out.png --districts` draws the
  district map of a run.

## 8. Ruin states

`ruins.py` gives every building a ruin state: intact, damaged, gutted or
collapsed. The game reads the state from `footprints.res` (one byte per
building):

| State | Look | Game rules (BuildingField) |
|---|---|---|
| Intact | Roof | As before |
| Damaged | Holes in the roof, mainly at the edge, and one near the centre. The interior shows through them. Rubble spills out, cracks run from the holes | As intact |
| Gutted | Two roof fragments. The outer wall is broken into segments with about 40% missing. Rubble and scorch inside and round it | The whole outline is still a wall. No entering (no zoom or darken) |
| Collapsed | A rubble heap a little larger than the footprint, 2 to 5 roof slabs with cracks, dense rubble, wall stubs at most corners. The slabs stay inside the footprint and off each other, and none is narrower than 3.5 m or 16% of the building's length (`collapsed_slabs`), so they never read as buildings on top of buildings | No wall, no slow at the edge, no roof |

All states are operations on any footprint, so no building needs a
hand-made ruined version. Roof items (AC boxes, tanks, solar sets) never
sit in a hole.

Which buildings: a damage map of `BLAST_CENTRES` seeded blast centres plus
smooth noise, so ruins cluster. Each building reads the map at its centre,
scaled by its district (`DISTRICT_SCALE`: industrial 1.3, market 1.1,
residential 1.0, farmland 0.6), plus a little jitter. The value against
`STATE_LIMITS` gives the state. Buildings larger than
`BIG_MAX_COLLAPSED_M2` (halls, sheds) are at most gutted. In Helwan about
70% of the buildings are intact, 17% damaged, 7% gutted and 6% collapsed.

**No overlaps.** After all district stages, `buildings.resolve_overlaps`
checks every pair of footprints. Where two overlap by more than 1 m2 or 2%
of the smaller one (`OVERLAP_M2`, `OVERLAP_SHARE`), the smaller is trimmed,
or dropped when less than 70% of it would be left. A shared wall is not an
overlap. `stats.json` lists the pairs before and after, by district and by
the stage that made each building (`overlaps`).

To change the amount of ruin, change `STATE_LIMITS` (higher limits, fewer
ruins) or `BLAST_CENTRES`. The rubble density is in the `RUBBLE_*`
constants; rubble is most of the extra mesh size of ruins.

## 9. District content

Each district module rebuilds the street blocks of its district before the
buildings are drawn. All new buildings are ordinary generated buildings
(walls, roofs, ruin states).

### 9.1 Industrial (industrial.py, plant.py, pipes.py)

Each industrial street block becomes a fenced compound. A block larger than
`COMPOUND_MAX_M2` (an estate, a works site) is tiled with rows of compound
plots (`PLOT_DEPTH_M` deep; `PLANT_PLOT_M` wide for a process plant,
`FACTORY_PLOT_M` for a factory) with service roads between them. Houses
inside compounds are removed; large roofs stay as the compound's halls. A
house that the fence cuts stays, unless it is under an overhead rack of a
plant (`density.clear_houses`).

- **Factory**: a sawtooth shed with loading docks (and trucks at some of
  them), a container yard or bus depot, an L workshop, a chimney, a silo
  cluster with a conveyor gantry, tanks in a bund, equipment yards.
- **Cement works**: the lots that are not process plants in the box
  `CEMENT_BOX_M` (`density.py`): a mill hall, a rotary kiln between its
  preheater tower and its cooler house, silo clusters with conveyors,
  material heaps, dump trucks.
- **Process plant**: section 9.1a.
- **The density pass**, on every lot: section 9.1b.
- Tanks, silos, chimneys, pump houses, control buildings, sheds and
  workshops are buildings.
- Pipe racks and single pipes on the ground and process unit pads are
  obstacles of kind `pipe`, pools of kind `pool` (`assets/maps/helwan/obstacles.res`). The
  game's `ObstacleField` puts them on the barrier layer: mechas move against
  them, shots and sight pass over them. Overhead racks, pipe bridges and
  conveyor gantries are only drawn (the `overheads` sublayer): mechs pass
  under.
- One obstacle outline is one part of a rack or pipe on the ground (not one
  per pipe). Outlines are simplified (0.3 m), have at most 64 points, and
  long runs are cut into pieces of at most 60 m (`obstacles.py`).

### 9.1a Process plants (plant.py)

A process plant is built network-first, after Yosqi's process plant
reference aerial: the pipe network is laid out first and every node hangs on
it. Pipes are long and connected, and they end at equipment or join another
pipe. The plant is built in the largest free rectangle of its compound:

1. **Internal roads**: cross roads about every 62 m (`COL_M`) and, in a
   plant deeper than `TWO_ROWS_M`, a spine road along the middle. They cut
   the plant into cells. Each road is a corridor 14 m wide (`CLEAR_M`) that
   stays free.
2. **Nodes**, one in each cell: a control building with a substation and a
   yard, a tank bund (round tanks and an empty pad), a pool with its pump
   house, 1 to 3 process units, equipment yards.
3. **The trunk rack** (4 or 5 pipes): a ring round the plant's perimeter, or
   a U that starts at the control building and ends in a process unit. Its
   pipes turn every corner together. It is overhead from end to end.
4. **Rungs**: racks of 3 pipes along the cross roads, from one long side of
   the trunk to the other. With the trunk they make loops round the blocks.
   They are overhead too, over the edge of their road.
5. **Branches** from the racks to every node, peeling off on concentric
   elbows: a branch rack into each process unit, a small pipe from every
   tank and from the pool, a branch from the control building, a utility
   pipe into each yard.
6. **Long single pipes** between distant nodes, along the road edges, with a
   jog of two 45 degree kinks where the lane has room: the large bright pipe
   (1.0 to 1.3 m) from the pool's pump house to the farthest process unit,
   the bund's manifold to a unit, and 2 or 3 parallel pipes between units.
7. **The manifolds in each unit**: an air-cooler bank (a frame of about 12
   tubes over fans), the branch pipes wrapped round it as nested rectangular
   loops with round corners, a row of pumps on a header, exchangers with
   U-loops, and a vessel where the large pipe ends.
8. **Expansion loops** on the long straight runs of the racks, where the
   bay beside a node leaves room.
9. **Links**: where two plants face each other across a road, an overhead
   rack joins their trunks (`LINK_MAX_M`), so an estate reads as one network.

The pipe drawing rules are in `pipes.py`: elbow radius 2.5 x the diameter,
concentric bends in a rack, flanges every 6 to 9 m, 3 to 5 pipes for each
rack at about 0.9 m spacing on runners with cross-members, diameters 0.4 to
1.3 m, pipes brighter than roofs.

**Passability.** Pipes and racks on the ground block mechas, so a connected
network could wall a plant off. The generator prevents this in four steps:

- **Overhead racks.** The long-haul racks (`OVERHEAD_ROLES`: the trunk and
  the rungs, and the links between plants) are trussed racks on supports
  every 26 m or less (`SUPPORT_M` in `pipes.py`). They are drawn in the
  `overheads` sublayer and are no obstacle, so mechas pass under them
  anywhere. The other runs are on the ground and are obstacles: the branch
  racks into the units, the long single pipes, the tank, pool and yard
  pipes.
- **Pass-under gaps.** A run on the ground is raised as a pipe bridge where
  it crosses an internal road, and so that no part on the ground is longer
  than 70 m (`MAX_GROUND_M`). Every raised part is at least 26 m long
  (`GAP_M`, one constant for road crossings, spacing bridges, the checks'
  repair bridges and marker bridges): an NPC needs about 24 m between
  obstacle outlines. A pipe bridge is in the `overheads` sublayer, on a
  truss with a support at each end. It is no obstacle.
- **The player's check**, for each plant. The generator rasterises its
  buildings, bund walls, pools and pipe obstacles (0.5 m cells), shrinks the
  free ground by 6 m (`SHRINK_M`: half a mecha's width and a margin), and
  flood-fills from the ground outside the plant. Every open area of 400 m2
  or more must be reached, and every salvage source must be within 8 m of
  reached ground. Where that fails, the generator raises the run that is in
  the way and checks again. A source that still cannot be reached is moved
  to reached ground or left out.
- **The NPCs' check** (`npc_access`), for all plants together. NPCs plan
  their way on the game's route grid: squares of 12.5 m from the play area's
  corner, closed when an obstacle outline grown by 2 m overlaps them
  (`BuildingField.gd`). The generator builds the same grid from its own
  outlines and floods it from the ground far from the plants. Every open
  square in or beside a plant must be reached, every node must have a
  reached square within 20 m (`NPC_NODE_M`) and every salvage source one
  within 17 m (`NPC_SOURCE_M`). Where that fails, the generator finds the
  cheapest way in (by the length of run that must be raised to open its
  squares) and raises those runs. Last, it places the salvage sources for
  NPCs (`place_sources`): for a goal in a closed square the game sends the
  NPC to the first open square in the rings round it. If that square is not
  reached, or is more than 15 m (`NPC_GOAL_M`) from the source, the source
  is moved at most 14 m into an open, reached square: off the roads, clear
  of the nodes and of other sources, and still within the player's reach.

The player's check treats buildings and bund walls as closed, which is
stricter than the game (mechas walk through buildings, and bund walls are
only drawn). The results are in `stats.json` under `plant_network`: `check`
(the player's check), `npc` (the NPCs' check: squares and goals cut off
before and after, sources moved), `raised_share` and `rack_raised_share`
(how much of the run length and of the rack length is overhead), with each
plant's pipe lengths, pipe ends and pipe bridges by reason.

**Markers.** The generator reads the exits, start positions, spawn zones and
cyst sites from the master scene. A marker in a compound keeps a circle of
14 m free (`KEEP_CLEAR_M`): no node is built there, and a run that passes it
is raised. `stats.json` lists any marker inside an obstacle (`markers`).

To change the plants: `PLANT_SHARE` (how many plots are plants) and the plot
sizes are in `industrial.py`; the layout sizes, the pipe bridge rules and
the check's limits are the constants at the top of `plant.py`.

### 9.1b The density pass (density.py)

After the lots are built and the plants are checked, `density.py` fills
every industrial lot (process plant, factory, depot, cement works), so that
it reads at three scales. Sizes are by footprint: big over 400 m2
(`BIG_M2`), medium 30 to 400 m2, small under 30 m2.

**How much.** A lot is filled until it has 4 medium and 15 small things for
each big one (`MEDIUM_PER_BIG`, `SMALL_PER_BIG`), or one medium thing for
every 450 m2 and one small thing for every 110 m2 of open ground
(`MEDIUM_GROUND_M2`, `SMALL_GROUND_M2`), whichever is more, up to
`MAX_MEDIUM` and `MAX_SMALL`. Medium things go within 16 m (`GROUP_M`) of a
big thing, or along the fence (`EDGE_SHARE`). Small things go round the
medium and big ones. Nothing goes on a plant's internal roads, under its
racks, or on a salvage source.

**What.**

- Medium, real buildings (60 m2 or more, `SUB_BUILDING_M2`): substations,
  pump and compressor shelters, workshops, rows of cooling tower cells, and
  tanks of 9 m or more across (`TANK_BUILDING_M`, 30% of the tanks).
  They have a footprint, a roof, a ruin state and the district byte like any
  building. Nothing under 60 m2 is a building: the game treats a mecha
  beside a footprint as indoors.
- Medium, drawn only: tanks under 9 m (with their shadow), vessel
  batteries, air-cooler banks, laydown squares (fenced, with stacks), fenced
  pens, tanker loading racks beside the bunds of a plant, material heaps
  (cement works, and most factories with silos).
- Small: columns (2.6 to 4 m, drawn only), huts and clutter.
- **Huts** are props of kind `hut`: guard huts, portable cabins (in rows),
  sheds, analyser shelters. They have no body and break like market stalls
  (the generated scene has a second `StallField`, `HutField`, with
  `kind = "hut"` and `spills_goods = false`). The hut layer lists the intact
  sprites and then their `_broken` sprites. A hut where a building would be
  gutted or collapsed (`ruins.state_at`) is spawned with the `_broken`
  variant: it is a ruin from the start.
- **Clutter** is props of kind `clutter`: drums, pallets, cable reels,
  cylinder racks, cabinets, hydrants, sleepers, skids. Sprites only, no
  body, never broken. The generated scene draws them in the `Clutter` layer.
- The placeholder sprites are `hut_<name>.png`, `hut_<name>_broken.png` and
  `clutter_<name>.png` from `make_placeholders.py` (section 2).

**Three classes of pipe.**

1. Trussed racks, overhead only: the trunks, rungs and links of the plants
   (section 9.1a), a rack along the service roads of an estate
   (`road_racks`), a stub from it to a lot's trunk or hall, and a rack from
   a factory's hall to one of its new tanks. No obstacle.
   - **Truss variants** (`pipes.truss_variant`): the truss under the pipes,
     over them, or both (the pipes between two trusses), about a third
     each. A rack takes one for its whole length, chosen from where it
     starts. `stats.json` gives the count, length and two examples of each
     (`density.truss`).
   - **Off the roofs.** The `overheads` sublayer is drawn above the roofs,
     so no rack, with its supports, comes within 1.5 m (`ROOF_CLEAR_M`) of
     a building footprint. A stub or a lot rack only touches the wall of the
     building it ends at.
   - A road rack runs on one verge, 3.5 m from the middle of its road
     (`ROAD_RACK_SIDE_M`). Along each road it takes the side with the most
     length clear of buildings, and only the stretches of 30 m or more
     (`ROAD_RACK_MIN_M`) that are clear. A road that is built over has no
     rack. A rack that meets another ends in a tee; any other end is at a
     drawn valve station.
2. Ground racks and pipes, obstacles: the unit-level pipes of the plants,
   with their 26 m gaps.
3. Thin pipes (0.12 to 0.28 m, `THIN_W`), drawn in the `groundlines`
   sublayer, no obstacle: a firewater ring inside each lot's fence with a
   hydrant every 34 m, a tracing line beside each overhead rack, and a line
   from each new tank, vessel battery, cooler, shelter and unit to the
   nearest rack or hall. Each joins something at both ends.

**Vehicles.** Tankers (`vehicle_tanker`) stand in the bays of the loading
racks, beside the bunds and on the service roads. Dump trucks
(`vehicle_dump_truck`) stand at the heaps and silos, beside laydown squares
and on the service roads. Each one stands inside a lot, turned with the
lot's frame, or on a paved service road of an estate, turned along the
road; on ground of the industrial district; and in the play area
(`may_park`). On a road, a vehicle stands only along a stretch that has a
rack (so not on a road that is built over), on the other side of the road,
at least 1 m from every building (`ROAD_PARK_M`). Both are sprites of kind `truck` with spawn weight 0: traffic
and the loading docks never pick them. Each is a salvage source (`tanker`,
`dump_truck`). The chances at the top of `density.py` (`TANKER_AT_RACK`
...) set how many there are. `stats.json` lists them by where they stand
(`density.vehicles`) and one by one (`density.vehicle_list`, px).

**Access.** Nothing the pass adds is an obstacle. In a process plant the
player's check runs again with the new buildings, and the ones that would
cut ground off are taken out. The NPCs' check is not affected: buildings
only cost more on the route grid.

**Numbers.** `stats.json`, `density`: `lots` (by lot type: big, medium and
small things and the built cover), `per_lot` (each lot's type, centre and
counts), `pipe_m` (pipe length by class) and `made` (vehicles, huts, ruined
huts, clutter, sub-buildings, racks). `industrial.DENSITY = False` builds
the lots without the pass, to count what they have before it.

### 9.2 Market (market.py)

In each market street block, the houses along the streets stay as shop
terraces, each with a canvas awning over the pavement. The block's middle is
cleared:

- Lanes cut through the terrace from the streets, with stalls on both sides.
- A plaza: a ring of stalls round its inside edge (2.2 m in from the edge,
  facing in, about 3.1 m apart), no stall within 6 m of a lane mouth, and
  two double rows of stalls inside, back to back, with a walkway through the
  middle.
- A market hall (barrel roof with arcade columns) in the larger blocks.
- Cart parks (hand carts in a row), and a diesel generator or two.

Stalls are props of kind `stall` (variants: 0 lean-to, 1 canopy, 2 table
with crates, 3 hand cart). They are not buildings: no wall, no AP cost.
The game's `StallField` breaks a stall when a mecha walks through it or a
shot passes it, and draws `stall_<name>_broken.png`.

### 9.3 Farmland (farmland.py)

The farmland district is cut into fields by the brief's field splitting
(section 5.2 of the districts brief): first by canals, burns and tracks,
then recursively across each piece's long axis until it is near its size
goal (0.55 to 1.7 x `FIELD_TARGET_M2`, 5,000 m2) and blocky enough
(`ASPECT_MAX`), with no field under `MIN_FIELD_M2`. Two neighbour pairs
merge into L shapes.

Each field has furrows along its long axis (25% turned 90 degrees), broken
where drift covers them, and tramlines every 18 to 22 m. Fields are split
by earth bunds or ditches. Bare tree husks stand on 30% of the long field
edges, round the farmland and along canals. Large farmland areas get a
frozen canal with pump houses, and burns. Farmhouse compounds have a walled
yard, a house, a pitched-roof barn, a round dovecote, pens, a well and a
derelict tractor. A few fenced solar arrays stand in the fields.

### 9.4 Military (military.py)

Tanks, APCs and military trucks are rare, so the energetics they give make
the dangerous places worth a visit:

- military sites: the airfield's hangar area, and two fenced compounds on
  open ground, with rows of parked vehicles, sandbag rings and a relay mast;
- checkpoints at main-road junctions, roadblocks (a tank across the road
  with wrecks), and convoys stopped in a lane;
- relay masts on the highest bare ground.

Each site also has a row of tents along its far edge (props of kind `hut`,
breakable like stalls, ruined where a building there would be) and crates,
jerrycans, tyres, sandbag stacks and tarps along the fence (`camp`).

### 9.5 Small things in the other districts (district_life.py)

The big-medium-small rule of the industrial density brief, for the
residential, market and farmland districts. Their houses, halls and farm
buildings are the big and medium things; `district_life.py` adds the small
ones as props (no body, no obstacle, nothing under 60 m2 is a building),
grouped where people leave things:

- **Residential:** rubbish heaps, tyres, crates, gensets, washing lines,
  drums and tarps against house walls, off the road; sheds and lean-tos
  against the walls (huts); kiosks at street corners (huts); trees in
  courtyards. On the roofs, satellite dishes join the water tanks, stair
  heads and roof rooms (`style.item_dishes`).
- **Market:** crates, sacks and tarps round the stalls, more stalls where
  there is room beside one, kiosks at the corners, wall clutter.
- **Farmland:** field huts and haystacks at field edges, carts near the
  farm buildings, palm rows along the farm tracks, and low mud walls with
  gaps along a third of the plain field edges (`farmland.WALL_SHARE`).

Huts break like stalls; a hut where a building would be gutted or
collapsed is a ruin from the start. The chances per candidate spot are the
`*_CHANCE` constants at the top of `district_life.py`; `stats.json` counts
what was made (`district_life`, `military_camp`).

### 9.6 Landmarks (landmarks.py, lm_*.py, lmkit.py)

Named set pieces at real Helwan places, built from the OSM data at each
place. `landmarks.py` runs first of the site modules: each builder claims
its land (`Site.claim`), registers its name (`Site.add_landmark`, written
to `landmarks.json`), clears what the district modules put there (their
buildings, props and sources, and, through `lmkit.mask_drawers`, what their
drawers would draw there and the sources they would register while
drawing; their ground obstacles there go too) and builds only when its land
touches the window of a window run. A builder skips its landmark when the
land is not free (`Site.is_free` without the district check: outside the
play area, in a KeepOut area, within 20 m of a marker or on an earlier
claim).

The builders lay a landmark out from the whole map's layout
(`site.full_layout`: its roads, and the large roofs that stay on the land,
through `lmkit.roads_near`, `kept_roofs` and `standing`), never from the
window's cut of `site.roads` or `site.buildings`, and draw their random
numbers whether or not a building stands in the window, so a window run
anywhere over a landmark shows what the full run makes there.

| Name | Module | Where (OSM) | What is built |
|---|---|---|---|
| Japanese Garden | `lm_garden.py` | the block holding the "Japanese Garden Mosque", the two ponds and the footways south of Sherif Street | coped wall with roofed gates at the ends of the paved spine, frozen ponds, plank footbridges, gravel paths, the hill with a two-tier pavilion (its upper tier in the talls), a round pavilion, water pavilions on both ponds (East-Asian roofs), rows of seated Buddhas facing the spine, a large Buddha in the round plaza, stone lanterns, rocks, raked gravel beds, bare trees; the OSM gatehouse at the west gate with a hipped roof; the mosque keeps its footprint with a domed roof and a 30 m minaret (talls) standing inside it; a yard with a shed, a generator and a cable drum; a pump by the largest pond |
| Helwan Observatory | `lm_observatory.py` | the "Helwan Observatory Museum" and the two `man_made=observatory` outlines on Al Marsed Street | a walled compound with the OSM buildings (flat roofs with observation domes), the main telescope dome at the OSM dome, a second dome, two outbuildings, a met enclosure, a 48 m guyed mast (talls), drives; the museum in a walled forecourt; the far dome fenced |
| Helwan Hospital | `lm_hospital.py` | the cluster of OSM hospital wards (no campus name in OSM) | the real buildings in a campus wall with gates where roads and paths enter, paved courts, lawns, paths, benches, an ambulance bay with ambulances, wrecks at the main gate; ambulances on the drive of the six-storey hospital block on Ismail Kamel Street |
| Helwan University | `lm_university.py` | the faculties at the north edge of the play area, grown from the Faculty of Medicine | the faculty buildings (an OSM building the large roofs lost, the Faculty of Education, is put back from its outline), campus wall (open where the campus runs on north), a main gate of two pylons and a lintel (talls), a paved quad on the largest open ground with a dry fountain, benches, lamp posts and a ring of trees |
| Helwan Court | `lm_court.py` | the OSM courthouse on Sherif Street | colonnade, steps, paved forecourt to the street of its address, flagpoles (talls), iron railings on a low plinth, guard hut |
| Helwan Cement Works | `lm_cement.py` | the cement works `industrial.py` builds in `density.CEMENT_BOX_M` and the OSM "Helwan Cement Plant" | no land taken: the preheater towers (about 50 m), silos (28 m) and chimneys (65 m) stand in the talls, the lowest drawn first (the talls have no depth test); a gutted one stands at half height, a collapsed one not at all. The name covers the works' compound plots (laid out again from `full_layout` with `industrial.plots`) and the OSM plant, grown 12 m, closed and joined into one outline, not the housing round them |

The landmarks' own building kinds (`lm_pavilion`, `lm_kiosk`, `lm_mosque`,
`lm_dome`, `lm_flat_domes`) are drawn by the roof functions in `lmkit.py`
and the standard ruin drawing; their ruin states are pinned to intact or
damaged so the set pieces stay readable. Everything else in a landmark is
drawn ground (walls are drawn, not buildings: mechas cross them as they
cross every wall). `stats.json` (`districts.landmarks`) counts what each
landmark made.
### 9.7 Infrastructure (infra.py)

`infra.py` is the second site module (after `landmarks.py`). It claims all
the land it builds on (`Site.claim`, owners `infra:...`), so the later site
modules build round it. Its parts, in the order they claim land:

- **The metro** (`metro.py`): Cairo Metro line 1, the OSM "Helwan-ElMarg
  Railway" (OSM `railway=subway`, which `gen_city` does not draw). A walled
  double-track corridor runs from the north edge of the map to the Helwan
  terminus, along the middle of the two OSM direction lines; houses in it
  are removed or trimmed back to the walls. The terminus has an island and
  two side platforms with canopies (overheads), buffer stops, a concourse
  and a station hall; Ain Helwan station gets side platforms where OSM maps
  them. Overhead line portals and contact wires are in the talls sublayer.
  Three stopped trains (8, 6 and 6 cars) stand at the terminus and on the
  open line; half the cars are `railcar` salvage sources. Landmarks:
  "Helwan Metro Station", "Ain Helwan Metro Station".
- **The rail yard** (`railyard.py`), round the OSM sidings north of the
  town (`YARD_BOX`): a depot shed (building kind `rail_shed`, drawn by its
  own function: tracks and inspection pits inside, skylights over each
  track, doors where the tracks enter, a car inside, pinned damaged) over
  the dead ends of the fan of sidings; a sawtooth works hall along the OSM
  traverser and the traverser pit with its table; goods trains (boxcars,
  hoppers, flat wagons, some carrying containers) on the free stretches of
  the sidings (`RAKE_SHARE`, `RAKE_FILL`; a share are `freight_wagon` or
  `shipping_container` sources; what the district modules left on a
  wagon's place, such as a lorry the industrial module parked across the
  sidings at a loading dock, is removed), broken by crossings: bands
  `CROSSING_M` wide across the yard every `CROSSING_EVERY_M` where no
  wagon stands (plates drawn over the tracks), so mechas can cross the
  sidings without pushing 25-60 t wagons; buffer stops and signals; one or
  two container terminals in the largest free rectangles (rows of
  containers in pairs, 15 m lanes and cross lanes, stacks 1 to 3 high, a
  gantry crane, floodlight masts); the traction substation's yard.
  Landmark: "Helwan Rail Yard". The yard's places depend on what the
  district modules built round it, so a window preview matches the full
  run only when it takes in the industrial blocks east of the yard too
  (`--window 400,-2700,1500,-1400`).
- **Container stacks.** Stacks of 2 or 3 are drawn in the talls sublayer.
  The stacks that touch form a block (`railkit.split_blocks`), and each
  block is one ground obstacle and one gutted building of kind
  `container_stack` that draws nothing itself (`railkit.stack_runs`): the
  obstacle stops mechas, the building's walls stop shots and sight and
  cast light shadows, so a stack gives cover like a container vehicle or
  a wall. A block smaller than 60 m² (`STACK_RUN_MIN_M2`) would be too
  small to be a building, so its containers stay single `container`
  vehicles instead. `industrial_stacks` stacks the blocks of the two
  outermost rows on each side of the industrial container yards
  (`YARD_STACK_SHARE`); the rows further in stay containers a mecha can
  push. `lot_yards` adds a small container yard (rows in pairs, no crane)
  to each industrial factory or depot lot that still has a free rectangle
  (`LOT_YARD_MIN_M`, `LOT_CLEAR_M` from everything on the lot; the
  industrial module exposes its lots as `site.industrial_lots`). The
  density pass fills most lots, so only a few have room.
- **Pylon lines and substations** (`power.py`): `SUBSTATIONS` (anchors)
  and `LINES` (from a stretch of a map edge, or from another substation).
  A line follows the cheapest path on a 7.5 m grid of the whole map in
  which buildings (with `CLEAR_M` round them), landmark claims and the real
  places in `RESERVED` are closed, and roads, rail, water and the
  industrial and market districts cost more. Towers then go along it
  every 250-350 m where the straight span crosses no building and the foot
  is on free ground. A substation no line reaches (the rail yard's: the
  town closes it in, so no route keeps a line off the roofs) is fed by
  underground cable and built all the same. Towers are
  36 m lattice pylons with three cross-arms (talls), their base a ground
  obstacle; six conductors and an earth wire run between them. The land
  under the wires (`SPAN_CLAIM_M` either side) is claimed, so the later
  site modules build nothing under them. Substations:
  fenced gravel yard, entry gantries, busbar portals, breaker bays
  (`switchgear` sources), two or three transformers (sources, obstacles),
  a control building, a cable drum and a control cabinet.
- **Flyovers** (`flyover.py`): `FLYOVERS` names the road kind and the
  junction. The deck (`DECK_H_M` over the middle, ramps of `RAMP_M` running
  linearly to the ground) follows the road's middle (the median of a dual
  carriageway). In the talls sublayer: deck (`DECK_V`, darker than the
  road concrete under it), side faces, parapets with light tops, a dark
  expansion joint over each pillar, lane markings, lamp posts, pier caps
  and pillars. On the ground: a pillar obstacle every `PILLAR_STEP_M`
  (none on crossing roads or rail), the deck's shadow under it and its
  shade along both edges (`SHADE_M` wide at full height, narrowing down
  the ramps), which marks the deck as raised where it does not lean (near
  the screen centre). Like the OSM viaduct, the deck itself does not collide:
  on Helwan's roads it is about as wide as the road, so a solid ramp end
  would close the road; instead mechas keep the whole road all along it,
  and the low ramp end fades near the player like the rest of the deck.
  No vehicle stands under the ramp where it is lower than `LOW_UNDER_M`.
  Under the arterial flyover a market fills the road between the pillars
  ("the Flyover Market").

Stacked containers, pylons, portals, gantries and the flyover decks are in
the `talls` sublayer (section 1.1); parked cars and traffic keep off the
pillars, ramps, the market and the metro corridor (`props.ROAD_KEEP_OFF`).
`stats.json` `districts.infra` has the counts of each part (and the
substations' places and each line's tower points).
### 9.8 Civic places (civic.py)

`civic.py` runs third of the site modules. Its parts, in the order they
take land (`Site.claim`): `cemetery.py`, `worship.py` (OSM mosques),
`grounds.py` (the club, then schools and pitches), `worship.py` (the
rest); shared helpers are in `civickit.py`. Every place is chosen over the
whole map from `site.full_layout` and claimed there, and built only where
it touches the window, so a window preview shows what a full run makes.

**Cemeteries** (`cemetery.py`): the two OSM `landuse=cemetery` areas in the
play area, "the East Cemetery" (about 7 ha after the roads) and "the West
Cemetery" (trimmed to its largest pieces, about 10.5 ha), both registered
as landmarks (their outline is the kept land with the lanes between its
pieces closed). The OSM service lanes inside stay; each piece between them
is laid out on its own as a maze of walled family plots (hosh, 60 to
400 m2), with lanes 10 to 16 m wide:

- Straight streets across long pieces (75 to 120 m apart; the middle one in
  each cemetery's largest piece is an avenue, 16 to 20 m).
- Bands of plots along the piece's long axis, two rows back to back (9 to
  13.5 m deep each; one row at an edge where that fits better), the
  arrangement that puts the most ground under plots; lanes of 10.5 to
  14.5 m between them. In a largest piece three or more bands wide the
  middle lane is a second avenue, crossing the first.
- Cross lanes (10 to 13 m) cut each band into blocks 35 to 80 m long,
  placed afresh in every band, so they meet the lanes at T-junctions and
  offsets; 30% open one row only (dead-end niches). Half the blocks sit up
  to 2.5 m off their band's line, so the lanes jog (kept 10 to 16 m).
- Each row is split into plots 7.5 to 15.5 m wide (some 16 to 26 m, some
  through both rows), clipped to the piece; now and then a plot stands
  across a lane between two of its openings (a dead end on each side, each
  with a way out). Ground still a lane's width from every plot gets bands
  of its own.
- Land 7 m or more from every plot (where the OSM service lanes are too
  close together for walled plots and mecha-wide lanes, as in the East
  Cemetery's south) is open burial ground: rows of simple graves, drawn
  only.

Plots stand 2.5 m back from the roads, so a 3.5 m service lane is a street
about 10 m wide. A 10 m mecha can reach every lane from outside the
cemetery without crossing a plot wall.

- A plot is a building of kind `hosh` pinned to the gutted state: its
  outline is a wall (sight, shots by AP, edge slow) but a mecha in it is
  not "inside" (no camera zoom). It draws itself as an open-topped walled
  enclosure: ground (some paved), cenotaphs, a small domed tomb room in
  about half, the walls with a gate towards a lane.
- Where the damage map says gutted, half the plots are damaged, plus 10%
  anywhere: their game wall stays whole, as a gutted building's does, and
  their breaches are drawn as the wall fallen into a heap of rubble along
  its line, so the outline still reads closed. Where it says collapsed,
  45% of the plots are collapsed (wall stubs, rubble, no game wall), plus
  4% anywhere; 35% of the collapsed ones are a `rubble` salvage source.
- Large domed mausoleums (`mausoleum`, about 0.5 per hectare) stand at
  block ends (the avenues' first) as ordinary roofed buildings.
- The perimeter wall is drawn only (as the farm yards' and military
  compounds' walls are): where a piece faces the outside of the cemetery,
  with a gate wherever a lane meets it. Bare trees stand in the lanes (one
  per 700 m2) and in some plots. The cemetery land is in `solid_extra`, so
  the generic props keep out of it, and the OSM lanes inside its outline
  are in `props.ROAD_KEEP_OFF`, so no parked cars, traffic or junction
  wrecks stand on them (the road props' kerb debris does).

**Mosques** (`worship.py`). Every mosque has a minaret in the talls
sublayer (`civickit.minaret`: Mamluk-like octagonal tiers with balconies
and a bulb, a slim Ottoman pencil with a cone cap, or a modern square
shaft with a balcony box; 25 to 40 m) at the footprint's corner nearest
the road, and a dome on its roof (plain, ribbed or a main dome with two
small ones), behind a crenellated parapet (kind `mosque`). The main dome
sits at the roof's middle where it fits clear of the minaret, else at the
nearest point where it does, else as large as fits at the point deepest
inside the roof (`worship.dome_spot`). A mosque keeps
the damage map's ruin state but no worse than damaged; where the map says
gutted or worse, half of them are gutted with only a stump of the minaret.

- The OSM mosques in the play area, except the Japanese Garden Mosque
  (built by `landmarks.py`); where the ground beside one is free (also of
  what the district modules built), a walled courtyard with an octagonal
  ablution fountain.
- Neighbourhood mosques: one per cell of a 6 x 6 grid over the play area,
  converting the best street-corner or street-facing building of 200 to
  1,500 m2 (at least 10 m wide, not a sliver) in a residential or market
  area, at least 250 m from any other mosque, large ones included (34 on
  this map). A building that fails `Site.is_free` (KeepOut, markers) is
  passed over. Where a
  district module has taken the chosen building, the best other building
  within 150 m that keeps the spacing is used (`neighbourhood_moved_to` in
  the stats).
- Large mosques (2 or 3) on main roads, 700 m or more from the OSM mosques
  and from each other (the neighbourhood mosques, chosen after them, keep
  250 m):
  a rebuilt compound with the prayer hall on the side towards the qibla
  (south-east), a courtyard with a domed fountain, arcades (`riwaq`, flat
  with crenellations or a dome per bay) round it, and two minarets on the
  front.

**Coptic church compounds** (3): a walled yard with a gate, the church
(`church`) along the compound's axis nearest east-west with a row of small
domes over the sanctuary at its east end, a larger dome over the nave and
twin bell towers at its west front (talls, 20 to 25 m), a paved forecourt
before the west door with a path from the gate, a service building and
trees round the inside of the wall.

**Schools and sports grounds** (`grounds.py`):

- The Helwan General Club, at the OSM sports centre (a landmark): the large
  OSM roof there is replaced by a 400 m running track round a football
  pitch, a main stand with a canopy and a small one (`stand`), four
  floodlight masts (talls, 21 to 25 m), tennis courts, a drained pool (a
  `pool` obstacle), a volleyball court, the clubhouse with an electrical
  cabinet against its front (a `control_cabinet` source); trees round the
  inside of the wall, clear of the buildings, courts and gates. It is not
  built where a district module has built on its ground (`club_district`
  in the stats).
- Schools (10): an L- or U-shaped building (`school`) round a yard with a
  football pitch and a basketball court where they fit, a flagpole (talls)
  by the gate, trees along the front wall (clear of the gate).
- Municipal pitches (5): a walled football ground with a small stand, a
  changing room and four floodlight masts (17 to 20 m).

Compound sites (schools, pitches, churches, large mosques) are rectangles
slid along residential (and, for mosques, market) street blocks with a road
in front, preferring open ground, a main road and a block corner, one per
cell of a coarse grid and 250 m or more apart (`civickit.compound_sites`,
`grid_pick`). Their walls are drawn only; the buildings in them are
ordinary buildings with walls and ruin states. Pitches and courts are
marked in `groundlines`, drawn in one chunk per compound (a large ground
fill drawn in a later chunk would otherwise cover markings in the chunk
next to it).

`stats.json` under `districts.civic`: per cemetery the plots, collapsed and
damaged plots, tomb rooms, mausoleums, trees and grave fields (m2) in the
run; OSM mosques and courtyards; schools, pitches and the club; large
mosques, churches and neighbourhood mosques, with the map positions
(`*_at`, metres) of every chosen compound and mosque.

On the full run of 24 November the civic places drew about 170,000
triangles (8,000 of them talls) in all: 254 plots in the East Cemetery and
333 in the West, about 57,000 triangles in a 580 x 460 m window over the
East Cemetery.
### 9.9 Urban fabric (fabric.py, estates.py, construction.py)

`fabric.py` is the fourth site module (after landmarks, infra and civic).
It builds on land that is still free (`Site.is_free`), claims what it
builds, and also keeps off the blocks that the district modules rebuild,
the OSM cemeteries and parks, and the real places of the other site modules
(`construction.reserved_area`).

**Public housing estates (`estates.py`).** Rows of identical slab blocks
(four to six storeys, 10 to 13 m deep, 28 to 66 m long) with 20 to 28 m of
open ground between the rows. The estates are at the places where the
satellite image shows such rows (`estates.PLACES`), and in large regular
residential blocks of generated lots while there are fewer than
`MIN_ESTATES`. Each estate has one design: all its blocks have the same
plan (a plain slab, an L or a U with the wings at the back), the same stair
cores and the same roof (a stair head over each core with water tanks
beside it); dish rows, shacks and pigeon towers vary from block to block.
A street block piece that would hold fewer than two blocks keeps its
lots. An estate takes only the land its rows use (`estates.estate_land`):
within half a row gap of its blocks, its lanes, and the generated lots that
reach into these, which are removed; lots beyond it stay. In the middle of
the open ground between two rows (past the wing tips of an L or U) there
is an access lane in every other gap, with cars parked along it (the
design's `lane_cars`, at most `MAX_CARS` per estate), or a footpath; both
run on to the street when it is within `LANE_REACH_M`. There are entrance
paths to the stair cores, worn ground, bare trees, washing lines and
rubbish, and one to three kiosks (`KIOSKS`, hut props) at the lane mouths
by the street, or else along the estate's edge by a street. The blocks are
buildings of kind `estate` with the usual ruin states; their interiors
show the flats either side of the stairwells.

**Building sites (`construction.py`).** A large site beside the OSM road
under construction (as near its concrete as there is room, over generated
lots if need be), `LARGE_SITES` more on open ground beside streets in the
city, and `INFILL_SITES` small ones in dense residential blocks, where the
two to five lots of the plot are taken out. The road under construction
itself is graded gravel with tyre tracks, barrier blocks across both ends
and a few gravel heaps. Sites keep `ROAD_SETBACK_M` off all other road
concrete, and the generic props keep off them. A site's half-built concrete
frame is a building of kind `frame` pinned to the collapsed state: the game
gives it no walls, no slow, no occluder and no route cost, so mechas walk
in and see and shoot through it. Its upper floors (3.2 m apart, 2 to 6 of
them) are in the talls sublayer: columns as posts, the poured bays as
translucent slabs (`SLAB_A`, less on tall frames: where the floors stack
straight below the camera they cover at most `SLAB_COVER` together, so a
mecha under them still shows), the beams, rebar on the top columns; the top
floor is only partly poured. The stair and lift core is a solid prism and a
ground obstacle. Large sites also have a tower crane (talls: a 35 to 50 m
lattice mast, a 40 to 60 m jib, the counter-jib and counterweight, the cab,
the hook with a load; its 6 m base pad is a ground obstacle with a
`control_cabinet` source behind it), sometimes a mobile crane (its chassis
an obstacle), a fence and gate, portacabins and a guard hut (huts), and a
yard: rebar stacks (a `building_materials` source), sand and gravel heaps,
formwork, pallets and sacks, a `cable_drum` source and a genset (a clutter
prop with no source: the sites give no fuel). The biggest large site is a
landmark ("the Big Crane", or "the Crane" when its crane is under
`BIG_CRANE_M`, 44 m). No dump trucks or tankers.

Every run, a window run too, lays out the estates and sites of the whole
map, claims their land and registers the landmark; only the ones that
touch the window are built. Outside the window an estate's land is worked
out with the whole map's lots and large roofs (`Site.full_layout`) in place
of the buildings, so the claims match the full run's but for what the
district modules built there.

**Rooftop variety (the Cairo roof kit, `style.py`).** Flat house roofs in
the residential and market districts (`buildings.CAIRO_DISTRICTS`) take
their items from `style.CAIRO_ITEMS`: the house items plus pigeon towers
(the lattice and cage stand 4.5 to 8 m up in the talls sublayer), water
tank stands and clusters, rooftop shacks with tin roofs and dish rows.
`UNFINISHED_SHARE` of these roofs (of at least `UNFINISHED_MIN_M2`) are an
unfinished top floor: a bare slab with no parapet, concrete columns with
rebar on a grid along the edge and across it, half-built brick walls, bricks
and sand, and a stair head. These items, the dishes and the tanks are
drawn with `style.Batch` (quads and fans of few sides, no shapely work),
which keeps them cheap in triangles. Gutted roofs have no items; on damaged
roofs the items keep clear of the holes.

`stats.json` (`districts.fabric`) lists the estates and sites claimed
(`names`, the whole map's in every run) and counts what was built, and
`triangles`: the triangles drawn by each part of the
kit, the estates and the sites (`style.KIT_TRIS`), with `estates_all` and
`sites_all` the totals of everything the estates and sites draw, in every
sublayer (`style.counted`).
### 9.10 Service sites (sites.py, sitekit.py, sitelots.py)

`sites.py` runs last of the site modules, on the land the others left. It
builds gas stations, garages, dealerships, truck repair yards, car parks,
bus depots and parking in front of large buildings. The site types are
rows of a table (`SITE_TYPES`, class `SiteType`): each names its lot finder
(the candidate places), how many and how far apart, how a candidate is
scored, its planner (the lot shaper and the pieces with their placement
rules) and its builder; the garages and the parking beside and in front of
buildings have choosers of their own. The types choose in the table's order
over the whole map from the city layout (also in a window run), each
keeping off the places the ones before chose, with random numbers seeded
by the position. At build time a place whose land another module took is
built on the free part only: a gas station is laid out again on its corner
lot less the land taken (and less the other site types' places beside it),
the others are cut back to what is free; a place is skipped when its
pieces no longer fit (it is not replaced, so 23 stations are chosen to
leave 20 or so). Each site claims what it builds on (`Site.claim`), and the
lot keeps the generic props (bushes, trees, kiosks) out (`solid_extra`). Lots leave the large
roofs and 2 m round them out (`Ctx.cut_big`). No place is chosen within
reach of a marker (start positions, exits, spawn zones) or in a KeepOut
area (`Ctx.blocked`): these are known in a window run too, so the next
candidate is chosen instead, the same way in both.

**Site templates** (`sitekit.py`). A site type is a lot finder, a lot
shaper and pieces:

- Lot finders: street corners (a convex block corner where a main road
  meets another road, `street_corners`) and frontages (points along the
  block edges that face a road, `frontages`). A street drawn under a rail
  line does not count.
- Lot shaper: the block near the corner (a parallelogram spanned by the two
  road edges) or along the frontage, kept 1 m off the road concrete. So the
  lot's outline follows the street layout. The generated houses it cuts are
  trimmed, or dropped when too little is left (less than half of the house,
  or under 60 m2 from a house that was larger; `trimmed_house`), and the lot
  grows over the ground they leave (`take_land`).
- Pieces: fixed shapes placed by rules in the lot's frame (x along the
  road, y into the block).
- Ground (`shape_ground`): the driveways are cut where the lot meets the
  roads; the lanes from the driveways round the pieces are joined and
  closed with a radius (`FILLET_M`) and become the apron (concrete like the
  roads, an edge line, slab joints). What is left of the lot becomes
  islands and verges (dark rough ground with a light kerb line): the verges
  along the roads, wide leftovers, and the street corner; thin strips along
  the back are paved.
- Vehicles (`Parker`): cars in bays, at pumps and in queues, kept clear of
  every vehicle the sites put down (`Placed`, on the Site), of buildings,
  of obstacles and of the islands. On the road, the other props are checked
  too (`Props.clear_of`). The generic road vehicles placed later
  (`props.build`) test their room with circles a little shorter than a car,
  so the sites' road vehicles (queues, cars at a garage's kerb) are marked
  in the props' room grid with a circle round their whole outline
  (`guard_vehicles`). The sites' clutter keeps off their vehicles, and a
  `car_parts` source goes down before its site's vehicles.

**Gas stations** (`STATIONS`, 23; at street corners on trunk, secondary
and tertiary roads, `STATION_SPACING_M` apart). The kiosk (one of four
outlines, building kind `fuel_kiosk`, a light fascia band along its front)
faces the main road, behind the canopy across a lane or beside it, never
within `CORNER_CLEAR_M` of the corner. The canopy (`CANOPIES`: one row of
two or three islands along the road, or two or three rows) covers the pump
islands (`overheads`: above mechas, fades near the player); a station takes
the first canopy size in a drawn order that fits its lot. Its deck is
see-through (`sitekit.CANOPY_A`), so the pump islands, pumps and cars
under it show and it does not pass for a roof (it stops neither shots nor
sight), with a thin bright fascia along its edge and light fittings over
the lanes. The pump islands
are ground obstacles (kind pipe) with `LANE_M` (13 m) lanes between the
rows; the canopy's pillars stand on them. NPC route planning (12.5 m cells,
obstacles grown by 2 m) counts the whole pump area as blocked, so NPCs
route round a canopy like round a small building; their steering near it
uses the lanes. Two fuel pumps (clutter
`fuel_pump`) per island. An entry and an exit on the main road (arrows,
stop line), one more on the side road; the street corner is an island with
the price sign pylon (`talls`, 8 to 12 m, so it leans), at the point of the
island nearest the corner. Tank fill covers on
the apron, an air and water post, tyres and drums by the kiosk, dry bushes
on the larger islands. `WASH_SHARE` of the stations want a drive-through
car wash (building kind `car_wash`, its long side along a lane, its ends
drawn open: the game still gives it four walls, like any building) and try
`WASH_TRIES` more layouts for room for one; about a third of the stations
get one. Cars at the pumps and in front of the kiosk, a few wrecks; on
`QUEUE_SHARE` of them an abandoned queue (`QUEUE_CARS`) nosed into the entry
and running back along the kerb lane of the main road (traffic drives on
the right). The pumps give nothing and do not explode: no fuel sources.

**Other sites** (`sitelots.py`):

| Site | How many | What |
|---|---|---|
| Backstreet garage | `GARAGES` 30 | A house on a residential or market street becomes a one-bay workshop (kind `garage`: sheet roof with a light sign board along the street side; the open bay, `GARAGE_BAY_W_M` 5 to 7 m wide, shows as a dark floor with an inspection pit between light jambs); on `GARAGE_YARD_SHARE` the next house is cleared into a walled yard of wrecks and parts. A car or wreck nosed into the bay (`garage_bay_cars`; shorter cars are tried in a narrow lane, and where none fits a car stands at the kerb in front of the bay), a tyre stack, drums and tyres along the wall on both sides of the mouth, one or two cars or wrecks at the kerb beside it, an oil stain, an engine, a `car_parts` source by the bay |
| Dealership | `DEALERSHIPS` 4, main roads | A showroom (kind `showroom`: deep glass front with mullions) at the back, two rows of new cars facing the road and the showroom, a pole sign (talls) |
| Truck repair yard | `TRUCK_YARDS` 6, industrial ground the industrial module left | A workshop hall (kind `workshop_hall`, bay doors), trucks nosed to the doors and parked round the yard (tankers and dump trucks only on industrial ground; they are in for repair, drained and stripped, so they carry no salvage source: `STRIPPED`), a fence, a `car_parts` source |
| Car park | `CAR_PARKS` 20, residential and market streets | Rows of bays and aisles (the lot shrinks to them, so the houses behind stay), `CAR_PARK_FULL` full, wrecks, kerbed islands, a guard hut on the island by the driveway |
| Bus depot | `BUS_DEPOTS` 5, main roads | A workshop hall, a row of buses under a see-through canopy (as the stations') at the back, a middle row in the open (buses where the lot is deep enough, else minibuses) with a 14 m aisle behind it (`DEPOT_AISLE_M`; the buses hold a mecha back) and a narrower one in front (its other side is the minibuses, which a mecha pushes aside), a row of minibuses along the front, a 14 m gate lane (`DEPOT_GATE_M`) kept open from the road to the back aisle, buses left askew off those lanes, a wall, a `car_parts` source |
| Parking out front | `FRONT_SHARE` of the free strips | Where the front of a large roof, or of a generated building of at least `FRONT_LOT_MIN_M2`, is 6 to 26 m from the road and the strip has no houses: bays straight in, angled where it is shallow, two rows and an aisle where it is deep; built only while the building stands, on the part of the strip that is free |
| Side car park | `SIDE_PARKS` 40 at most | On open ground beside a large roof (or a generated building of at least `SIDE_LOT_MIN_M2`) that reaches a road: an aisle along the wall and one or two rows of bays; the ground they leave (the plots of houses it grew over) becomes kerbed islands |

New clutter sprites (grey placeholders, `make_placeholders.py`
`SITES_CLUTTER`): `fuel_pump`, `air_post`, `tyre_stack`, `engine`. New
salvage source kind `car_parts` (car battery, alloy wheels, catalytic
converter, wiring harness, scrap, sometimes an electric motor; table in
`tools/salvage_loot/make_source_loot.py`).

The sites' buildings (kiosk, car wash, garage, showroom, halls) take their
ruin state from the damage map like the others, but never worse than gutted
(`sitekit.pin_state`): a collapsed one is drawn as a rubble heap and the
site would no longer read.

`stats.json` `districts.sites` counts what was chosen and built (the
stations' canopy sizes as `canopies_<rows>x<per row>`), the vehicles still
on the map by kind (`vehicles`, `vehicles_total`; `vehicles_cleared_later`
those a later place's land took), the houses removed, the places skipped
because another module took their land (`stations_replanned` the stations
laid out again), and the triangles
the sites' ground, canopies and signs add (`triangles`; their buildings are
counted with the others). `chosen` lists every place chosen over the whole
map (kind and centre in metres), also in a window run, so a window can be
aimed at one; `places` lists the ones built.

## 10. Salvage sources

The generator writes every salvage source to
`assets/maps/helwan/salvage.res` (`SalvageSpawnSet`): kind, position,
outline box, the building whose roof holds it, an amount, and whether it
is a vehicle. Every source is something the player can see, and it shows
what it gives. No source is placed in the border band or in a KeepOut area
(`salvage.py`).

| Kind | Where | Visual |
|---|---|---|
| `bus` | Main roads | `bus` vehicle prop |
| `tank` | Military sites, checkpoints, roadblocks | `military` vehicle prop |
| `military_vehicle` | Military sites, checkpoints, convoys | `military` vehicle prop (APC, truck) |
| `container_truck` | Main roads, loading docks | `truck` vehicle prop |
| `shipping_container` | Container yards (half of the containers) | `container` vehicle prop |
| `tanker` | Loading racks of the plants, beside factory tanks, estate service roads | `truck` vehicle prop |
| `dump_truck` | Heaps and silos, laydown squares, estate service roads | `truck` vehicle prop |
| `solar_panels` | Roofs and ground arrays (section 10.1) | roof or ground mesh |
| `roof_ac` | Flat roofs with AC boxes (a share per district, `AC_SOURCE_SHARE`) | roof mesh |
| `diesel_generator` | Flat roofs, markets, yards, farmhouses | roof or ground mesh |
| `transformer` | Industrial yards and substations | ground mesh |
| `electric_motor`, `industrial_pump`, `control_cabinet`, `valve_assembly` | Skids, pump houses, pools, canals, racks, control buildings, yards | ground mesh |
| `oil_drums`, `cable_drum` | Industrial yards, farms | ground mesh |
| `tractor` | Farmyards, fields | ground mesh |
| `relay_mast` | Military sites, high bare ground | ground mesh |
| `rubble` | One search point in 30% of the collapsed buildings and 35% of the collapsed cemetery plots | the rubble |
| `telescope` | Each observatory dome (inside the dome) | the dome roof |
| `lab_equipment` | By an observatory outbuilding and two university faculties | cases on a pallet |
| `medical_store` | By the hospital's outpatient clinics and its largest ward | cases marked with a cross |
| `railcar` | Stopped metro trains (half the cars), a car in the depot shed | `railcar` vehicle prop (metro car) |
| `freight_wagon` | Goods trains on the yard's sidings (a share of the boxcars and hoppers) | `railcar` vehicle prop |
| `switchgear` | Breaker bays of the substations | ground mesh |
| `building_materials` | The rebar stacks of a large building site | ground mesh |
| `car_parts` | Garages, truck repair yards, bus depot workshops (section 9.10) | an engine block and tyre stacks |

Ruin states change rooftop sources: a damaged roof keeps them, a gutted or
collapsed one has none.

The equipment shapes are in `equipment.py`. The roof kit (`style.py`)
places the AC boxes; `buildings.py` decides which roofs have solar
installations and generators and registers their sources with the roof's
building id.

### 10.1 Solar installations (solar.py)

| Type | Where |
|---|---|
| Tilted rack rows | Large flat roofs |
| Raised canopy | Large flat roofs; drawn over the roof items |
| Low ballasted rows | Long flat roofs and industrial roofs, with a guard rail |
| Small house set (2 to 6 modules) | Flat house roofs |
| Flush on a tile roof | Pitched roofs |
| Ground array | Farmland fields, fenced |

Module styles (mono 60-cell, mono 72-cell, half-cut, poly, black frame)
vary per installation. About 4% of modules are missing (only the rails
show), 4% are cracked, a few have glare. The source's amount is the number
of intact modules. The roof kit does not put tanks, dishes or AC boxes
under a rack or a set. The chance of each type per district is in
`buildings.py` (`SOLAR_*`).

## 11. Tests

These suites test sections 4, 5 and 6:

- `MapWallsTest`: walls, AP, fuses, sight and foliage.
- `MapVehiclesTest`: pushing, heavy vehicles, settling, chain pushes,
  walls, shot chance, sight, vehicle streaming and `kept_share` thinning
  (never set pieces).
- `MapStreamingTest`: chunk hiding, streamed scenes, and the NPC thinking
  rule.
- `MapTallsTest`: the talls height channel, the lean rule, the Talls
  node's material, and the ghosts both the talls and the overheads fade
  over.
- `MapLandmarksTest`: named places, their look-ups and the HUD notice.
- `MapKindsTest`: new prop and salvage kinds work by name.

Probes (run only when named): `VehicleStreamProbe` (the cost of 15,700
parked vehicles, steering in a dense car park, the route grid) and
`TallsRenderProbe`, which needs a renderer:

```
godot --rendering-driver d3d12 --resolution 1920x1080 res://game/test/RunAllTests.tscn -- --suite=TallsRenderProbe --quit --bins=<dir of talls_*.bin> --out=<dir> [--centre=x,y]
```

`--bins` can be any work dir of a run (a window run's `talls_*.bin`
files); `--centre` (world px) puts the camera over one object, for example
a crane, instead of the middle of all the meshes.

Run them from the `project/` folder:

```
godot --headless res://game/test/RunAllTests.tscn -- --suite=MapWalls,MapVehicles,MapStreaming
```

## 12. Files

| File | Use |
|---|---|
| `run_all.py` | Runs the full generator (or a window of it). |
| `geo.py`, `frame.py` | Read the OSM data and convert it to map metres; the map frame and the border band. |
| `features.py`, `zones.py` | Read the reference image into the grid and sort the map into zones. |
| `fit_image.py` | Finds where a new reference image is on the OSM data. |
| `calibrate_image.py` | Calibrates a new reference image's brightness and texture. |
| `gen_city.py` | Makes water, roads, rail, street blocks and building lots. |
| `districts.py` | Tags the map with districts (section 7). |
| `site_ctx.py` | What the district modules share while they build. |
| `industrial.py`, `market.py`, `farmland.py`, `military.py` | District content (section 9). |
| `plant.py` | Process plants: the pipe network, the nodes, overhead racks, pipe bridges and the two passability checks (section 9.1a). |
| `pipes.py` | How pipes, racks and pipe bridges are shaped and drawn. |
| `district_life.py` | Small things for the residential, market and farmland districts (section 9.5). |
| `landmarks.py`, `lm_garden.py`, `lm_observatory.py`, `lm_hospital.py`, `lm_university.py`, `lm_court.py`, `lm_cement.py` | Named set pieces at real places (section 9.6). |
| `lmkit.py` | Drawing helpers for the landmarks: ponds, bridges, statues, lanterns, walls and gates, East-Asian roofs, domes, minaret, mast. |
| `civic.py`, `cemetery.py`, `worship.py`, `grounds.py`, `civickit.py` | Civic places: cemeteries, mosques, church compounds, schools and sports grounds (section 9.8). |
| `density.py` | The industrial density pass: medium and small things on every lot, huts, clutter, thin pipes, road racks, tankers and dump trucks (section 9.1b). |
| `infra.py`, `metro.py`, `railyard.py`, `power.py`, `flyover.py`, `railkit.py` | Infrastructure: the metro line and stations, the rail yard, container stacks, pylon lines and substations, flyovers, and their drawing helpers (section 9.7). |
| `fabric.py`, `estates.py`, `construction.py` | The urban fabric site module: public housing estates, building sites with frames and cranes (section 9.9). |
| `kit.py` | Helpers for the district modules: frames, free space, fences, paving. |
| `sites.py`, `sitekit.py`, `sitelots.py` | Service sites (section 9.10): the module and gas stations; the site templates (lot finders and shapers, apron and islands, bays, vehicles, the sites' building kinds); garages, dealerships, truck yards, car parks, bus depots and parking. |
| `buildings.py` | The building record, the building kinds, and drawing every building by kind and ruin state. |
| `ruins.py` | Ruin states (section 8). |
| `style.py` | The mesh layers, roofs and roof kit, pitched roofs and interiors; writes the mesh files. |
| `solar.py` | Solar installations (section 10.1). |
| `equipment.py` | Ground equipment that shows a salvage source. |
| `salvage.py`, `obstacles.py` | Collect and write the salvage sources and the obstacles. |
| `gen_ground.py` | Makes the ground mask and tone textures. |
| `props.py` | Makes the prop spawns. |
| `markers.py` | Picks the first positions of exits, starts, spawns and cysts. |
| `master_io.py` | Reads the KeepOut areas, the district zones and the marker positions from the master scene. |
| `gen_scene.py` | Writes the two scenes. |
| `prep_sprites.py` | Prepares the prop sprites and writes `sprite_catalogue.json`. |
| `make_placeholders.py` | Draws the placeholder sprites for the new vehicles, the stalls, the huts and the clutter. |
| `render_preview.py`, `review_boards.py` | Preview renders (section 2.3a). |
| `build_meshes.gd` | Converts the work files to Godot resources. |

Work files (in the work dir): `<sublayer>_<row>_<col>.bin` and
`manifest.json` (meshes), `footprints.bin` (outlines, ruin states,
districts), `districts.bin`, `obstacles.bin`, `props.json`, `salvage.json`,
`landmarks.json` (named places, section 6.5), `stats.json`,
`city_cache.pkl`.

## 13. Repository size

The files in `project/assets/maps/helwan/` are approximately 304 MB
(631 files). Each run changes all of them. We recommend that you store
them with Git LFS:

```
git lfs track "project/assets/maps/helwan/*.res"
```
