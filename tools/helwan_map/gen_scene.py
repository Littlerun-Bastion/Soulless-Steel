"""Writes the two Helwan map scenes.

helwan_generated.tscn  Everything the generator makes: ground, city meshes
                       (seven sublayers, overheads and talls among them), MapBounds,
                       BuildingField, ObstacleField, SalvageField, the prop
                       sprite layers with VehicleField and StallField, the
                       named places (Landmarks) and the OSM viaduct. Rewritten
                       on every run; never edit it by hand.
helwan_master.tscn     The map the game loads (Map.gd). It instances the
                       generated scene and holds everything hand-made: prop
                       zones and points, extra overheads, keep-out areas,
                       district zones, exits, start positions, spawn zones and
                       cyst sites. Written only when it does not exist yet, so
                       hand work in it is never overwritten.
"""

from frame import BORDER_M, MAP_PX as _MAP_PX, MOCK_N, PX_PER_M

MAP_PX = int(round(_MAP_PX))
HALF = MAP_PX // 2
BORDER_PX = int(round(BORDER_M * PX_PER_M))
PLAY_HALF = HALF - BORDER_PX
MESH_DIR = "res://assets/maps/helwan"
IMG_DIR = "res://assets/images/map/helwan"
PROPS_DIR = "res://assets/images/map/props"
GENERATED_PATH = "res://database/maps/helwan_generated.tscn"

SUBLAYER_NODES = {
    "ground": "Ground", "groundlines": "GroundLines", "halos": "Halos",
    "interiors": "Interiors", "roofs": "Roofs", "overheads": "Overheads",
    "talls": "Talls",
}
# Prop kinds on each sprite layer, in draw order (later kinds on top). Every
# kind is found by name: its sprites are sprite_catalogue.json[kind] (or
# SPRITE_KIND's kind), and VEHICLE_KINDS also get bodies in the VehicleField
# with each sprite's mass_kg and shot_block. A new kind needs only its name
# here (and its sprites in the catalogue).
VEHICLE_KINDS = ("vehicle_wreck", "vehicle", "truck", "bus", "military", "container", "railcar")
# Small things that never break (no body).
CLUTTER_KINDS = ("clutter",)
FOLIAGE_KINDS = ("bush", "tree")
# Kinds drawn with another kind's sprites.
SPRITE_KIND = {"vehicle_wreck": "vehicle"}

GENERATED_HEAD = f"""[gd_scene format=3]

[ext_resource type="Script" path="res://game/map/GroundLayer.gd" id="ground"]
[ext_resource type="Shader" path="res://assets/shaders/GroundSplatMacro.gdshader" id="splat"]
[ext_resource type="Texture2D" path="{IMG_DIR}/ground_mask.png" id="mask"]
[ext_resource type="Texture2D" path="{IMG_DIR}/macro_tone.png" id="macro"]
[ext_resource type="Texture2D" path="res://assets/images/map/ground/snow.png" id="snow"]
[ext_resource type="Texture2D" path="res://assets/images/map/ground/sand.png" id="sand"]
[ext_resource type="Texture2D" path="res://assets/images/map/ground/dirt.png" id="dirt"]
[ext_resource type="Texture2D" path="res://assets/images/map/ground/cracked.png" id="cracked"]
[ext_resource type="Shader" path="res://assets/shaders/CityGrain.gdshader" id="grain"]
[ext_resource type="Script" path="res://game/map/BuildingField.gd" id="field"]
[ext_resource type="Resource" path="{MESH_DIR}/footprints.res" id="footprints"]
[ext_resource type="Script" path="res://game/map/OverheadPath.gd" id="overhead"]
[ext_resource type="Script" path="res://game/map/props/PropSpriteLayer.gd" id="sprite_layer"]
[ext_resource type="Script" path="res://game/map/props/VehicleField.gd" id="vehicle_field"]
[ext_resource type="Script" path="res://game/map/MapStreamer.gd" id="map_streamer"]
[ext_resource type="Script" path="res://game/map/ChunkMesh.gd" id="chunk_mesh"]
[ext_resource type="Script" path="res://game/map/MapBounds.gd" id="bounds"]
[ext_resource type="Script" path="res://game/map/ObstacleField.gd" id="obstacle_field"]
[ext_resource type="Script" path="res://game/map/salvage/SalvageField.gd" id="salvage_field"]
[ext_resource type="Script" path="res://game/map/props/StallField.gd" id="stall_field"]
[ext_resource type="Script" path="res://game/map/OverheadMeshFade.gd" id="overhead_fade"]
[ext_resource type="Shader" path="res://assets/shaders/OverheadGrain.gdshader" id="overhead_grain"]
[ext_resource type="Resource" path="{MESH_DIR}/districts.res" id="districts"]
[ext_resource type="Resource" path="{MESH_DIR}/obstacles.res" id="obstacles"]
[ext_resource type="Resource" path="{MESH_DIR}/salvage.res" id="salvage"]
[ext_resource type="Shader" path="res://assets/shaders/TallsLean.gdshader" id="talls_lean"]
[ext_resource type="Script" path="res://game/map/TallsLean.gd" id="talls_script"]
[ext_resource type="Script" path="res://game/map/Landmarks.gd" id="landmarks_script"]
"""

GENERATED_BODY = """
[sub_resource type="FastNoiseLite" id="Noise_tone"]
frequency = 0.012

[sub_resource type="NoiseTexture2D" id="NoiseTex_tone"]
width = 256
height = 256
seamless = true
noise = SubResource("Noise_tone")

[sub_resource type="ShaderMaterial" id="Mat_ground"]
shader = ExtResource("splat")
shader_parameter/ground_mask = ExtResource("mask")
shader_parameter/macro_tone = ExtResource("macro")
shader_parameter/tex_snow = ExtResource("snow")
shader_parameter/tex_sand = ExtResource("sand")
shader_parameter/tex_dirt = ExtResource("dirt")
shader_parameter/tex_cracked = ExtResource("cracked")
shader_parameter/tone_noise = SubResource("NoiseTex_tone")
shader_parameter/map_size = Vector2({S}, {S})
shader_parameter/tile_size = 4096.0
shader_parameter/macro_strength = 1.0
shader_parameter/tone_scale = 930.0
shader_parameter/tone_strength = 0.15

[sub_resource type="FastNoiseLite" id="Noise_grain"]
noise_type = 1
frequency = 0.04
fractal_octaves = 4

[sub_resource type="NoiseTexture2D" id="NoiseTex_grain"]
width = 512
height = 512
seamless = true
generate_mipmaps = true
noise = SubResource("Noise_grain")

[sub_resource type="ShaderMaterial" id="Mat_concrete"]
shader = ExtResource("grain")
shader_parameter/grain = SubResource("NoiseTex_grain")
shader_parameter/grain_scale = 900.0
shader_parameter/grain_strength = 0.2
shader_parameter/speckle_scale = 40.0
shader_parameter/speckle_strength = 0.45

[sub_resource type="ShaderMaterial" id="Mat_lines"]
shader = ExtResource("grain")
shader_parameter/grain = SubResource("NoiseTex_grain")
shader_parameter/grain_scale = 900.0
shader_parameter/grain_strength = 0.2
shader_parameter/speckle_strength = 0.0

[sub_resource type="ShaderMaterial" id="Mat_interiors"]
shader = ExtResource("grain")
shader_parameter/grain = SubResource("NoiseTex_grain")
shader_parameter/grain_scale = 500.0
shader_parameter/grain_strength = 0.35
shader_parameter/speckle_strength = 0.0

[sub_resource type="ShaderMaterial" id="Mat_roofs"]
shader = ExtResource("grain")
shader_parameter/grain = SubResource("NoiseTex_grain")
shader_parameter/grain_scale = 700.0
shader_parameter/grain_strength = 0.3
shader_parameter/speckle_strength = 0.0

[sub_resource type="ShaderMaterial" id="Mat_overheads"]
shader = ExtResource("overhead_grain")
shader_parameter/grain = SubResource("NoiseTex_grain")

[sub_resource type="ShaderMaterial" id="Mat_talls"]
shader = ExtResource("talls_lean")
shader_parameter/grain = SubResource("NoiseTex_grain")

; GENERATED by tools/helwan_map. Do not edit: the next run replaces this
; file. Hand-made content goes in helwan_master.tscn.
;
; {S} px square centred on the origin, in {C} x {C} chunks.
[node name="HelwanGenerated" type="Node2D"]

; The ground polygon runs from (0, 0) to map_size, so it sits at the map's
; top-left corner.
[node name="Ground" type="Polygon2D" parent="."]
material = SubResource("Mat_ground")
position = Vector2(-{H}, -{H})
polygon = PackedVector2Array(0, 0, {S}, 0, {S}, {S}, 0, {S})
script = ExtResource("ground")
map_size = Vector2({S}, {S})

; Seven sublayers, each one mesh per chunk; every chunk of a sublayer draws
; before the next sublayer, so neighbouring chunks never cover each other's
; detail. Roofs sit at z 1, above mechas, as Building.tscn's roofs do.
; Overheads (pipe bridges, strut frames, canopies) sit at z 3 and fade over
; the player and over the other mechas the player can see.
[node name="City" type="Node2D" parent="."]

[node name="Ground" type="Node2D" parent="City"]
material = SubResource("Mat_concrete")

[node name="GroundLines" type="Node2D" parent="City"]
material = SubResource("Mat_lines")

[node name="Halos" type="Node2D" parent="City"]

[node name="Interiors" type="Node2D" parent="City"]
material = SubResource("Mat_interiors")

[node name="Roofs" type="Node2D" parent="City"]
z_index = 1
material = SubResource("Mat_roofs")

[node name="Overheads" type="Node2D" parent="City"]
z_index = 3
material = SubResource("Mat_overheads")
script = ExtResource("overhead_fade")

; Tall things (crane masts and jibs, pylons, minarets, frame floors) sit at
; z 4. Every vertex carries its height; TallsLean leans it away from the
; screen's centre by that height and fades the talls over the player and
; over the other mechas the player can see.
[node name="Talls" type="Node2D" parent="City"]
z_index = 4
material = SubResource("Mat_talls")
script = ExtResource("talls_script")

; The map's edges: the camera never shows past map_rect, and the outer
; `border` px of it is a band no mecha, NPC or Entity can enter.
[node name="MapBounds" type="Node2D" parent="."]
script = ExtResource("bounds")
map_rect = Rect2(-{H}, -{H}, {S}, {S})
border = {B}.0
"""

GENERATED_TAIL = """
; The prop sprite layers draw the spawn points of the PropSpawner in
; helwan_master.tscn (three levels up once this scene is instanced there).
; Parked and abandoned vehicles, at ground level (below mechas and roofs).
; Wrecks use the car sprites, drawn darker.
[node name="Vehicles" type="Node2D" parent="."]
script = ExtResource("sprite_layer")
spawner_path = NodePath("../../../PropSpawner")
kinds = PackedStringArray({VEHICLE_KINDS})
{VEHICLE_PROPS}tones = {"vehicle_wreck": 0.55}
tone_jitter = 0.15

; Gives the vehicles bodies: mechas push them, and they stop shots by chance
; (see VehicleField and MapSenses). Mass and shot_block come per sprite from
; sprite_catalogue.json.
[node name="VehicleField" type="Node2D" parent="."]
script = ExtResource("vehicle_field")
spawner_path = NodePath("../../../PropSpawner")
layer_path = NodePath("../Vehicles")
kinds = PackedStringArray({VEHICLE_KINDS})
{VEHICLE_PHYSICS}
; Market stalls, at ground level. They have no bodies: StallField breaks a
; stall when a mecha walks through it or a shot passes it, and draws its
; broken sprite (stall_<name>_broken.png next to the intact one).
[node name="Stalls" type="Node2D" parent="."]
script = ExtResource("sprite_layer")
spawner_path = NodePath("../../../PropSpawner")
kinds = PackedStringArray("stall")
{STALL_PROPS}tone_jitter = 0.12

[node name="StallField" type="Node2D" parent="."]
script = ExtResource("stall_field")
spawner_path = NodePath("../../../PropSpawner")
layer_path = NodePath("../Stalls")

; Small yard items of the industrial lots (drums, pallets, cable reels ...),
; at ground level. Sprites only: they have no body and never break.
[node name="Clutter" type="Node2D" parent="."]
script = ExtResource("sprite_layer")
spawner_path = NodePath("../../../PropSpawner")
kinds = PackedStringArray({CLUTTER_KINDS})
{CLUTTER_PROPS}tone_jitter = 0.12

; Industrial huts and cabins. They break like market stalls (a second
; StallField, with no goods to spill). The layer's first variants are the
; intact huts, the rest their ruins: a hut spawned with a ruin's variant is
; a ruin from the start.
[node name="Huts" type="Node2D" parent="."]
script = ExtResource("sprite_layer")
spawner_path = NodePath("../../../PropSpawner")
kinds = PackedStringArray("hut")
{HUT_PROPS}tone_jitter = 0.1

[node name="HutField" type="Node2D" parent="."]
script = ExtResource("stall_field")
spawner_path = NodePath("../../../PropSpawner")
layer_path = NodePath("../Huts")
kind = "hut"
spills_goods = false

; Trees and bushes, above mechas. Each tree is 2-3 bare branch slices
; stacked. Plants near the player fade; they also hide what is under them
; from detection (see MapSenses).
[node name="Foliage" type="Node2D" parent="."]
z_index = 2
script = ExtResource("sprite_layer")
spawner_path = NodePath("../../../PropSpawner")
kinds = PackedStringArray({FOLIAGE_KINDS})
{FOLIAGE_PROPS}layers = {"tree": Vector2i(2, 3)}
tones = {"tree": 0.85, "bush": 0.6}
fade_near_player = true
conceals = true

; Pipe runs, pipe racks and pools: mechas move against them, shots and
; sight pass over. It builds before BuildingField, whose route grid reads it.
[node name="ObstacleField" type="Node2D" parent="."]
script = ExtResource("obstacle_field")
obstacles = ExtResource("obstacles")

; Makes the generated buildings enterable, gives them walls that stop shots
; and block sight, and fades the roofs round the player. Ruin states and
; districts come with the footprints and the district grid.
[node name="BuildingField" type="Node2D" parent="."]
script = ExtResource("field")
footprints = ExtResource("footprints")
districts = ExtResource("districts")
roof_material = SubResource("Mat_roofs")

; Salvage sources (buses, roof AC boxes, solar panels, pumps ...): searched
; by the player; vehicle sources follow their VehicleField vehicle, rooftop
; sources their building.
[node name="SalvageField" type="Node2D" parent="."]
script = ExtResource("salvage_field")
sources = ExtResource("salvage")
vehicle_field_path = NodePath("../VehicleField")
building_field_path = NodePath("../BuildingField")

; Hides map chunks away from the camera and streams StreamedScene nodes in
; the master scene round the mechas (see MapStreamer).
[node name="MapStreamer" type="Node" parent="."]
script = ExtResource("map_streamer")

; The map's named places (the Japanese Garden, the cemeteries ...): the
; HUD names a place as the player enters it, and quest hints can point at
; them (Landmarks.describe). It loads landmarks.res (build_meshes.gd)
; when it is ready, and has none until that file exists.
[node name="Landmarks" type="Node2D" parent="."]
script = ExtResource("landmarks_script")
landmarks_path = "{LANDMARKS_PATH}"

; Elevated structures from OpenStreetMap, above mechas, foliage and roofs.
[node name="Overheads" type="Node2D" parent="."]
z_index = 3
"""


def sprite_blocks(catalogue):
    """ext_resource lines for every prop sprite, and PropSpriteLayer
    textures/spans property lines for the foliage and the vehicle layers.
    catalogue is sprite_catalogue.json (see prep_sprites.py)."""
    res = []
    rid = {}
    for kind, entries in catalogue.items():
        for e in entries:
            rid[e["file"]] = "spr_" + e["file"][:-4]
            res.append(f'[ext_resource type="Texture2D" path="{PROPS_DIR}/{e["file"]}" id="{rid[e["file"]]}"]\n')

    def props_for(kinds):
        tex, span, height = [], [], []
        for kind in kinds:
            entries = catalogue.get(SPRITE_KIND.get(kind, kind), [])
            if not entries:
                continue
            tex.append(f'"{kind}": [{", ".join(f'ExtResource("{rid[e["file"]]}")' for e in entries)}]')
            span.append(f'"{kind}": PackedFloat32Array({", ".join(str(e["span"]) for e in entries)})')
            if any("height_m" in e for e in entries):
                height.append(f'"{kind}": PackedFloat32Array({", ".join(str(float(e.get("height_m", 0.0))) for e in entries)})')
        out = f"textures = {{{', '.join(tex)}}}\nspans = {{{', '.join(span)}}}\n"
        if height:
            out += f"shadow_heights = {{{', '.join(height)}}}\n"
        return out

    return ("".join(res), props_for(FOLIAGE_KINDS), props_for(VEHICLE_KINDS), props_for(["stall"]),
            props_for(CLUTTER_KINDS), props_for(["hut"]))


def vehicle_physics(catalogue, kinds=VEHICLE_KINDS):
    """VehicleField masses/shot_blocks property lines: per kind, one value per
    sprite variant, in the same order as the sprite layer's textures."""
    mass, block = [], []
    for kind in kinds:
        entries = catalogue.get(SPRITE_KIND.get(kind, kind), [])
        if not entries:
            continue
        mass.append(f'"{kind}": PackedFloat32Array({", ".join(str(float(e.get("mass_kg", 1500))) for e in entries)})')
        block.append(f'"{kind}": PackedFloat32Array({", ".join(str(float(e.get("shot_block", 0.5))) for e in entries)})')
    return f"masses = {{{', '.join(mass)}}}\nshot_blocks = {{{', '.join(block)}}}\n"


def write_generated(path, meshes, catalogue, overheads=()):
    """meshes: {name: [x, y, width, height]} with names like "roofs_2_3"
    (sublayer_row_col) and bounds in world px. Each becomes a ChunkMesh that
    a MapStreamer loads near the camera.
    overheads: point lists (world px) for OverheadPath nodes."""
    order = {k: i for i, k in enumerate(SUBLAYER_NODES)}
    names = sorted(meshes, key=lambda m: (order[m.rsplit("_", 2)[0]], m))
    spr_res, fol_props, veh_props, stall_props, clutter_props, hut_props = sprite_blocks(catalogue)
    chunks = len({m.rsplit("_", 2)[1] for m in meshes}) or 1
    out = [GENERATED_HEAD, spr_res]
    out.append(GENERATED_BODY.replace("{S}", str(MAP_PX)).replace("{H}", str(HALF))
               .replace("{B}", str(BORDER_PX)).replace("{C}", str(chunks)))
    for m in names:
        parent = SUBLAYER_NODES[m.rsplit("_", 2)[0]]
        x, y, w, h = meshes[m]
        out.append(
            f'\n[node name="{m}" type="MeshInstance2D" parent="City/{parent}"]\n'
            f'use_parent_material = true\n'
            f'script = ExtResource("chunk_mesh")\n'
            f'mesh_path = "{MESH_DIR}/{m}.res"\n'
            f'bounds = Rect2({x:.0f}, {y:.0f}, {w:.0f}, {h:.0f})\n'
        )
    quoted = lambda ks: ", ".join(f'"{k}"' for k in ks)
    out.append(GENERATED_TAIL.replace("{VEHICLE_PROPS}", veh_props).replace("{FOLIAGE_PROPS}", fol_props)
               .replace("{STALL_PROPS}", stall_props).replace("{VEHICLE_KINDS}", quoted(VEHICLE_KINDS))
               .replace("{CLUTTER_KINDS}", quoted(CLUTTER_KINDS)).replace("{FOLIAGE_KINDS}", quoted(FOLIAGE_KINDS))
               .replace("{CLUTTER_PROPS}", clutter_props).replace("{HUT_PROPS}", hut_props)
               .replace("{VEHICLE_PHYSICS}", vehicle_physics(catalogue))
               .replace("{LANDMARKS_PATH}", f"{MESH_DIR}/landmarks.res"))
    for i, pts in enumerate(overheads):
        flat = ", ".join(f"{x:.0f}, {y:.0f}" for x, y in pts)
        out.append(
            f'\n[node name="Viaduct{i + 1}" type="Line2D" parent="Overheads"]\n'
            f'points = PackedVector2Array({flat})\n'
            f'width = 200.0\n'
            f'script = ExtResource("overhead")\n'
        )
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("".join(out))


MASTER_HEAD = f"""[gd_scene format=3]

[ext_resource type="Script" uid="uid://cvuj4dem66ujh" path="res://database/maps/Map.gd" id="map"]
[ext_resource type="PackedScene" path="{GENERATED_PATH}" id="generated"]
[ext_resource type="PackedScene" path="res://game/arena/StartPoint.tscn" id="start"]
[ext_resource type="PackedScene" uid="uid://dwf22ocgt8ucl" path="res://game/arena/ExitPoint.tscn" id="exit"]
[ext_resource type="Script" path="res://game/map/EditorOnly.gd" id="editor_only"]
[ext_resource type="Texture2D" path="{IMG_DIR}/mockup_reference.png" id="mockup"]
[ext_resource type="Resource" path="{MESH_DIR}/props.res" id="props"]
[ext_resource type="Script" path="res://game/map/props/PropSpawner.gd" id="spawner"]
"""

MASTER_BODY = """
[sub_resource type="NavigationPolygon" id="NavPoly_Helwan"]
vertices = PackedVector2Array(-{P}, -{P}, {P}, -{P}, {P}, {P}, -{P}, {P})
polygons = Array[PackedInt32Array]([PackedInt32Array(0, 1, 2, 3)])
outlines = Array[PackedVector2Array]([PackedVector2Array(-{P}, -{P}, {P}, -{P}, {P}, {P}, -{P}, {P})])

; Helwan: the map the game loads. Hand-made content lives here; the
; generator never rewrites this file once it exists.
;   BG/Generated   the generated city (helwan_generated.tscn), regenerated
;                  by tools/helwan_map
;   KeepOut        Polygon2D children: the generator builds nothing and
;                  spawns no props inside them; rerun it after drawing one.
;   DistrictZones  Polygon2D children with a "district" metadata
;                  (residential, industrial, market or farmland): the
;                  district painted by hand wins over the generator's.
;   The outer border band of the map (MapBounds in the generated scene) is
;   closed to mechas; markers stay in the play area inside it.
;   PropSpawner    PropZone and PropSpawnPoint children add or clear props.
;   Overheads      add OverheadPath (Line2D) children for more overpasses.
;   Buildings      hand-made buildings (draw a KeepOut round each).
[node name="Helwan" type="Node2D"]
script = ExtResource("map")

[node name="BG" type="Node2D" parent="."]

[node name="Generated" parent="BG" instance=ExtResource("generated")]

; Where props go: the generator's spawn points, plus PropZone (CLEAR or
; SCATTER areas) and PropSpawnPoint (single props) children added by hand.
[node name="PropSpawner" type="Node2D" parent="." node_paths=PackedStringArray("building_field")]
script = ExtResource("spawner")
spawn_set = ExtResource("props")
building_field = NodePath("../BG/Generated/BuildingField")

; Hand-placed elevated structures (OverheadPath children), above foliage.
[node name="Overheads" type="Node2D" parent="."]
z_index = 3

[node name="SurfaceOverlays" type="Node2D" parent="."]

[node name="Decals" type="Node2D" parent="."]

; Map.gd expects these containers to exist, even when empty.
[node name="Bushes" type="Node2D" parent="."]

[node name="Props" type="Node2D" parent="."]

[node name="Walls" type="Node2D" parent="."]

[node name="Trees" type="Node2D" parent="."]

[node name="Buildings" type="Node2D" parent="."]

[node name="Texts" type="Node2D" parent="."]

[node name="Triggers" type="Node2D" parent="."]

; Extraction points, on roads near the four edges of the play area. Found
; at runtime via the "exit_point" group.
[node name="Exits" type="Node2D" parent="."]
{EXITS}
; The first start position is the player spawn; ExpeditionDirector uses the
; rest for NPCs. All on roads, spread over the map.
[node name="StartPositions" type="Node2D" parent="."]
{STARTS}
; Soft-spawn points for ExpeditionDirector (Map.get_spawn_zones).
[node name="SpawnZones" type="Node2D" parent="."]
{SPAWNS}
; Entity nests (Map.get_cyst_sites), on open ground away from the starts.
[node name="CystSites" type="Node2D" parent="."]
{CYSTS}
; One square over the play area (the map less its border band).
[node name="NavigationRegion2D" type="NavigationRegion2D" parent="."]
navigation_polygon = SubResource("NavPoly_Helwan")

; The generator reads the Polygon2D children of KeepOut (position, rotation,
; scale and polygon; KeepOut itself must stay at the origin). Editor only.
[node name="KeepOut" type="Node2D" parent="."]
script = ExtResource("editor_only")

; The generator reads the Polygon2D children of DistrictZones the same way,
; each with metadata/district = "industrial" (or residential, market,
; farmland). A painted polygon wins over the generator; a later one wins
; over an earlier one. DistrictZones itself must stay at the origin. Editor
; only.
[node name="DistrictZones" type="Node2D" parent="."]
script = ExtResource("editor_only")

; Editor-only guides, removed when the game runs. The mockup is hidden; show
; it to compare. Scale {MS} makes its {N} px cover the whole map.
[node name="Reference" type="Node2D" parent="."]
script = ExtResource("editor_only")

[node name="MockupUnderlay" type="Sprite2D" parent="Reference"]
visible = false
modulate = Color(1, 1, 1, 0.5)
scale = Vector2({MS}, {MS})
texture = ExtResource("mockup")
"""


def _markers(parent, names, points, kind):
    """names: a list of node names, or a prefix numbered from 1."""
    out = []
    for i, (x, y) in enumerate(points):
        name = names[i] if isinstance(names, list) else f"{names}{i + 1}"
        if kind == "marker":
            out.append(f'\n[node name="{name}" type="Marker2D" parent="{parent}"]\n')
        else:
            out.append(f'\n[node name="{name}" parent="{parent}" instance=ExtResource("{kind}")]\n')
        out.append(f"position = Vector2({x:.0f}, {y:.0f})\n")
    return "".join(out)


def write_master(path, exits, starts, spawns, cysts):
    """Points are world px. exits (north, east, south, west) and starts
    become ExitPoint and StartPoint instances; spawns and cysts become
    Marker2D nodes. Exits are named as in big_map.tscn (Exit_N and so on),
    which tests look up by name."""
    esc = lambda s: s.replace("{", "{{").replace("}", "}}")
    body = (MASTER_BODY
            .replace("{EXITS}", esc(_markers("Exits", ["Exit_N", "Exit_E", "Exit_S", "Exit_W"], exits, "exit")))
            .replace("{STARTS}", esc(_markers("StartPositions", "Pos", starts, "start")))
            .replace("{SPAWNS}", esc(_markers("SpawnZones", "Spawn", spawns, "marker")))
            .replace("{CYSTS}", esc(_markers("CystSites", "Cyst", cysts, "marker"))))
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(MASTER_HEAD + body.format(H=HALF, P=PLAY_HALF, N=MOCK_N, MS=round(MAP_PX / MOCK_N, 4)))
