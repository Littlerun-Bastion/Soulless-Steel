"""Named set pieces at their real places in Helwan.

Runs first of the site modules (after the district modules): it claims the
land of each landmark (Site.claim) and registers it by name
(Site.add_landmark) so the game can name the place. Each landmark is built
by its own module from the OSM data at its real place:

  lm_garden.py       the Japanese Garden (ponds, bridges, hill pavilion,
                     rows of seated Buddhas, the garden mosque's minaret)
  lm_observatory.py  the Helwan Observatory (telescope domes, a guyed mast,
                     a walled compound by Al Marsed Street, the museum)
  lm_hospital.py     the hospital campus (the OSM wards inside a campus wall,
                     ambulances and wrecks at the gate)
  lm_university.py   the south edge of Helwan University (campus wall, main
                     gate, paved quad, the OSM faculty buildings)
  lm_court.py        Helwan Court on Sherif Street (colonnade, steps,
                     forecourt with flagpoles, railings)
  lm_cement.py       names the cement works (built by industrial.py) and
                     stands their preheater towers, silos and chimneys up
                     in the talls

The places are chosen over the whole map (site.full_layout and the OSM
features), so a window run (run_all.py --window) builds what the full run
builds there; each builder claims its land and registers its name in every
run, and builds only when its land touches the window. lmkit.py holds the
drawing helpers they share.

The building kinds of the landmarks are registered here (buildings.KINDS).
"""
import buildings as bl
import lm_cement
import lm_court
import lm_garden
import lm_hospital
import lm_observatory
import lm_university
import lmkit
import style

bl.KINDS.update({
    "lm_pavilion": (lmkit.roof_pavilion, False, style.HALO_HOUSE_M),
    "lm_kiosk": (lmkit.roof_kiosk, False, style.HALO_HOUSE_M),
    "lm_mosque": (lmkit.roof_mosque, True, style.HALO_BIG_M),
    "lm_dome": (lmkit.roof_dome, True, style.HALO_BIG_M),
    "lm_flat_domes": (lmkit.roof_flat_domes, True, style.HALO_BIG_M),
})

BUILDERS = (
    ("japanese_garden", lm_garden.build),
    ("observatory", lm_observatory.build),
    ("hospital", lm_hospital.build),
    ("university", lm_university.build),
    ("court", lm_court.build),
    ("cement_works", lm_cement.build),
)


def build(site):
    """Builds every landmark. Returns the module's stats: one entry per
    landmark, and the names registered.

    Each builder adds the land it builds on to `masks`; what the district
    modules' drawers would draw there (and the sources they would register
    while drawing) is then left out (lmkit.mask_drawers), and their ground
    obstacles there go."""
    out = {}
    first_own = len(site.drawers)
    masks = []
    for name, fn in BUILDERS:
        out[name] = fn(site, masks)
    if masks:
        area = lmkit.as_multi(masks)
        site.drawers[:first_own] = lmkit.mask_drawers(site, site.drawers[:first_own], area)
        out["district_obstacles_removed"] = lmkit.drop_obstacles(site, area)
    out["registered"] = [lm["name"] for lm in site.landmarks]
    return out
