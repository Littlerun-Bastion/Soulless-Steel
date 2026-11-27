"""Civic places: cemeteries, mosques and church compounds, schools and
walled sports grounds.

Runs after infra.py; claims its land with Site.claim. The parts, in the
order they take land:

  cemetery.py  the two cemeteries at the OSM cemetery areas
  worship.py   minarets, domes and courtyards for the OSM mosques
  grounds.py   the Helwan General Club (OSM sports centre), then schools
               and municipal walled pitches
  worship.py   large courtyard mosques, Coptic church compounds and
               neighbourhood mosques in converted street-corner buildings

Every place is chosen over the whole map from site.full_layout and built
only where it touches site.window, so a window run shows what a full run
makes there.
"""
import cemetery
import civickit
import grounds
import worship


def build(site):
    """Builds the civic places. Returns the module's stats."""
    stats = {}
    compounds = []
    lay = civickit.Layout(site)
    stats["cemeteries"] = cemetery.build(site, lay)
    stats["mosques_osm"], mosques = worship.build_osm(site, lay)
    stats["grounds"] = grounds.build(site, lay, compounds)
    stats["worship"] = worship.build_rest(site, lay, mosques, compounds)
    return stats
