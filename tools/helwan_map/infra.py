"""Infrastructure: the metro line and its stations, the rail yard and stopped
trains, container rows, electrical substations and pylon lines, and road
overpasses.

Runs after landmarks.py and before the other site modules; claims its land
with Site.claim. The parts, in the order they claim land:

  metro.py      Cairo Metro line 1 from the north edge to the Helwan
                terminus (OSM "Helwan-ElMarg Railway")
  railyard.py   the rail yard among the OSM sidings north of the town:
                works hall and traverser, depot shed, goods trains,
                container terminal
  power.py      high-voltage pylon lines from the map edges to substations
  flyover.py    elevated roads over the busiest junctions
  containers    stacks in the industrial container yards
                (railyard.industrial_stacks) and new rows of containers in
                free corners of the industrial lots (railyard.lot_yards)
"""
import flyover
import metro
import power
import railyard


def build(site):
    """Builds the infrastructure. Returns the module's stats."""
    stats = {}
    M = metro.build(site, stats)
    railyard.build(site, stats, M)
    power.build(site, stats)
    flyover.build(site, stats)
    railyard.industrial_stacks(site, stats)
    railyard.lot_yards(site, stats)
    return stats
