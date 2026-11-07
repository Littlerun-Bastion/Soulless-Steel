# The Memorial Wall's data

`memorialwall.org` is a NET site: a public registry of pilots who did not come back. The code is `game/net/memorial/MemorialWall.gd` (the records) and `game/ui/net/sites/memorial/` (the pages). This folder holds its texts. Every file is JSON with an `"_about"` key.

| File | What it holds |
|---|---|
| `regions.json` | `regions`: where background losses happen. Placeholders (`[REGION A]` ... `[REGION H]`). |
| `condolences.json` | The short messages other pilots leave, in five groups (below). `{name}` becomes the pilot's callsign. Placeholder lines. |
| `tributes.json` | Callsign -> the tribute shown on a named pilot's record. A named pilot with no entry gets Lorem Ipsum. |
| `site.json` | `moderator` (the name the moderator posts under), `welcome` (the front page), `about` (the About page). |

## How a record is made

- **A loss in an expedition.** When an NPC mecha is killed (not extracted) in an Expedition, `CombatScene` asks the Wall to record it (`records_losses` is on for the Expedition only; the Arena, the test arena and the Ladder record nothing). The record waits as pending, and goes onto the Wall at the start of the next day. `PilotNet.pilot_lost(record)` fires then.
- **Background losses.** Each new day adds 3-8 losses elsewhere, for the day before: a generated callsign, a region, mostly an unknown cause (some Entities), a build of listed parts. The same day always gives the same losses. A new profile starts with 14 days of them.
- **What a record keeps.** The callsign (or `Unidentified pilot` for an Anonymous pilot), the squad tag, the day, the site, the build, the cause, the pilot it was fighting (only if that pilot was on the Local roster, and `Unknown` if it was Anonymous: the player too), its last line on Local, its personality, candles and messages.
- **Callsigns.** A lost pilot's callsign is retired: the callsign generator never gives it again (an Anonymous pilot's real callsign too).
- **Messages.** Rolled once when the record is made, and saved: 0-6 for a generic pilot, 6-14 for a named pilot, one from each surviving squadmate, and one from the killer when it is an NPC Hunter or Rat. Each arrives on the record's day plus 0-3 days. The player can post one message (100 characters) per record.
- **Candles.** A record starts with 0-12 (more with a squad, more for a named pilot) and gains a few a day for a week. The player can light one per record.
- **The registry.** `Pilots registered` is 41,220 (`REGISTRY_BASE`, a placeholder for every loss since the Impact) plus the records put up. The Wall keeps at most 1,000 records: the oldest generic and background records go first; named records and the player's kills always stay.

## Message groups

| Group | Written by | When |
|---|---|---|
| `stranger` | anyone (a generated callsign) | any record |
| `squadmate` | a surviving member of the pilot's squad | the pilot had a squad |
| `entity_loss` | anyone | an Entity killed the pilot (half of its messages) |
| `rival` | the killer | the killer is an NPC Hunter or Rat. Short and cold, never cruel |
| `anonymous` | anyone | an Unidentified pilot |

Write them in netizen voice: lower case, abbreviations, typos. No lore: no factions, places or events. The Wall's body font has no curly quotes, dashes or `…`; the page swaps them for plain ones.

## Story flags

| Flag | Set when |
|---|---|
| `lost:<callsign>` | a named NPC is lost (for example `lost:Lady Volk`). |
| `memorial_candles_for_own_kills` | goes up by one each time the player lights a candle on a pilot the player killed. Nothing on the page shows it. |
| `memorial_hide_player` | set it to true to hide the player's notice. |

## The player's notice

When the player loses an expedition, the next day the side column shows `MISSING, PRESUMED LOST: <callsign> (<site>)`. When the player next deploys, it changes to `NOTICE WITHDRAWN: pilot reported alive` with a count (`Withdrawn 3 times`). The player is never a record. The page never explains this.

## Testing

`MemorialWallTest` checks these files (`MemorialWall.check_content()`), and that every named NPC in `database/npcs/special_npcs/` (but Test Dummy) has a tribute. Press **F9** in the game to read the files again.
