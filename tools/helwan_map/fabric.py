"""Urban fabric: public housing estates (estates.py), building sites with
half-built concrete frames and tower cranes (construction.py), and the
rooftop variety of ordinary buildings (the Cairo roof kit in style.py:
CAIRO_ITEMS and unfinished top floors, used by buildings.roof_house).

Runs after civic.py; claims its land with Site.claim.
"""
import construction
import estates
import style


def build(site):
    """Builds the estates and building sites. Returns the module's stats;
    "triangles" and "drawn" (style.KIT_TRIS, KIT_COUNT) fill in while the
    meshes are drawn, after this returns: per roof kit item and estate or
    site part, and in all ("estates_all", "sites_all": every triangle the
    estates' and sites' drawers and buildings add, in every sublayer)."""
    made = {"triangles": style.KIT_TRIS, "drawn": style.KIT_COUNT}
    estates.build(site, made)
    construction.build(site, made)
    return made
