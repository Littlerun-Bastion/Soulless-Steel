# pilot.net: content guide

pilot.net is the pilots' message board on the NET. This guide tells you how to add content to it. You do not need to write code for most content.

The code is `game/net/pilotnet/PilotNet.gd` (the data) and `game/ui/net/sites/pilotnet/` (the pages: `PilotNetSite.gd` picks what they show, `PilotNetPage.gd` and `PilotNetPortalPage.gd` are the two looks).

## The files

| File | What it holds |
|---|---|
| `posts/*.json` | Posts. PilotNet reads every `.json` file in this folder. |
| `boards.json` | The boards (the sections of the site). |
| `world.json` | The lines of the WORLD STATUS box. |
| `gigs.json` | Gig templates (small side jobs). |
| `pilots.json` | Pilot profiles. |
| `site.json` | Which look the site has (see "The two looks"). |

Each file starts with an `"_about"` key. It says what the file is. PilotNet ignores every key that starts with `_`.

`posts/samples.json` holds test posts only. Delete it when the real posts exist.

## Conditions and effects

Posts, boards, world lines, gigs and pilots use the shapes of `StoryDirector`.

A **condition** dictionary (`requires`, `hidden_if`) can have these keys:

| Key | Passes when |
|---|---|
| `"reached": "chapter_2"` or `"chapter_2/beat"` | The story reached that chapter or beat. |
| `"not_reached": "chapter_2"` | The story did not reach it. |
| `"flags": {"volk_met": true}` | Each flag has that value. |
| `"manual": true` | Never by itself. Only `show_post` shows the post. |

An empty dictionary always passes.

**Use true/false flags in conditions.** `StoryDirector.meets` compares a flag that is not set with `false`. A condition on a number flag (for example `{"flags": {"helwan_threat": 2}}`) causes an engine error until the flag has a value. Use a true/false flag, or give the number flag a value at the start of the story. World-status lines are not conditions: they can use number flags.

An **effect** dictionary (`on_read`, mission `story_effects`, reply `story_effects`) can have these keys:

| Key | What it does |
|---|---|
| `"flags": {"read_rumour": true}` | Sets the flags. |
| `"advance": "chapter_2/start"` | Moves the story. |
| `"pilotnet": {"show": [...], "hide": [...], "post": {...}}` | Shows posts, hides posts, or adds a post. |

## How to write a post

Put the post in a list called `"posts"` in a file in `posts/`. Use one file per story arc or per event. The split is your choice.

```json
{
	"id": "volk_rumour_1",
	"board": "general",
	"author": "GREYWAKE",
	"title": "Anyone else seen lights over the cement works?",
	"body": "First paragraph.\n\nSecond paragraph.",
	"requires": {"flags": {"volk_met": true}},
	"hidden_if": {"reached": "chapter_2"},
	"notify": false,
	"pinned": false,
	"order": 0,
	"on_read": {"flags": {"read_volk_rumour": true}},
	"replies": [
		{"author": "KESTREL", "body": "Reply text.", "requires": {}}
	],
	"gig": "coyote_cull"
}
```

| Field | Required | Meaning |
|---|---|---|
| `id` | Yes | A name for the post. Use each id one time only, in all files. |
| `board` | Yes | The id of a board in `boards.json`. |
| `title` | Yes | The title. |
| `body` | Yes | The text. Write `\n\n` between paragraphs. |
| `author` | No | A callsign. Use `"{player}"` for the player. A callsign in `pilots.json` links to that profile. |
| `requires` | No | The post shows only while these conditions pass. |
| `hidden_if` | No | The post goes away when these conditions pass. |
| `notify` | No | `true` makes the post unread until the player opens it. The NET tile counts it. One LOG line tells the player. Use this only for posts that matter. |
| `pinned` | No | `true` puts the post at the top of its board. |
| `order` | No | A number. Posts that appear on the same day sort by it, low first. |
| `on_read` | No | Effects. They run one time, when the player first opens the post. Use this to turn a rumour into a plot hook. |
| `replies` | No | A list of replies. Each reply has `author`, `body` and an optional `requires`. A thread can grow as the story moves. |
| `gig` | No | The id of a gig template. The post offers that gig with an ACCEPT button. |

Posts sort like this: pinned posts first, then the newest day first, then `order`.

PilotNet stamps each post with the day it first appears. The day goes up by one each time an expedition ends.

Do not change a post's `id` after release. Old saves use the id for the read state.

## How to write a board

Add the board to the list in `boards.json`. The site shows the boards in this order.

```json
{"id": "news", "name": "NEWS & EVENTS", "blurb": "One line under the name.", "requires": {}}
```

| Field | Required | Meaning |
|---|---|---|
| `id` | Yes | The name that posts use in `board`. |
| `name` | Yes | The title on the site. |
| `blurb` | Yes | One line under the name. |
| `requires` | No | The board and its posts show only while these conditions pass. |

The boards `news` and `gigs` are special. The front page shows the latest `news` posts. Gigs go on `gigs`. Posts on the other boards show in the front page's HOT IN THE FORUMS box.

The site calls the boards "forums" and the posts "topics". The forum index shows each board's topics, posts and last post.

## The two looks

pilot.net has two looks. Both show the same content at the same addresses.

| Look | What it looks like | Code |
|---|---|---|
| The board (`bbs`) | A black text-mode board in VT323, with ASCII boxes. The site starts with this look. | `PilotNetPage.gd` |
| The portal (`portal`) | A light web portal from about 2006: a dark header band with the logo, tabs and a search box, three columns of boxes on the front page, striped tables, message blocks with a picture for each pilot. | `PilotNetPortalPage.gd` |

Use the switch to make it look as if someone rebuilt the site during the story.

`site.json` sets the switch:

```json
"new_look": {
	"requires": {"flags": {"pilotnet_new_look": true}},
	"notice": "pilot.net has a new look."
}
```

| Field | Required | Meaning |
|---|---|---|
| `requires` | No | The portal shows while these conditions pass. An empty object always passes: then the site always has the portal. |
| `notice` | No | One line along the top of the portal. It can use the text tags. Leave it out for no line. |

To switch in the story, set the flag in one of the usual ways:

- From the story script: `StoryDirector.set_flag("pilotnet_new_look", true)`
- From a mission or a Messenger reply: `{"flags": {"pilotnet_new_look": true}}` in `story_effects`
- From a map: a `map_trigger` named `story:flag=pilotnet_new_look`

The page that is open does not change. The next page the player opens has the new look.

To show content only with the new look, give it the same `requires`. The sample post `sample_new_look` in `posts/samples.json` does this.

To see a look in the game without the story, press **Shift+F9**. Each press goes to the next look: the portal, the board, then the look that `site.json` gives. The output prints the look. The game does not save this.

## Where content shows

pilot.net is the NET's home page. HOME in the browser opens it.

| Page | Content |
|---|---|
| Front page (`pilot.net/`) | TOP STORY: the first pinned `news` post (or the newest one), with the start of its body. In the portal look, the top story is the first slide of the feature box; the other slides show the best gig, amazing.com's featured part, the FourX Composite and Steelapedia's featured article. NEWS: the next five `news` posts. HOT IN THE FORUMS: the newest posts on the other boards. GIG BOARD: four open gigs. On the right: MY PILOT, FOURX MARKETS (`database/fourx/`), TOP DEALS ON AMAZING.COM (amazing.com's picks), WORLD STATUS (`world.json`) and FROM STEELAPEDIA (the featured article). |
| Forum index (`pilot.net/forums`) | Every board, with its blurb, its counts and its last post. Who is online, and the statistics. |
| A board (`pilot.net/board/<id>`) | Its topics, 20 a page: `!` pinned, `*` new, `$` a gig. |
| A topic (`pilot.net/post/<id>`) | The post and its replies as cards, 10 replies a page. Each card shows the author's callsign, an avatar made from the callsign, a rank from the number of posts (Rookie, Pilot, Veteran, Ace), the post count and the day the pilot was last seen. |
| Gigs (`pilot.net/gigs`) | The open gigs, your gigs with a progress bar, and complete gigs. |
| Pilots (`pilot.net/pilots`) | Every profile and every pilot met in the field, in one table. |
| Search (`pilot.net/search?q=`) | The NET search: posts, pilots, Steelapedia articles, amazing.com parts and FourX quotes. |

## How to write a world-status line

Add an entry to `world.json`. The key is the name of a story flag.

```json
"helwan_threat": {"label": "Helwan threat", "values": {"0": "Quiet", "1": "Active", "2": "Swarming"}, "default": "0", "requires": {}}
```

| Field | Required | Meaning |
|---|---|---|
| `label` | Yes | The name of the line. |
| `values` | Yes | The text for each value of the flag. Write each value as text: `"0"`, `"2"`, `"true"`, `"false"`. |
| `default` | No | The value to use when the flag is not set. Write it as text. |
| `requires` | No | The line shows only while these conditions pass. |

Set the value from the story script: `StoryDirector.set_flag("helwan_threat", 2)`. A value with no text shows as the value itself. pilot.net only shows these values. Other systems can read the same flags.

## How to write a gig template

Add the template to the list in `gigs.json`.

```json
{
	"id": "coyote_cull",
	"title": "Clear {count} {kind_plural} near Helwan",
	"type": "kill",
	"kind": "Coyote",
	"count": [4, 8],
	"reward": [300, 600],
	"reputation": 1,
	"weight": 1.0,
	"requires": {}
}
```

| Field | Required | Meaning |
|---|---|---|
| `id` | Yes | A name for the template. |
| `title` | Yes | The title. It can use `{count}`, `{kind}`, `{kind_plural}` and `{item}`. |
| `type` | Yes | `kill`, `extract` or `extract_with`. |
| `kind` | For `kill` | `"mech"` or an Entity species, for example `"Coyote"`. The board offers only kinds that the Expedition spawns. |
| `item` | For `extract_with` | An item id (`"acid_gland"`) or a tag (`"bio"`). |
| `count` | Yes | `[min, max]`. The board picks a number one time, when it posts the gig. |
| `reward` | Yes | `[min, max]` in credits. The board rounds it to the nearest 10. |
| `reputation` | No | Reputation that the player gets on payment. |
| `weight` | No | How often the board picks this template. The default is 1. |
| `requires` | No | The board offers the template only while these conditions pass. |
| `poster` | No | A callsign. With no poster, the board picks a random callsign. |
| `kind_plural` | No | The plural for `{kind_plural}`. The default adds `s` to `kind`. |
| `item_name` | No | The name for `{item}`. The default is the item's name, or the tag. |

How gigs work:

- The board has 5 open gigs. An open gig that nobody accepts goes away after 3 days. New gigs fill the board.
- The player can accept 3 gigs at a time. The player can abandon a gig. There is no penalty.
- `kill`: the player kills `count` of `kind`.
- `extract`: the player extracts `count` times.
- `extract_with`: the player extracts with at least `count` of the item in the mech cargo. The best single extraction counts.
- Progress from a run counts only if the run ends in an extraction. Progress adds up across runs.
- A complete gig pays when the player is next in the Hangar. The poster sends a "Payment sent" post.

Gigs are not missions. They do not use `MissionManager`.

## How to write a pilot profile

Add an entry to `pilots.json`. The key is the callsign. Use the `mecha_name` of a named NPC in `database/npcs/special_npcs/`.

```json
"Lady Volk": {"affiliation": "One line.", "bio": "Profile text.\n\nSecond paragraph.", "requires": {}, "steelapedia": "lady_volk"}
```

| Field | Required | Meaning |
|---|---|---|
| `affiliation` | Yes | One line under the callsign. |
| `bio` | Yes | The profile text. |
| `requires` | No | The profile shows only while these conditions pass. |
| `steelapedia` | No | The slug of a Steelapedia article. The profile links to it. |

The profile also shows the pilot's frame. It comes from the named NPC's `special_npc` resource. It also shows the pilot's posts and "Last seen: Day n" when the player has met the pilot.

When a pilot joins Local in an expedition, pilot.net records the callsign and the day. A met pilot with no profile gets a short page.

## The five ways in

All five ways make the same kind of post.

| Way | Example |
|---|---|
| A. A data file with `requires` | `"requires": {"flags": {"volk_met": true}}` |
| B. One call from code | `PilotNet.post({"id": "x", "board": "news", "title": "T", "body": "B"})` |
| C. A story effect | `{"flags": {"volk_met": true}, "pilotnet": {"show": ["volk_rumour_1"]}}` |
| D. A map trigger | A `map_trigger` named `story:pilotnet=volk_rumour_1` |
| E. A world-status value | `StoryDirector.set_flag("helwan_threat", 2)` |

The other calls from code:

- `PilotNet.show_post("id")` shows a post. It shows the post even when its `requires` does not pass.
- `PilotNet.hide_post("id")` hides a post.
- `PilotNet.reply("post_id", {"author": "KESTREL", "body": "Text."})` adds a reply.

PilotNet saves the posts from code, and the shown and hidden ids.

## Which way to use

- For most story posts, use a data file with `requires`. Write the post now. Connect it later with a flag name.
- From a mission or a Messenger reply, use the `"pilotnet"` effect in `story_effects`.
- From a map, use a `story:pilotnet=<id>` trigger.
- From code that does not use `StoryDirector`, use `PilotNet.post`, `show_post` or `hide_post`.

Any system can add its own effect key. Use `StoryDirector.register_effect("key", handler)`. The handler gets the value of the key. A map trigger `story:key=text` also calls it, with the text.

## Text tags

Titles, bodies, authors and replies can use these tags. pilot.net fills them in when it shows the page.

| Tag | Becomes |
|---|---|
| `{player}` | The player's callsign. |
| `{day}` | The current day, as a number (`15`). |
| `{date}` | The current day as a date (`Mon 15 Jan 2035`). |
| `{flag:name}` | The value of the story flag `name`. |
| `{world:name}` | The world-status text for the flag `name`. |

pilot.net does not change a tag that it does not know. `PilotNetTest` reports it.

## Dates

The NET shows dates, not day numbers. Day 1 is `PilotNet.CALENDAR_START` (`2035-01-01`, a placeholder), and Day n is n − 1 days later. `PilotNet.day` is still the number underneath.

| Function | Gives | Used on |
|---|---|---|
| `PilotNet.date_text(day)` | `Mon 15 Jan 2035` | the login line, the front page |
| `PilotNet.short_date(day)` | `15/01/2035` | the text-mode look and FourX.net |
| `PilotNet.long_date(day)` | `15 Jan 2035` | the portal look, Steelapedia, the Memorial Wall |
| `PilotNet.stamp(day, time)` | `15 Jan 2035 · 03:14` | the portal look's post stamps |

Nothing outside the NET shows a date.

## In memoriam

Both looks have an **In memoriam** box on the front page: the three newest records on the Memorial Wall (`memorialwall.org`), with links to them. A pilot's profile, or the page of a pilot you met, shows `† Lost 15 Jan 2035 — Memorial Wall` when that callsign is on the Wall. See `database/memorial/README.md`.

## How to test a post in the game

1. Start the game.
2. Press **F9** (the action `debug_8`).
3. pilot.net reads all its files again. Steelapedia and FourX also read their files again.
4. Read the list in the output. Each post shows `+` (visible) or `-` (hidden). A hidden post shows the reason.

Use **F7** to see the story state (StoryDirector).

Run `run_tests.bat --suite=PilotNet` after you change a file. The test finds these mistakes:

- a JSON file that does not parse
- an id that is not unique
- a board that does not exist
- an unknown key in a post, a condition or an effect
- a `show` or `hide` id that is not a post
- a `gig` that is not a template
- an unknown text tag
- a world-status text that is not a string
