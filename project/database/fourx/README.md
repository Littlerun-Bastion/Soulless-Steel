# FourX.net: market guide

FourX.net is the regional exchange on the NET (`fourx.net`). It shows a price for every instrument, one price for each day. This guide tells you how the market works and how to change it.

The code is `game/net/fourx/FourX.gd` (the market) and `game/ui/net/sites/fourx/FourXPage.gd` (the pages). pilot.net's front page shows a FOURX MARKETS box. Each maker's Steelapedia article shows its stock symbol.

FourX only shows prices. The player cannot trade yet. Nothing in the game uses the prices yet. `FourX.price_factor(symbol)` is the hook for a system that must follow the market (for example, a sell price): it gives the last price divided by the base price.

## The instruments

The game makes most instruments from its data. You do not need to add them.

| Group | Instruments | Base price |
|---|---|---|
| `makers` | One stock for each maker in `Manufacturers` (not the test maker). | The mean price of the maker's parts on amazing.com, divided by 20, between 5 and 500. |
| `salvage` | One quote for each item with a price in `database/items/` (not `test/`). | The item's `price`. |
| `bio` | The same, for items with the tag `bio`. | The item's `price`. |
| `index` | `FXC` (FourX Composite): all makers. `SALV` (Salvage Index): all salvage and bio items. | 1000. The index is 1000 times the mean of (price / base price) of its members. |
| your group | The instruments in `market.json`. | The `base` you give. |

A new maker or a new item gets an instrument automatically. Its price history starts when the game first sees it.

## Symbols

The game makes a symbol of 3 or 4 letters from each name:

- One word: the first letter, then the consonants after it. "Martel" is `MRTL`.
- Two or more words: the first letter of each word, then the consonants of the last word. "Acid Gland" is `AGLN`.
- When a symbol is already used, its last letter becomes a digit (`MRT2`).

To set a symbol yourself, add it to `"symbols"` in `market.json`. The key is the maker id or the item id:

```json
"symbols": {"silver_star_europe": "SSEU", "acid_gland": "ACID"}
```

A symbol is 1 to 5 capital letters or digits. Do not change a symbol after release: saves keep the prices by symbol.

## How prices move

- The day is pilot.net's day. It goes up by one each time an expedition ends.
- Each day, each price takes one step. The step has three parts:
  - **drift**: a fixed change each day (0.01 = about +1 % a day).
  - **reversion**: a pull back toward the base price (0.05 = 5 % of the gap each day).
  - **volatility**: a random change (0.03 = a typical day moves about 3 %).
- A price stays between 0.1 and 10 times its base price.
- The random part comes from the profile's market seed, the symbol and the day. The same profile always gets the same market.
- The game keeps 30 prices (30 days) for each instrument. A new profile starts with 30 days of made-up history.
- The market starts the first time the player opens a page that shows prices (pilot.net's front page does).

## The file: market.json

`database/fourx/market.json` has four lists. Each key that starts with `_` is a note. The game ignores it.

### groups

The groups, in the order that the site shows them. Each group is a button on the site, except `index`.

```json
{"id": "salvage", "name": "SALVAGE", "volatility": 0.05, "reversion": 0.08, "drift": 0.0}
```

| Field | Required | Meaning |
|---|---|---|
| `id` | Yes | The group's name in the code. The game uses `index`, `makers`, `salvage` and `bio`. |
| `name` | Yes | The name on the site. |
| `volatility` | No | The random change of each instrument in the group. |
| `reversion` | No | The pull back toward the base price. |
| `drift` | No | The fixed change each day. |

### instruments

Instruments that you add by hand (for example, a currency or a fuel price).

```json
{"symbol": "FUEL", "name": "Diesel, per drum", "group": "other", "base": 120, "volatility": 0.04, "requires": {}}
```

| Field | Required | Meaning |
|---|---|---|
| `symbol` | Yes | 1 to 5 capital letters or digits. Use each symbol one time only. |
| `name` | Yes | The name on the site. |
| `group` | Yes | The id of a group in `groups` (not `index`). |
| `base` | Yes | The base price. It must be above 0. |
| `volatility`, `reversion`, `drift` | No | These replace the group's values for this instrument. |
| `requires` | No | Story conditions. The instrument shows on the site only while they pass. Its price moves all the time. |
| `steelapedia` | No | The slug of a Steelapedia article. The quote page links to it. |

The file has one sample instrument, `SMPL`. Delete it when you do not need it.

### events

An event changes the market while its story conditions pass. Use events to make the market react to the story.

```json
{"id": "helwan_swarm", "requires": {"flags": {"helwan_swarming": true}}, "targets": ["group:bio", "AGLN"], "drift": 0.03, "volatility": 0.02}
```

| Field | Required | Meaning |
|---|---|---|
| `id` | Yes | A name for the event. |
| `requires` | No | Story conditions (`reached`, `not_reached`, `flags`). With no `requires`, the event is always on. |
| `targets` | Yes | Symbols, or `group:<id>` for a whole group. |
| `drift` | No | Added to each target's drift each day. 0.03 = about +3 % a day. A negative number makes prices fall. |
| `volatility` | No | Added to each target's volatility each day. |

The game checks the conditions on each new day. An event changes only the days that pass while it is on.

The file has one sample event, `sample_bio_rally`. It lifts the bio group while the flag `sample_bio_rally` is true. Delete it when you do not need it.

**Use true/false flags in `requires`.** `StoryDirector.meets` compares a flag that is not set with `false`. A condition on a number flag (for example `{"flags": {"helwan_threat": 2}}`) causes an engine error until the flag has a value. Set a true/false flag for the event, or give the number flag a value at the start of the story.

## The site

| Address | Page |
|---|---|
| `fourx.net/` | The markets: the indexes, the five biggest rises and falls of the day, the groups. |
| `fourx.net/group/<id>` | Every instrument in a group, A-Z by symbol. |
| `fourx.net/q/<symbol>` | One quote: a 30-day chart, the key figures, and links (a maker's Steelapedia article, its parts on amazing.com and its own site). |
| `fourx.net/search?q=` | Symbol lookup. An exact symbol goes straight to its quote. |

## How to test a change

1. Edit `market.json`.
2. In the game, press **F9**. FourX reads the file again (pilot.net and Steelapedia also do). The prices made so far stay.
3. Open `fourx.net`.

Run `run_tests.bat --suite=FourX` after you change the file. The test reports an unknown key, a bad symbol, a symbol used twice, a group that does not exist, a `base` that is not above 0, an event target that does not exist and an unknown condition.
